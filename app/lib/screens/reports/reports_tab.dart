import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
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
            title: Text('Reportes'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Tabs de filtro (preparados para el futuro)
                _FilterChips(),
                const SizedBox(height: 24),

                // Tarjetas de resumen (esqueleto)
                _SummaryRow(),
                const SizedBox(height: 24),

                // Gráfica placeholder
                _ChartPlaceholder(),
                const SizedBox(height: 24),

                // Historial placeholder
                _HistoryPlaceholder(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chips de filtro temporal ────────────────────────────────────────────────
class _FilterChips extends StatefulWidget {
  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  int _selected = 0;
  final _filters = ['Hoy', 'Semana', 'Mes', 'Año'];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_filters.length, (i) {
          final sel = _selected == i;
          return GestureDetector(
            onTap: () => setState(() => _selected = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: sel
                    ? AppTheme.primary
                    : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: sel ? AppTheme.primary : AppTheme.divider,
                ),
              ),
              child: Text(
                _filters[i],
                style: TextStyle(
                  color: sel
                      ? Colors.white
                      : AppTheme.textSecondary,
                  fontWeight: sel
                      ? FontWeight.w700
                      : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Tarjetas de resumen ──────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryCard(
          icon: Icons.opacity_rounded,
          label: 'Agua total',
          value: '— L',
          color: AppTheme.accent,
        ),
        const SizedBox(width: 12),
        _SummaryCard(
          icon: Icons.repeat_rounded,
          label: 'Riegos',
          value: '—',
          color: AppTheme.primary,
        ),
        const SizedBox(width: 12),
        _SummaryCard(
          icon: Icons.timer_outlined,
          label: 'Tiempo total',
          value: '— min',
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
            Text(
              value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
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
      ),
    );
  }
}

// ── Gráfica placeholder ──────────────────────────────────────────────────────
class _ChartPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withOpacity(0.1),
            ),
            child: const Icon(Icons.bar_chart_rounded,
                color: AppTheme.primary, size: 30),
          ),
          const SizedBox(height: 16),
          const Text(
            'Gráfica de consumo',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Próximamente disponible',
            style: TextStyle(
                color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Historial placeholder ─────────────────────────────────────────────────────
class _HistoryPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Historial de riegos',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: [
              Icon(
                Icons.history_rounded,
                color: AppTheme.textMuted,
                size: 44,
              ),
              const SizedBox(height: 16),
              const Text(
                'Sin registros aún',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aquí aparecerá el historial detallado de cada sesión de riego',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
