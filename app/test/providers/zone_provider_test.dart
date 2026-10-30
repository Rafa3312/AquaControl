import 'dart:async';
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/providers/zone_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pruebas de los nombres de zona (Sprint 5, HU-7) con Firestore simulado.
void main() {
  late FakeFirebaseFirestore firestore;
  late StreamController<String?> session;
  late ZoneProvider zones;

  // Deja que terminen las lecturas asíncronas (caché y Firestore)
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    firestore = FakeFirebaseFirestore();
    session = StreamController<String?>();
    zones = ZoneProvider(firestore: firestore, uidChanges: session.stream);
  });

  tearDown(() async {
    zones.dispose();
    await session.close();
  });

  test('sin sesión se usan los nombres por defecto y no se puede renombrar', () async {
    // Arrange
    session.add(null);
    await settle();

    // Act
    final error = await zones.rename(1, 'Jardín');

    // Assert
    expect(zones.nameOf(1), 'Zona 1');
    expect(error, 'No hay sesión activa');
  });

  test('al iniciar sesión lee los nombres de Firestore e ignora datos inválidos', () async {
    // Arrange
    await firestore.doc('users/u1/zones/2').set({'name': 'Jardín'});
    await firestore.doc('users/u1/zones/9').set({'name': 'No existe'});
    await firestore.doc('users/u1/zones/1').set({'name': 42});

    // Act
    session.add('u1');
    await settle();

    // Assert
    expect(zones.nameOf(1), 'Zona 1');
    expect(zones.nameOf(2), 'Jardín');
  });

  test('muestra la caché local aunque Firestore no tenga datos', () async {
    // Arrange: nombre guardado en el teléfono de una sesión anterior
    SharedPreferences.setMockInitialValues({
      'zoneNames_u1': jsonEncode({'1': 'Huerto'}),
    });

    // Act
    session.add('u1');
    await settle();

    // Assert
    expect(zones.nameOf(1), 'Huerto');
  });

  test('rename valida el nombre y la zona antes de guardar', () async {
    // Arrange
    session.add('u1');
    await settle();

    // Act
    final vacio = await zones.rename(1, '   ');
    final largo = await zones.rename(1, 'x' * 31);
    final zonaMala = await zones.rename(3, 'Patio');

    // Assert
    expect(vacio, 'Escribe un nombre para la zona');
    expect(largo, 'Máximo 30 caracteres');
    expect(zonaMala, 'Zona inválida');
  });

  test('rename guarda el nombre limpio en Firestore y en la caché', () async {
    // Arrange
    session.add('u1');
    await settle();

    // Act
    final error = await zones.rename(2, '  Pasto  ');

    // Assert
    expect(error, isNull);
    expect(zones.nameOf(2), 'Pasto');
    final doc = await firestore.doc('users/u1/zones/2').get();
    expect(doc.data()?['name'], 'Pasto');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('zoneNames_u1'), contains('Pasto'));
  });

  test('al cerrar sesión se vuelve a los nombres por defecto', () async {
    // Arrange
    await firestore.doc('users/u1/zones/1').set({'name': 'Frente'});
    session.add('u1');
    await settle();
    expect(zones.nameOf(1), 'Frente');

    // Act
    session.add(null);
    await settle();

    // Assert
    expect(zones.nameOf(1), 'Zona 1');
  });
}
