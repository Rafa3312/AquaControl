import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/smart_irrigation.dart';
import 'package:irrigation_app/providers/device_provider.dart';
import 'package:irrigation_app/providers/smart_irrigation_provider.dart';

/// ESP32 falso: guarda la configuración que recibe y puede rechazarla.
class FakeDevice extends ChangeNotifier implements DeviceProvider {
  bool connected = true;
  bool accepts = true;
  final List<String> sent = [];

  @override
  bool get isConnected => connected;

  @override
  Future<bool> setSmart({
    required int zone,
    required bool enabled,
    required int threshold,
  }) async {
    sent.add('zona $zone: $enabled, $threshold%');
    return accepts;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pruebas de la configuración del riego inteligente (Sprint 6, HU-10):
/// validación del umbral, envío al ESP32 y respaldo en Firestore.
void main() {
  late FakeFirebaseFirestore firestore;
  late StreamController<String?> session;
  late FakeDevice device;
  late SmartIrrigationProvider smart;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() {
    firestore = FakeFirebaseFirestore();
    session = StreamController<String?>();
    device = FakeDevice();
    smart = SmartIrrigationProvider(firestore: firestore, uidChanges: session.stream)
      ..setDeviceProvider(device);
  });

  tearDown(() async {
    smart.dispose();
    await session.close();
  });

  test('sin configuración guardada el riego inteligente está apagado con umbral de 60%', () async {
    // Arrange
    session.add('u1');
    await settle();

    // Act
    final settings = smart.settingsFor(1);

    // Assert
    expect(settings.enabled, isFalse);
    expect(settings.threshold, SmartSettings.defaultThreshold);
  });

  test('al iniciar sesión lee la configuración de cada zona e ignora datos inválidos', () async {
    // Arrange
    await firestore.doc('users/u1/zones/1').set({'smartEnabled': true, 'threshold': 45});
    await firestore.doc('users/u1/zones/2').set({'smartEnabled': true, 'threshold': 150});
    await firestore.doc('users/u1/zones/7').set({'smartEnabled': true, 'threshold': 30});

    // Act
    session.add('u1');
    await settle();

    // Assert
    expect(smart.settingsFor(1).threshold, 45);
    expect(smart.settingsFor(2).enabled, isTrue);
    expect(smart.settingsFor(2).threshold, SmartSettings.defaultThreshold);
  });

  test('un umbral fuera de 10% a 90% se rechaza sin contactar al ESP32', () async {
    // Arrange
    session.add('u1');
    await settle();

    // Act
    final bajo = await smart.update(1, enabled: true, threshold: 9);
    final alto = await smart.update(1, enabled: true, threshold: 91);
    final zona = await smart.update(3, enabled: true);

    // Assert
    expect(bajo, 'El umbral debe estar entre 10% y 90%');
    expect(alto, 'El umbral debe estar entre 10% y 90%');
    expect(zona, 'Zona inválida');
    expect(device.sent, isEmpty);
  });

  test('sin sesión o sin programador conectado no se guarda nada', () async {
    // Arrange
    session.add(null);
    await settle();

    // Act
    final sinSesion = await smart.update(1, enabled: true);
    session.add('u1');
    await settle();
    device.connected = false;
    final sinEquipo = await smart.update(1, enabled: true);

    // Assert
    expect(sinSesion, 'No hay sesión activa');
    expect(sinEquipo, contains('Conéctate al programador'));
    expect(device.sent, isEmpty);
  });

  test('update envía la configuración al ESP32 y la respalda sin borrar el nombre', () async {
    // Arrange: la zona ya tenía nombre (Sprint 5)
    await firestore.doc('users/u1/zones/2').set({'name': 'Huerto'});
    session.add('u1');
    await settle();

    // Act
    final error = await smart.update(2, enabled: true, threshold: 55);

    // Assert
    expect(error, isNull);
    expect(device.sent, ['zona 2: true, 55%']);
    expect(smart.settingsFor(2).enabled, isTrue);
    expect(smart.saving, isFalse);
    final doc = await firestore.doc('users/u1/zones/2').get();
    expect(doc.data()?['name'], 'Huerto');
    expect(doc.data()?['smartEnabled'], isTrue);
    expect(doc.data()?['threshold'], 55);
  });

  test('si el ESP32 rechaza la configuración no se guarda en Firestore', () async {
    // Arrange: firmware anterior a la v3.3 (no conoce /smart)
    device.accepts = false;
    session.add('u1');
    await settle();

    // Act
    final error = await smart.update(1, enabled: true);

    // Assert
    expect(error, contains('firmware v3.3'));
    expect(smart.settingsFor(1).enabled, isFalse);
    final doc = await firestore.doc('users/u1/zones/1').get();
    expect(doc.exists, isFalse);
  });

  test('preview aplica la configuración de la zona a una lectura', () async {
    // Arrange: zona 1 con riego inteligente y umbral de 60%
    session.add('u1');
    await settle();
    await smart.update(1, enabled: true, threshold: 60);
    const humedo = MoistureReading(valid: true, percent: 70);

    // Act
    final zona1 = smart.preview(1, humedo, 10);
    final zona2 = smart.preview(2, humedo, 10); // zona 2 sin riego inteligente

    // Assert
    expect(zona1.action, SmartAction.skip);
    expect(zona1.message, 'Omitido por humedad suficiente');
    expect(zona2.action, SmartAction.full);
    expect(zona2.minutes, 10);
  });

  test('al cerrar sesión se olvida la configuración', () async {
    // Arrange
    await firestore.doc('users/u1/zones/1').set({'smartEnabled': true, 'threshold': 40});
    session.add('u1');
    await settle();

    // Act
    session.add(null);
    await settle();

    // Assert
    expect(smart.settingsFor(1).enabled, isFalse);
  });
}
