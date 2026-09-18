import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';
import '../main_screen.dart';
import '../auth/device_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure       = true;
  bool _loading       = false;
  bool _bioAvailable  = false;  // hardware disponible
  bool _bioEnabled    = false;  // usuario lo activó antes
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  /// Verifica hardware Y si el usuario anterior activó la biometría.
  /// Se llama en initState y también al regresar de registro.
  Future<void> _checkBiometric() async {
    final auth = context.read<AuthProvider>();
    final hwOk     = await auth.isBiometricAvailable();
    final wasOn    = await auth.wasBiometricEnabled();
    if (mounted) {
      setState(() {
        _bioAvailable = hwOk;
        _bioEnabled   = wasOn;
      });
    }
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    final auth = context.read<AuthProvider>();
    final err = await auth.login(
      email:    _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!mounted) return;
    setState(() { _loading = false; _error = err; });
    if (err == null) _goNext(auth);
  }

  Future<void> _biometricLogin() async {
    setState(() { _loading = true; _error = null; });
    final auth = context.read<AuthProvider>();
    final err  = await auth.biometricLogin();
    if (!mounted) return;
    setState(() { _loading = false; _error = err; });
    if (err == null) _goNext(auth);
  }


  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    String? result;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Recuperar contraseña',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Te enviaremos un correo para restablecer tu contraseña.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              if (result != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: result!.startsWith('✓')
                        ? AppTheme.success.withOpacity(0.12)
                        : AppTheme.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(result!,
                      style: TextStyle(
                        color: result!.startsWith('✓')
                            ? AppTheme.success
                            : AppTheme.danger,
                        fontSize: 12,
                      )),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final auth = context.read<AuthProvider>();
                final err  = await auth.sendPasswordReset(ctrl.text);
                setDialogState(() {
                  result = err == null
                      ? '✓ Correo enviado. Revisa tu bandeja de entrada.'
                      : err;
                });
                if (err == null) await Future.delayed(const Duration(seconds: 2));
                if (ctx.mounted && err == null) Navigator.pop(ctx);
              },
              child: const Text('Enviar correo'),
            ),
          ],
        ),
      ),
    );
  }

  void _goNext(AuthProvider auth) {
    final dest = auth.hasLinkedDevice
        ? const MainScreen()
        : const DeviceSetupScreen(isOnboarding: true);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => dest),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // ── Marca ────────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppTheme.accent, AppTheme.primary],
                      ),
                    ),
                    child: const Icon(Icons.water_drop_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Text('AquaControl',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),

              const SizedBox(height: 48),

              const Text(
                'Bienvenido\nde vuelta',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Inicia sesión para controlar tu riego',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
              ),

              const SizedBox(height: 40),

              // ── Error ─────────────────────────────────────────────────────
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppTheme.danger, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppTheme.danger, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── Campos ────────────────────────────────────────────────────
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: AppTheme.textPrimary),
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ── Olvidé contraseña ─────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  ),
                  child: const Text(
                    '¿Olvidaste tu contraseña?',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Botón login ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Iniciar sesión'),
                ),
              ),

              // ── Botón huella ──────────────────────────────────────────────
              // Aparece solo si el hardware está disponible Y el usuario
              // había activado biometría en su cuenta.
              if (_bioAvailable && _bioEnabled) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _biometricLogin,
                    icon: const Icon(Icons.fingerprint,
                        color: AppTheme.primary, size: 24),
                    label: const Text('Entrar con huella digital',
                        style: TextStyle(color: AppTheme.primary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppTheme.primary, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],

              // Si el hw está disponible pero biometría no está activada,
              // mostrar un aviso sutil.
              if (_bioAvailable && !_bioEnabled) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Activa la huella desde Registrarte → opciones',
                    style: TextStyle(
                        color: AppTheme.textMuted.withOpacity(0.7),
                        fontSize: 12),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // ── Registro ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('¿Primera vez? ',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  TextButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen()),
                      );
                      // Al volver del registro, re-verificar biometría
                      _checkBiometric();
                    },
                    child: const Text('Crear cuenta'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
