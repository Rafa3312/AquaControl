import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/schedule.dart';
import 'package:irrigation_app/providers/irrigation_provider.dart';
import 'package:irrigation_app/providers/schedule_provider.dart';
import 'package:irrigation_app/providers/scheduler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pruebas de las programaciones por zona (Sprint 5, HU-7): qué programación
/// queda activa en cada zona y cuándo el scheduler enciende y apaga la zona.
/// La hora se simula con un reloj inyectado.
void main() {
  late ScheduleProvider schedules;
  late IrrigationProvider irrigation;
  late SchedulerService scheduler;
  // Lunes 05/10/2026 a las 06:00:10
  var now = DateTime(2026, 10, 5, 6, 0, 10);

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  Schedule riego(String id, {int zone = 1, bool active = false}) => Schedule(
        id: id,
        name: 'Riego $id',
        days: [0], // lunes
        startHour: 6,
        startMinute: 0,
        durationMinutes: 10,
        zone: zone,
        isActive: active,
      );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 5, 6, 0, 10);
    schedules = ScheduleProvider();
    await settle(); // termina de cargar
    irrigation = IrrigationProvider();
    scheduler = SchedulerService(clock: () => now);
  });

  tearDown(() {
    scheduler.dispose();
    irrigation.dispose();
  });

  group('ScheduleProvider por zona', () {
    test('activar una programación desactiva solo las de su misma zona', () async {
      // Arrange
      await schedules.addSchedule(riego('a', zone: 1, active: true));
      await schedules.addSchedule(riego('b', zone: 1));
      await schedules.addSchedule(riego('c', zone: 2, active: true));

      // Act
      await schedules.toggleActive('b');
      await schedules.toggleActive('no-existe');

      // Assert
      expect(schedules.activeScheduleFor(1)?.id, 'b');
      expect(schedules.activeScheduleFor(2)?.id, 'c');
      expect(schedules.schedulesFor(1), hasLength(2));
    });

    test('desactivar la programación activa deja la zona sin programación', () async {
      // Arrange
      await schedules.addSchedule(riego('a', zone: 2, active: true));

      // Act
      await schedules.toggleActive('a');

      // Assert
      expect(schedules.activeScheduleFor(2), isNull);
    });

    test('buildNew crea la programación en la zona indicada', () {
      // Act
      final nueva = schedules.buildNew(
          name: 'Tarde', days: [1, 3], hour: 18, minute: 30, duration: 15, zone: 2);

      // Assert
      expect(nueva.zone, 2);
      expect(nueva.isActive, isFalse);
      expect(nueva.id, isNotEmpty);
    });
  });

  group('SchedulerService', () {
    test('a la hora y el día programados enciende solo la zona de la programación', () async {
      // Arrange
      await schedules.addSchedule(riego('c', zone: 2, active: true));

      // Act
      scheduler.init(irrigation, schedules);

      // Assert
      expect(irrigation.zone(2).isActive, isTrue);
      expect(irrigation.zone(2).scheduledRun, isTrue);
      expect(irrigation.zone(1).isActive, isFalse);
    });

    test('no vuelve a disparar la misma programación en el mismo minuto', () async {
      // Arrange: ya disparó y el usuario apagó la zona
      await schedules.addSchedule(riego('c', zone: 2, active: true));
      scheduler.init(irrigation, schedules);
      await irrigation.turnOff(zone: 2);

      // Act
      now = now.add(const Duration(seconds: 30));
      scheduler.tick();

      // Assert
      expect(irrigation.zone(2).isActive, isFalse);
    });

    test('al cumplirse la duración apaga la zona', () async {
      // Arrange
      await schedules.addSchedule(riego('a', zone: 1, active: true));
      scheduler.init(irrigation, schedules);

      // Act: pasan 11 minutos (la programación dura 10)
      now = now.add(const Duration(minutes: 11));
      scheduler.tick();

      // Assert
      expect(irrigation.zone(1).isActive, isFalse);
    });

    test('fuera del día programado no enciende', () async {
      // Arrange: martes a la misma hora
      await schedules.addSchedule(riego('a', active: true));
      now = DateTime(2026, 10, 6, 6, 0, 10);

      // Act
      scheduler.init(irrigation, schedules);

      // Assert
      expect(irrigation.anyActive, isFalse);
    });

    test('fuera de la ventana de un minuto no enciende', () async {
      // Arrange: lunes a las 06:05
      await schedules.addSchedule(riego('a', active: true));
      now = DateTime(2026, 10, 5, 6, 5);

      // Act
      scheduler.init(irrigation, schedules);

      // Assert
      expect(irrigation.anyActive, isFalse);
    });

    test('invalidate cancela el apagado pendiente', () async {
      // Arrange
      await schedules.addSchedule(riego('a', active: true));
      scheduler.init(irrigation, schedules);

      // Act: se edita la programación y después pasa la duración
      scheduler.invalidate();
      now = now.add(const Duration(minutes: 11));
      scheduler.tick();

      // Assert: ya no hay apagado pendiente para esa zona
      expect(irrigation.zone(1).isActive, isTrue);
    });
  });
}
