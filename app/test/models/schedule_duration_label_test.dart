import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/schedule.dart';

/// Pruebas de Schedule.durationLabel (AquaControl).
///
/// Recibe la duración del riego en minutos (durationMinutes) y devuelve el
/// texto que se muestra en la app:
///   - menos de 60 min  -> "N min"
///   - horas exactas    -> "Nh"
///   - horas y minutos  -> "Nh Mmin"
///
/// Se aplica análisis de valores límite (59/60 min) y el patrón AAA.
void main() {
  // Programación mínima; solo importa durationMinutes para estas pruebas.
  Schedule buildSchedule(int durationMinutes) => Schedule(
        id: 'p1',
        name: 'Riego de prueba',
        days: [0],
        startHour: 6,
        startMinute: 0,
        durationMinutes: durationMinutes,
      );

  group('Schedule.durationLabel', () {
    test('CP-01 muestra solo minutos cuando la duración es menor a una hora',
        () {
      // ARRANGE: una programación de 30 minutos
      final schedule = buildSchedule(30);

      // ACT: se obtiene la etiqueta de duración
      final label = schedule.durationLabel;

      // ASSERT: debe mostrarse en minutos
      expect(label, '30 min');
    });

    test('CP-02 valor límite: 59 minutos sigue mostrándose en minutos', () {
      // ARRANGE: el último valor antes de completar una hora
      final schedule = buildSchedule(59);

      // ACT
      final label = schedule.durationLabel;

      // ASSERT: todavía no se convierte a horas
      expect(label, '59 min');
    });

    test('CP-03 valor límite: 60 minutos se muestra como "1h"', () {
      // ARRANGE: exactamente una hora
      final schedule = buildSchedule(60);

      // ACT
      final label = schedule.durationLabel;

      // ASSERT: horas exactas, sin minutos sobrantes
      expect(label, '1h');
    });

    test('CP-04 combina horas y minutos: 90 minutos es "1h 30min"', () {
      // ARRANGE: una hora y media
      final schedule = buildSchedule(90);

      // ACT
      final label = schedule.durationLabel;

      // ASSERT: horas y minutos restantes separados por espacio
      expect(label, '1h 30min');
    });

    test('CP-05 el máximo permitido (120 minutos) se muestra como "2h"', () {
      // ARRANGE: duración máxima que acepta el firmware (MAX_SCHEDULE_MIN)
      final schedule = buildSchedule(120);

      // ACT
      final label = schedule.durationLabel;

      // ASSERT: dos horas exactas
      expect(label, '2h');
    });
  });
}
