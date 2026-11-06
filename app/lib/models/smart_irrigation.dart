/// Riego inteligente por humedad del suelo (Sprint 6, HU-10).
///
/// Tabla de decisión (criterios del PO en docs/sprints/sprint-06.md), igual a
/// la del firmware (smart_irrigation.h):
///   - humedad >= umbral                  → se omite el riego
///   - umbral - 15 <= humedad < umbral    → se riega la mitad (mínimo 1 min)
///   - humedad < umbral - 15              → se riega completo
///   - lectura inválida (sensor en falla) → se riega lo programado y se avisa
///   - riego inteligente apagado          → se riega lo programado
library;

/// Estado del suelo que se muestra en el Dashboard.
enum MoistureLevel { dry, moist, saturated }

/// Lectura del sensor de humedad de una zona, tal como la reporta el ESP32.
class MoistureReading {
  /// Debajo de este porcentaje el suelo se considera seco.
  static const int moistFrom = 35;

  /// Desde este porcentaje el suelo se considera saturado.
  static const int saturatedFrom = 80;

  final bool valid;
  final int percent; // 0..100
  final int? raw;    // valor crudo del ADC, para calibrar

  const MoistureReading({required this.valid, required this.percent, this.raw});

  /// Lee el objeto "moisture" de una zona en GET /status. Devuelve null si el
  /// firmware no lo envía (versión anterior a la v3.3 o sin sensor).
  static MoistureReading? fromJson(Object? json) {
    if (json is! Map) return null;
    final percent = json['percent'];
    final raw = json['raw'];
    final valid = json['valid'] == true &&
        percent is int &&
        percent >= 0 &&
        percent <= 100;
    return MoistureReading(
      valid: valid,
      percent: valid ? percent : 0,
      raw: raw is int ? raw : null,
    );
  }

  /// null cuando la lectura no es válida.
  MoistureLevel? get level {
    if (!valid) return null;
    if (percent >= saturatedFrom) return MoistureLevel.saturated;
    if (percent >= moistFrom) return MoistureLevel.moist;
    return MoistureLevel.dry;
  }

  String get levelLabel => switch (level) {
        MoistureLevel.dry => 'Seco',
        MoistureLevel.moist => 'Húmedo',
        MoistureLevel.saturated => 'Saturado',
        null => 'Sin lectura',
      };
}

/// Configuración del riego inteligente de una zona.
class SmartSettings {
  static const int minThreshold = 10;
  static const int maxThreshold = 90;
  static const int defaultThreshold = 60;

  /// Rango debajo del umbral en el que se riega la mitad.
  static const int reduceBand = 15;

  final bool enabled;
  final int threshold; // % de humedad

  const SmartSettings({this.enabled = false, this.threshold = defaultThreshold});

  /// Devuelve un mensaje de error o null si el umbral es válido.
  /// El mismo rango lo validan el firmware y las reglas de Firestore.
  static String? validateThreshold(int value) =>
      value < minThreshold || value > maxThreshold
          ? 'El umbral debe estar entre $minThreshold% y $maxThreshold%'
          : null;

  /// Lee la configuración guardada en users/{uid}/zones/{id}. Un umbral
  /// fuera de rango se ignora y se usa el valor por defecto.
  factory SmartSettings.fromMap(Map<String, dynamic>? data) {
    final threshold = data?['threshold'];
    return SmartSettings(
      enabled: data?['smartEnabled'] == true,
      threshold: threshold is int && validateThreshold(threshold) == null
          ? threshold
          : defaultThreshold,
    );
  }

  Map<String, dynamic> toMap() => {'smartEnabled': enabled, 'threshold': threshold};

  SmartSettings copyWith({bool? enabled, int? threshold}) => SmartSettings(
        enabled: enabled ?? this.enabled,
        threshold: threshold ?? this.threshold,
      );
}

/// Qué hace el programador con un riego programado.
enum SmartAction { full, half, skip }

/// Motivo de la decisión. El nombre coincide con el que envía el firmware.
enum SmartReason {
  off('Riego inteligente apagado', SmartAction.full),
  sensor('Sensor sin lectura: se riega lo programado', SmartAction.full),
  wet('Omitido por humedad suficiente', SmartAction.skip),
  near('Reducido a la mitad por humedad', SmartAction.half),
  dry('Riego completo: suelo seco', SmartAction.full);

  final String message;
  final SmartAction action;
  const SmartReason(this.message, this.action);

  static SmartReason? fromName(Object? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// Resultado de aplicar la tabla de decisión a un riego programado.
class SmartDecision {
  final SmartReason reason;
  final int minutes; // minutos que se riegan (0 si se omite)

  const SmartDecision(this.reason, this.minutes);

  SmartAction get action => reason.action;
  String get message => reason.message;

  static SmartDecision decide({
    required SmartSettings settings,
    required MoistureReading reading,
    required int minutes,
  }) {
    if (!settings.enabled) return SmartDecision(SmartReason.off, minutes);
    if (!reading.valid) return SmartDecision(SmartReason.sensor, minutes);
    if (reading.percent >= settings.threshold) {
      return const SmartDecision(SmartReason.wet, 0);
    }
    if (reading.percent >= settings.threshold - SmartSettings.reduceBand) {
      final half = minutes ~/ 2;
      return SmartDecision(SmartReason.near, half < 1 ? 1 : half);
    }
    return SmartDecision(SmartReason.dry, minutes);
  }
}

/// Última decisión que tomó el ESP32 en una zona ("lastSmart" en /status).
class SmartRecord {
  final SmartReason reason;
  final int? percent;
  final String? at; // HH:mm

  const SmartRecord({required this.reason, this.percent, this.at});

  static SmartRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final reason = SmartReason.fromName(json['reason']);
    if (reason == null) return null;
    final percent = json['percent'];
    return SmartRecord(
      reason: reason,
      percent: percent is int ? percent : null,
      at: json['at'] as String?,
    );
  }

  String get message => reason.message;
}
