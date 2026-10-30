import 'dart:async';
import 'package:flutter/material.dart';
import '../models/zone.dart';
import 'device_provider.dart';

enum IrrigationStatus { idle, active, scheduled, error }

/// Estado del riego de una zona en la app.
class ZoneRuntime {
  final int id;
  IrrigationStatus status = IrrigationStatus.idle;
  bool manualOverride = false;
  bool scheduledRun = false;
  bool fault = false;
  DateTime? startTime;
  String? stopAt;

  ZoneRuntime(this.id);

  bool get isActive => status == IrrigationStatus.active;

  String get statusLabel {
    if (fault && !isActive) return 'Falla en la válvula';
    switch (status) {
      case IrrigationStatus.active:
        return scheduledRun ? 'Riego Programado' : 'Riego Manual';
      case IrrigationStatus.scheduled:
        return 'Programado';
      case IrrigationStatus.error:
        return 'Error de conexión';
      case IrrigationStatus.idle:
        return 'En reposo';
    }
  }

  String get elapsedTime {
    if (startTime == null) return '00:00';
    final d = DateTime.now().difference(startTime!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Controla el riego de cada zona. Las propiedades sin zona (isActive,
/// statusLabel, turnOn…) se refieren a la zona seleccionada en el Dashboard.
class IrrigationProvider extends ChangeNotifier {
  DeviceProvider? _device;
  Timer?          _pollTimer;   // Consulta periódica al ESP cada 5s

  final Map<int, ZoneRuntime> _zones = {
    for (final id in Zones.ids) id: ZoneRuntime(id),
  };
  int    _selectedZone    = 1;
  double _waterUsageToday = 0;
  int    _sessionsToday   = 0;

  // ── Zonas ────────────────────────────────────────────────────────────────
  List<ZoneRuntime> get zones => _zones.values.toList();
  ZoneRuntime zone(int id) => _zones[id]!;
  int  get selectedZone => _selectedZone;
  bool get anyActive    => _zones.values.any((z) => z.isActive);
  int  get activeCount  => _zones.values.where((z) => z.isActive).length;

  void selectZone(int id) {
    if (!Zones.isValid(id) || id == _selectedZone) return;
    _selectedZone = id;
    notifyListeners();
  }

  ZoneRuntime get _sel => _zones[_selectedZone]!;

  // ── Zona seleccionada ────────────────────────────────────────────────────
  IrrigationStatus get status         => _sel.status;
  bool   get manualOverride  => _sel.manualOverride;
  bool   get isActive        => _sel.isActive;
  bool   get isScheduledRun  => _sel.scheduledRun; // para bloquear botones manuales
  bool   get canManualControl => !_sel.scheduledRun;
  DateTime? get startTime    => _sel.startTime;
  String get statusLabel     => _sel.statusLabel;
  String get elapsedTime     => _sel.elapsedTime;

  bool   get deviceOnline    => _device?.isConnected ?? false;
  double get waterUsageToday => _waterUsageToday;
  int    get sessionsToday   => _sessionsToday;

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
  // SINCRONIZACIÓN CON EL ESP (estado de cada zona)
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> syncStatus() async {
    final espStatus = await _device?.getStatus();
    if (espStatus == null) return;

    var changed = false;
    for (final zs in ZoneStatus.listFromStatus(espStatus)) {
      final z = _zones[zs.id]!;
      if (zs.valveOpen && !z.isActive) {
        // El ESP está regando pero la app no lo sabía → actualizar
        z.status         = IrrigationStatus.active;
        z.manualOverride = zs.manual;
        z.scheduledRun   = !zs.manual;
        z.startTime    ??= DateTime.now(); // no sobreescribir si ya tenía
        changed = true;
      } else if (!zs.valveOpen && z.isActive) {
        // El ESP terminó de regar esa zona
        _finishSession(z);
        changed = true;
      }
      if (z.fault != zs.fault || z.stopAt != zs.stopAt) {
        z.fault  = zs.fault;
        z.stopAt = zs.stopAt;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ── Encender manual ──────────────────────────────────────────────────────
  Future<void> turnOn({int? zone}) async {
    final z = _zones[zone ?? _selectedZone]!;
    if (z.isActive) return;

    // Optimistic UI
    z.status         = IrrigationStatus.active;
    z.manualOverride = true;
    z.scheduledRun   = false;
    z.fault          = false;
    z.startTime      = DateTime.now();
    notifyListeners();

    final ok = await _device?.turnOn(zone: z.id, durationMinutes: 0) ?? false;
    if (!ok) {
      z.status         = IrrigationStatus.error;
      z.manualOverride = false;
      z.startTime      = null;
      notifyListeners();
    }
  }

  // ── Modo prueba rápida ───────────────────────────────────────────────────
  Future<void> turnOnTest({int seconds = 30, int? zone}) async {
    final z = _zones[zone ?? _selectedZone]!;
    if (z.isActive) return;
    z.status         = IrrigationStatus.active;
    z.manualOverride = true;
    z.scheduledRun   = false;
    z.fault          = false;
    z.startTime      = DateTime.now();
    notifyListeners();

    // Enviar duración en minutos (redondeado hacia arriba, mínimo 1)
    final durationMin = (seconds / 60).ceil().clamp(1, 120);
    final ok = await _device?.turnOn(zone: z.id, durationMinutes: durationMin) ?? false;
    if (!ok) {
      z.status    = IrrigationStatus.error;
      z.startTime = null;
      notifyListeners();
      return;
    }

    // Timer local para mostrar que terminó en la UI
    Timer(Duration(seconds: seconds), () {
      if (z.isActive && z.manualOverride) {
        _finishSession(z);
        notifyListeners();
      }
    });
  }

  // ── Apagar manual ────────────────────────────────────────────────────────
  Future<void> turnOff({int? zone}) async {
    final z = _zones[zone ?? _selectedZone]!;
    if (!z.isActive) return;
    _finishSession(z);
    notifyListeners();
    await _device?.turnOff(zone: z.id);
  }

  /// Interruptor de la pantalla "Zonas de riego".
  Future<void> toggleZone(int id) =>
      _zones[id]!.isActive ? turnOff(zone: id) : turnOn(zone: id);

  // ── Activar desde scheduler interno de Flutter ───────────────────────────
  void activateFromSchedule(int zone) {
    final z = _zones[zone];
    if (z == null) return;
    z.status         = IrrigationStatus.active;
    z.manualOverride = false;
    z.scheduledRun   = true;
    z.startTime      = DateTime.now();
    notifyListeners();
  }

  void _finishSession(ZoneRuntime z) {
    if (z.startTime != null) {
      final dur = DateTime.now().difference(z.startTime!);
      _waterUsageToday += dur.inMinutes * 0.8;
      if (dur.inSeconds >= 10) _sessionsToday++; // solo contar si duró algo
    }
    z.status         = IrrigationStatus.idle;
    z.manualOverride = false;
    z.scheduledRun   = false;
    z.startTime      = null;
    z.stopAt         = null;
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
