import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/schedule.dart';

class ScheduleProvider extends ChangeNotifier {
  List<Schedule> _schedules = [];
  bool _loading = false;
  static const _key = 'schedules_v1';

  List<Schedule> get schedules => List.unmodifiable(_schedules);
  bool get loading => _loading;
  Schedule? get activeSchedule =>
      _schedules.where((s) => s.isActive).firstOrNull;

  /// Programación activa de una zona (solo puede haber una por zona).
  Schedule? activeScheduleFor(int zone) =>
      _schedules.where((s) => s.isActive && s.zone == zone).firstOrNull;

  List<Schedule> schedulesFor(int zone) =>
      _schedules.where((s) => s.zone == zone).toList();
  int get totalCount => _schedules.length;

  ScheduleProvider() {
    _load();
  }

  Future<void> _load() async {
    _loading = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _schedules = list.map((e) => Schedule.fromJson(e)).toList();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_schedules.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> addSchedule(Schedule schedule) async {
    _schedules.insert(0, schedule);
    await _save();
    notifyListeners();
  }

  Future<void> updateSchedule(Schedule updated) async {
    final idx = _schedules.indexWhere((s) => s.id == updated.id);
    if (idx == -1) return;
    _schedules[idx] = updated;
    await _save();
    notifyListeners();
  }

  Future<void> deleteSchedule(String id) async {
    _schedules.removeWhere((s) => s.id == id);
    await _save();
    notifyListeners();
  }

  // Solo una programación activa POR ZONA: activar una desactiva las demás
  // de la misma zona; las de otras zonas no cambian.
  Future<void> toggleActive(String id) async {
    final target = _schedules.where((s) => s.id == id).firstOrNull;
    if (target == null) return;
    final activate = !target.isActive;
    if (activate) {
      for (final s in _schedules) {
        if (s.zone == target.zone) s.isActive = false;
      }
    }
    target.isActive = activate;
    await _save();
    notifyListeners();
  }

  Schedule buildNew({
    required String name,
    required List<int> days,
    required int hour,
    required int minute,
    required int duration,
    int zone = 1,
  }) =>
      Schedule(
        id: const Uuid().v4(),
        name: name,
        days: days,
        startHour: hour,
        startMinute: minute,
        durationMinutes: duration,
        zone: zone,
      );
}
