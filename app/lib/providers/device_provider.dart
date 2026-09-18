import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

/// Estado de conexión con el ESP32
enum DeviceConnectionState { disconnected, searching, found, paired, error }

/// Maneja todo lo relacionado con el ESP32:
///   - Descubrimiento en la red local (mDNS + fallback IP)
///   - Vinculación con token seguro
///   - Almacenamiento del token en Firestore + SecureStorage
///   - Comandos HTTP autenticados (on/off/schedules)
class DeviceProvider extends ChangeNotifier {
  final _secure    = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _firestore = FirebaseFirestore.instance;
  final _auth      = FirebaseAuth.instance;

  // ── Estado ──────────────────────────────────────────────────────────────
  DeviceConnectionState _connState = DeviceConnectionState.disconnected;
  String?  _deviceIp;
  String?  _deviceToken;
  String?  _deviceId;      // nombre/hostname del ESP32
  bool     _valveOpen   = false;
  String?  _lastError;
  bool     _checking    = false;

  DeviceConnectionState get connState   => _connState;
  bool   get isConnected  => _connState == DeviceConnectionState.paired;
  bool   get valveOpen    => _valveOpen;
  String get deviceIp     => _deviceIp ?? '';
  String get deviceId     => _deviceId ?? '';
  String? get lastError   => _lastError;

  static const _mdnsHost  = 'aquacontrol.local';
  static const _port      = 80;
  static const _timeout   = Duration(seconds: 5);

  DeviceProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadLocalToken();
    if (_deviceToken != null && _deviceIp != null) {
      // Intentar reconexión automática en segundo plano
      _tryConnect(_deviceIp!);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DESCUBRIMIENTO
  // ══════════════════════════════════════════════════════════════════════════

  /// Intenta encontrar el ESP32.
  /// 1. mDNS  →  aquacontrol.local
  /// 2. IP guardada previamente
  /// 3. Escaneo de subnet /24
  Future<String?> discover({void Function(String)? onProgress}) async {
    _setState(DeviceConnectionState.searching);
    _lastError = null;

    // ── 1. mDNS ─────────────────────────────────────────────────────────────
    onProgress?.call('Buscando via mDNS...');
    final mdnsIp = await _resolveMDNS();
    if (mdnsIp != null) {
      debugPrint('[Device] mDNS → $mdnsIp');
      _deviceIp = mdnsIp;
      _setState(DeviceConnectionState.found);
      return mdnsIp;
    }

    // ── 2. Última IP conocida ────────────────────────────────────────────────
    if (_deviceIp != null) {
      onProgress?.call('Probando última IP conocida...');
      if (await _pingDevice(_deviceIp!)) {
        debugPrint('[Device] IP cache hit → $_deviceIp');
        _setState(DeviceConnectionState.found);
        return _deviceIp;
      }
    }

    // ── 3. Escaneo de subnet ─────────────────────────────────────────────────
    onProgress?.call('Escaneando red local...');
    final found = await _scanSubnet(onProgress: onProgress);
    if (found != null) {
      _deviceIp = found;
      _setState(DeviceConnectionState.found);
      return found;
    }

    _lastError = 'No se encontró el dispositivo en la red';
    _setState(DeviceConnectionState.error);
    return null;
  }

  Future<String?> _resolveMDNS() async {
    try {
      // InternetAddress.lookup funciona con mDNS en iOS y Android >= 12
      // con el flag de red correctamente configurado.
      final results = await InternetAddress.lookup(_mdnsHost)
          .timeout(const Duration(seconds: 3));
      if (results.isNotEmpty) {
        final ip = results.first.address;
        if (await _pingDevice(ip)) return ip;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _scanSubnet({void Function(String)? onProgress}) async {
    // Obtener IP local para deducir la subnet
    final localIp = await _getLocalIp();
    if (localIp == null) return null;

    final parts   = localIp.split('.');
    if (parts.length != 4) return null;
    final subnet  = '${parts[0]}.${parts[1]}.${parts[2]}';

    debugPrint('[Device] Escaneando $subnet.0/24...');

    // Escanear en grupos paralelos de 20 para ser más rápido
    for (int group = 1; group <= 254; group += 20) {
      final end  = (group + 19).clamp(1, 254);
      onProgress?.call('Escaneando $subnet.$group – $subnet.$end');

      final futures = <Future<String?>>[];
      for (int i = group; i <= end; i++) {
        futures.add(_pingDevice('$subnet.$i').then((ok) => ok ? '$subnet.$i' : null));
      }

      final results = await Future.wait(futures);
      final hit = results.firstWhere((r) => r != null, orElse: () => null);
      if (hit != null) {
        debugPrint('[Device] Encontrado en $hit');
        return hit;
      }
    }
    return null;
  }

  Future<bool> _pingDevice(String ip) async {
    try {
      final res = await http
          .get(Uri.parse('http://$ip:$_port/status'))
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return json['online'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VINCULACIÓN (PAIRING)
  // ══════════════════════════════════════════════════════════════════════════

  /// Resultado del intento de pairing
  /// null = éxito
  /// String = mensaje de error
  /// 'ALREADY_PAIRED' = ESP ya tiene token (recuperar o resetear)
  static const _alreadyPaired = 'ALREADY_PAIRED';

  Future<String?> pairDevice(String ip) async {
    final user = _auth.currentUser;
    if (user == null) return 'No hay sesión activa';

    // ── 1. Intentar pairing normal con token nuevo ─────────────────────────
    final newToken = const Uuid().v4();
    try {
      final res = await http.post(
        Uri.parse('http://$ip:$_port/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': newToken, 'uid': user.uid}),
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        // Pairing exitoso → guardar y listo
        return await _savePairing(ip: ip, token: newToken, uid: user.uid);
      }

      if (res.statusCode == 403) {
        // ESP ya tiene token → intentar recuperar
        return _alreadyPaired;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['error'] ?? 'Error (${res.statusCode})';

    } catch (e) {
      return 'Sin conexión con el dispositivo: $e';
    }
  }

  /// Llamar cuando pairDevice devuelve 'ALREADY_PAIRED'.
  /// Intenta usar el token que ya tenemos en SecureStorage o Firestore.
  /// Devuelve null si tuvo éxito, mensaje de error si no.
  Future<String?> recoverPairing(String ip) async {
    final user = _auth.currentUser;
    if (user == null) return 'No hay sesión activa';

    // Buscar token en SecureStorage primero, luego en Firestore
    String? token = await _secure.read(key: 'device_token_${user.uid}');
    if (token == null) {
      await _fetchTokenFromFirestore(user.uid);
      token = _deviceToken;
    }

    if (token == null) {
      return 'NO_TOKEN'; // sin token local → necesita factory reset
    }

    // Verificar que el ESP acepta ese token haciendo GET /status con él
    try {
      final res = await http.get(
        Uri.parse('http://$ip:$_port/status'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        // El token funciona → restaurar Firestore y listo
        _deviceToken = token;
        _deviceIp    = ip;
        _deviceId    = _mdnsHost;
        await _savePairingFirestore(ip: ip, token: token, uid: user.uid);
        await _secure.write(key: 'device_token_${user.uid}', value: token);
        await _secure.write(key: 'device_ip_${user.uid}',    value: ip);
        _setState(DeviceConnectionState.paired);
        debugPrint('[Device] Pairing recuperado con token existente');
        return null; // éxito
      }

      if (res.statusCode == 401) {
        return 'NO_TOKEN'; // token local no coincide con el del ESP → reset
      }

      return 'Error inesperado (${res.statusCode})';
    } catch (e) {
      return 'Sin conexión: $e';
    }
  }

  Future<String?> _savePairing({
    required String ip,
    required String token,
    required String uid,
  }) async {
    await _secure.write(key: 'device_token_$uid', value: token);
    await _secure.write(key: 'device_ip_$uid',    value: ip);
    await _savePairingFirestore(ip: ip, token: token, uid: uid);
    _deviceToken = token;
    _deviceIp    = ip;
    _deviceId    = _mdnsHost;
    _valveOpen   = false;
    _setState(DeviceConnectionState.paired);
    return null;
  }

  Future<void> _savePairingFirestore({
    required String ip,
    required String token,
    required String uid,
  }) async {
    await _firestore.collection('devices').doc(uid).set({
      'token':    token,
      'ip':       ip,
      'hostname': _mdnsHost,
      'pairedAt': FieldValue.serverTimestamp(),
      'uid':      uid,
    });
  }

  /// Carga el token desde SecureStorage. Si no está, lo busca en Firestore.
  Future<void> _loadLocalToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _deviceToken = await _secure.read(key: 'device_token_${user.uid}');
    _deviceIp    = await _secure.read(key: 'device_ip_${user.uid}');

    if (_deviceToken == null) {
      // Intentar recuperar de Firestore
      await _fetchTokenFromFirestore(user.uid);
    }
  }

  Future<void> _fetchTokenFromFirestore(String uid) async {
    try {
      final doc = await _firestore.collection('devices').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _deviceToken = data['token'] as String?;
        _deviceIp    = data['ip']    as String?;
        _deviceId    = data['hostname'] as String?;

        if (_deviceToken != null) {
          // Guardar localmente para no depender de Firestore cada vez
          await _secure.write(key: 'device_token_$uid', value: _deviceToken!);
          if (_deviceIp != null) {
            await _secure.write(key: 'device_ip_$uid', value: _deviceIp!);
          }
          debugPrint('[Device] Token recuperado de Firestore');
        }
      }
    } catch (e) {
      debugPrint('[Device] Error al leer Firestore: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RECONEXIÓN AUTOMÁTICA
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _tryConnect(String ip) async {
    if (_checking) return;
    _checking = true;
    final ok = await _pingDevice(ip);
    if (ok) {
      _setState(DeviceConnectionState.paired);
    } else {
      _setState(DeviceConnectionState.disconnected);
    }
    _checking = false;
  }

  /// Llamar periódicamente o cuando la app vuelve al primer plano
  Future<void> checkConnection() async {
    if (_deviceIp == null) {
      await _loadLocalToken();
    }
    if (_deviceIp != null) {
      await _tryConnect(_deviceIp!);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMANDOS HTTP (autenticados)
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getStatus() async {
    try {
      final res = await _get('/status');
      if (res != null) {
        _valveOpen = res['valve'] == true;
        notifyListeners();
      }
      return res;
    } catch (_) { return null; }
  }

  Future<bool> turnOn({int durationMinutes = 0}) async {
    final res = await _post('/on', {'duration': durationMinutes});
    if (res != null && res['ok'] == true) {
      _valveOpen = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> turnOff() async {
    final res = await _post('/off', {});
    if (res != null && res['ok'] == true) {
      _valveOpen = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Empuja todas las programaciones al ESP32 (replace total)
  Future<bool> syncSchedules(List<Map<String, dynamic>> schedules) async {
    final res = await _post('/schedules', {'schedules': schedules});
    return res != null && res['ok'] == true;
  }

  Future<bool> deleteSchedule(String id) async {
    final res = await _post('/schedules/delete', {'id': id});
    return res != null && res['ok'] == true;
  }

  Future<bool> setScheduleActive(String id, bool active) async {
    final res = await _post('/schedules/active', {'id': id, 'active': active});
    return res != null && res['ok'] == true;
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  Map<String, String> get _headers => {
    'Content-Type':  'application/json',
    'Authorization': 'Bearer $_deviceToken',
  };

  Future<Map<String, dynamic>?> _get(String path) async {
    if (!_canSend) return null;
    try {
      final res = await http.get(
        Uri.parse('http://$_deviceIp:$_port$path'),
        headers: _headers,
      ).timeout(_timeout);
      _handleResponse(res);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on SocketException {
      _onConnectionLost();
      return null;
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>?> _post(String path, Map<String, dynamic> body) async {
    if (!_canSend) return null;
    try {
      final res = await http.post(
        Uri.parse('http://$_deviceIp:$_port$path'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(_timeout);
      _handleResponse(res);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on SocketException {
      _onConnectionLost();
      return null;
    } catch (_) { return null; }
  }

  bool get _canSend => _deviceIp != null && _deviceToken != null;

  void _handleResponse(http.Response res) {
    if (res.statusCode == 401) {
      debugPrint('[Device] Token inválido — limpiar y reconectar');
      _setState(DeviceConnectionState.error);
      _lastError = 'Token inválido. Reconecta el dispositivo.';
    } else if (res.statusCode == 200 &&
               _connState != DeviceConnectionState.paired) {
      _setState(DeviceConnectionState.paired);
    }
  }

  void _onConnectionLost() {
    if (_connState == DeviceConnectionState.paired) {
      _setState(DeviceConnectionState.disconnected);
      debugPrint('[Device] Conexión perdida');
    }
  }



  /// Espera a que el ESP vuelva a estar en línea tras un reinicio.
  /// Prueba mDNS primero (rápido), luego la última IP conocida.
  /// Devuelve true si lo encontró.
  Future<bool> waitForDeviceOnline() async {
    // Intentar mDNS
    final mdnsIp = await _resolveMDNS();
    if (mdnsIp != null) {
      _deviceIp = mdnsIp;
      return true;
    }
    // Intentar última IP conocida
    if (_deviceIp != null && await _pingDevice(_deviceIp!)) {
      return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MODO SETUP (cuando el ESP está en SoftAP)
  // ══════════════════════════════════════════════════════════════════════════

  /// Detecta si el celular está conectado a la red WiFi del ESP32 en modo setup.
  /// El ESP en setup tiene IP fija 192.168.4.1
  Future<bool> detectSetupMode() async {
    try {
      final res = await http
          .get(Uri.parse('http://192.168.4.1/setup/info'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return json['mode'] == 'setup';
      }
    } catch (_) {}
    return false;
  }

  /// Envía las credenciales WiFi al ESP32 cuando está en modo setup.
  Future<String?> configureWiFi(String ssid, String password) async {
    try {
      final res = await http.post(
        Uri.parse('http://192.168.4.1/setup'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'ssid=${Uri.encodeComponent(ssid)}&pass=${Uri.encodeComponent(password)}',
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        return null; // OK, ESP se reiniciará y conectará al WiFi
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['error'] ?? 'Error al guardar WiFi';
    } catch (e) {
      return 'Error de conexión: $e';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FACTORY RESET CON PIN
  // ══════════════════════════════════════════════════════════════════════════

  /// Envía /reset al ESP sin token (el PIN actúa como credencial única).
  /// Útil cuando el token del ESP y el de la app no coinciden.
  Future<String?> factoryResetWithPin(String ip, String pin) async {
    try {
      // El reset no requiere Bearer token — usa el PIN derivado del MAC
      final res = await http.post(
        Uri.parse('http://$ip:$_port/reset-pin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        // Limpiar datos locales también
        final user = _auth.currentUser;
        if (user != null) {
          await _secure.delete(key: 'device_token_${user.uid}');
          await _secure.delete(key: 'device_ip_${user.uid}');
          await _firestore.collection('devices').doc(user.uid).delete()
              .catchError((_) {});
        }
        _deviceToken = null;
        _deviceIp    = null;
        _deviceId    = null;
        _setState(DeviceConnectionState.disconnected);
        return null; // éxito
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['error'] ?? 'Error al resetear (${res.statusCode})';

    } catch (e) {
      return 'Sin conexión con el dispositivo';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESET / DESVINCULACIÓN
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> unpair() async {
    // Intentar factory reset en el ESP (puede fallar si no hay conexión)
    await _post('/reset', {});

    final user = _auth.currentUser;
    if (user != null) {
      await _secure.delete(key: 'device_token_${user.uid}');
      await _secure.delete(key: 'device_ip_${user.uid}');
      await _firestore.collection('devices').doc(user.uid).delete();
    }

    _deviceToken = null;
    _deviceIp    = null;
    _deviceId    = null;
    _valveOpen   = false;
    _setState(DeviceConnectionState.disconnected);
  }

  void _setState(DeviceConnectionState s) {
    _connState = s;
    notifyListeners();
  }
}
