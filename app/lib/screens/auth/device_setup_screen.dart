import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/device_provider.dart';
import '../main_screen.dart';
import 'wifi_setup_screen.dart';

class DeviceSetupScreen extends StatefulWidget {
  final bool isOnboarding;
  const DeviceSetupScreen({super.key, this.isOnboarding = false});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  _ScanState _state    = _ScanState.scanning;
  String?    _foundIp;
  String     _progress = 'Buscando dispositivo...';
  String?    _error;

  // true = token local no coincide con ESP → necesita reset físico
  bool _needsHardReset = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startScan();
  }

  // ─── Descubrimiento ───────────────────────────────────────────────────────
  Future<void> _startScan() async {
    setState(() {
      _state         = _ScanState.scanning;
      _foundIp       = null;
      _error         = null;
      _needsHardReset = false;
      _progress      = 'Buscando dispositivo en la red...';
    });

    final device = context.read<DeviceProvider>();

    // ¿El celular está conectado al ESP en modo SETUP?
    setState(() => _progress = 'Verificando modo de configuración...');
    final inSetupMode = await device.detectSetupMode();
    if (inSetupMode && mounted) {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const WifiSetupScreen()),
      );
      if (!mounted) return;
      if (result == true) {
        // Esperar a que el ESP reinicie y se conecte al WiFi de casa
        // Polling cada 3s hasta que responda (máx 60s)
        setState(() => _progress = 'Esperando que el dispositivo se reconecte...');
        final device = context.read<DeviceProvider>();
        bool found = false;
        for (int i = 0; i < 20 && !found; i++) {
          await Future.delayed(const Duration(seconds: 3));
          if (!mounted) return;
          final elapsed = (i + 1) * 3;
          setState(() => _progress = 'Reconectando... (${elapsed}s)');
          // Intentar mDNS directo que es más rápido que el escaneo completo
          found = await device.waitForDeviceOnline();
        }
        if (mounted) _startScan();
      } else {
        setState(() { _state = _ScanState.error; _error = 'Configuración cancelada'; });
      }
      return;
    }

    // Buscar en la red normal
    final ip = await device.discover(
      onProgress: (msg) { if (mounted) setState(() => _progress = msg); },
    );

    if (!mounted) return;

    if (ip != null) {
      setState(() { _state = _ScanState.found; _foundIp = ip; });
    } else {
      setState(() {
        _state = _ScanState.error;
        _error = device.lastError ?? 'No se encontró el dispositivo';
      });
    }
  }

  // ─── Reset con PIN ───────────────────────────────────────────────────────
  Future<void> _showResetWithPin() async {
    final pinCtrl = TextEditingController();
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: AppTheme.warning, size: 22),
              SizedBox(width: 10),
              Text('Resetear dispositivo',
                  style: TextStyle(color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El PIN de 6 dígitos aparece en el Monitor Serial del Arduino IDE al arrancar el ESP32:',
                style: TextStyle(color: AppTheme.textSecondary,
                    fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.bgSecondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: const Text(
                  '[Sec] 07:00:00  event=reset_pin_XXXXXX',
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: '000000',
                  counterText: '',
                ),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 10),
                Text(dialogError!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warning,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (pinCtrl.text.length != 6) {
                  setS(() => dialogError = 'Ingresa los 6 dígitos');
                  return;
                }
                // Cerrar diálogo y ejecutar reset
                Navigator.pop(ctx);
                await _doResetWithPin(pinCtrl.text);
              },
              child: const Text('Resetear'),
            ),
          ],
        ),
      ),
    );
    pinCtrl.dispose();
  }

  Future<void> _doResetWithPin(String pin) async {
    if (_foundIp == null) {
      // Si no tenemos IP, intentar encontrar el dispositivo primero
      setState(() { _state = _ScanState.scanning; _progress = 'Buscando para resetear...'; });
      final device = context.read<DeviceProvider>();
      final ip = await device.discover();
      if (!mounted) return;
      if (ip == null) {
        setState(() { _state = _ScanState.error; _error = 'No se encontró el dispositivo'; });
        return;
      }
      _foundIp = ip;
    }

    setState(() { _state = _ScanState.connecting; _progress = 'Enviando reset...'; });

    final device = context.read<DeviceProvider>();
    final err = await device.factoryResetWithPin(_foundIp!, pin);

    if (!mounted) return;

    if (err == null) {
      // Reset exitoso → el ESP reinicia → esperar y buscar de nuevo
      setState(() => _progress = 'Reset exitoso. Esperando reinicio...');
      await Future.delayed(const Duration(seconds: 5));
      if (mounted) _startScan();
    } else {
      setState(() {
        _state = _ScanState.error;
        _needsHardReset = true;
        _error = err;
      });
    }
  }

  // ─── Pairing (con recuperación automática) ────────────────────────────────
  Future<void> _pair() async {
    if (_foundIp == null) return;
    setState(() { _state = _ScanState.connecting; _error = null; });

    final device = context.read<DeviceProvider>();
    final err = await device.pairDevice(_foundIp!);

    if (!mounted) return;

    // ── Caso 1: éxito normal ─────────────────────────────────────────────
    if (err == null) {
      await _finishPairing();
      return;
    }

    // ── Caso 2: ESP ya tiene token → intentar recuperar ──────────────────
    if (err == 'ALREADY_PAIRED') {
      setState(() => _progress = 'Recuperando vinculación existente...');
      final recoverErr = await device.recoverPairing(_foundIp!);

      if (!mounted) return;

      if (recoverErr == null) {
        // Token local coincide → restaurado
        await _finishPairing();
        return;
      }

      if (recoverErr == 'NO_TOKEN') {
        // No hay token local o no coincide → necesita reset físico del ESP
        setState(() {
          _state          = _ScanState.error;
          _needsHardReset = true;
          _error = 'El dispositivo ya está vinculado con un token diferente.\n'
                   'Necesitas hacer un reset de fábrica del ESP32.';
        });
        return;
      }

      setState(() {
        _state = _ScanState.error;
        _error = recoverErr;
      });
      return;
    }

    // ── Caso 3: error real ────────────────────────────────────────────────
    setState(() { _state = _ScanState.error; _error = err; });
  }

  Future<void> _finishPairing() async {
    final auth = context.read<AuthProvider>();
    await auth.linkDevice('aquacontrol.local');

    setState(() => _state = _ScanState.connected);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    if (widget.isOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: widget.isOnboarding
          ? null
          : AppBar(
              backgroundColor: AppTheme.bgPrimary,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('Conectar dispositivo'),
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: ConstrainedBox(
            // Mínimo la altura disponible para que los Spacers funcionen
            // cuando el contenido es corto, y scroll cuando es largo
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  (widget.isOnboarding ? 0 : kToolbarHeight) -
                  64, // padding vertical
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  if (widget.isOnboarding) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Conectar dispositivo',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Asegúrate de estar en la misma red WiFi que tu ESP32.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                  const Spacer(),
                  _buildRadar(),
                  const SizedBox(height: 32),
                  _buildStatusInfo(),
                  const Spacer(),
                  const SizedBox(height: 24),
                  _buildButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadar() {
    final color = switch (_state) {
      _ScanState.found || _ScanState.connected => AppTheme.success,
      _ScanState.error                         => AppTheme.danger,
      _                                        => AppTheme.primary,
    };

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          for (final r in [80.0, 105.0, 130.0])
            Container(
              width:  r * (_state == _ScanState.scanning ? _pulseAnim.value : 1),
              height: r * (_state == _ScanState.scanning ? _pulseAnim.value : 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.18), width: 1.5),
              ),
            ),
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.14),
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(_stateIcon(), color: color, size: 28),
          ),
        ],
      ),
    );
  }

  IconData _stateIcon() => switch (_state) {
    _ScanState.connected => Icons.check_rounded,
    _ScanState.error     => _needsHardReset
        ? Icons.lock_reset_rounded
        : Icons.wifi_off_rounded,
    _ => Icons.router_rounded,
  };

  Widget _buildStatusInfo() {
    return switch (_state) {
      _ScanState.scanning => Column(
        children: [
          Text(_progress,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          const Text('mDNS → IP guardada → escaneo de red',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),

      _ScanState.found => Column(
        children: [
          const Text('¡Dispositivo encontrado!',
              style: TextStyle(
                  color: AppTheme.success,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.success.withOpacity(0.4)),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.memory_rounded, color: AppTheme.success, size: 20),
                    SizedBox(width: 10),
                    Text('aquacontrol.local',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace')),
                  ],
                ),
                const SizedBox(height: 6),
                Text('IP: $_foundIp',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),

      _ScanState.connecting => Column(
        children: [
          Text(_progress.contains('Recuperando') ? 'Recuperando vinculación...' : 'Vinculando...',
              style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            _progress.contains('Recuperando')
                ? 'Verificando token existente'
                : 'Generando token de seguridad',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          const LinearProgressIndicator(
              backgroundColor: AppTheme.bgCard, color: AppTheme.primary),
        ],
      ),

      _ScanState.connected => const Column(
        children: [
          Icon(Icons.verified_rounded, color: AppTheme.success, size: 52),
          SizedBox(height: 12),
          Text('¡Vinculado correctamente!',
              style: TextStyle(
                  color: AppTheme.success,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Token de seguridad guardado',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),

      _ScanState.error => Column(
        children: [
          Icon(
            _needsHardReset ? Icons.lock_reset_rounded : Icons.wifi_off_rounded,
            color: AppTheme.danger,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            _needsHardReset ? 'Reset de fábrica necesario' : 'No se pudo conectar',
            style: const TextStyle(
                color: AppTheme.danger,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            _error ?? 'Error desconocido',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          ),
          if (_needsHardReset) ...[
            const SizedBox(height: 16),
            _HardResetInstructions(),
          ],
        ],
      ),
    };
  }

  Widget _buildButtons() {
    if (_state == _ScanState.scanning ||
        _state == _ScanState.connecting ||
        _state == _ScanState.connected) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (_state == _ScanState.found)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pair,
              icon: const Icon(Icons.link_rounded, size: 20),
              label: const Text('Vincular dispositivo'),
            ),
          ),
        const SizedBox(height: 12),
        // Botón de reset con PIN cuando hay token diferente
        if (_needsHardReset) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showResetWithPin,
              icon: const Icon(Icons.lock_reset_rounded, size: 20),
              label: const Text('Resetear con PIN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warning,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Buscar de nuevo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        if (!widget.isOnboarding) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            child: const Text('Cancelar'),
          ),
        ],
      ],
    );
  }
}

// ── Instrucciones de reset físico ─────────────────────────────────────────────
class _HardResetInstructions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.warning, size: 16),
              SizedBox(width: 8),
              Text('Cómo hacer el reset',
                  style: TextStyle(
                      color: AppTheme.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          _step('1', 'Abre el Monitor Serial del Arduino IDE (115200 baud)'),
          _step('2', 'Busca el PIN de reset: aparece en el log como "Reset PIN: XXXXXX"'),
          _step('3', 'Envía el comando: POST /reset con ese PIN'),
          _step('4', 'O presiona el botón EN (Enable) del ESP32 durante 10 segundos'),
          const SizedBox(height: 8),
          const Text(
            'Alternativa rápida: sube el firmware de nuevo desde Arduino IDE — '
            'eso borra la flash y el ESP queda sin token.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.warning.withOpacity(0.2),
              ),
              alignment: Alignment.center,
              child: Text(n,
                  style: const TextStyle(
                      color: AppTheme.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.4)),
            ),
          ],
        ),
      );
}

enum _ScanState { scanning, found, connecting, connected, error }
