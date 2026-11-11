import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/smart_irrigation.dart';
import '../../../providers/irrigation_provider.dart';
import '../../../providers/schedule_provider.dart';
import '../../../providers/smart_irrigation_provider.dart';
import '../../../theme/app_theme.dart';
import '../../smart/smart_irrigation_screen.dart';

/// Tarjeta del Dashboard con la humedad del suelo de la zona seleccionada
/// y el estado del riego inteligente (Sprint 6, HU-10).
class MoistureCard extends StatelessWidget {
  final int zone;
  final String zoneName;

  const MoistureCard({super.key, required this.zone, required this.zoneName});

  static Color colorFor(MoistureLevel? level) => switch (level) {
        MoistureLevel.dry => AppTheme.warning,
        MoistureLevel.moist => AppTheme.success,
        MoistureLevel.saturated => AppTheme.primary,
        null => AppTheme.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final irr = context.watch<IrrigationProvider>();
    final smart = context.watch<SmartIrrigationProvider>();
    final sched = context.watch<ScheduleProvider>();

    final runtime = irr.zone(zone);
    final reading = runtime.moisture;
    final settings = smart.settingsFor(zone);
    final schedule = sched.activeScheduleFor(zone);
    final color = colorFor(reading?.level);
    final hasValue = reading != null && reading.valid;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.water_drop_outlined, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Humedad del suelo',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reading == null ? 'Sin sensor conectado' : reading.levelLabel,
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Text(
                hasValue ? '${reading.percent}%' : '--',
                style: TextStyle(
                  color: hasValue ? AppTheme.textPrimary : AppTheme.textMuted,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: hasValue ? reading.percent / 100 : 0,
              minHeight: 8,
              backgroundColor: AppTheme.bgCardLight,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: settings.enabled ? Icons.auto_mode_rounded : Icons.do_not_disturb_on_outlined,
            color: settings.enabled ? AppTheme.success : AppTheme.textMuted,
            text: settings.enabled
                ? 'Riego inteligente activo · umbral ${settings.threshold}%'
                : 'Riego inteligente apagado',
          ),
          if (settings.enabled && schedule != null && reading != null)
            _InfoRow(
              icon: Icons.schedule_rounded,
              color: AppTheme.textSecondary,
              text: 'Si riega a las ${schedule.timeLabel}: '
                  '${smart.preview(zone, reading, schedule.durationMinutes).message}',
            ),
          if (runtime.lastSmart != null)
            _InfoRow(
              icon: Icons.history_rounded,
              color: AppTheme.textSecondary,
              text: 'Último riego'
                  '${runtime.lastSmart!.at != null ? ' (${runtime.lastSmart!.at})' : ''}: '
                  '${runtime.lastSmart!.message}',
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SmartIrrigationScreen(zone: zone, zoneName: zoneName),
                ),
              ),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Configurar'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
