import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/irrigation_notification.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_theme.dart';

/// Pantalla "Notificaciones": activar avisos con consentimiento y ver el
/// historial de inicio, fin y falla del riego por zona.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notif = context.watch<NotificationProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgPrimary,
        title: const Text('Notificaciones'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _ConsentCard(notif: notif),
          const SizedBox(height: 24),
          const Text(
            'AVISOS RECIENTES',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          if (notif.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Aún no hay avisos. Aparecerán aquí cuando una zona\ninicie, termine o falle.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.5),
                ),
              ),
            )
          else
            for (final n in notif.items)
              Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => notif.remove(n.id),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                ),
                child: _NotificationTile(item: n),
              ),
        ],
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final NotificationProvider notif;
  const _ConsentCard({required this.notif});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                notif.enabled
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_outlined,
                color: notif.enabled ? AppTheme.primary : AppTheme.textMuted,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Avisos en este teléfono',
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (notif.busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                )
              else
                Switch(
                  value: notif.enabled,
                  activeColor: AppTheme.primary,
                  onChanged: notif.supported ? (on) => _toggle(context, on) : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            notif.supported
                ? 'Te avisamos cuando el riego de una zona inicia, termina o falla, '
                    'aunque la app esté cerrada.'
                : 'Las notificaciones push en iOS aún no están disponibles: requieren una '
                    'clave APNs de Apple Developer. Puedes consultar los avisos en esta lista.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, bool on) async {
    final provider = context.read<NotificationProvider>();
    if (!on) {
      await provider.disable();
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Activar notificaciones',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Para enviarte los avisos guardaremos un identificador de este teléfono '
          '(token de notificaciones) en tu cuenta. Solo se usa para avisarte del '
          'riego de tus zonas y puedes desactivarlo cuando quieras; al hacerlo, '
          'el identificador se elimina.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Acepto'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final error = await provider.enable();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _NotificationTile extends StatelessWidget {
  final IrrigationNotification item;
  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.kind) {
      NotificationKind.fail  => (Icons.warning_amber_rounded, AppTheme.danger),
      NotificationKind.end   => (Icons.check_circle_outline_rounded, AppTheme.primary),
      NotificationKind.start => (Icons.water_drop_rounded, AppTheme.success),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.isFailure ? AppTheme.danger.withValues(alpha: 0.10) : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isFailure ? AppTheme.danger.withValues(alpha: 0.5) : AppTheme.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: TextStyle(
                        color: item.isFailure ? AppTheme.danger : AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(item.body,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
                const SizedBox(height: 6),
                Text(
                  '${item.manual ? 'Manual' : 'Programado'} · ${_when(item.createdAt)}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _when(DateTime? date) {
    if (date == null) return 'ahora';
    final d = DateTime.now().difference(date);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mi = date.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }
}
