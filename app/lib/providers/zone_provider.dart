import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/zone.dart';

/// Nombres de las zonas de riego del usuario.
/// Se guardan en Firestore (users/{uid}/zones/{id}) y en caché local para
/// mostrarlos aunque no haya internet.
class ZoneProvider extends ChangeNotifier {
  final _firestore = FirebaseFirestore.instance;
  final Map<int, String> _names = {};
  StreamSubscription<User?>? _authSub;
  String? _uid;

  ZoneProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  String nameOf(int id) => _names[id] ?? Zones.defaultName(id);

  Future<void> _onUser(User? user) async {
    _uid = user?.uid;
    _names.clear();
    notifyListeners();
    if (user == null) return;

    // 1. Caché local (inmediato)
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey(user.uid));
    if (cached != null) {
      final map = jsonDecode(cached) as Map<String, dynamic>;
      map.forEach((k, v) => _names[int.parse(k)] = v as String);
      notifyListeners();
    }

    // 2. Firestore (fuente de verdad)
    try {
      final snap = await _firestore.collection('users/${user.uid}/zones').get();
      for (final doc in snap.docs) {
        final id = int.tryParse(doc.id);
        final name = doc.data()['name'];
        if (id != null && Zones.isValid(id) && name is String) _names[id] = name;
      }
      await _saveCache();
      notifyListeners();
    } catch (e) {
      debugPrint('[Zonas] No se pudieron leer los nombres: $e');
    }
  }

  /// Cambia el nombre de una zona. Devuelve un mensaje de error o null.
  Future<String?> rename(int id, String name) async {
    final error = Zones.validateName(name);
    if (error != null) return error;
    if (!Zones.isValid(id)) return 'Zona inválida';
    final uid = _uid;
    if (uid == null) return 'No hay sesión activa';

    try {
      await _firestore.doc('users/$uid/zones/$id').set({
        'name': name.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      return 'No se pudo guardar el nombre. Revisa tu conexión.';
    }
    _names[id] = name.trim();
    await _saveCache();
    notifyListeners();
    return null;
  }

  String _cacheKey(String uid) => 'zoneNames_$uid';

  Future<void> _saveCache() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(uid),
      jsonEncode(_names.map((k, v) => MapEntry('$k', v))),
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
