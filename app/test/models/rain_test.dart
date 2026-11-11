import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/rain.dart';

/// Pruebas del riego por lluvia (Sprint 7, SB7-05) con valores simulados:
/// con lluvia, sin lluvia y sensor en falla. Patrón AAA.
void main() {
  group('RainStatus.fromJson', () {
    test('CP-01 lee el estado que reporta el ESP32 en /status', () {
      // Arrange
      final json = {'valid': true, 'raining': true, 'raw': 1500};

      // Act
      final status = RainStatus.fromJson(json);

      // Assert
      expect(status?.valid, isTrue);
      expect(status?.raining, isTrue);
      expect(status?.raw, 1500);
      expect(status?.label, 'Lloviendo');
    });

    test('CP-02 sin el dato (firmware anterior a la v3.4) devuelve null', () {
      // Act / Assert
      expect(RainStatus.fromJson(null), isNull);
      expect(RainStatus.fromJson('n/a'), isNull);
    });

    test('CP-03 sensor en falla: no es válido aunque diga que llueve', () {
      // Arrange
      final json = {'valid': false, 'raining': true, 'raw': 0};

      // Act
      final status = RainStatus.fromJson(json);

      // Assert
      expect(status?.valid, isFalse);
      expect(status?.label, 'Sensor sin lectura');
    });

    test('CP-04 sin lluvia: la etiqueta es "Sin lluvia"', () {
      // Act
      final status = RainStatus.fromJson({'valid': true, 'raining': false, 'raw': 3900});

      // Assert
      expect(status?.label, 'Sin lluvia');
    });
  });

  group('RainStatus.rawIsWet y rawIsValid', () {
    test('CP-05 valor límite: igual a 2600 es mojado, 2601 es seco', () {
      // Act / Assert
      expect(RainStatus.rawIsWet(RainStatus.wetRaw), isTrue);
      expect(RainStatus.rawIsWet(RainStatus.wetRaw + 1), isFalse);
    });

    test('CP-06 valores límite del rango válido: 100 y 4090 son válidos', () {
      // Act / Assert
      expect(RainStatus.rawIsValid(RainStatus.validMin), isTrue);
      expect(RainStatus.rawIsValid(RainStatus.validMax), isTrue);
      expect(RainStatus.rawIsValid(RainStatus.validMin - 1), isFalse);
      expect(RainStatus.rawIsValid(RainStatus.validMax + 1), isFalse);
    });

    test('CP-07 lectura 0 (desconectado con resistencia a GND) es inválida', () {
      // Act / Assert
      expect(RainStatus.rawIsValid(0), isFalse);
    });
  });

  group('RainStatus.verdict (prioridad lluvia)', () {
    test('CP-08 sin lluvia el riego sigue', () {
      // Act
      final v = RainStatus.verdict(raining: false, waited: Duration.zero);

      // Assert
      expect(v, RainVerdict.resume);
    });

    test('CP-09 con lluvia al dispararse, el riego se pospone', () {
      // Act
      final v = RainStatus.verdict(raining: true, waited: Duration.zero);

      // Assert
      expect(v, RainVerdict.wait);
    });

    test('CP-10 valor límite: a 2 h menos un minuto sigue esperando', () {
      // Act
      final v = RainStatus.verdict(
        raining: true,
        waited: RainStatus.maxWait - const Duration(minutes: 1),
      );

      // Assert
      expect(v, RainVerdict.wait);
    });

    test('CP-11 valor límite: a las 2 h con lluvia se cancela', () {
      // Act
      final v = RainStatus.verdict(raining: true, waited: RainStatus.maxWait);

      // Assert
      expect(v, RainVerdict.cancel);
    });

    test('CP-12 dejó de llover durante la espera: se reanuda', () {
      // Act
      final v = RainStatus.verdict(raining: false, waited: const Duration(hours: 1));

      // Assert
      expect(v, RainVerdict.resume);
    });

    test('CP-13 son 8 reintentos de 15 min antes de cancelar', () {
      // Act / Assert
      expect(RainStatus.maxWait.inMinutes ~/ RainStatus.retryInterval.inMinutes, 8);
    });
  });
}
