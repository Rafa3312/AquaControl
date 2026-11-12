import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/water_stats.dart';
import 'package:irrigation_app/providers/history_provider.dart';

/// Pruebas del historial y las estadísticas (Sprint 8) con Firestore simulado.
void main() {
  late FakeFirebaseFirestore firestore;
  late StreamController<String?> session;
  late HistoryProvider history;

  // Miércoles 21/10/2026 a las 12:00 hora local (= 18:00 UTC)
  final now = DateTime.utc(2026, 10, 21, 18);

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

  Future<void> addRecord(String id, String localIso, int zone, String outcome, int seconds,
      {String reason = 'none'}) {
    final instant = DateTime.parse('${localIso}Z').add(const Duration(hours: 6));
    return firestore.doc('users/u1/history/$id').set({
      'startAt': Timestamp.fromDate(instant),
      'date': localIso.substring(0, 10),
      'zone': zone,
      'outcome': outcome,
      'reason': reason,
      'seconds': seconds,
      'manual': false,
    });
  }

  Future<void> addDay(String date, Map<String, Map<String, int>> zones) =>
      firestore.doc('users/u1/dailyStats/$date').set({'date': date, 'zones': zones});

  setUp(() {
    firestore = FakeFirebaseFirestore();
    session = StreamController<String?>();
    history = HistoryProvider(firestore: firestore, uidChanges: session.stream, clock: () => now);
  });

  tearDown(() async {
    history.dispose();
    await session.close();
  });

  test('sin sesión no hay datos y no se puede guardar el caudal', () async {
    session.add(null);
    await settle();

    expect(history.signedIn, isFalse);
    expect(history.records, isEmpty);
    expect(history.stats.liters, 0);
    expect(await history.setFlow(1, 7.2), 'No hay sesión activa');
  });

  test('carga el historial de la semana, del más reciente al más antiguo', () async {
    // Arrange
    await addRecord('a', '2026-10-21T06:00:00', 1, 'done', 600, reason: 'dry');
    await addRecord('b', '2026-10-20T18:30:00', 2, 'skipped', 0, reason: 'wet');
    await addRecord('c', '2026-10-10T06:00:00', 1, 'done', 600); // fuera de la semana

    // Act
    session.add('u1');
    await settle();

    // Assert
    expect(history.records.map((r) => r.id), ['a', 'b']);
    expect(history.loading, isFalse);
  });

  test('el límite de la semana: 00:00 local del primer día entra, un minuto antes no', () async {
    await addRecord('dentro', '2026-10-15T00:00:00', 1, 'done', 60);
    await addRecord('fuera', '2026-10-14T23:59:00', 1, 'done', 60);

    session.add('u1');
    await settle();

    expect(history.records.map((r) => r.id), ['dentro']);
  });

  test('el filtro de periodo vuelve a consultar (Hoy muestra solo lo de hoy)', () async {
    await addRecord('hoy', '2026-10-21T06:00:00', 1, 'done', 600);
    await addRecord('ayer', '2026-10-20T06:00:00', 1, 'done', 600);
    session.add('u1');
    await settle();
    expect(history.records.length, 2);

    history.setPeriod(HistoryPeriod.today);
    await settle();

    expect(history.period, HistoryPeriod.today);
    expect(history.records.map((r) => r.id), ['hoy']);
  });

  test('cambiar al mismo periodo o a la misma zona no hace nada', () async {
    session.add('u1');
    await settle();
    var notified = 0;
    history.addListener(() => notified++);

    history.setPeriod(HistoryPeriod.week);
    history.setZone(null);

    expect(notified, 0);
  });

  test('el filtro de zona limita la lista y las estadísticas', () async {
    await addRecord('a', '2026-10-21T06:00:00', 1, 'done', 600);
    await addRecord('b', '2026-10-21T18:30:00', 2, 'done', 480);
    await addDay('2026-10-21', {'1': {'runs': 1, 'seconds': 600}, '2': {'runs': 1, 'seconds': 480}});
    session.add('u1');
    await settle();
    expect(history.records.length, 2);
    expect(history.stats.runs, 2);

    history.setZone(2);

    expect(history.zoneFilter, 2);
    expect(history.records.map((r) => r.id), ['b']);
    expect(history.stats.runs, 1);
    expect(history.stats.liters, closeTo(64, 0.001)); // 8 min × 8 L/min
  });

  test('las estadísticas usan los resúmenes diarios y el caudal ajustado', () async {
    await addDay('2026-10-20', {'1': {'runs': 1, 'seconds': 600}});
    await addDay('2026-10-21',
        {'1': {'runs': 1, 'seconds': 600}, '2': {'runs': 1, 'seconds': 480, 'skipped': 2}});
    session.add('u1');
    await settle();

    final nominal = history.stats;
    expect(nominal.runs, 3);
    expect(nominal.skipped, 2);
    expect(nominal.liters, closeTo(160 + 64, 0.001));

    // Act: se mide la zona 1 con la cubeta (7.2 L/min)
    expect(await history.setFlow(1, 7.2), isNull);

    // Assert: los litros se recalculan sin tocar los resúmenes
    expect(history.flowOf(1), 7.2);
    expect(history.stats.liters, closeTo(72 * 2 + 64, 0.001));
  });

  test('el caudal guardado en Firestore se lee al iniciar sesión; los inválidos se ignoran', () async {
    await firestore.doc('users/u1/zones/1').set({'name': 'Jardín', 'flowLpm': 6.8});
    await firestore.doc('users/u1/zones/2').set({'flowLpm': 99});

    session.add('u1');
    await settle();

    expect(history.flowOf(1), 6.8);
    expect(history.flowOf(2), 8.0);
  });

  test('setFlow valida el rango y guarda sin borrar el nombre de la zona', () async {
    await firestore.doc('users/u1/zones/1').set({'name': 'Jardín'});
    session.add('u1');
    await settle();

    expect(await history.setFlow(1, 0.5), isNotNull);
    expect(await history.setFlow(1, 31), isNotNull);
    expect(await history.setFlow(1, null), isNotNull);
    expect(await history.setFlow(3, 8), 'Zona inválida');
    expect(await history.setFlow(1, 7.2), isNull);

    final doc = await firestore.doc('users/u1/zones/1').get();
    expect(doc.data()!['flowLpm'], 7.2);
    expect(doc.data()!['name'], 'Jardín');
  });

  test('los documentos inválidos del historial y de los resúmenes se ignoran', () async {
    await firestore.doc('users/u1/history/mal').set({
      'startAt': Timestamp.fromDate(DateTime.utc(2026, 10, 21, 18)),
      'zone': 7,
      'outcome': 'done',
      'reason': 'none',
      'seconds': 60,
    });
    await firestore
        .doc('users/u1/dailyStats/2026-10-21')
        .set({'date': '2026-10-21', 'zones': {'1': {'runs': 1, 'seconds': 60}}});
    await firestore.doc('users/u1/dailyStats/raro').set({'date': '2026-10-21'});

    session.add('u1');
    await settle();

    expect(history.records, isEmpty);
    expect(history.stats.runs, 1);
  });

  test('al cerrar sesión se borran los datos', () async {
    await addRecord('a', '2026-10-21T06:00:00', 1, 'done', 600);
    session.add('u1');
    await settle();
    expect(history.records, isNotEmpty);

    session.add(null);
    await settle();

    expect(history.records, isEmpty);
    expect(history.signedIn, isFalse);
  });

  test('la lista carga como máximo 200 riegos', () async {
    session.add('u1');
    await settle();
    expect(history.truncated, isFalse);
    expect(HistoryProvider.listLimit, 200);
  });
}
