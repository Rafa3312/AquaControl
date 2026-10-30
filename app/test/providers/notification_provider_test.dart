import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/irrigation_notification.dart';
import 'package:irrigation_app/providers/notification_provider.dart';
import 'package:irrigation_app/services/push_messaging.dart';

/// FCM falso: permiso y token configurables, sin Firebase.
class FakePush implements PushMessaging {
  bool permission = true;
  String? token = 'tok-1';
  bool deleted = false;
  final refresh = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> deleteToken() async => deleted = true;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;
}

/// Pruebas de las notificaciones de riego (Sprint 5, HU-8): consentimiento,
/// token FCM y lista de avisos, con Firestore simulado.
void main() {
  late FakeFirebaseFirestore firestore;
  late StreamController<String?> session;
  late FakePush push;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  NotificationProvider build({bool supported = true}) => NotificationProvider(
        firestore: firestore,
        uidChanges: session.stream,
        messaging: push,
        supported: supported,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    session = StreamController<String?>();
    push = FakePush();
  });

  tearDown(() async {
    await session.close();
    await push.refresh.close();
  });

  test('sin sesión no se pueden activar las notificaciones', () async {
    // Arrange
    final provider = build();
    session.add(null);
    await settle();

    // Act
    final error = await provider.enable();
    await provider.disable();
    await provider.remove('x');

    // Assert
    expect(error, 'No hay sesión activa');
    expect(provider.enabled, isFalse);
    expect(provider.items, isEmpty);
    provider.dispose();
  });

  test('lee el consentimiento y los avisos más recientes primero', () async {
    // Arrange
    await firestore.doc('users/u1').set({'notificationsEnabled': true});
    final notifs = firestore.collection('users/u1/notifications');
    await notifs.doc('a').set({
      'type': 'start',
      'zone': 1,
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1, 6)),
    });
    await notifs.doc('b').set({
      'type': 'fail',
      'zone': 2,
      'zoneName': 'Jardín',
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1, 7)),
    });
    await notifs.doc('c').set({
      'type': 'end',
      'zone': 1,
      'source': 'manual',
      'title': 'Fin del riego',
      'body': 'Duró 10 min',
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1, 8)),
    });
    final provider = build();

    // Act
    session.add('u1');
    await settle();

    // Assert
    expect(provider.enabled, isTrue);
    expect(provider.items.map((n) => n.id), ['c', 'b', 'a']);
    expect(provider.failureCount, 1);
    expect(provider.items[0].title, 'Fin del riego');
    expect(provider.items[0].manual, isTrue);
    expect(provider.items[1].kind, NotificationKind.fail);
    expect(provider.items[1].title, 'Falla en Jardín');
    expect(provider.items[2].title, 'Riego iniciado · Zona 1');
    expect(provider.items[2].createdAt, DateTime(2026, 10, 1, 6));
    provider.dispose();
  });

  test('enable guarda primero el consentimiento y luego el token', () async {
    // Arrange
    final provider = build();
    session.add('u1');
    await settle();

    // Act
    final error = await provider.enable();

    // Assert
    expect(error, isNull);
    expect(provider.enabled, isTrue);
    expect(provider.busy, isFalse);
    final profile = await firestore.doc('users/u1').get();
    expect(profile.data()?['notificationsEnabled'], isTrue);
    final token = await firestore.doc('users/u1/fcmTokens/tok-1').get();
    expect(token.exists, isTrue);
    provider.dispose();
  });

  test('si el usuario niega el permiso no se guarda nada', () async {
    // Arrange
    push.permission = false;
    final provider = build();
    session.add('u1');
    await settle();

    // Act
    final error = await provider.enable();

    // Assert
    expect(error, contains('denegado'));
    expect(provider.enabled, isFalse);
    final profile = await firestore.doc('users/u1').get();
    expect(profile.exists, isFalse);
    provider.dispose();
  });

  test('sin token de FCM avisa al usuario', () async {
    // Arrange
    push.token = null;
    final provider = build();
    session.add('u1');
    await settle();

    // Act
    final error = await provider.enable();

    // Assert
    expect(error, 'No se pudo obtener el identificador del teléfono.');
    expect(provider.enabled, isFalse);
    provider.dispose();
  });

  test('en iOS (sin APNs) no se pide permiso', () async {
    // Arrange
    final provider = build(supported: false);
    session.add('u1');
    await settle();

    // Act
    final error = await provider.enable();

    // Assert
    expect(provider.supported, isFalse);
    expect(error, contains('iOS'));
    provider.dispose();
  });

  test('disable borra el token del teléfono y retira el consentimiento', () async {
    // Arrange
    final provider = build();
    session.add('u1');
    await settle();
    await provider.enable();

    // Act
    await provider.disable();

    // Assert
    expect(provider.enabled, isFalse);
    expect(push.deleted, isTrue);
    final token = await firestore.doc('users/u1/fcmTokens/tok-1').get();
    expect(token.exists, isFalse);
    final profile = await firestore.doc('users/u1').get();
    expect(profile.data()?['notificationsEnabled'], isFalse);
    provider.dispose();
  });

  test('si FCM cambia el token se guarda el nuevo solo con consentimiento', () async {
    // Arrange
    final provider = build();
    session.add('u1');
    await settle();

    // Act 1: sin consentimiento el token nuevo no se guarda
    push.refresh.add('tok-sin-permiso');
    await settle();
    // Act 2: con consentimiento sí
    await provider.enable();
    push.refresh.add('tok-2');
    await settle();

    // Assert
    final sinPermiso = await firestore.doc('users/u1/fcmTokens/tok-sin-permiso').get();
    final nuevo = await firestore.doc('users/u1/fcmTokens/tok-2').get();
    expect(sinPermiso.exists, isFalse);
    expect(nuevo.exists, isTrue);
    provider.dispose();
  });

  test('remove borra el aviso de la lista', () async {
    // Arrange
    await firestore.doc('users/u1/notifications/n1').set({
      'type': 'end',
      'zone': 1,
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
    });
    final provider = build();
    session.add('u1');
    await settle();
    expect(provider.items, hasLength(1));

    // Act
    await provider.remove('n1');
    await settle();

    // Assert
    expect(provider.items, isEmpty);
    provider.dispose();
  });
}
