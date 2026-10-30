import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/irrigation_notification.dart';
import 'package:irrigation_app/models/schedule.dart';

/// Pruebas de programaciones por zona y de avisos de riego (Sprint 5).
void main() {
  group('Schedule con zona', () {
    test('conserva la zona al guardar y leer', () {
      // Arrange
      final original = Schedule(
        id: 'p1',
        name: 'Huerto',
        days: [0, 2, 4],
        startHour: 6,
        startMinute: 30,
        durationMinutes: 15,
        zone: 2,
      );

      // Act
      final leido = Schedule.fromJson(original.toJson());

      // Assert
      expect(leido.zone, 2);
      expect(leido.name, 'Huerto');
    });

    test('una programación guardada antes del Sprint 5 queda en la zona 1', () {
      // Arrange
      final legacy = {
        'id': 'p0',
        'name': 'Riego matutino',
        'days': [0, 1, 2, 3, 4],
        'startHour': 7,
        'startMinute': 0,
        'durationMinutes': 20,
        'isActive': true,
      };

      // Act
      final s = Schedule.fromJson(legacy);

      // Assert
      expect(s.zone, 1);
      expect(s.isActive, isTrue);
    });
  });

  group('IrrigationNotification', () {
    test('un aviso de falla se identifica como falla', () {
      // Arrange
      final data = {
        'type': 'fail',
        'zone': 2,
        'zoneName': 'Huerto',
        'title': 'Falla en Huerto',
        'body': 'La válvula no respondió.',
        'source': 'schedule',
      };

      // Act
      final n = IrrigationNotification.fromMap('n1', data);

      // Assert
      expect(n.isFailure, isTrue);
      expect(n.kind, NotificationKind.fail);
      expect(n.zone, 2);
      expect(n.manual, isFalse);
    });

    test('sin título usa uno por defecto con el nombre de la zona', () {
      // Arrange
      final data = {'type': 'end', 'zone': 1, 'source': 'manual'};

      // Act
      final n = IrrigationNotification.fromMap('n2', data);

      // Assert
      expect(n.title, 'Riego terminado · Zona 1');
      expect(n.isFailure, isFalse);
      expect(n.manual, isTrue);
    });
  });
}
