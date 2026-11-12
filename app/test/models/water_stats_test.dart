import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/irrigation_record.dart';
import 'package:irrigation_app/models/water_stats.dart';
import 'package:irrigation_app/models/zone.dart';
import 'package:irrigation_app/utils/local_time.dart';

/// Pruebas del historial y las estadísticas (Sprint 8, HU-14 y HU-16):
/// hora local UTC-6, periodos, agregación por zona y litros estimados.
void main() {
  // Instante real = hora local + 6 h
  DateTime at(String localIso) => DateTime.parse('${localIso}Z').add(const Duration(hours: 6));

  // Miércoles 21/10/2026 a las 12:00 hora local
  final now = at('2026-10-21T12:00:00');

  DailyStat day(String date, {int s1 = 0, int s2 = 0, int runs1 = 0, int runs2 = 0, int skipped = 0}) => DailyStat(date, {
        if (s1 > 0 || runs1 > 0) 1: ZoneDay(runs: runs1, seconds: s1, skipped: skipped),
        if (s2 > 0 || runs2 > 0) 2: ZoneDay(runs: runs2, seconds: s2),
      });

  group('hora local (UTC-6)', () {
    test('un riego de las 23:30 queda en su día, no en el siguiente', () {
      // Arrange: 23:30 local del 21 = 05:30 UTC del 22
      final instant = DateTime.utc(2026, 10, 22, 5, 30);
      // Act / Assert
      expect(dayKey(localDay(instant)), '2026-10-21');
      expect(localClock(instant).hour, 23);
    });

    test('valores límite: 00:00 y 23:59 local, y cambio de mes y de año', () {
      expect(dayKey(localDay(DateTime.utc(2026, 11, 1, 6, 0))), '2026-11-01');
      expect(dayKey(localDay(DateTime.utc(2026, 11, 1, 5, 59, 59))), '2026-10-31');
      expect(dayKey(localDay(DateTime.utc(2027, 1, 1, 5, 59))), '2026-12-31');
      expect(startOfLocalDay(DateTime.utc(2026, 11, 1)), DateTime.utc(2026, 11, 1, 6));
    });

    test('formatea fecha y mes con ceros', () {
      expect(dayKey(DateTime.utc(2026, 3, 5)), '2026-03-05');
      expect(monthKey(DateTime.utc(2026, 3, 5)), '2026-03');
    });
  });

  group('periodos', () {
    test('Hoy es un día; Semana, 7 días; Mes, 30 días', () {
      expect(HistoryPeriod.today.range(now).firstKey, '2026-10-21');
      expect(HistoryPeriod.today.range(now).lastKey, '2026-10-21');
      expect(HistoryPeriod.week.range(now).firstKey, '2026-10-15');
      expect(HistoryPeriod.month.range(now).firstKey, '2026-09-22');
      expect(HistoryPeriod.week.range(now).lastKey, '2026-10-21');
    });

    test('Año empieza el día 1 del mes de hace 11 meses (cruza el año)', () {
      expect(HistoryPeriod.year.range(now).firstKey, '2025-11-01');
      expect(HistoryPeriod.year.range(at('2026-02-10T08:00:00')).firstKey, '2025-03-01');
    });

    test('a las 23:30 locales el periodo todavía es el del día local', () {
      final late = at('2026-10-21T23:30:00');
      expect(HistoryPeriod.today.range(late).lastKey, '2026-10-21');
    });

    test('el inicio del periodo es medianoche local como instante real', () {
      expect(HistoryPeriod.today.range(now).startInstant, DateTime.utc(2026, 10, 21, 6));
    });

    test('containsKey incluye los dos extremos y excluye lo de fuera', () {
      final r = HistoryPeriod.week.range(now);
      expect(r.containsKey('2026-10-15'), isTrue);
      expect(r.containsKey('2026-10-21'), isTrue);
      expect(r.containsKey('2026-10-14'), isFalse);
      expect(r.containsKey('2026-10-22'), isFalse);
    });

    test('etiquetas de los filtros', () {
      expect(HistoryPeriod.values.map((p) => p.label), ['Hoy', 'Semana', 'Mes', 'Año']);
    });
  });

  group('estadísticas de consumo', () {
    test('litros = minutos × caudal de cada zona', () {
      // Arrange: zona 1 10 min a 7.2 L/min y zona 2 8 min a 6.8 L/min (medidos con cubeta)
      final days = [day('2026-10-21', s1: 600, runs1: 1, s2: 480, runs2: 1)];
      // Act
      final s = WaterStats.compute(
          period: HistoryPeriod.today, now: now, days: days, flowLpm: {1: 7.2, 2: 6.8});
      // Assert
      expect(s.liters, closeTo(72 + 54.4, 0.001));
      expect(s.runs, 2);
      expect(s.seconds, 1080);
    });

    test('sin caudal ajustado usa el nominal de 8 L/min', () {
      final s = WaterStats.compute(
          period: HistoryPeriod.today, now: now, days: [day('2026-10-21', s1: 600, runs1: 1)]);
      expect(s.liters, closeTo(80, 0.001));
    });

    test('sin datos todo es cero y no falla', () {
      final s = WaterStats.compute(period: HistoryPeriod.month, now: now, days: const []);
      expect(s.liters, 0);
      expect(s.runs, 0);
      expect(s.bars.length, 30);
      expect(s.bars.every((b) => b.total == 0), isTrue);
    });

    test('ignora los días fuera del periodo (límite de la semana)', () {
      final days = [
        day('2026-10-14', s1: 600, runs1: 1), // un día antes de la semana
        day('2026-10-15', s1: 600, runs1: 1), // primer día de la semana
        day('2026-10-21', s1: 600, runs1: 1), // hoy
        day('2026-10-22', s1: 600, runs1: 1), // futuro
      ];
      final s = WaterStats.compute(period: HistoryPeriod.week, now: now, days: days);
      expect(s.runs, 2);
    });

    test('el filtro de zona suma solo esa zona', () {
      final days = [day('2026-10-21', s1: 600, runs1: 1, s2: 480, runs2: 1)];
      final z2 = WaterStats.compute(
          period: HistoryPeriod.today, now: now, days: days, flowLpm: {2: 5}, zone: 2);
      expect(z2.runs, 1);
      expect(z2.liters, closeTo(40, 0.001));
      expect(z2.bars.map((b) => b.key), ['zona-2']);
    });

    test('cuenta los riegos omitidos o cancelados (agua ahorrada)', () {
      final s = WaterStats.compute(
          period: HistoryPeriod.today,
          now: now,
          days: [day('2026-10-21', s1: 600, runs1: 1, skipped: 3)]);
      expect(s.skipped, 3);
    });

    test('Semana: 7 barras, una por día, con la etiqueta del día', () {
      final s = WaterStats.compute(
          period: HistoryPeriod.week, now: now, days: [day('2026-10-19', s1: 600, runs1: 1)]);
      expect(s.bars.length, 7);
      expect(s.bars.first.label, 'Jue'); // 15/10/2026 fue jueves
      expect(s.bars.last.label, 'Mié'); // 21/10/2026 fue miércoles
      expect(s.bars.firstWhere((b) => b.key == '2026-10-19').total, closeTo(80, 0.001));
    });

    test('Mes: 30 barras numeradas por día del mes', () {
      final s = WaterStats.compute(period: HistoryPeriod.month, now: now, days: const []);
      expect(s.bars.first.label, '22');
      expect(s.bars.last.label, '21');
    });

    test('Año: 12 barras, una por mes, y el cambio de mes no mezcla días', () {
      final days = [
        day('2026-09-30', s1: 600, runs1: 1),
        day('2026-10-01', s1: 300, runs1: 1),
        day('2026-10-21', s1: 300, runs1: 1),
      ];
      final s = WaterStats.compute(period: HistoryPeriod.year, now: now, days: days);
      expect(s.bars.length, 12);
      expect(s.bars.first.key, '2025-11');
      expect(s.bars.last.key, '2026-10');
      expect(s.bars.last.label, 'Oct');
      expect(s.bars.firstWhere((b) => b.key == '2026-09').total, closeTo(80, 0.001));
      expect(s.bars.firstWhere((b) => b.key == '2026-10').total, closeTo(80, 0.001));
    });

    test('Hoy: una barra por zona', () {
      final s = WaterStats.compute(
          period: HistoryPeriod.today, now: now, days: [day('2026-10-21', s1: 600, runs1: 1)]);
      expect(s.bars.map((b) => b.label), ['Zona 1', 'Zona 2']);
      expect(s.bars[0].total, closeTo(80, 0.001));
      expect(s.bars[1].total, 0);
    });

    test('formatea litros y minutos', () {
      expect(WaterStats.formatLiters(0), '0.0 L');
      expect(WaterStats.formatLiters(12.44), '12.4 L');
      expect(WaterStats.formatLiters(99.94), '99.9 L');
      expect(WaterStats.formatLiters(100), '100 L');
      expect(WaterStats.formatLiters(1234.5), '1235 L');
      expect(WaterStats.formatMinutes(0), '0 min');
      expect(WaterStats.formatMinutes(2700), '45 min');
      expect(WaterStats.formatMinutes(3600), '1 h 00 min');
      expect(WaterStats.formatMinutes(7500), '2 h 05 min');
    });
  });

  group('resumen diario de Firestore', () {
    test('lee las zonas, ignora zonas y campos inválidos', () {
      final d = DailyStat.tryParse('2026-10-21', {
        'zones': {
          '1': {'runs': 2, 'seconds': 900, 'skipped': 1},
          '2': {'runs': -1, 'seconds': 'x'},
          '9': {'runs': 5, 'seconds': 100},
          '3': 'no es un mapa',
        },
      })!;
      expect(d.zones.keys, [1, 2]);
      expect(d.zones[1]!.seconds, 900);
      expect(d.zones[2]!.runs, 0);
      expect(d.zones[2]!.seconds, 0);
    });

    test('un id que no es fecha se descarta; sin zonas queda vacío', () {
      expect(DailyStat.tryParse('abc', {}), isNull);
      expect(DailyStat.tryParse('2026-10-21', {})!.zones, isEmpty);
    });
  });

  group('registro de riego', () {
    Map<String, dynamic> data({String outcome = 'done', String reason = 'none', int seconds = 600, bool manual = false}) => {
          'startAt': Timestamp.fromDate(DateTime.utc(2026, 10, 21, 12)),
          'zone': 1,
          'outcome': outcome,
          'reason': reason,
          'seconds': seconds,
          'manual': manual,
        };

    test('lee un registro válido y calcula la hora local', () {
      final r = IrrigationRecord.tryParse('h1', data())!;
      expect(r.zone, 1);
      expect(r.local.hour, 6);
      expect(r.watered, isTrue);
      expect(r.durationLabel, '10 min');
    });

    test('descarta registros con datos inválidos', () {
      expect(IrrigationRecord.tryParse('h', data(outcome: 'x')), isNull);
      expect(IrrigationRecord.tryParse('h', data(reason: 'x')), isNull);
      expect(IrrigationRecord.tryParse('h', data(seconds: -1)), isNull);
      expect(IrrigationRecord.tryParse('h', {...data(), 'zone': 3}), isNull);
      expect(IrrigationRecord.tryParse('h', {...data(), 'zone': '1'}), isNull);
      expect(IrrigationRecord.tryParse('h', {...data(), 'seconds': 1.5}), isNull);
      expect(IrrigationRecord.tryParse('h', {...data()}..remove('startAt')), isNull);
    });

    test('acepta DateTime además de Timestamp', () {
      final r = IrrigationRecord.tryParse('h', {...data(), 'startAt': DateTime.utc(2026, 10, 21, 12)});
      expect(r, isNotNull);
    });

    test('el estado y el motivo explican cada decisión', () {
      String reason(String outcome, String why, {bool manual = false}) =>
          IrrigationRecord.tryParse('h', data(outcome: outcome, reason: why, manual: manual))!.reasonText;
      String status(String outcome) => IrrigationRecord.tryParse('h', data(outcome: outcome))!.statusLabel;

      expect(reason('done', 'none'), 'Riego programado');
      expect(reason('done', 'none', manual: true), 'Riego manual');
      expect(reason('done', 'dry'), 'Suelo seco: riego completo');
      expect(reason('done', 'sensor'), 'Sensor sin lectura: se regó lo programado');
      expect(reason('reduced', 'near'), 'Reducido a la mitad por humedad');
      expect(reason('skipped', 'wet'), 'Omitido por humedad suficiente');
      expect(reason('postponed', 'rain'), 'Pospuesto por lluvia');
      expect(reason('cancelled', 'rain'), 'Cancelado por lluvia (2 h)');
      expect(reason('failed', 'valve'), 'La válvula no respondió');
      expect([for (final o in IrrigationOutcome.values) status(o.name)],
          ['Completado', 'Reducido', 'Omitido', 'Pospuesto', 'Cancelado', 'Falla']);
    });

    test('solo los riegos completados o reducidos cuentan como agua usada', () {
      for (final o in IrrigationOutcome.values) {
        final r = IrrigationRecord.tryParse('h', data(outcome: o.name))!;
        expect(r.watered, o == IrrigationOutcome.done || o == IrrigationOutcome.reduced, reason: o.name);
      }
    });

    test('formatea la duración: segundos, minutos y horas (valores límite)', () {
      expect(IrrigationRecord.formatDuration(0), '—');
      expect(IrrigationRecord.formatDuration(-5), '—');
      expect(IrrigationRecord.formatDuration(45), '45 s');
      expect(IrrigationRecord.formatDuration(59), '59 s');
      expect(IrrigationRecord.formatDuration(60), '1 min');
      expect(IrrigationRecord.formatDuration(3540), '59 min');
      expect(IrrigationRecord.formatDuration(3600), '1 h 00 min');
      expect(IrrigationRecord.formatDuration(3900), '1 h 05 min');
    });
  });

  group('caudal de la zona', () {
    test('valida el rango de 1 a 30 L/min', () {
      expect(Zones.validateFlow(8), isNull);
      expect(Zones.validateFlow(1), isNull);
      expect(Zones.validateFlow(30), isNull);
      expect(Zones.validateFlow(0.9), isNotNull);
      expect(Zones.validateFlow(30.1), isNotNull);
      expect(Zones.validateFlow(null), isNotNull);
      expect(Zones.validateFlow(double.nan), isNotNull);
    });
  });
}
