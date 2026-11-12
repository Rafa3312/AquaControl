import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/local_time.dart';
import 'zone.dart';

/// Cómo terminó un riego (HU-14). Es el "estado" que muestra el historial.
enum IrrigationOutcome { done, reduced, skipped, postponed, cancelled, failed }

/// Por qué terminó así: la regla que decidió (humedad, lluvia, válvula…).
enum IrrigationReason { none, wet, near, dry, sensor, rain, valve }

/// Un riego del historial: users/{uid}/history/{id}. Lo escribe la Cloud
/// Function deviceHistory a partir del registro que guarda el ESP32.
class IrrigationRecord {
  final String id;
  final DateTime startAt;          // instante real (UTC)
  final int zone;
  final IrrigationOutcome outcome;
  final IrrigationReason reason;
  final int seconds;               // lo que realmente regó
  final bool manual;

  const IrrigationRecord({
    required this.id,
    required this.startAt,
    required this.zone,
    required this.outcome,
    required this.reason,
    required this.seconds,
    this.manual = false,
  });

  /// Hora local (UTC-6) del riego, para mostrarla y agrupar por día.
  DateTime get local => localClock(startAt);

  /// Si el riego usó agua (solo estos suman al consumo).
  bool get watered =>
      outcome == IrrigationOutcome.done || outcome == IrrigationOutcome.reduced;

  String get statusLabel {
    switch (outcome) {
      case IrrigationOutcome.done:
        return 'Completado';
      case IrrigationOutcome.reduced:
        return 'Reducido';
      case IrrigationOutcome.skipped:
        return 'Omitido';
      case IrrigationOutcome.postponed:
        return 'Pospuesto';
      case IrrigationOutcome.cancelled:
        return 'Cancelado';
      case IrrigationOutcome.failed:
        return 'Falla';
    }
  }

  /// Motivo en palabras, con los mismos textos que los avisos y la tarjeta
  /// de humedad.
  String get reasonText {
    switch (outcome) {
      case IrrigationOutcome.done:
        if (manual) return 'Riego manual';
        if (reason == IrrigationReason.dry) return 'Suelo seco: riego completo';
        if (reason == IrrigationReason.sensor) {
          return 'Sensor sin lectura: se regó lo programado';
        }
        return 'Riego programado';
      case IrrigationOutcome.reduced:
        return 'Reducido a la mitad por humedad';
      case IrrigationOutcome.skipped:
        return 'Omitido por humedad suficiente';
      case IrrigationOutcome.postponed:
        return 'Pospuesto por lluvia';
      case IrrigationOutcome.cancelled:
        return 'Cancelado por lluvia (2 h)';
      case IrrigationOutcome.failed:
        return 'La válvula no respondió';
    }
  }

  /// "10 min", "1 h 05 min", "45 s" o "—" si no regó.
  String get durationLabel => formatDuration(seconds);

  static String formatDuration(int seconds) {
    if (seconds <= 0) return '—';
    if (seconds < 60) return '$seconds s';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final m = minutes % 60;
    return '${minutes ~/ 60} h ${m.toString().padLeft(2, '0')} min';
  }

  /// Devuelve null si el documento no es un registro válido (se ignora).
  static IrrigationRecord? tryParse(String id, Map<String, dynamic> data) {
    final outcome = _byName(IrrigationOutcome.values, data['outcome']);
    final reason = _byName(IrrigationReason.values, data['reason']);
    final zone = data['zone'];
    final seconds = data['seconds'];
    final raw = data['startAt'];
    final startAt = raw is Timestamp
        ? raw.toDate()
        : raw is DateTime
            ? raw
            : null;
    if (outcome == null || reason == null || startAt == null) return null;
    if (zone is! int || !Zones.isValid(zone)) return null;
    if (seconds is! int || seconds < 0) return null;
    return IrrigationRecord(
      id: id,
      startAt: startAt.toUtc(),
      zone: zone,
      outcome: outcome,
      reason: reason,
      seconds: seconds,
      manual: data['manual'] == true,
    );
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
