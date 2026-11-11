import 'package:cloud_firestore/cloud_firestore.dart';

import 'zone.dart';

/// skip, reduce y sensor son del riego inteligente (Sprint 6, HU-10).
enum NotificationKind { start, end, fail, skip, reduce, sensor, postpone, cancel, rainSensor }

/// Aviso de riego guardado por la Cloud Function en users/{uid}/notifications.
class IrrigationNotification {
  final String id;
  final NotificationKind kind;
  final int zone;
  final String zoneName;
  final String title;
  final String body;
  final bool manual;
  final DateTime? createdAt;

  const IrrigationNotification({
    required this.id,
    required this.kind,
    required this.zone,
    required this.zoneName,
    required this.title,
    required this.body,
    this.manual = false,
    this.createdAt,
  });

  /// Falla de la válvula o del sensor de humedad: se resalta en la lista.
  bool get isFailure =>
      kind == NotificationKind.fail ||
      kind == NotificationKind.sensor ||
      kind == NotificationKind.rainSensor;

  factory IrrigationNotification.fromMap(String id, Map<String, dynamic> data) {
    final kind = switch (data['type']) {
      'fail' => NotificationKind.fail,
      'end' => NotificationKind.end,
      'skip' => NotificationKind.skip,
      'reduce' => NotificationKind.reduce,
      'sensor' => NotificationKind.sensor,
      'postpone' => NotificationKind.postpone,
      'cancel' => NotificationKind.cancel,
      'rainsensor' => NotificationKind.rainSensor,
      _ => NotificationKind.start,
    };
    final rawZone = data['zone'];
    final zone = rawZone is int && Zones.isValid(rawZone) ? rawZone : 1;
    final zoneName = (data['zoneName'] as String?) ?? Zones.defaultName(zone);

    final rawDate = data['createdAt'];
    final createdAt = rawDate is Timestamp
        ? rawDate.toDate()
        : rawDate is DateTime
            ? rawDate
            : null;

    return IrrigationNotification(
      id: id,
      kind: kind,
      zone: zone,
      zoneName: zoneName,
      title: (data['title'] as String?) ?? _defaultTitle(kind, zoneName),
      body: (data['body'] as String?) ?? '',
      manual: data['source'] == 'manual',
      createdAt: createdAt,
    );
  }

  static String _defaultTitle(NotificationKind kind, String zoneName) {
    switch (kind) {
      case NotificationKind.start:
        return 'Riego iniciado · $zoneName';
      case NotificationKind.end:
        return 'Riego terminado · $zoneName';
      case NotificationKind.fail:
        return 'Falla en $zoneName';
      case NotificationKind.skip:
        return 'Riego omitido · $zoneName';
      case NotificationKind.reduce:
        return 'Riego reducido · $zoneName';
      case NotificationKind.sensor:
        return 'Sensor de humedad sin lectura · $zoneName';
      case NotificationKind.postpone:
        return 'Riego pospuesto por lluvia · $zoneName';
      case NotificationKind.cancel:
        return 'Riego cancelado por lluvia · $zoneName';
      case NotificationKind.rainSensor:
        return 'Sensor de lluvia sin lectura';
    }
  }
}
