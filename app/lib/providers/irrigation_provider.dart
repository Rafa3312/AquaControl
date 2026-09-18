import 'dart:async';
import 'package:flutter/material.dart';
import 'device_provider.dart';

enum IrrigationStatus { idle, active, scheduled, error }

class IrrigationProvider extends ChangeNotifier {
  DeviceProvider? _device;
  Timer?          _pollTimer;   // Consulta periódica al ESP cada 5s

  IrrigationStatus _status         = IrrigationStatus.idle;
  bool             _manualOverride = false;
  bool             _scheduledRun   = false; // corriendo por programación
  DateTime?        _startTime;
  double           _waterUsageToday = 0;
  int              _sessionsToday   = 0;

  IrrigationStatus get status         => _status;
  bool   get manualOverride  => _manualOverride;
  bool   get isActive        => _status == IrrigationStatus.active;
  bool   get isScheduledRun  => _scheduledRun; // para bloquear botones manuales
  bool   get canManualControl => !_scheduledRun; // false = botones deshabilitados
  DateTime? get startTime    => _startTime;
  bool   get deviceOnline    => _device?.isConnected ?? false;
  double get waterUsageToday => _waterUsageToday;
  int    get sessionsToday   => _sessionsToday;

  String get statusLabel {
    switch (_status) {
      case IrrigationStatus.active:
        return _scheduledRun ? 'Riego Programado' : 'Riego Manual';
      case IrrigationStatus.scheduled: return 'Programado';
      case IrrigationStatus.error:     return 'Error de conexión';
      case IrrigationStatus.idle:      return 'En reposo';
    }
  }

  String get elapsedTime {
    if (_startTime == null) return '00:00';
    final d = DateTime.now().difference(_startTime!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Inyectar DeviceProvider ─────────────────────────────────────────────
  void setDeviceProvider(DeviceProvider device) {
    _device = device;
    device.addListener(_onDeviceChanged);
    // Arrancar polling periódico al ESP cada 5 segundos
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => syncStatus());
    notifyListeners();
  }

  void _onDeviceChanged() {
    if (_device?.isConnected == true) {
      // Al reconectar, sincronizar estado inmediatamente
      syncStatus();
    }
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SINCRONIZACIÓN CON EL ESP ← esto es lo que faltaba
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> syncStatus() async {
    final espStatus = await _device?.getStatus();
    if (espStatus == null) return;

    final valveOpen = espStatus['valve'] == true;
    final isManual  = espStatus['manual'] == true;

    if (valveOpen && !isActive) {
      // El ESP está regando pero la app no lo sabía → actualizar
      _status        = IrrigationStatus.active;
      _manualOverride = isManual;
      _scheduledRun  = !isManual;
      _startTime     ??= DateTime.now(); // no sobreescribir si ya tenía
      notifyListeners();
    } else if (!valveOpen && isActive) {
      // El ESP terminó de regar (programación cumplió duración)
      _finishSession();
      notifyListeners();
    }
  }

  // ── Encender manual ──────────────────────────────────────────────────────
  Future<void> turnOn() async {
    if (isActive) return;

    // Optimistic UI
    _status         = IrrigationStatus.active;
    _manualOverride = true;
    _scheduledRun   = false;
    _startTime      = DateTime.now();
    notifyListeners();

    final ok = await _device?.turnOn(durationMinutes: 0) ?? false;
    if (!ok) {
      _status         = IrrigationStatus.error;
      _manualOverride = false;
      _startTime      = null;
      notifyListeners();
    }
  }

  // ── Modo prueba rápida (30 segundos) ─────────────────────────────────────
  Future<void> turnOnTest({int seconds = 30}) async {
    if (isActive) return;
    _status         = IrrigationStatus.active;
    _manualOverride = true;
    _scheduledRun   = false;
    _startTime      = DateTime.now();
    notifyListeners();

    // Enviar duración en minutos (redondeado hacia arriba, mínimo 1)
    final durationMin = (seconds / 60).ceil().clamp(1, 480);
    final ok = await _device?.turnOn(durationMinutes: durationMin) ?? false;
    if (!ok) {
      _status     = IrrigationStatus.error;
      _startTime  = null;
      notifyListeners();
      return;
    }

    // Timer local para mostrar que terminó en la UI
    Timer(Duration(seconds: seconds), () {
      if (isActive && _manualOverride) {
        _finishSession();
        notifyListeners();
      }
    });
  }

  // ── Apagar manual ────────────────────────────────────────────────────────
  Future<void> turnOff() async {
    if (!isActive) return;
    _finishSession();
    notifyListeners();
    await _device?.turnOff();
  }

  // ── Activar desde scheduler interno de Flutter ───────────────────────────
  void activateFromSchedule() {
    _status        = IrrigationStatus.active;
    _manualOverride = false;
    _scheduledRun  = true;
    _startTime     = DateTime.now();
    notifyListeners();
  }

  void _finishSession() {
    if (_startTime != null) {
      final dur = DateTime.now().difference(_startTime!);
      _waterUsageToday += dur.inMinutes * 0.8;
      if (dur.inSeconds >= 10) _sessionsToday++; // solo contar si duró algo
    }
    _status         = IrrigationStatus.idle;
    _manualOverride = false;
    _scheduledRun   = false;
    _startTime      = null;
  }

  void resetDailyStats() {
    _waterUsageToday = 0;
    _sessionsToday   = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _device?.removeListener(_onDeviceChanged);
    super.dispose();
  }
}
