import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/irrigation_provider.dart';
import '../auth/login_screen.dart';
import '../auth/device_setup_screen.dart';

class ProfileDrawer extends StatefulWidget {
  const ProfileDrawer({super.key});

  @override
  State<ProfileDrawer> createState() => _ProfileDrawerState();
}

class _ProfileDrawerState extends State<ProfileDrawer> {
  bool _bioHwAvailable = false;
  bool _loadingBio = false;

  @override
  void initState() {
    super.initState();
    _checkBioHw();
  }

  Future<void> _checkBioHw() async {
    final ok = await context.read<AuthProvider>().isBiometricAvailable();
    if (mounted) setState(() => _bioHwAvailable = ok);
  }

  // ── Cerrar sesión ────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cerrar sesión',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          '¿Seguro que quieres salir?\nTu huella digital seguirá configurada para el próximo acceso.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── Toggle biometría ─────────────────────────────────────────────────────
  Future<void> _toggleBiometric(bool enable) async {
    setState(() => _loadingBio = true);
    final auth = context.read<AuthProvider>();

    if (enable) {
      // Verificar huella antes de activarla
      final ok = await auth.isBiometricAvailable();
      if (!ok) {
        if (mounted) {
          _showSnack('Huella no disponible en este dispositivo', isError: true);
        }
        setState(() => _loadingBio = false);
        return;
      }
      await auth.enableBiometric();
      if (mounted) _showSnack('Huella digital activada');
    } else {
      await auth.disableBiometric();
      if (mounted) _showSnack('Huella digital desactivada');
    }

    if (mounted) setState(() => _loadingBio = false);
  }

  // ── Reconectar dispositivo ───────────────────────────────────────────────
  void _reconnectDevice() {
    Navigator.of(context).pop(); // Cerrar drawer
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DeviceSetupScreen(isOnboarding: false),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? AppTheme.danger : AppTheme.success,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(msg),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.bgCardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final irr  = context.watch<IrrigationProvider>();

    return Drawer(
      backgroundColor: AppTheme.bgSecondary,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header del perfil ────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0A1E35), Color(0xFF112240)],
                ),
                border: Border(
                  bottom: BorderSide(color: AppTheme.divider, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppTheme.accent, AppTheme.primary],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _initials(auth.userName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Nombre
                  Text(
                    auth.userName ?? 'Usuario',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // Email
                  Text(
                    auth.userEmail ?? '',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Chip dispositivo
                  _DeviceChip(
                    deviceId: auth.deviceId,
                    isOnline: irr.deviceOnline,
                    onReconnect: _reconnectDevice,
                  ),
                ],
              ),
            ),

            // ── Opciones ─────────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  // Mis datos
                  _SectionLabel('MI CUENTA'),
                  _DrawerTile(
                    icon: Icons.person_outline_rounded,
                    label: 'Mis datos',
                    onTap: () => _showUserDataSheet(context, auth),
                  ),

                  const SizedBox(height: 8),
                  _SectionLabel('SEGURIDAD'),

                  // Toggle huella
                  _bioHwAvailable
                      ? _DrawerSwitch(
                          icon: Icons.fingerprint,
                          label: 'Huella digital',
                          subtitle: auth.biometricEnabled
                              ? 'Activa — acceso rápido habilitado'
                              : 'Inactiva — usa contraseña al entrar',
                          value: auth.biometricEnabled,
                          loading: _loadingBio,
                          onChanged: _toggleBiometric,
                        )
                      : _DrawerTile(
                          icon: Icons.fingerprint,
                          label: 'Huella digital',
                          subtitle: 'No disponible en este dispositivo',
                          trailing: const Icon(Icons.block_rounded,
                              color: AppTheme.textMuted, size: 18),
                          onTap: null,
                        ),

                  const SizedBox(height: 8),
                  _SectionLabel('DISPOSITIVO'),

                  // Reconectar ESP
                  _DrawerTile(
                    icon: Icons.router_rounded,
                    label: 'Reconectar dispositivo',
                    subtitle: auth.deviceId != null
                        ? auth.deviceId!
                        : 'Sin dispositivo vinculado',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: irr.deviceOnline
                            ? AppTheme.success.withOpacity(0.15)
                            : AppTheme.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        irr.deviceOnline ? 'En línea' : 'Buscar',
                        style: TextStyle(
                          color: irr.deviceOnline
                              ? AppTheme.success
                              : AppTheme.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    onTap: _reconnectDevice,
                  ),
                ],
              ),
            ),

            // ── Botón cerrar sesión ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppTheme.divider, width: 1)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded,
                      color: AppTheme.danger, size: 20),
                  label: const Text('Cerrar sesión',
                      style: TextStyle(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.danger, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  void _showUserDataSheet(BuildContext ctx, AuthProvider auth) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Mis datos',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            _DataRow(label: 'Nombre', value: auth.userName ?? '—'),
            const Divider(color: AppTheme.divider, height: 24),
            _DataRow(label: 'Correo', value: auth.userEmail ?? '—'),
            const Divider(color: AppTheme.divider, height: 24),
            _DataRow(
              label: 'Dispositivo vinculado',
              value: auth.deviceId ?? 'Sin vincular',
            ),
            const Divider(color: AppTheme.divider, height: 24),
            _DataRow(
              label: 'Huella digital',
              value: auth.biometricEnabled ? 'Activada' : 'Desactivada',
              valueColor: auth.biometricEnabled
                  ? AppTheme.success
                  : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widgets internos
// ══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 11),
              overflow: TextOverflow.ellipsis)
          : null,
      trailing: trailing ??
          const Icon(Icons.chevron_right_rounded,
              color: AppTheme.textMuted, size: 20),
      onTap: onTap,
    );
  }
}

class _DrawerSwitch extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final bool loading;
  final ValueChanged<bool> onChanged;

  const _DrawerSwitch({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.loading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            color: value ? AppTheme.primary : AppTheme.textMuted, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      trailing: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.primary),
            )
          : Switch(
              value: value,
              onChanged: onChanged,
            ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final String? deviceId;
  final bool isOnline;
  final VoidCallback onReconnect;

  const _DeviceChip({
    required this.deviceId,
    required this.isOnline,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isOnline ? null : onReconnect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isOnline
              ? AppTheme.success.withOpacity(0.12)
              : AppTheme.warning.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOnline
                ? AppTheme.success.withOpacity(0.35)
                : AppTheme.warning.withOpacity(0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline ? AppTheme.success : AppTheme.warning,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              isOnline
                  ? (deviceId ?? 'Conectado')
                  : 'Sin conexión — toca para reconectar',
              style: TextStyle(
                color: isOnline ? AppTheme.success : AppTheme.warning,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DataRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13)),
        Text(value,
            style: TextStyle(
              color: valueColor ?? AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}
