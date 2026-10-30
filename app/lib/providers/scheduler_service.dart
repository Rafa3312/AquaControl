import 'dart:async';
import 'package:flutter/material.dart';
import '../models/zone.dart';
import 'irrigation_provider.dart';
import 'schedule_provider.dart';

/// Corre un timer cada 30 segundos y compara la hora actual con la
/// programación activa de cada zona. Si coincide hora y día, marca la zona
/// como regando; cuando se cumple la duración, la apaga. El ESP32 ejecuta
/// los horarios por su cuenta; esto mantiene la UI al día.
class SchedulerService {
  /// [clock] se inyecta en las pruebas para simular la hora.
  SchedulerService({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;
  Timer? _timer;
  IrrigationProvider? _irrigation;
  ScheduleProvider? _schedules;

  // Por zona: ID del schedule ya disparado y hora de apagado pendiente
  final Map<int, String?>   _lastFiredId   = {};
  final Map<int, DateTime?> _scheduledStop = {};

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

  /// Ejecuta una revisión sin esperar al timer (para las pruebas).
  @visibleForTesting
  void tick() => _check();

  void _check() {
    final irrigation = _irrigation;
    final schedules  = _schedules;
    if (irrigation == null || schedules == null) return;

    final now = _now();
    for (final zoneId in Zones.ids) {
      _checkZone(zoneId, now, irrigation, schedules);
    }
  }

  void _checkZone(int zoneId, DateTime now, IrrigationProvider irrigation,
      ScheduleProvider schedules) {
    final zone   = irrigation.zone(zoneId);
    final active = schedules.activeScheduleFor(zoneId);
    final stop   = _scheduledStop[zoneId];

    // ── 1. Chequear si hay que APAGAR por duración cumplida ──────────────
    if (stop != null && now.isAfter(stop)) {
      if (zone.isActive && !zone.manualOverride) {
        irrigation.turnOff(zone: zoneId);
        debugPrint('[Scheduler] Zona $zoneId: riego terminado por duración.');
      }
      _scheduledStop[zoneId] = null;
      _lastFiredId[zoneId]   = null;
      return;
    }

    // ── 2. Sin programación activa en la zona → nada que hacer ────────────
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
    if (_lastFiredId[zoneId] == active.id) return;
    if (zone.isActive) return; // la zona ya está regando (p. ej. manual)

    // ── 6. ¡Disparar! ────────────────────────────────────────────────────
    _lastFiredId[zoneId]   = active.id;
    _scheduledStop[zoneId] = now.add(Duration(minutes: active.durationMinutes));
    irrigation.activateFromSchedule(zoneId);
    debugPrint(
      '[Scheduler] Zona $zoneId: riego iniciado → ${active.name} '
      'hasta ${_scheduledStop[zoneId].toString().substring(11, 16)}',
    );
  }

  /// Llama esto cuando el usuario edita/elimina una programación activa
  /// para cancelar cualquier stop pendiente.
  void invalidate() {
    _scheduledStop.clear();
    _lastFiredId.clear();
  }
}
