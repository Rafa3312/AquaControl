import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/device_provider.dart';

/// Pantalla que aparece cuando se detecta el ESP32 en modo SETUP (SoftAP).
/// El usuario debe estar conectado a la red "AquaControl-XXXXXX" del ESP.
/// Aquí ingresa las credenciales de su WiFi de casa para que el ESP las guarde.
class WifiSetupScreen extends StatefulWidget {
  const WifiSetupScreen({super.key});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool   _obscure = true;
  bool   _loading = false;
  String? _error;
  bool    _success = false;

  Future<void> _submit() async {
    if (_ssidCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa el nombre de tu red WiFi');
      return;
    }
    if (_passCtrl.text.length < 8) {
      setState(() => _error = 'Contraseña mínimo 8 caracteres');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final device = context.read<DeviceProvider>();
    final err = await device.configureWiFi(
      _ssidCtrl.text.trim(),
      _passCtrl.text,
    );

    if (!mounted) return;

    if (err == null) {
      setState(() { _loading = false; _success = true; });
    } else {
      // Agregar tip si el error viene del ESP
      final msg = err.contains('2.4')
          ? err
          : '$err\n\nRecuerda: el ESP32 solo soporta redes 2.4 GHz, no 5 GHz.';
      setState(() { _loading = false; _error = msg; });
    }
  }

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Configurar WiFi del dispositivo'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: _success ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.success.withOpacity(0.15),
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: AppTheme.success, size: 56),
        ),
        const SizedBox(height: 24),
        const Text(
          '¡WiFi guardado!',
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: const Column(
            children: [
              Text(
                'Próximos pasos',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 14),
              _Step(num: '1', text: 'El dispositivo se está reiniciando...'),
              SizedBox(height: 10),
              _Step(num: '2', text: 'Conecta tu celular a tu WiFi de casa'),
              SizedBox(height: 10),
              _Step(num: '3', text: 'Vuelve a la app — buscaremos el dispositivo automáticamente'),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Entendido'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner informativo
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.wifi_tethering_rounded,
                  color: AppTheme.primary, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tu celular está conectado al dispositivo en modo configuración. Ingresa tu WiFi de casa.',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.danger, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 13))),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        const Text('Nombre de tu red WiFi (SSID)',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        TextField(
          controller: _ssidCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'MiRedWiFi',
            prefixIcon: Icon(Icons.wifi_rounded),
          ),
        ),

        const SizedBox(height: 16),

        const Text('Contraseña WiFi',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        TextField(
          controller: _passCtrl,
          obscureText: _obscure,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Mínimo 8 caracteres',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),

        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outlined, color: AppTheme.success, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La contraseña se cifra antes de guardarse en el dispositivo',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Guardar y reiniciar dispositivo'),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String num;
  final String text;
  const _Step({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary.withOpacity(0.2),
          ),
          alignment: Alignment.center,
          child: Text(num,
              style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              textAlign: TextAlign.left,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
        ),
      ],
    );
  }
}
