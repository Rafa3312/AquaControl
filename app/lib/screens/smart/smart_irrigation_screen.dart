import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/smart_irrigation.dart';
import '../../providers/smart_irrigation_provider.dart';
import '../../theme/app_theme.dart';

/// Configuración del riego inteligente de una zona (Sprint 6, HU-10):
/// interruptor para activarlo y umbral de humedad de 10% a 90%.
class SmartIrrigationScreen extends StatefulWidget {
  final int zone;
  final String zoneName;

  const SmartIrrigationScreen({super.key, required this.zone, required this.zoneName});

  @override
  State<SmartIrrigationScreen> createState() => _SmartIrrigationScreenState();
}

class _SmartIrrigationScreenState extends State<SmartIrrigationScreen> {
  late bool _enabled;
  late int _threshold;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SmartIrrigationProvider>().settingsFor(widget.zone);
    _enabled = settings.enabled;
    _threshold = settings.threshold;
  }

  Future<void> _save() async {
    final smart = context.read<SmartIrrigationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final error = await smart.update(widget.zone, enabled: _enabled, threshold: _threshold);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      backgroundColor: error == null ? AppTheme.success : AppTheme.danger,
      content: Text(error ?? 'Riego inteligente guardado para ${widget.zoneName}'),
    ));
    if (error == null) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final saving = context.watch<SmartIrrigationProvider>().saving;
    final reduceFrom = _threshold - SmartSettings.reduceBand;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgPrimary,
        elevation: 0,
        title: Text('Riego inteligente · ${widget.zoneName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              activeColor: AppTheme.primary,
              onChanged: saving ? null : (v) => setState(() => _enabled = v),
              title: const Text(
                'Activar riego inteligente',
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Antes de cada riego programado el programador mide la humedad del suelo.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Umbral de humedad',
                        style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '$_threshold%',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _threshold.toDouble(),
                  min: SmartSettings.minThreshold.toDouble(),
                  max: SmartSettings.maxThreshold.toDouble(),
                  divisions: (SmartSettings.maxThreshold - SmartSettings.minThreshold) ~/ 5,
                  label: '$_threshold%',
                  activeColor: AppTheme.primary,
                  onChanged: saving || !_enabled
                      ? null
                      : (v) => setState(() => _threshold = v.round()),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('10%', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    Text('90%', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Qué hará el programador',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                _Rule(color: AppTheme.primary, text: 'Humedad de $_threshold% o más: omite el riego'),
                _Rule(
                  color: AppTheme.warning,
                  text: 'De ${reduceFrom < 0 ? 0 : reduceFrom}% a ${_threshold - 1}%: riega la mitad',
                ),
                _Rule(
                  color: AppTheme.success,
                  text: 'Menos de ${reduceFrom < 0 ? 0 : reduceFrom}%: riega completo',
                ),
                const _Rule(
                  color: AppTheme.danger,
                  text: 'Si el sensor falla: riega lo programado y te avisa',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Guardar', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: child,
    );
  }
}

class _Rule extends StatelessWidget {
  final Color color;
  final String text;
  const _Rule({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
