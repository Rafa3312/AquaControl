/// Hora local del proyecto: México (Querétaro) usa UTC-6 todo el año, sin
/// horario de verano. Agrupar por fecha UTC movía los riegos de las 23:30 al
/// día siguiente (error del Sprint 3 que volvió a aparecer en el Sprint 8),
/// por eso todo el historial se agrupa con estas funciones.
const Duration kLocalOffset = Duration(hours: -6);

/// Hora local de un instante. El resultado es un DateTime en UTC cuyos campos
/// (año, mes, día, hora…) son los de la hora local; no se debe convertir otra vez.
DateTime localClock(DateTime instant) => instant.toUtc().add(kLocalOffset);

/// Día local (medianoche) de un instante.
DateTime localDay(DateTime instant) {
  final l = localClock(instant);
  return DateTime.utc(l.year, l.month, l.day);
}

/// Instante real en que empieza un día local.
DateTime startOfLocalDay(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).subtract(kLocalOffset);

/// AAAA-MM-DD de un día local (es también el id de users/{uid}/dailyStats).
String dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${_two(day.month)}-${_two(day.day)}';

/// AAAA-MM de un día local.
String monthKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-${_two(day.month)}';

String _two(int n) => n.toString().padLeft(2, '0');
