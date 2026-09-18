import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../auth/device_setup_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _obscure   = true;
  bool _obscure2  = true;
  bool _loading   = false;
  bool _enableBio = false;
  bool _bioHwOk   = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBioHardware();
  }

  Future<void> _checkBioHardware() async {
    final ok = await context.read<AuthProvider>().isBiometricAvailable();
    if (mounted) setState(() => _bioHwOk = ok);
  }

  Future<void> _register() async {
    if (_passCtrl.text != _pass2Ctrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final auth = context.read<AuthProvider>();

    // 1. Registrar en Firebase
    final err = await auth.register(
      name:     _nameCtrl.text.trim(),
      email:    _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!mounted) return;

    if (err != null) {
      setState(() { _loading = false; _error = err; });
      return;
    }

    // 2. Activar biometría si el usuario lo pidió
    //    enableBiometric() guarda uid+email en SharedPreferences para que
    //    la LoginScreen pueda encontrarlo en la siguiente sesión.
    if (_enableBio) {
      await auth.enableBiometric();
    }

    setState(() => _loading = false);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => const DeviceSetupScreen(isOnboarding: true)),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Crear cuenta',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Regístrate para comenzar a regar inteligente',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 32),

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
                const SizedBox(height: 16),
              ],

              // ── Campos ────────────────────────────────────────────────────
              _label('Nombre completo'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Tu nombre',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

              _label('Correo electrónico'),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'tu@correo.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),

              _label('Contraseña'),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Mínimo 6 caracteres',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _label('Confirmar contraseña'),
              const SizedBox(height: 8),
              TextField(
                controller: _pass2Ctrl,
                obscureText: _obscure2,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Repite tu contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure2
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ),
              ),

              // ── Toggle biometría ─────────────────────────────────────────
              if (_bioHwOk) ...[
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _enableBio
                          ? AppTheme.primary.withOpacity(0.4)
                          : AppTheme.divider,
                    ),
                  ),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    title: const Text(
                      'Habilitar huella digital',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Inicia sesión más rápido en futuros accesos',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _enableBio
                            ? AppTheme.primary.withOpacity(0.15)
                            : AppTheme.bgCardLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.fingerprint,
                          color: _enableBio
                              ? AppTheme.primary
                              : AppTheme.textMuted,
                          size: 22),
                    ),
                    value: _enableBio,
                    onChanged: (v) => setState(() => _enableBio = v),
                  ),
                ),
              ] else ...[
                // Hw no disponible — aviso informativo
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.warning.withOpacity(0.25)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppTheme.warning, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'La huella no está disponible en este dispositivo',
                          style: TextStyle(
                              color: AppTheme.warning, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Crear cuenta'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      );
}
