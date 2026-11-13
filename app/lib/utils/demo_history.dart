import '../models/irrigation_record.dart';
import '../models/water_stats.dart';
import 'local_time.dart';

/// Riegos y resúmenes diarios simulados para la demostración del Sprint 8.
class DemoHistory {
  final List<IrrigationRecord> records;
  final List<DailyStat> days;
  const DemoHistory(this.records, this.days);

  /// Genera [months] meses de riegos que terminan en [now] (hora local UTC-6).
  /// Es determinista: la misma [seed] produce siempre los mismos datos.
  ///
  /// Cada día hay un riego programado en la zona 1 (06:00, 10 min) y otro en
  /// la zona 2 (18:30, 8 min). Los sábados la zona 1 riega también a las 23:30
  /// (borde de día) y cada 9 días hay un riego manual. El resultado de cada
  /// riego programado sigue las reglas de los sprints 6 y 7: omitido por
  /// humedad, reducido a la mitad, cancelado por lluvia (tras quedar pospuesto
  /// 2 h), con falla de válvula o completo.
  static DemoHistory generate({required DateTime now, int months = 6, int seed = 8}) {
    var state = seed == 0 ? 1 : seed;
    double rand() {
      state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
      return state / 4294967296;
    }

    final today = localDay(now);
    final totalDays = (months * 30.4).round();
    final records = <IrrigationRecord>[];
    var n = 0;

    void add(DateTime day, int hour, int minute, int zone, IrrigationOutcome outcome,
        IrrigationReason reason, int seconds, {bool manual = false}) {
      final instant = DateTime.utc(day.year, day.month, day.day, hour, minute).subtract(kLocalOffset);
      if (instant.isAfter(now)) return; // lo de hoy que aún no ha pasado
      records.add(IrrigationRecord(
        id: 'demo-${n++}',
        startAt: instant,
        zone: zone,
        outcome: outcome,
        reason: reason,
        seconds: seconds,
        manual: manual,
      ));
    }

    for (var d = totalDays - 1; d >= 0; d--) {
      final day = today.subtract(Duration(days: d));
      final slots = [
        (zone: 1, hour: 6, minute: 0, seconds: 600),
        (zone: 2, hour: 18, minute: 30, seconds: 480),
        if (day.weekday == DateTime.saturday) (zone: 1, hour: 23, minute: 30, seconds: 360),
      ];

      for (final s in slots) {
        final roll = rand();
        if (roll < 0.15) {
          add(day, s.hour, s.minute, s.zone, IrrigationOutcome.skipped, IrrigationReason.wet, 0);
        } else if (roll < 0.25) {
          add(day, s.hour, s.minute, s.zone, IrrigationOutcome.reduced, IrrigationReason.near,
              (s.seconds ~/ 2).clamp(60, s.seconds));
        } else if (roll < 0.30) {
          // Llueve: queda pospuesto y, tras 2 h con lluvia, se cancela
          add(day, s.hour, s.minute, s.zone, IrrigationOutcome.postponed, IrrigationReason.rain, 0);
          add(day, s.hour + 2, s.minute, s.zone, IrrigationOutcome.cancelled, IrrigationReason.rain, 0);
        } else if (roll < 0.32) {
          add(day, s.hour, s.minute, s.zone, IrrigationOutcome.failed, IrrigationReason.valve, 0);
        } else {
          add(day, s.hour, s.minute, s.zone, IrrigationOutcome.done,
              roll < 0.6 ? IrrigationReason.dry : IrrigationReason.none, s.seconds);
        }
      }
      if (d % 9 == 4) {
        add(day, 20, 15, 1, IrrigationOutcome.done, IrrigationReason.none, 300, manual: true);
      }
    }

    records.sort((a, b) => b.startAt.compareTo(a.startAt)); // más reciente primero
    return DemoHistory(records, _dailyStats(records));
  }

  /// Resumen diario con la misma regla que la Cloud Function: solo los riegos
  /// completados o reducidos suman agua; los omitidos y cancelados suman a
  /// "ahorrado".
  static List<DailyStat> _dailyStats(List<IrrigationRecord> records) {
    final byDay = <String, Map<int, ZoneDay>>{};
    for (final r in records) {
      final zones = byDay.putIfAbsent(dayKey(localDay(r.startAt)), () => {});
      final z = zones[r.zone] ?? const ZoneDay();
      zones[r.zone] = ZoneDay(
        runs: z.runs + (r.watered ? 1 : 0),
        seconds: z.seconds + (r.watered ? r.seconds : 0),
        skipped: z.skipped +
            (r.outcome == IrrigationOutcome.skipped || r.outcome == IrrigationOutcome.cancelled ? 1 : 0),
      );
    }
    return [for (final e in byDay.entries) DailyStat(e.key, e.value)];
  }
}
