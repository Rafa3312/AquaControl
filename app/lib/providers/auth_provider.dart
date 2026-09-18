import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth         _firebaseAuth  = FirebaseAuth.instance;
  final LocalAuthentication  _localAuth     = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  User?   _firebaseUser;
  String? _userName;
  String? _deviceId;
  bool    _biometricEnabled = false;
  bool    _loading          = true;

  bool    get isLoggedIn       => _firebaseUser != null;
  bool    get biometricEnabled => _biometricEnabled;
  bool    get loading          => _loading;
  String? get userEmail        => _firebaseUser?.email;
  String? get userName         => _userName ?? _firebaseUser?.displayName;
  String? get deviceId         => _deviceId;
  bool    get hasLinkedDevice  => _deviceId != null && _deviceId!.isNotEmpty;

  AuthProvider() { _init(); }

  Future<void> _init() async {
    final cached = _firebaseAuth.currentUser;

    if (cached != null) {
      // ── FIX: verificar que la cuenta siga existiendo en Firebase ──────────
      // currentUser puede tener un usuario cacheado aunque haya sido eliminado
      // desde la consola. reload() lanza excepción si la cuenta ya no existe.
      try {
        await cached.reload();
        _firebaseUser = _firebaseAuth.currentUser; // refresca el token
        if (_firebaseUser != null) await _loadLocalData();
      } on FirebaseAuthException {
        // Cuenta eliminada o token inválido → limpiar sesión local
        await _firebaseAuth.signOut();
        _firebaseUser = null;
        await _clearLocalSession();
      }
    }

    _loading = false;
    notifyListeners();

    _firebaseAuth.authStateChanges().listen((user) async {
      _firebaseUser = user;
      if (user != null) {
        await _loadLocalData();
      } else {
        _userName         = null;
        _deviceId         = null;
        _biometricEnabled = false;
      }
      notifyListeners();
    });
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _firebaseUser?.uid;
    _userName         = prefs.getString('userName_$uid');
    _deviceId         = prefs.getString('deviceId_$uid');
    _biometricEnabled = prefs.getBool('biometricEnabled_$uid') ?? false;
  }

  Future<void> _clearLocalSession() async {
    final prefs   = await SharedPreferences.getInstance();
    final lastUid = prefs.getString('lastUid');
    if (lastUid != null) {
      await prefs.remove('userName_$lastUid');
      await prefs.remove('deviceId_$lastUid');
      await prefs.remove('biometricEnabled_$lastUid');
    }
    await prefs.remove('lastUid');
    await prefs.remove('lastEmail');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REGISTRO
  // ══════════════════════════════════════════════════════════════════════════
  Future<String?> register({
    required String name,
    required String email,
    required String password,
  }) async {
    if (name.trim().isEmpty) return 'El nombre es requerido';
    if (password.length < 6)  return 'Mínimo 6 caracteres';

    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(), password: password,
      );
      await cred.user?.updateDisplayName(name.trim());
      await cred.user?.reload();
      _firebaseUser = _firebaseAuth.currentUser;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName_${cred.user!.uid}', name.trim());
      _userName = name.trim();

      await _secureStorage.write(key: 'pass_${cred.user!.uid}', value: password);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _firebaseErrorMsg(e.code);
    } catch (e) {
      return 'Error inesperado: $e';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGIN
  // ══════════════════════════════════════════════════════════════════════════
  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(), password: password,
      );
      _firebaseUser = cred.user;
      await _loadLocalData();

      await _secureStorage.write(key: 'pass_${cred.user!.uid}', value: password);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastUid',   cred.user!.uid);
      await prefs.setString('lastEmail', cred.user!.email ?? '');

      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _firebaseErrorMsg(e.code);
    } catch (e) {
      return 'Error inesperado: $e';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OLVIDÉ MI CONTRASEÑA
  // ══════════════════════════════════════════════════════════════════════════
  Future<String?> sendPasswordReset(String email) async {
    if (email.trim().isEmpty || !email.contains('@')) {
      return 'Ingresa un correo válido';
    }
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
      return null; // éxito
    } on FirebaseAuthException catch (e) {
      return _firebaseErrorMsg(e.code);
    } catch (e) {
      return 'Error al enviar el correo: $e';
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BIOMETRÍA
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck    = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _promptBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Confirma tu identidad para entrar a AquaControl',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<String?> biometricLogin() async {
    final prefs     = await SharedPreferences.getInstance();
    final lastUid   = prefs.getString('lastUid');
    final lastEmail = prefs.getString('lastEmail');

    if (lastUid == null || lastEmail == null) {
      return 'No hay cuenta guardada para biometría';
    }

    final password = await _secureStorage.read(key: 'pass_$lastUid');
    if (password == null) {
      return 'Sesión de biometría expirada. Inicia sesión con tu contraseña';
    }

    final ok = await _promptBiometric();
    if (!ok) return 'Autenticación cancelada';

    return login(email: lastEmail, password: password);
  }

  Future<void> enableBiometric() async {
    if (_firebaseUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    _biometricEnabled = true;
    await prefs.setBool('biometricEnabled_${_firebaseUser!.uid}', true);
    await prefs.setString('lastUid',   _firebaseUser!.uid);
    await prefs.setString('lastEmail', _firebaseUser!.email ?? '');
    notifyListeners();
  }

  Future<void> disableBiometric() async {
    if (_firebaseUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    _biometricEnabled = false;
    await prefs.setBool('biometricEnabled_${_firebaseUser!.uid}', false);
    notifyListeners();
  }

  Future<bool> wasBiometricEnabled() async {
    final prefs   = await SharedPreferences.getInstance();
    final lastUid = prefs.getString('lastUid');
    if (lastUid == null) return false;
    return prefs.getBool('biometricEnabled_$lastUid') ?? false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISPOSITIVO
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> linkDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = deviceId;
    await prefs.setString('deviceId_${_firebaseUser?.uid}', deviceId);
    notifyListeners();
  }

  Future<void> unlinkDevice() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = null;
    await prefs.remove('deviceId_${_firebaseUser?.uid}');
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOGOUT
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> logout() async {
    // Conservamos lastUid/lastEmail y la contraseña en SecureStorage
    // para que la biometría siga funcionando en el próximo inicio.
    await _firebaseAuth.signOut();
    _firebaseUser     = null;
    _userName         = null;
    _deviceId         = null;
    _biometricEnabled = false;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILIDADES
  // ══════════════════════════════════════════════════════════════════════════
  String _firebaseErrorMsg(String code) {
    switch (code) {
      case 'email-already-in-use':   return 'El correo ya está registrado';
      case 'invalid-email':          return 'Correo electrónico inválido';
      case 'weak-password':          return 'La contraseña es muy débil';
      case 'user-not-found':         return 'No existe cuenta con ese correo';
      case 'wrong-password':         return 'Contraseña incorrecta';
      case 'invalid-credential':     return 'Correo o contraseña incorrectos';
      case 'too-many-requests':      return 'Demasiados intentos. Intenta más tarde';
      case 'user-disabled':          return 'Esta cuenta ha sido deshabilitada';
      case 'network-request-failed': return 'Sin conexión a internet';
      default:                       return 'Error de autenticación ($code)';
    }
  }
}
