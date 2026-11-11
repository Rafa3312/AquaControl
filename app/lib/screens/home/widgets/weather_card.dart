import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/rain.dart';
import '../../../providers/irrigation_provider.dart';
import '../../../theme/app_theme.dart';

/// Tarjeta del Dashboard con el clima según el sensor de lluvia (Sprint 7, HU-11):
/// sol o lluvia, y qué pasa con los riegos programados.
class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final rain = context.watch<IrrigationProvider>().rain;

    final (icon, color, detail) = switch (rain) {
      null => (
          Icons.cloud_off_outlined,
          AppTheme.textMuted,
          'Sin sensor de lluvia. Los riegos se ejecutan según la programación.',
        ),
      RainStatus(valid: false) => (
          Icons.sensors_off_rounded,
          AppTheme.danger,
          'Revisa el sensor de lluvia. Mientras tanto se riega según la programación.',
        ),
      RainStatus(raining: true) => (
          Icons.umbrella_rounded,
          AppTheme.accent,
          'Los riegos programados se posponen y se reintentan cada 15 min, hasta 2 h.',
        ),
      _ => (
          Icons.wb_sunny_rounded,
          AppTheme.warning,
          'Sin lluvia: los riegos programados se ejecutan normalmente.',
        ),
    };

    final label = rain?.label ?? 'Sin sensor';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clima',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
