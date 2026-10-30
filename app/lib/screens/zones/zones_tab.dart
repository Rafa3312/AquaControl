import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/zone.dart';
import '../../providers/irrigation_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/zone_provider.dart';
import '../../theme/app_theme.dart';

/// Pantalla "Zonas de riego": cada zona se enciende o apaga por separado.
class ZonesTab extends StatelessWidget {
  const ZonesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final irr = context.watch<IrrigationProvider>();
    final names = context.watch<ZoneProvider>();
    final sched = context.watch<ScheduleProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            backgroundColor: AppTheme.bgPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text('Zonas de riego'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  irr.deviceOnline
                      ? 'Cada zona tiene su propia válvula: enciéndelas o apágalas por separado.'
                      : 'El programador está sin conexión. Los cambios se aplicarán al reconectar.',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 18),
                for (final zone in irr.zones) ...[
                  _ZoneCard(
                    zone: zone,
                    name: names.nameOf(zone.id),
                    scheduleName: sched.activeScheduleFor(zone.id)?.name,
                    enabled: irr.deviceOnline,
                    onToggle: () => irr.toggleZone(zone.id),
                    onRename: () =>
                        _rename(context, zone.id, names.nameOf(zone.id)),
                  ),
                  const SizedBox(height: 14),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, int id, String current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameZoneDialog(zoneId: id, initialName: current),
    );
    if (name == null || !context.mounted) return;
    final error = await context.read<ZoneProvider>().rename(id, name);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _ZoneCard extends StatelessWidget {
  final ZoneRuntime zone;
  final String name;
  final String? scheduleName;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onRename;

  const _ZoneCard({
    required this.zone,
    required this.name,
    required this.scheduleName,
    required this.enabled,
    required this.onToggle,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final active = zone.isActive;
    final fault = zone.fault && !active;
    final color = fault
        ? AppTheme.danger
        : active
            ? AppTheme.success
            : AppTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active || fault
              ? color.withValues(alpha: 0.45)
              : AppTheme.divider,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  fault
                      ? Icons.warning_amber_rounded
                      : active
                          ? Icons.water_drop_rounded
                          : Icons.water_drop_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '${Zones.defaultName(zone.id)} · ${zone.statusLabel}',
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Switch(
                value: active,
                activeColor: AppTheme.success,
                onChanged: enabled ? (_) => onToggle() : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _detail,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Renombrar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _detail {
    if (zone.fault && !zone.isActive) {
      return 'La válvula no respondió en el último riego. Revisa la conexión.';
    }
    if (zone.isActive) {
      final stop =
          zone.stopAt != null ? ' · se apaga a las ${zone.stopAt}' : '';
      return 'Regando desde hace ${zone.elapsedTime}$stop';
    }
    return scheduleName != null
        ? 'Programación activa: $scheduleName'
        : 'Sin programación activa';
  }
}

/// Diálogo para renombrar una zona. Es dueño de su TextEditingController
/// para liberarlo hasta que el diálogo sale de pantalla (tras su animación).
class _RenameZoneDialog extends StatefulWidget {
  final int zoneId;
  final String initialName;
  const _RenameZoneDialog({required this.zoneId, required this.initialName});

  @override
  State<_RenameZoneDialog> createState() => _RenameZoneDialogState();
}

class _RenameZoneDialogState extends State<_RenameZoneDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: Text('Nombre de la ${Zones.defaultName(widget.zoneId)}',
          style: const TextStyle(color: AppTheme.textPrimary)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: Zones.maxNameLength,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(hintText: 'Ej: Jardín frontal'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
