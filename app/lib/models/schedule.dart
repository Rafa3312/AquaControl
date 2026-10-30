import 'package:flutter/material.dart';

import 'zone.dart';

class Schedule {
  final String id;
  String name;
  List<int> days; // 0=Lunes … 6=Domingo
  int startHour;
  int startMinute;
  int durationMinutes;
  int zone; // 1..Zones.count
  bool isActive;
  DateTime createdAt;

  Schedule({
    required this.id,
    required this.name,
    required this.days,
    required this.startHour,
    required this.startMinute,
    required this.durationMinutes,
    this.zone = 1,
    this.isActive = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  TimeOfDay get time => TimeOfDay(hour: startHour, minute: startMinute);

  String get daysLabel {
    const labels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    if (days.length == 7) return 'Todos los días';
    if (days.isEmpty) return 'Sin días';
    return days.map((d) => labels[d]).join(', ');
  }

  String get timeLabel {
    final h = startHour.toString().padLeft(2, '0');
    final m = startMinute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get durationLabel {
    if (durationMinutes < 60) return '$durationMinutes min';
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'days': days,
        'startHour': startHour,
        'startMinute': startMinute,
        'durationMinutes': durationMinutes,
        'zone': zone,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Las programaciones guardadas antes del Sprint 5 no tienen zona:
  /// se asignan a la zona 1, igual que en el firmware.
  factory Schedule.fromJson(Map<String, dynamic> json) {
    final rawZone = json['zone'];
    return Schedule(
      id: json['id'],
      name: json['name'],
      days: List<int>.from(json['days']),
      startHour: json['startHour'],
      startMinute: json['startMinute'],
      durationMinutes: json['durationMinutes'],
      zone: rawZone is int && Zones.isValid(rawZone) ? rawZone : 1,
      isActive: json['isActive'] ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  Schedule copyWith({
    String? name,
    List<int>? days,
    int? startHour,
    int? startMinute,
    int? durationMinutes,
    int? zone,
    bool? isActive,
  }) =>
      Schedule(
        id: id,
        name: name ?? this.name,
        days: days ?? List.from(this.days),
        startHour: startHour ?? this.startHour,
        startMinute: startMinute ?? this.startMinute,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        zone: zone ?? this.zone,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );
}
