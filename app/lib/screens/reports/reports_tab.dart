import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/irrigation_record.dart';
import '../../models/water_stats.dart';
import '../../models/zone.dart';
import '../../providers/history_provider.dart';
import '../../providers/zone_provider.dart';
import '../../theme/app_theme.dart';

/// Reportes (Sprint 8): estadísticas de consumo de agua (HU-16) e historial
/// de riegos (HU-14), por zona y periodo.
class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    final names = context.watch<ZoneProvider>();
    final stats = history.stats;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppTheme.bgPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text('Reportes'),
            actions: [
              PopupMenuButton<bool>(
                tooltip: 'Más opciones',
                color: AppTheme.bgCard,
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (on) => on ? history.enableDemo() : history.disableDemo(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: !history.demo,
                    child: Text(history.demo ? 'Salir de la demostración' : 'Cargar datos de demostración'),
                  ),
                ],
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (history.demo) ...[
                  _DemoBanner(onExit: history.disableDemo),
                  const SizedBox(height: 16),
                ],
                _PeriodChips(history: history),
                const SizedBox(height: 12),
                _ZoneChips(history: history, names: names),
                const SizedBox(height: 20),
                _SummaryRow(stats: stats),
                const SizedBox(height: 10),
                _EstimateNote(history: history, names: names),
                const SizedBox(height: 20),
                _ConsumptionChart(stats: stats, names: names),
                const SizedBox(height: 28),
                _HistoryList(history: history, names: names),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// Color de cada zona en la gráfica y la lista
Color _zoneColor(int zone) => zone == 1 ? AppTheme.primary : AppTheme.accent;

/// Aviso de que se están viendo datos simulados (demostración del Sprint 8).
class _DemoBanner extends StatelessWidget {
  final VoidCallback onExit;
  const _DemoBanner({required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, color: AppTheme.warning, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Modo demostración: datos simulados de 6 meses. No son tus riegos reales.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
            ),
          ),
          TextButton(onPressed: onExit, child: const Text('Salir', style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

// ── Filtros ──────────────────────────────────────────────────────────────────
class _PeriodChips extends StatelessWidget {
  final HistoryProvider history;
  const _PeriodChips({required this.history});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in HistoryPeriod.values)
            _Chip(
              label: p.label,
              selected: history.period == p,
              onTap: () => history.setPeriod(p),
            ),
        ],
      ),
    );
  }
}

class _ZoneChips extends StatelessWidget {
  final HistoryProvider history;
  final ZoneProvider names;
  const _ZoneChips({required this.history, required this.names});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            label: 'Todas',
            selected: history.zoneFilter == null,
            onTap: () => history.setZone(null),
            small: true,
          ),
          for (final z in Zones.ids)
            _Chip(
              label: names.nameOf(z),
              selected: history.zoneFilter == z,
              onTap: () => history.setZone(z),
              small: true,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;
  const _Chip({required this.label, required this.selected, required this.onTap, this.small = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 10),
        padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20, vertical: small ? 7 : 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            fontSize: small ? 12 : 13,
          ),
        ),
      ),
    );
  }
}

// ── Tarjetas de resumen ──────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final WaterStats stats;
  const _SummaryRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryCard(
          icon: Icons.opacity_rounded,
          label: 'Agua total (est.)',
          value: WaterStats.formatLiters(stats.liters),
          color: AppTheme.accent,
        ),
        const SizedBox(width: 12),
        _SummaryCard(
          icon: Icons.repeat_rounded,
          label: 'Riegos',
          value: '${stats.runs}',
          color: AppTheme.primary,
        ),
        const SizedBox(width: 12),
        _SummaryCard(
          icon: Icons.timer_outlined,
          label: 'Tiempo total',
          value: WaterStats.formatMinutes(stats.seconds),
          color: AppTheme.warning,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Aclara que los litros son una estimación y permite ajustar el caudal.
class _EstimateNote extends StatelessWidget {
  final HistoryProvider history;
  final ZoneProvider names;
  const _EstimateNote({required this.history, required this.names});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'El consumo es una estimación: minutos regados × caudal de cada zona.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4),
          ),
        ),
        TextButton(
          onPressed: history.signedIn ? () => _editFlows(context, history, names) : null,
          child: const Text('Ajustar caudal', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

Future<void> _editFlows(BuildContext context, HistoryProvider history, ZoneProvider names) async {
  final messenger = ScaffoldMessenger.of(context);
  final values = await showDialog<Map<int, String>>(
    context: context,
    builder: (_) => _FlowDialog(
      initial: {for (final z in Zones.ids) z: _fmtFlow(history.flowOf(z))},
      names: names,
    ),
  );
  if (values == null) return;

  for (final z in Zones.ids) {
    final value = double.tryParse(values[z]!.trim().replaceAll(',', '.'));
    final error = await history.setFlow(z, value);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text('${names.nameOf(z)}: $error')));
      break;
    }
  }
}

/// Diálogo con un campo de caudal por zona. Los controladores viven en su
/// propio estado para liberarse cuando termina la animación de cierre.
class _FlowDialog extends StatefulWidget {
  final Map<int, String> initial;
  final ZoneProvider names;
  const _FlowDialog({required this.initial, required this.names});

  @override
  State<_FlowDialog> createState() => _FlowDialogState();
}

class _FlowDialogState extends State<_FlowDialog> {
  late final Map<int, TextEditingController> _controllers = {
    for (final e in widget.initial.entries) e.key: TextEditingController(text: e.value),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('Caudal de cada zona'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mide cuántos litros salen en un minuto (por ejemplo con una cubeta) '
              'para que la estimación sea más exacta. Entre 1 y 30 L/min.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final z in Zones.ids)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  key: ValueKey('flow-$z'),
                  controller: _controllers[z],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: widget.names.nameOf(z), suffixText: 'L/min'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.pop(context, {for (final e in _controllers.entries) e.key: e.value.text}),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

String _fmtFlow(double flow) => flow == flow.roundToDouble() ? flow.toStringAsFixed(0) : flow.toStringAsFixed(1);

// ── Gráfica de consumo ───────────────────────────────────────────────────────
class _ConsumptionChart extends StatelessWidget {
  final WaterStats stats;
  final ZoneProvider names;
  const _ConsumptionChart({required this.stats, required this.names});

  @override
  Widget build(BuildContext context) {
    final bars = stats.bars;
    final maxTotal = bars.fold<double>(0, (m, b) => b.total > m ? b.total : m);
    final zones = bars.expand((b) => b.liters.keys).toSet().toList()..sort();
    // Con 30 barras solo se rotulan algunas para que las etiquetas no se encimen
    final labelEvery = bars.length > 14 ? 5 : 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Consumo de agua',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (maxTotal > 0)
                Text(
                  'máx. ${WaterStats.formatLiters(maxTotal)}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (maxTotal == 0)
            const SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Sin consumo en este periodo',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < bars.length; i++)
                    Expanded(
                      child: _Bar(
                        bar: bars[i],
                        maxTotal: maxTotal,
                        showLabel: i % labelEvery == 0 || i == bars.length - 1 && labelEvery == 1,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            children: [
              for (final z in zones)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _zoneColor(z), borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 6),
                    Text(names.nameOf(z), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final ChartBar bar;
  final double maxTotal;
  final bool showLabel;
  const _Bar({required this.bar, required this.maxTotal, required this.showLabel});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${bar.label}: ${WaterStats.formatLiters(bar.total)}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: bar.total / maxTotal,
                widthFactor: 0.7,
                child: Column(
                  children: [
                    for (final e in bar.liters.entries.toList().reversed)
                      if (e.value > 0)
                        Expanded(
                          flex: (e.value * 1000).round().clamp(1, 1 << 30),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _zoneColor(e.key),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 14,
            child: showLabel
                ? OverflowBox(
                    maxWidth: 48,
                    child: Text(
                      bar.label,
                      maxLines: 1,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

// ── Historial de riegos ──────────────────────────────────────────────────────
class _HistoryList extends StatelessWidget {
  final HistoryProvider history;
  final ZoneProvider names;
  const _HistoryList({required this.history, required this.names});

  @override
  Widget build(BuildContext context) {
    final records = history.records;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Historial de riegos',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        if (history.error != null)
          _Message(icon: Icons.cloud_off_rounded, title: 'Sin conexión', text: history.error!)
        else if (history.loading && records.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (records.isEmpty)
          _Message(
            icon: Icons.history_rounded,
            title: 'Sin registros en este periodo',
            text: history.signedIn
                ? 'Aquí aparecerá cada riego con su zona, duración, estado y motivo.'
                : 'Inicia sesión para ver tu historial de riegos.',
          )
        else ...[
          for (final r in records) _RecordTile(record: r, zoneName: names.nameOf(r.zone)),
          if (history.truncated)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Se muestran los 200 riegos más recientes. Elige un periodo más corto para ver otros.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ),
        ],
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  final IrrigationRecord record;
  final String zoneName;
  const _RecordTile({required this.record, required this.zoneName});

  Color get _statusColor {
    switch (record.outcome) {
      case IrrigationOutcome.done:
        return AppTheme.success;
      case IrrigationOutcome.reduced:
        return AppTheme.primary;
      case IrrigationOutcome.skipped:
      case IrrigationOutcome.postponed:
      case IrrigationOutcome.cancelled:
        return AppTheme.warning;
      case IrrigationOutcome.failed:
        return AppTheme.danger;
    }
  }

  IconData get _icon {
    switch (record.outcome) {
      case IrrigationOutcome.done:
      case IrrigationOutcome.reduced:
        return Icons.water_drop_rounded;
      case IrrigationOutcome.skipped:
        return Icons.opacity_rounded;
      case IrrigationOutcome.postponed:
      case IrrigationOutcome.cancelled:
        return Icons.umbrella_rounded;
      case IrrigationOutcome.failed:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = record.local;
    String two(int n) => n.toString().padLeft(2, '0');
    final when = '${two(l.day)}/${two(l.month)}/${l.year} · ${two(l.hour)}:${two(l.minute)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: _statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: _zoneColor(record.zone), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        zoneName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      record.statusLabel,
                      style: TextStyle(color: _statusColor, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(when, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '${record.durationLabel} · ${record.reasonText}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _Message({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.textMuted, size: 44),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}
