import 'dart:async';
import 'package:flutter/material.dart';
import 'irrigation_provider.dart';
import 'schedule_provider.dart';

/// Corre un timer cada 30 segundos y compara la hora actual
/// con la programación activa. Si coincide hora y día, enciende
/// el riego; cuando se cumple la duración, lo apaga.
class SchedulerService {
  Timer? _timer;
  IrrigationProvider? _irrigation;
  ScheduleProvider? _schedules;

  // Guarda el ID del schedule que ya fue disparado en este minuto
  // para no re-disparararlo cada tick.
  String? _lastFiredId;
  DateTime? _scheduledStop;

  void init(IrrigationProvider irrigation, ScheduleProvider schedules) {
    _irrigation = irrigation;
    _schedules  = schedules;

    // Primer chequeo inmediato, luego cada 30 s
    _check();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _check() {
    final irrigation = _irrigation;
    final schedules  = _schedules;
    if (irrigation == null || schedules == null) return;

    final now    = DateTime.now();
    final active = schedules.activeSchedule;

    // ── 1. Chequear si hay que APAGAR por duración cumplida ──────────────
    if (_scheduledStop != null && now.isAfter(_scheduledStop!)) {
      if (irrigation.isActive && !irrigation.manualOverride) {
        irrigation.turnOff();
        _scheduledStop = null;
        _lastFiredId   = null;
        debugPrint('[Scheduler] Riego terminado por duración.');
      }
      return;
    }

    // ── 2. Sin programación activa → nada que hacer ───────────────────────
    if (active == null) return;

    // ── 3. Verificar DÍA de la semana ────────────────────────────────────
    // DateTime.weekday: 1=Lun … 7=Dom  |  nuestro modelo: 0=Lun … 6=Dom
    final todayIdx = now.weekday - 1; // 0-6
    if (!active.days.contains(todayIdx)) return;

    // ── 4. Verificar HORA dentro de la ventana de 1 minuto ───────────────
    final schedStart = DateTime(
      now.year, now.month, now.day,
      active.startHour, active.startMinute,
    );
    final diff = now.difference(schedStart).inSeconds.abs();

    // La ventana es ±60 s para no depender del tick exacto
    final withinWindow = diff <= 60 &&
        now.isAfter(schedStart.subtract(const Duration(seconds: 5)));

    if (!withinWindow) return;

    // ── 5. ¿Ya lo disparamos en este ciclo? ─────────────────────────────
    if (_lastFiredId == active.id) return;
    if (irrigation.isActive)       return; // manual override activo

    // ── 6. ¡Disparar! ────────────────────────────────────────────────────
    _lastFiredId   = active.id;
    _scheduledStop = now.add(Duration(minutes: active.durationMinutes));
    irrigation.activateFromSchedule();
    debugPrint(
      '[Scheduler] Riego iniciado → ${active.name} '
      'hasta ${_scheduledStop.toString().substring(11, 16)}',
    );
  }

  /// Llama esto cuando el usuario edita/elimina una programación activa
  /// para cancelar cualquier stop pendiente.
  void invalidate() {
    _scheduledStop = null;
    _lastFiredId   = null;
  }
}
