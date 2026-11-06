import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/smart_irrigation.dart';
import '../models/zone.dart';
import 'device_provider.dart';

/// Configuración del riego inteligente por zona (Sprint 6, HU-10).
///
/// El ESP32 es quien decide al momento de regar, así que primero se le envía
/// la configuración y, solo si la acepta, se guarda en Firestore
/// (users/{uid}/zones/{id}) para recuperarla al reinstalar la app.
class SmartIrrigationProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final Map<int, SmartSettings> _settings = {};
  StreamSubscription<String?>? _authSub;
  DeviceProvider? _device;
  String? _uid;
  bool _saving = false;

  /// [firestore] y [uidChanges] se inyectan en las pruebas; en la app se usan
  /// Firestore y la sesión de Firebase Auth.
  SmartIrrigationProvider({
    FirebaseFirestore? firestore,
    Stream<String?>? uidChanges,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _authSub = (uidChanges ??
            FirebaseAuth.instance.authStateChanges().map((u) => u?.uid))
        .listen(_onUser);
  }

  bool get saving => _saving;

  SmartSettings settingsFor(int zone) => _settings[zone] ?? const SmartSettings();

  void setDeviceProvider(DeviceProvider device) => _device = device;

  /// Qué pasaría si la programación de la zona arrancara ahora mismo.
  SmartDecision preview(int zone, MoistureReading reading, int minutes) =>
      SmartDecision.decide(
        settings: settingsFor(zone),
        reading: reading,
        minutes: minutes,
      );

  Future<void> _onUser(String? uid) async {
    _uid = uid;
    _settings.clear();
    notifyListeners();
    if (uid == null) return;

    try {
      final snap = await _firestore.collection('users/$uid/zones').get();
      for (final doc in snap.docs) {
        final id = int.tryParse(doc.id);
        if (id != null && Zones.isValid(id)) {
          _settings[id] = SmartSettings.fromMap(doc.data());
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Riego inteligente] No se pudo leer la configuración: $e');
    }
  }

  /// Cambia la configuración de una zona. Devuelve un mensaje de error o null.
  Future<String?> update(int zone, {bool? enabled, int? threshold}) async {
    if (!Zones.isValid(zone)) return 'Zona inválida';
    final next = settingsFor(zone).copyWith(enabled: enabled, threshold: threshold);
    final error = SmartSettings.validateThreshold(next.threshold);
    if (error != null) return error;

    final uid = _uid;
    if (uid == null) return 'No hay sesión activa';
    final device = _device;
    if (device == null || !device.isConnected) {
      return 'Conéctate al programador para cambiar el riego inteligente';
    }

    _setSaving(true);
    try {
      final ok = await device.setSmart(
        zone: zone,
        enabled: next.enabled,
        threshold: next.threshold,
      );
      if (!ok) {
        return 'El programador no aceptó el cambio. Revisa que tenga el firmware v3.3.';
      }
      await _firestore.doc('users/$uid/zones/$zone').set({
        ...next.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _settings[zone] = next;
      return null;
    } catch (e) {
      debugPrint('[Riego inteligente] Error al guardar: $e');
      return 'No se pudo guardar la configuración. Revisa tu conexión.';
    } finally {
      _setSaving(false);
    }
  }

  void _setSaving(bool value) {
    _saving = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
