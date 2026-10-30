import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/zone.dart';

/// Pruebas del modelo de zonas (Sprint 5, HU-7) con patrón AAA.
void main() {
  group('ZoneStatus.listFromStatus', () {
    test('lee el estado independiente de cada zona', () {
      // Arrange
      final status = {
        'valve': true,
        'zones': [
          {'id': 1, 'valve': false, 'manual': false, 'fault': false},
          {'id': 2, 'valve': true, 'manual': true, 'fault': false, 'stopAt': '07:30'},
        ],
      };

      // Act
      final zones = ZoneStatus.listFromStatus(status);

      // Assert
      expect(zones.length, Zones.count);
      expect(zones[0].valveOpen, isFalse);
      expect(zones[1].valveOpen, isTrue);
      expect(zones[1].manual, isTrue);
      expect(zones[1].stopAt, '07:30');
    });

    test('con firmware anterior (sin "zones") usa "valve" para la zona 1', () {
      // Arrange
      final status = {'valve': true, 'manual': false, 'stopAt': '06:20'};

      // Act
      final zones = ZoneStatus.listFromStatus(status);

      // Assert
      expect(zones[0].valveOpen, isTrue);
      expect(zones[0].stopAt, '06:20');
      expect(zones[1].valveOpen, isFalse);
    });

    test('ignora zonas que no existen y reporta la falla', () {
      // Arrange
      final status = {
        'zones': [
          {'id': 9, 'valve': true},
          {'id': 1, 'valve': false, 'fault': true},
        ],
      };

      // Act
      final zones = ZoneStatus.listFromStatus(status);

      // Assert
      expect(zones.map((z) => z.id), [1, 2]);
      expect(zones[0].fault, isTrue);
      expect(zones.any((z) => z.valveOpen), isFalse);
    });
  });

  group('Zones.validateName', () {
    test('acepta un nombre válido y rechaza vacío o demasiado largo', () {
      // Arrange
      final largo = 'x' * (Zones.maxNameLength + 1);

      // Act / Assert
      expect(Zones.validateName('Jardín frontal'), isNull);
      expect(Zones.validateName('   '), isNotNull);
      expect(Zones.validateName(largo), isNotNull);
    });
  });
}
