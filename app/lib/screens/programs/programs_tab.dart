import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/schedule.dart';
import '../../providers/schedule_provider.dart';
import 'add_edit_schedule_screen.dart';

class ProgramsTab extends StatelessWidget {
  const ProgramsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final sched = context.watch<ScheduleProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            backgroundColor: AppTheme.bgPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text('Programas'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded,
                    color: AppTheme.primary, size: 26),
                onPressed: () => _openAddEdit(context, null),
              ),
            ],
          ),

          if (sched.loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            )
          else if (sched.schedules.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                onAdd: () => _openAddEdit(context, null),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final s = sched.schedules[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ScheduleCard(
                        schedule: s,
                        onEdit: () => _openAddEdit(context, s),
                        onDelete: () => _confirmDelete(context, s),
                        onToggle: () => sched.toggleActive(s.id),
                      ),
                    );
                  },
                  childCount: sched.schedules.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: sched.schedules.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _openAddEdit(context, null),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva programación',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
    );
  }

  void _openAddEdit(BuildContext ctx, Schedule? existing) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => AddEditScheduleScreen(existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, Schedule s) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Eliminar programación',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          '¿Eliminar "${s.name}"? Esta acción no se puede deshacer.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true && ctx.mounted) {
      ctx.read<ScheduleProvider>().deleteSchedule(s.id);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tarjeta de programación
// ══════════════════════════════════════════════════════════════════════════════
class _ScheduleCard extends StatelessWidget {
  final Schedule schedule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _ScheduleCard({
    required this.schedule,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final active = schedule.isActive;
    final borderColor =
        active ? AppTheme.success.withOpacity(0.4) : AppTheme.divider;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        children: [
          // Franja superior de color si activo
          if (active)
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.success, AppTheme.accent],
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(18)),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                // Fila superior: nombre + toggle
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: active
                            ? AppTheme.success.withOpacity(0.15)
                            : AppTheme.bgCardLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: active
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            schedule.name,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (active)
                            const Text(
                              'Programación activa',
                              style: TextStyle(
                                color: AppTheme.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Toggle activar/desactivar
                    GestureDetector(
                      onTap: onToggle,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 50,
                        height: 28,
                        decoration: BoxDecoration(
                          color: active
                              ? AppTheme.success
                              : AppTheme.bgCardLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          alignment: active
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: AppTheme.divider),
                const SizedBox(height: 14),

                // Detalles
                Row(
                  children: [
                    _DetailChip(
                      icon: Icons.calendar_month_outlined,
                      label: schedule.daysLabel,
                    ),
                    const SizedBox(width: 8),
                    _DetailChip(
                      icon: Icons.access_time_rounded,
                      label: schedule.timeLabel,
                    ),
                    const SizedBox(width: 8),
                    _DetailChip(
                      icon: Icons.timer_outlined,
                      label: schedule.durationLabel,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Botones editar / eliminar
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Editar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(
                              color: AppTheme.primary, width: 1),
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          textStyle: const TextStyle(fontSize: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 16),
                        label: const Text('Eliminar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(
                              color: AppTheme.danger, width: 1),
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          textStyle: const TextStyle(fontSize: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.bgCardLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppTheme.primary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Estado vacío
// ══════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withOpacity(0.1),
              ),
              child: const Icon(Icons.calendar_month_outlined,
                  color: AppTheme.primary, size: 44),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sin programaciones',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Crea tu primera programación de riego para automatizar tus aspersores',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear programación'),
            ),
          ],
        ),
      ),
    );
  }
}
