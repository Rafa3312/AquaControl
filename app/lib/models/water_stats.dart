import '../utils/local_time.dart';
import 'zone.dart';

/// Periodos de Reportes: Hoy, Semana, Mes y Año (HU-14 y HU-16).
enum HistoryPeriod { today, week, month, year }

extension HistoryPeriodInfo on HistoryPeriod {
  String get label {
    switch (this) {
      case HistoryPeriod.today:
        return 'Hoy';
      case HistoryPeriod.week:
        return 'Semana';
      case HistoryPeriod.month:
        return 'Mes';
      case HistoryPeriod.year:
        return 'Año';
    }
  }

  /// Días locales que cubre, terminando hoy:
  /// Hoy = 1 día · Semana = 7 días · Mes = 30 días · Año = 12 meses naturales
  /// (desde el día 1 del mes de hace 11 meses; los datos se guardan 12 meses).
  PeriodRange range(DateTime now) {
    final today = localDay(now);
    switch (this) {
      case HistoryPeriod.today:
        return PeriodRange(today, today);
      case HistoryPeriod.week:
        return PeriodRange(today.subtract(const Duration(days: 6)), today);
      case HistoryPeriod.month:
        return PeriodRange(today.subtract(const Duration(days: 29)), today);
      case HistoryPeriod.year:
        // DateTime.utc normaliza los meses fuera de rango (mes -3 = octubre del año anterior)
        return PeriodRange(DateTime.utc(today.year, today.month - 11, 1), today);
    }
  }
}

/// Primer y último día local de un periodo (ambos incluidos).
class PeriodRange {
  final DateTime firstDay;
  final DateTime lastDay;
  const PeriodRange(this.firstDay, this.lastDay);

  String get firstKey => dayKey(firstDay);
  String get lastKey => dayKey(lastDay);

  /// Instante real en que empieza el periodo (para consultar el historial).
  DateTime get startInstant => startOfLocalDay(firstDay);

  bool containsKey(String key) => key.compareTo(firstKey) >= 0 && key.compareTo(lastKey) <= 0;
}

/// Lo regado por una zona en un día (un campo de users/{uid}/dailyStats/{fecha}).
class ZoneDay {
  final int runs;
  final int seconds;
  final int skipped;
  const ZoneDay({this.runs = 0, this.seconds = 0, this.skipped = 0});
}

/// Resumen de un día: users/{uid}/dailyStats/{AAAA-MM-DD}.
class DailyStat {
  final String date;
  final Map<int, ZoneDay> zones;
  const DailyStat(this.date, this.zones);

  /// Devuelve null si el id no es una fecha válida; ignora zonas inválidas.
  static DailyStat? tryParse(String id, Map<String, dynamic> data) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(id)) return null;
    final zones = <int, ZoneDay>{};
    final raw = data['zones'];
    if (raw is Map) {
      raw.forEach((key, value) {
        final zone = int.tryParse('$key');
        if (zone == null || !Zones.isValid(zone) || value is! Map) return;
        zones[zone] = ZoneDay(
          runs: _count(value['runs']),
          seconds: _count(value['seconds']),
          skipped: _count(value['skipped']),
        );
      });
    }
    return DailyStat(id, zones);
  }

  static int _count(Object? v) => v is num && v >= 0 ? v.toInt() : 0;
}

/// Una barra de la gráfica de consumo: litros por zona en ese día, mes o zona.
class ChartBar {
  final String key;
  final String label;
  final Map<int, double> liters;
  const ChartBar(this.key, this.label, this.liters);

  double get total => liters.values.fold(0.0, (a, b) => a + b);
}

/// Estadísticas de consumo de agua de un periodo (HU-16).
///
/// El consumo es una **estimación**: minutos regados × caudal de la zona
/// (L/min). El caudal se mide con una cubeta y se puede ajustar por zona.
class WaterStats {
  final double liters;
  final int runs;
  final int seconds;
  final int skipped;
  final List<ChartBar> bars;

  const WaterStats({
    required this.liters,
    required this.runs,
    required this.seconds,
    required this.skipped,
    required this.bars,
  });

  static const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _months = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  /// Calcula las estadísticas de [period] con los resúmenes diarios [days].
  /// [zone] filtra una sola zona (null = todas). [flowLpm] es el caudal de
  /// cada zona; si falta, se usa el nominal ([Zones.defaultFlowLpm]).
  static WaterStats compute({
    required HistoryPeriod period,
    required DateTime now,
    required List<DailyStat> days,
    Map<int, double> flowLpm = const {},
    int? zone,
  }) {
    final range = period.range(now);
    final zoneIds = zone == null ? Zones.ids : [zone];
    double flow(int z) => flowLpm[z] ?? Zones.defaultFlowLpm;

    // Solo los días dentro del periodo (una consulta puede traer de más)
    final byDay = {
      for (final d in days)
        if (range.containsKey(d.date)) d.date: d,
    };

    var liters = 0.0;
    var runs = 0;
    var seconds = 0;
    var skipped = 0;
    final litersOfDay = <String, Map<int, double>>{};

    for (final d in byDay.values) {
      final perZone = <int, double>{};
      for (final z in zoneIds) {
        final zd = d.zones[z];
        if (zd == null) continue;
        final l = zd.seconds / 60 * flow(z);
        perZone[z] = l;
        liters += l;
        runs += zd.runs;
        seconds += zd.seconds;
        skipped += zd.skipped;
      }
      litersOfDay[d.date] = perZone;
    }

    return WaterStats(
      liters: liters,
      runs: runs,
      seconds: seconds,
      skipped: skipped,
      bars: _bars(period, range, zoneIds, litersOfDay),
    );
  }

  static List<ChartBar> _bars(
    HistoryPeriod period,
    PeriodRange range,
    List<int> zoneIds,
    Map<String, Map<int, double>> litersOfDay,
  ) {
    // Hoy: un solo día, así que las barras son las zonas
    if (period == HistoryPeriod.today) {
      final today = litersOfDay[range.lastKey] ?? const <int, double>{};
      return [
        for (final z in zoneIds) ChartBar('zona-$z', 'Zona $z', {z: today[z] ?? 0}),
      ];
    }

    // Año: una barra por mes natural
    if (period == HistoryPeriod.year) {
      final bars = <ChartBar>[];
      for (var m = range.firstDay; !m.isAfter(range.lastDay); m = DateTime.utc(m.year, m.month + 1, 1)) {
        final key = monthKey(m);
        final perZone = <int, double>{for (final z in zoneIds) z: 0};
        litersOfDay.forEach((date, zones) {
          if (date.startsWith(key)) zones.forEach((z, l) => perZone[z] = (perZone[z] ?? 0) + l);
        });
        bars.add(ChartBar(key, _months[m.month - 1], perZone));
      }
      return bars;
    }

    // Semana y Mes: una barra por día
    final bars = <ChartBar>[];
    for (var d = range.firstDay; !d.isAfter(range.lastDay); d = d.add(const Duration(days: 1))) {
      final key = dayKey(d);
      final label = period == HistoryPeriod.week ? _weekdays[d.weekday - 1] : '${d.day}';
      bars.add(ChartBar(key, label, {
        for (final z in zoneIds) z: litersOfDay[key]?[z] ?? 0,
      }));
    }
    return bars;
  }

  /// "12.4 L" (menos de 100 L con un decimal; desde 100 L, entero).
  static String formatLiters(double liters) {
    if (liters >= 100) return '${liters.round()} L';
    return '${liters.toStringAsFixed(1)} L';
  }

  /// "45 min" o "2 h 05 min".
  static String formatMinutes(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
  }
}
