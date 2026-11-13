import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/irrigation_record.dart';
import 'package:irrigation_app/models/water_stats.dart';
import 'package:irrigation_app/providers/history_provider.dart';
import 'package:irrigation_app/utils/demo_history.dart';
import 'package:irrigation_app/utils/local_time.dart';

/// Datos simulados de la demostración del Sprint 8 y su modo en el provider.
void main() {
  // Miércoles 21/10/2026 a las 12:00 hora local (= 18:00 UTC)
  final now = DateTime.utc(2026, 10, 21, 18);

  group('generador', () {
    test('es determinista: la misma semilla produce los mismos datos', () {
      final a = DemoHistory.generate(now: now, seed: 3);
      final b = DemoHistory.generate(now: now, seed: 3);
      expect(a.records.map((r) => r.startAt), b.records.map((r) => r.startAt));
      expect(a.records.map((r) => r.outcome), b.records.map((r) => r.outcome));
      expect(DemoHistory.generate(now: now, seed: 4).records.map((r) => r.outcome),
          isNot(a.records.map((r) => r.outcome)));
    });

    test('cubre 6 meses, sin riegos futuros y del más reciente al más antiguo', () {
      final d = DemoHistory.generate(now: now);
      expect(d.records.length, greaterThan(350));
      expect(d.records.every((r) => !r.startAt.isAfter(now)), isTrue);
      for (var i = 1; i < d.records.length; i++) {
        expect(d.records[i - 1].startAt.isBefore(d.records[i].startAt), isFalse);
      }
      final first = localDay(d.records.last.startAt);
      expect(localDay(now).difference(first).inDays, inInclusiveRange(180, 183));
    });

    test('incluye todos los estados, riegos manuales y uno de las 23:30', () {
      final d = DemoHistory.generate(now: now);
      expect(d.records.map((r) => r.outcome).toSet(), IrrigationOutcome.values.toSet());
      expect(d.records.any((r) => r.manual), isTrue);
      expect(d.records.any((r) => r.local.hour == 23 && r.local.minute == 30), isTrue);
    });

    test('cada riego cancelado por lluvia queda antes pospuesto, 2 h antes', () {
      final d = DemoHistory.generate(now: now);
      final cancelled = d.records.where((r) => r.outcome == IrrigationOutcome.cancelled);
      expect(cancelled, isNotEmpty);
      for (final c in cancelled) {
        final postponed = d.records.where((r) =>
            r.outcome == IrrigationOutcome.postponed &&
            r.zone == c.zone &&
            c.startAt.difference(r.startAt) == const Duration(hours: 2));
        expect(postponed.length, 1);
      }
    });

    test('los resúmenes diarios cuadran con los riegos (mismas reglas que la nube)', () {
      final d = DemoHistory.generate(now: now);
      final watered = d.records.where((r) => r.watered).toList();
      final runs = d.days.fold<int>(0, (a, day) => a + day.zones.values.fold(0, (b, z) => b + z.runs));
      final seconds = d.days.fold<int>(0, (a, day) => a + day.zones.values.fold(0, (b, z) => b + z.seconds));
      final skipped = d.days.fold<int>(0, (a, day) => a + day.zones.values.fold(0, (b, z) => b + z.skipped));
      expect(runs, watered.length);
      expect(seconds, watered.fold<int>(0, (a, r) => a + r.seconds));
      expect(
          skipped,
          d.records
              .where((r) => r.outcome == IrrigationOutcome.skipped || r.outcome == IrrigationOutcome.cancelled)
              .length);
    });

    test('un riego de las 23:30 cuenta en su día local en el resumen', () {
      final d = DemoHistory.generate(now: now);
      final late = d.records.firstWhere((r) => r.local.hour == 23 && r.local.minute == 30 && r.watered);
      final day = d.days.firstWhere((x) => x.date == dayKey(localDay(late.startAt)));
      expect(day.zones[late.zone]!.runs, greaterThan(0));
    });

    test('la semilla 0 también funciona y un mes genera menos riegos', () {
      expect(DemoHistory.generate(now: now, seed: 0).records, isNotEmpty);
      expect(DemoHistory.generate(now: now, months: 1).records.length,
          lessThan(DemoHistory.generate(now: now, months: 6).records.length));
    });
  });

  group('modo demostración del provider', () {
    late FakeFirebaseFirestore firestore;
    late StreamController<String?> session;
    late HistoryProvider history;

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

    setUp(() {
      firestore = FakeFirebaseFirestore();
      session = StreamController<String?>();
      history = HistoryProvider(firestore: firestore, uidChanges: session.stream, clock: () => now);
    });

    tearDown(() async {
      history.dispose();
      await session.close();
    });

    test('al activarlo muestra riegos y consumo de la semana sin tocar Firestore', () async {
      session.add('u1');
      await settle();
      expect(history.records, isEmpty);

      history.enableDemo();

      expect(history.demo, isTrue);
      expect(history.records, isNotEmpty);
      expect(history.stats.liters, greaterThan(0));
      expect(history.stats.runs, greaterThan(5));
      expect(history.stats.bars.length, 7);
      expect((await firestore.collection('users/u1/history').get()).size, 0);
    });

    test('los periodos filtran los datos simulados (Hoy < Semana < Mes < Año)', () async {
      session.add('u1');
      await settle();
      history.enableDemo();

      final runs = <int>[];
      for (final p in HistoryPeriod.values) {
        history.setPeriod(p);
        runs.add(history.stats.runs);
      }

      expect(runs[0], lessThan(runs[1]));
      expect(runs[1], lessThan(runs[2]));
      expect(runs[2], lessThan(runs[3]));
      expect(history.records.length, HistoryProvider.listLimit); // el año llega al límite de la lista
      expect(history.truncated, isTrue);
    });

    test('el filtro de zona y el caudal ajustado funcionan en demostración', () async {
      session.add('u1');
      await settle();
      history.enableDemo();
      history.setPeriod(HistoryPeriod.month);

      final all = history.stats.liters;
      history.setZone(2);
      expect(history.records.every((r) => r.zone == 2), isTrue);
      expect(history.stats.liters, lessThan(all));

      final before = history.stats.liters;
      expect(await history.setFlow(2, 16), isNull);
      expect(history.stats.liters, closeTo(before * 2, 0.001));
      expect(await history.setFlow(2, 99), isNotNull);
      // el caudal de la demostración no se guarda en Firestore
      expect((await firestore.doc('users/u1/zones/2').get()).exists, isFalse);
    });

    test('al salir vuelve a los datos reales y al cerrar sesión se descarta', () async {
      final instant = DateTime.utc(2026, 10, 21, 12);
      await firestore.doc('users/u1/history/real').set({
        'startAt': instant,
        'zone': 1,
        'outcome': 'done',
        'reason': 'none',
        'seconds': 600,
        'manual': false,
      });
      session.add('u1');
      await settle();
      history.enableDemo();
      expect(history.records.any((r) => r.id == 'real'), isFalse);

      history.disableDemo();
      await settle();
      expect(history.demo, isFalse);
      expect(history.records.map((r) => r.id), ['real']);

      history.enableDemo();
      session.add(null);
      await settle();
      expect(history.demo, isFalse);
      expect(history.records, isEmpty);

      history.disableDemo(); // sin demostración activa no hace nada
      expect(history.demo, isFalse);
    });
  });
}
