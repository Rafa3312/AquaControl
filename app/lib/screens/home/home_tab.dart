import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/irrigation_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/zone_provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/schedule.dart';
import '../notifications/notifications_screen.dart';
import '../main_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  late AnimationController _waveCtrl;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final irr = context.watch<IrrigationProvider>();
    final sched = context.watch<ScheduleProvider>();
    final names = context.watch<ZoneProvider>();
    final notif = context.watch<NotificationProvider>();
    final active = irr.isActive;
    final zoneName = names.nameOf(irr.selectedZone);

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: CustomScrollView(
        slivers: [
          // AppBar
          SliverAppBar(
            backgroundColor: AppTheme.bgPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, ${auth.userName?.split(' ').first ?? 'Usuario'} 👋',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const Text(
                  'AquaControl',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            actions: [
              // Notificaciones de riego (HU-8)
              IconButton(
                tooltip: 'Notificaciones',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
                icon: Badge(
                  isLabelVisible: notif.failureCount > 0,
                  backgroundColor: AppTheme.danger,
                  smallSize: 8,
                  child: const Icon(Icons.notifications_none_rounded,
                      color: AppTheme.textSecondary),
                ),
              ),

              // Indicador de dispositivo
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: irr.deviceOnline
                      ? AppTheme.success.withOpacity(0.15)
                      : AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: irr.deviceOnline
                        ? AppTheme.success.withOpacity(0.4)
                        : AppTheme.divider,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: irr.deviceOnline
                            ? AppTheme.success
                            : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      irr.deviceOnline ? 'En línea' : 'Sin conexión',
                      style: TextStyle(
                        color: irr.deviceOnline
                            ? AppTheme.success
                            : AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Avatar → abre el drawer de perfil
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => AppDrawerCallback.of(context)?.onOpen(),
                  child: _AvatarButton(name: auth.userName),
                ),
              ),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Selector de zona (HU-7) ───────────────────────────────────
                _ZoneSelector(irr: irr, names: names),
                const SizedBox(height: 16),

                // ── Tarjeta de estado principal ──────────────────────────────
                _StatusCard(
                  active: active,
                  irr: irr,
                  names: names,
                  zoneName: zoneName,
                  waveCtrl: _waveCtrl,
                ),
                const SizedBox(height: 20),

                // ── Control manual (zona seleccionada) ───────────────────────
                _ManualControlCard(irr: irr, zoneName: zoneName),
                const SizedBox(height: 20),

                // ── Programación activa de la zona ────────────────────────────
                _ActiveScheduleCard(
                  active: sched.activeScheduleFor(irr.selectedZone),
                ),
                const SizedBox(height: 20),

                // ── Stats del día ─────────────────────────────────────────────
                _DailyStatsRow(irr: irr),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tarjeta de estado grande
// ══════════════════════════════════════════════════════════════════════════════
class _StatusCard extends StatelessWidget {
  final bool active;
  final IrrigationProvider irr;
  final ZoneProvider names;
  final String zoneName;
  final AnimationController waveCtrl;

  const _StatusCard({
    required this.active,
    required this.irr,
    required this.names,
    required this.zoneName,
    required this.waveCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.success : AppTheme.primary;
    final bgColor = active
        ? AppTheme.success.withOpacity(0.08)
        : AppTheme.primary.withOpacity(0.06);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? [const Color(0xFF0D3025), const Color(0xFF0A2A1E)]
              : [const Color(0xFF0A1E35), const Color(0xFF061422)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                // Ícono animado
                AnimatedBuilder(
                  animation: waveCtrl,
                  builder: (_, __) => Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.15),
                      border: Border.all(
                        color: color.withOpacity(
                            0.3 + 0.2 * waveCtrl.value),
                        width: 2,
                      ),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.25),
                                blurRadius: 20 * waveCtrl.value,
                                spreadRadius: 4 * waveCtrl.value,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      active
                          ? Icons.water_drop_rounded
                          : Icons.water_drop_outlined,
                      color: color,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        zoneName,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        irr.statusLabel,
                        style: TextStyle(
                          color: color,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active
                            ? 'Tiempo transcurrido: ${irr.elapsedTime}'
                            : 'Los aspersores están detenidos',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                // Indicador animado
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Pulse(),
                        SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: AppTheme.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            if (active) ...[
              const SizedBox(height: 20),
              Divider(color: AppTheme.success.withOpacity(0.2)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MiniStat(
                    label: 'Modo',
                    value: irr.manualOverride ? 'Manual' : 'Auto',
                    icon: irr.manualOverride
                        ? Icons.touch_app_rounded
                        : Icons.schedule_rounded,
                    color: AppTheme.primary,
                  ),
                  _MiniStat(
                    label: 'Caudal',
                    value: '~0.8 L/min',
                    icon: Icons.speed_rounded,
                    color: AppTheme.accent,
                  ),
                  _MiniStat(
                    label: 'Aspersores',
                    value: 'Activos',
                    icon: Icons.scatter_plot_rounded,
                    color: AppTheme.success,
                  ),
                ],
              ),
            ],

            // Estado de cada zona
            const SizedBox(height: 18),
            Divider(color: color.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            for (final z in irr.zones)
              _ZoneStateRow(zone: z, name: names.nameOf(z.id)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Control manual
// ══════════════════════════════════════════════════════════════════════════════
class _ManualControlCard extends StatelessWidget {
  final IrrigationProvider irr;
  final String zoneName;
  const _ManualControlCard({required this.irr, required this.zoneName});

  @override
  Widget build(BuildContext context) {
    // Bloqueado si hay un riego por programación activo
    final blocked  = irr.isScheduledRun;
    final canStart = !irr.isActive && !blocked;
    final canStop  = irr.isActive  && !blocked;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: blocked ? AppTheme.warning.withOpacity(0.35) : AppTheme.divider,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.touch_app_rounded,
                  color: blocked ? AppTheme.warning : AppTheme.primary,
                  size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Control manual · $zoneName',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: blocked ? AppTheme.warning : AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            blocked
                ? 'Bloqueado — programación en curso. Apaga el riego primero si quieres interrumpirla.'
                : 'Enciende o apaga el riego de esta zona sin afectar a las demás',
            style: TextStyle(
              color: blocked ? AppTheme.warning : AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),

          // Botones ON / OFF
          Row(
            children: [
              Expanded(
                child: _ControlButton(
                  label: 'Encender',
                  icon: Icons.play_arrow_rounded,
                  color: AppTheme.success,
                  enabled: canStart,
                  onTap: canStart ? () => irr.turnOn() : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ControlButton(
                  label: 'Apagar',
                  icon: Icons.stop_rounded,
                  color: AppTheme.danger,
                  enabled: canStop,
                  onTap: canStop ? () => irr.turnOff() : null,
                ),
              ),
            ],
          ),

          // Botón de prueba rápida (solo visible cuando está inactivo y no bloqueado)
          if (!irr.isActive && !blocked) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showTestDialog(context),
                icon: const Icon(Icons.science_outlined, size: 17),
                label: const Text('Prueba rápida'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: const BorderSide(color: AppTheme.accent, width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showTestDialog(BuildContext context) {
    int seconds = 30;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.science_outlined, color: AppTheme.accent, size: 22),
              SizedBox(width: 10),
              Text('Prueba rápida',
                  style: TextStyle(color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enciende el riego por unos segundos para revisar los aspersores.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              Text(
                '$seconds segundos',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Slider(
                value: seconds.toDouble(),
                min: 10,
                max: 120,
                divisions: 11,
                activeColor: AppTheme.accent,
                inactiveColor: AppTheme.divider,
                label: '$seconds s',
                onChanged: (v) => setS(() => seconds = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [10, 30, 60, 120].map((s) {
                  return GestureDetector(
                    onTap: () => setS(() => seconds = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: seconds == s
                            ? AppTheme.accent.withOpacity(0.2)
                            : AppTheme.bgCardLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: seconds == s ? AppTheme.accent : AppTheme.divider,
                        ),
                      ),
                      child: Text(
                        s < 60 ? '${s}s' : '${s ~/ 60}m',
                        style: TextStyle(
                          color: seconds == s ? AppTheme.accent : AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                irr.turnOnTest(seconds: seconds);
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text('Iniciar $seconds s'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: enabled
              ? color.withOpacity(0.15)
              : AppTheme.bgCardLight.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? color.withOpacity(0.4) : AppTheme.divider,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: enabled ? color : AppTheme.textMuted,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: enabled ? color : AppTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Programación activa
// ══════════════════════════════════════════════════════════════════════════════
class _ActiveScheduleCard extends StatelessWidget {
  final Schedule? active;
  const _ActiveScheduleCard({required this.active});

  @override
  Widget build(BuildContext context) {
    final active = this.active;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active != null
                  ? AppTheme.primary.withOpacity(0.15)
                  : AppTheme.bgCardLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.schedule_rounded,
              color: active != null ? AppTheme.primary : AppTheme.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: active != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${active.daysLabel}  •  ${active.timeLabel}  •  ${active.durationLabel}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  )
                : const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sin programación activa en esta zona',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Activa una desde la pestaña Programas',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
          ),
          if (active != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'ACTIVA',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Stats del día
// ══════════════════════════════════════════════════════════════════════════════
class _DailyStatsRow extends StatelessWidget {
  final IrrigationProvider irr;
  const _DailyStatsRow({required this.irr});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.opacity_rounded,
            label: 'Agua hoy',
            value: '${irr.waterUsageToday.toStringAsFixed(1)} L',
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.repeat_rounded,
            label: 'Riegos hoy',
            value: '${irr.sessionsToday}',
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.wb_sunny_outlined,
            label: 'Estado',
            value: 'Normal',
            color: AppTheme.warning,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13),
        ),
        Text(
          label,
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

// Indicador pulsante LIVE
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.success,
        ),
      ),
    );
  }
}

// Avatar compacto para AppBar
class _AvatarButton extends StatelessWidget {
  final String? name;
  const _AvatarButton({super.key, this.name});

  String get _initials {
    if (name == null || name!.isEmpty) return '?';
    final parts = name!.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name![0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppTheme.accent, AppTheme.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          _initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Selector de zona del Dashboard (HU-7)
// ══════════════════════════════════════════════════════════════════════════════
class _ZoneSelector extends StatelessWidget {
  final IrrigationProvider irr;
  final ZoneProvider names;
  const _ZoneSelector({required this.irr, required this.names});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final z in irr.zones) ...[
          if (z.id > 1) const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => irr.selectZone(z.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: irr.selectedZone == z.id
                      ? AppTheme.primary.withValues(alpha: 0.18)
                      : AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: irr.selectedZone == z.id ? AppTheme.primary : AppTheme.divider,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: z.fault && !z.isActive
                            ? AppTheme.danger
                            : z.isActive
                                ? AppTheme.success
                                : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        names.nameOf(z.id),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: irr.selectedZone == z.id
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Fila de la tarjeta de estado con el riego de cada zona.
class _ZoneStateRow extends StatelessWidget {
  final ZoneRuntime zone;
  final String name;
  const _ZoneStateRow({required this.zone, required this.name});

  @override
  Widget build(BuildContext context) {
    final color = zone.fault && !zone.isActive
        ? AppTheme.danger
        : zone.isActive
            ? AppTheme.success
            : AppTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            zone.isActive ? Icons.water_drop_rounded : Icons.water_drop_outlined,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
          ),
          Text(
            zone.isActive ? '${zone.statusLabel} · ${zone.elapsedTime}' : zone.statusLabel,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
