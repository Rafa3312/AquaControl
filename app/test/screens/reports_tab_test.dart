import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/providers/history_provider.dart';
import 'package:irrigation_app/providers/zone_provider.dart';
import 'package:irrigation_app/screens/reports/reports_tab.dart';
import 'package:irrigation_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prueba de humo de Reportes (Sprint 8): la pantalla dibuja el historial, las
/// tarjetas y la gráfica sin errores de layout, y los filtros responden.
void main() {
  late FakeFirebaseFirestore firestore;
  late StreamController<String?> session;
  late HistoryProvider history;
  late ZoneProvider zones;

  // Miércoles 21/10/2026 a las 12:00 hora local (= 18:00 UTC)
  final now = DateTime.utc(2026, 10, 21, 18);

  Future<void> addRecord(String id, String localIso, int zone, String outcome, int seconds, String reason) {
    final instant = DateTime.parse('${localIso}Z').add(const Duration(hours: 6));
    return firestore.doc('users/u1/history/$id').set({
      'startAt': Timestamp.fromDate(instant),
      'zone': zone,
      'outcome': outcome,
      'reason': reason,
      'seconds': seconds,
      'manual': false,
    });
  }

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HistoryProvider>.value(value: history),
          ChangeNotifierProvider<ZoneProvider>.value(value: zones),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const ReportsTab()),
      ),
    );
    session.add('u1');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    firestore = FakeFirebaseFirestore();
    session = StreamController<String?>.broadcast();
    history = HistoryProvider(firestore: firestore, uidChanges: session.stream, clock: () => now);
    zones = ZoneProvider(firestore: firestore, uidChanges: session.stream);
  });

  tearDown(() async {
    history.dispose();
    zones.dispose();
    await session.close();
  });

  testWidgets('sin registros muestra el estado vacío y la gráfica sin consumo', (tester) async {
    await pumpTab(tester);

    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Sin registros en este periodo'), findsOneWidget);
    expect(find.text('Sin consumo en este periodo'), findsOneWidget);
    expect(find.text('0.0 L'), findsOneWidget);
  });

  testWidgets('muestra cada riego con su zona, estado y motivo, y las tarjetas', (tester) async {
    // Arrange
    await addRecord('a', '2026-10-21T06:00:00', 1, 'done', 600, 'dry');
    await addRecord('b', '2026-10-20T18:30:00', 2, 'skipped', 0, 'wet');
    await addRecord('c', '2026-10-20T06:00:00', 1, 'cancelled', 0, 'rain');
    await firestore.doc('users/u1/zones/1').set({'name': 'Jardín'});
    await firestore.doc('users/u1/dailyStats/2026-10-21').set({
      'date': '2026-10-21',
      'zones': {'1': {'runs': 1, 'seconds': 600}},
    });

    // Act
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpTab(tester);

    // Assert
    expect(find.text('Completado'), findsOneWidget);
    expect(find.text('Omitido'), findsOneWidget);
    expect(find.text('Cancelado'), findsOneWidget);
    expect(find.textContaining('Suelo seco: riego completo'), findsOneWidget);
    expect(find.textContaining('Omitido por humedad suficiente'), findsOneWidget);
    expect(find.textContaining('Cancelado por lluvia'), findsOneWidget);
    expect(find.text('21/10/2026 · 06:00'), findsOneWidget);
    expect(find.text('80.0 L'), findsOneWidget); // 10 min × 8 L/min
    expect(find.text('10 min'), findsWidgets);
    expect(find.text('Jardín'), findsWidgets);
    expect(find.text('Sin consumo en este periodo'), findsNothing);
  });

  testWidgets('los filtros de periodo y zona cambian lo que se ve', (tester) async {
    await addRecord('hoy', '2026-10-21T06:00:00', 1, 'done', 600, 'dry');
    await addRecord('ayer', '2026-10-20T18:30:00', 2, 'skipped', 0, 'wet');
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpTab(tester);
    expect(find.text('Omitido'), findsOneWidget);

    // Hoy: solo el riego de hoy
    await tester.tap(find.text('Hoy'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Omitido'), findsNothing);
    expect(find.text('Completado'), findsOneWidget);

    // Año y zona 2: no hay riegos de la zona 2 hoy ni este periodo con agua
    await tester.tap(find.text('Año'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.tap(find.text('Zona 2').first);
    await tester.pump();
    expect(find.text('Completado'), findsNothing);
    expect(find.text('Omitido'), findsOneWidget);
  });

  testWidgets('Ajustar caudal abre el diálogo y guarda el valor medido', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpTab(tester);

    await tester.tap(find.text('Ajustar caudal'));
    await tester.pumpAndSettle();
    expect(find.text('Caudal de cada zona'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('flow-1')), '7,2');
    await tester.tap(find.text('Guardar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(history.flowOf(1), 7.2);
    expect(history.flowOf(2), 8.0);
  });

  testWidgets('un caudal fuera de rango muestra el error y no se guarda', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpTab(tester);

    await tester.tap(find.text('Ajustar caudal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('flow-1')), '99');
    await tester.tap(find.text('Guardar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.textContaining('El caudal debe estar entre 1 y 30'), findsOneWidget);
    expect(history.flowOf(1), 8.0);
  });

  testWidgets('el menú carga datos de demostración y se puede salir', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpTab(tester);
    expect(find.textContaining('Modo demostración'), findsNothing);

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cargar datos de demostración'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Modo demostración'), findsOneWidget);
    expect(find.text('Sin registros en este periodo'), findsNothing);
    expect(find.text('Sin consumo en este periodo'), findsNothing);
    expect(history.demo, isTrue);

    await tester.tap(find.text('Salir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Modo demostración'), findsNothing);
    expect(history.demo, isFalse);
  });
}
