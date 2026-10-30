import 'package:firebase_messaging/firebase_messaging.dart';

/// Lo que NotificationProvider necesita del servicio de push. Se separa de
/// FirebaseMessaging para poder probar el provider sin Firebase.
abstract class PushMessaging {
  /// Pide permiso al usuario; devuelve false si lo negó.
  Future<bool> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
}

/// Implementación real con Firebase Cloud Messaging.
class FcmMessaging implements PushMessaging {
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  @override
  Future<bool> requestPermission() async {
    final settings = await _fcm.requestPermission();
    return settings.authorizationStatus != AuthorizationStatus.denied;
  }

  @override
  Future<String?> getToken() => _fcm.getToken();

  @override
  Future<void> deleteToken() => _fcm.deleteToken();

  @override
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;
}
