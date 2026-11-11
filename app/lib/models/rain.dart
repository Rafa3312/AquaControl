/// Riego por lluvia (Sprint 7, HU-11).
///
/// Las reglas viven en el firmware (firmware/AquaControl_v3_secure/rain_logic.h).
/// Aquí solo se lee el estado que reporta el ESP32 en GET /status y se muestra,
/// con las mismas constantes para explicar al usuario qué pasó.
library;

/// Qué hace el programador cuando llega un riego programado.
enum RainVerdict { resume, wait, cancel }

/// Estado del sensor de lluvia tal como lo reporta el ESP32 ("rain" en /status).
class RainStatus {
  /// Lectura igual o menor a este valor = mojado (calibrar en el firmware).
  static const int wetRaw = 2600;

  /// Fuera de este rango el sensor está desconectado, en corto o sin señal.
  static const int validMin = 100;
  static const int validMax = 4090;

  /// Reintento de un riego pospuesto y tiempo máximo de espera.
  static const Duration retryInterval = Duration(minutes: 15);
  static const Duration maxWait = Duration(hours: 2);

  final bool valid;
  final bool raining;
  final int? raw;

  const RainStatus({required this.valid, required this.raining, this.raw});

  /// null si el firmware no envía el dato (versión anterior a la v3.4).
  static RainStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['raw'];
    return RainStatus(
      valid: json['valid'] == true,
      raining: json['raining'] == true,
      raw: raw is int ? raw : null,
    );
  }

  static bool rawIsValid(int raw) => raw >= validMin && raw <= validMax;

  static bool rawIsWet(int raw) => raw <= wetRaw;

  String get label {
    if (!valid) return 'Sensor sin lectura';
    return raining ? 'Lloviendo' : 'Sin lluvia';
  }

  /// Qué hacer con un riego programado. [waited] es el tiempo ya pospuesto
  /// (cero al dispararse). Igual que rainVerdict() en el firmware.
  static RainVerdict verdict({required bool raining, required Duration waited}) {
    if (!raining) return RainVerdict.resume;
    if (waited >= maxWait) return RainVerdict.cancel;
    return RainVerdict.wait;
  }
}
