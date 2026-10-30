import 'dart:async';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/irrigation_notification.dart';

/// Avisos de inicio, fin y falla del riego (HU-8).
///
/// - Consentimiento: el usuario activa las notificaciones de forma explícita;
///   hasta entonces no se pide permiso ni se guarda su token FCM.
/// - Token FCM: se guarda en users/{uid}/fcmTokens/{token} solo con
///   consentimiento (lo exigen también las reglas de Firestore).
/// - Lista: lee users/{uid}/notifications, que escribe la Cloud Function.
class NotificationProvider extends ChangeNotifier {
  final _firestore = FirebaseFirestore.instance;

  bool    _enabled = false;
  bool    _busy    = false;
  String? _uid;
  List<IrrigationNotification> _items = [];

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _listSub;
  StreamSubscription<String>? _tokenSub;

  bool get enabled => _enabled;
  bool get busy    => _busy;
  List<IrrigationNotification> get items => List.unmodifiable(_items);
  int  get failureCount => _items.where((n) => n.isFailure).length;

  /// En iOS FCM necesita una clave APNs de una cuenta de Apple Developer de
  /// paga, que el equipo no tiene (pendiente del Sprint 5 → Sprint 6).
  bool get supported => !Platform.isIOS;

  NotificationProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  Future<void> _onUser(User? user) async {
    await _listSub?.cancel();
    await _tokenSub?.cancel();
    _uid = user?.uid;
    _items = [];
    _enabled = false;
    notifyListeners();
    if (user == null) return;

    try {
      final profile = await _firestore.doc('users/${user.uid}').get();
      _enabled = profile.data()?['notificationsEnabled'] == true;
    } catch (e) {
      debugPrint('[Avisos] No se pudo leer el consentimiento: $e');
    }

    _listSub = _firestore
        .collection('users/${user.uid}/notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snap) {
            _items = snap.docs
                .map((d) => IrrigationNotification.fromMap(d.id, d.data()))
                .toList();
            notifyListeners();
          },
          onError: (e) => debugPrint('[Avisos] Error al escuchar avisos: $e'),
        );

    // Si FCM cambia el token, se reemplaza el guardado (solo con consentimiento)
    if (supported) {
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        if (_enabled) _saveToken(token);
      });
    }
    notifyListeners();
  }

  /// Activa las notificaciones tras el consentimiento del usuario.
  /// Devuelve un mensaje de error o null si todo salió bien.
  Future<String?> enable() async {
    final uid = _uid;
    if (uid == null) return 'No hay sesión activa';
    if (!supported) {
      return 'Las notificaciones push en iOS aún no están disponibles.';
    }
    _setBusy(true);
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return 'Permiso de notificaciones denegado. Actívalo en los ajustes del teléfono.';
      }

      // Primero el consentimiento: las reglas no aceptan un token sin él
      await _firestore.doc('users/$uid').set({
        'notificationsEnabled': true,
        'consentAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return 'No se pudo obtener el identificador del teléfono.';
      await _saveToken(token);

      _enabled = true;
      return null;
    } catch (e) {
      debugPrint('[Avisos] Error al activar: $e');
      return 'No se pudieron activar las notificaciones. Revisa tu conexión.';
    } finally {
      _setBusy(false);
    }
  }

  /// Retira el consentimiento: borra el token de este teléfono.
  Future<void> disable() async {
    final uid = _uid;
    if (uid == null) return;
    _setBusy(true);
    try {
      if (supported) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await _firestore.doc('users/$uid/fcmTokens/$token').delete();
        }
        await FirebaseMessaging.instance.deleteToken();
      }
      await _firestore.doc('users/$uid').set({
        'notificationsEnabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _enabled = false;
    } catch (e) {
      debugPrint('[Avisos] Error al desactivar: $e');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> remove(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _firestore.doc('users/$uid/notifications/$id').delete();
  }

  Future<void> _saveToken(String token) async {
    final uid = _uid;
    if (uid == null) return;
    await _firestore.doc('users/$uid/fcmTokens/$token').set({
      'platform': Platform.isIOS ? 'ios' : 'android',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _listSub?.cancel();
    _tokenSub?.cancel();
    super.dispose();
  }
}
