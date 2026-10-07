import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error devuelto por el API REST del programador (ESP32) o por falta de
/// conexión con él. [statusCode] es 0 cuando no hubo respuesta HTTP.
class DeviceApiException implements Exception {
  final int statusCode;
  final String message;

  const DeviceApiException(this.statusCode, this.message);

  bool get isUnauthorized => statusCode == 401;
  bool get isOffline => statusCode == 0;

  @override
  String toString() => 'DeviceApiException($statusCode): $message';
}

/// Cliente del API REST que expone el firmware AquaControl v3 en el ESP32.
///
/// Encapsula el contrato de los endpoints (/status, /pair, /on, /off,
/// /schedules, ...): rutas, autenticación Bearer, cuerpos JSON y el mapeo
/// de códigos de error. Además valida en el cliente las mismas reglas que el
/// firmware, para no gastar intentos de vinculación (el ESP32 bloquea 5 min
/// tras 5 tokens inválidos) ni enviar datos que el dispositivo descarta.
///
/// Recibe un [http.Client] inyectable para poder probarse sin hardware.
class DeviceApiClient {
  /// Longitud mínima del token de vinculación (MIN_TOKEN_LEN en el firmware).
  static const int minTokenLength = 32;

  /// Máximo de programaciones que guarda el ESP32 (MAX_SCHEDULES).
  static const int maxSchedules = 10;

  /// Duración máxima del riego manual, en minutos.
  static const int maxManualMinutes = 120;

  final Uri baseUri;
  final String? token;
  final http.Client _client;
  final Duration timeout;

  DeviceApiClient({
    required this.baseUri,
    this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  /// GET /status — estado de la válvula, vinculación, reloj, etc.
  Future<Map<String, dynamic>> getStatus() => _send('GET', '/status');

  /// POST /pair — vincula el dispositivo con un token y el UID del usuario.
  /// No requiere token Bearer (es el paso que lo crea).
  Future<Map<String, dynamic>> pair({
    required String pairingToken,
    required String uid,
  }) {
    if (pairingToken.length < minTokenLength) {
      throw ArgumentError.value(pairingToken.length, 'pairingToken',
          'El token debe tener al menos $minTokenLength caracteres');
    }
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'El UID es requerido');
    }
    return _send('POST', '/pair',
        body: {'token': pairingToken, 'uid': uid}, authenticated: false);
  }

  /// POST /on — enciende el riego. [durationMinutes] = 0 significa sin
  /// apagado automático.
  Future<Map<String, dynamic>> turnOn({int durationMinutes = 0}) {
    if (durationMinutes < 0 || durationMinutes > maxManualMinutes) {
      throw RangeError.range(
          durationMinutes, 0, maxManualMinutes, 'durationMinutes');
    }
    return _send('POST', '/on', body: {'duration': durationMinutes});
  }

  /// POST /off — apaga el riego.
  Future<Map<String, dynamic>> turnOff() =>
      _send('POST', '/off', body: const {});

  /// POST /schedules — reemplaza todas las programaciones del dispositivo.
  Future<Map<String, dynamic>> syncSchedules(
      List<Map<String, dynamic>> schedules) {
    if (schedules.length > maxSchedules) {
      throw ArgumentError.value(schedules.length, 'schedules',
          'El dispositivo admite como máximo $maxSchedules programaciones');
    }
    return _send('POST', '/schedules', body: {'schedules': schedules});
  }

  /// POST /schedules/delete — elimina una programación por id.
  Future<Map<String, dynamic>> deleteSchedule(String id) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'El id es requerido');
    }
    return _send('POST', '/schedules/delete', body: {'id': id});
  }

  /// POST /schedules/active — activa o desactiva una programación.
  Future<Map<String, dynamic>> setScheduleActive(String id, bool active) =>
      _send('POST', '/schedules/active', body: {'id': id, 'active': active});

  void close() => _client.close();

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    if (authenticated && (token == null || token!.isEmpty)) {
      throw StateError('Dispositivo no vinculado: falta el token Bearer');
    }

    final request = http.Request(method, baseUri.resolve(path));
    request.headers['Content-Type'] = 'application/json';
    if (authenticated) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(
          await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw const DeviceApiException(0, 'El dispositivo no respondió a tiempo');
    } on http.ClientException catch (e) {
      throw DeviceApiException(0, 'Sin conexión con el dispositivo: ${e.message}');
    }

    final decoded = _decode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final error = decoded['error'] ?? 'Error HTTP ${res.statusCode}';
      throw DeviceApiException(res.statusCode, error.toString());
    }
    return decoded;
  }

  static Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return {};
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : {};
    } on FormatException {
      return {};
    }
  }
}
