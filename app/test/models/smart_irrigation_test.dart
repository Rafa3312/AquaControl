import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/smart_irrigation.dart';

/// Pruebas del riego inteligente con valores de humedad simulados
/// (Sprint 6, SB6-05 · HU-10).
///
/// Tabla de decisión con umbral de 60% (criterios del PO):
///   humedad >= 60%        -> se omite
///   45% <= humedad < 60%  -> se riega la mitad
///   humedad < 45%         -> se riega completo
///   lectura inválida      -> se riega lo programado (falla segura)
///
/// Se usan valores límite alrededor de 45% y 60% y el patrón AAA.
void main() {
  const conUmbral60 = SmartSettings(enabled: true, threshold: 60);

  MoistureReading humedad(int percent) =>
      MoistureReading(valid: true, percent: percent);

  SmartDecision decidir(MoistureReading lectura,
          {SmartSettings settings = conUmbral60, int minutos = 10}) =>
      SmartDecision.decide(settings: settings, reading: lectura, minutes: minutos);

  group('SmartDecision.decide con valores simulados', () {
    test('CP-01 suelo seco (30%) riega completo', () {
      // Arrange
      final lectura = humedad(30);

      // Act
      final decision = decidir(lectura);

      // Assert
      expect(decision.action, SmartAction.full);
      expect(decision.minutes, 10);
      expect(decision.message, 'Riego completo: suelo seco');
    });

    test('CP-02 valor límite: 44% todavía riega completo', () {
      // Act
      final decision = decidir(humedad(44));

      // Assert
      expect(decision.action, SmartAction.full);
    });

    test('CP-03 valor límite: 45% riega la mitad', () {
      // Act
      final decision = decidir(humedad(45));

      // Assert
      expect(decision.action, SmartAction.half);
      expect(decision.minutes, 5);
    });

    test('CP-04 valor límite: 59% sigue regando la mitad', () {
      // Act
      final decision = decidir(humedad(59));

      // Assert
      expect(decision.action, SmartAction.half);
      expect(decision.message, 'Reducido a la mitad por humedad');
    });

    test('CP-05 valor límite: 60% (igual al umbral) se omite', () {
      // Act
      final decision = decidir(humedad(60));

      // Assert
      expect(decision.action, SmartAction.skip);
      expect(decision.minutes, 0);
      expect(decision.message, 'Omitido por humedad suficiente');
    });

    test('CP-06 falla segura: con lectura inválida riega lo programado', () {
      // Arrange: sensor desconectado
      const lectura = MoistureReading(valid: false, percent: 0);

      // Act
      final decision = decidir(lectura);

      // Assert
      expect(decision.action, SmartAction.full);
      expect(decision.minutes, 10);
      expect(decision.reason, SmartReason.sensor);
    });

    test('CP-07 con el riego inteligente apagado riega aunque el suelo esté saturado', () {
      // Arrange
      const apagado = SmartSettings(enabled: false, threshold: 60);

      // Act
      final decision = decidir(humedad(95), settings: apagado);

      // Assert
      expect(decision.action, SmartAction.full);
      expect(decision.reason, SmartReason.off);
    });

    test('CP-08 la mitad de un riego de 1 minuto sigue siendo 1 minuto', () {
      // Act
      final decision = decidir(humedad(50), minutos: 1);

      // Assert
      expect(decision.action, SmartAction.half);
      expect(decision.minutes, 1);
    });
  });

  group('Validación y clasificación', () {
    test('CP-09 el umbral solo acepta de 10% a 90% (valores límite)', () {
      // Act / Assert
      expect(SmartSettings.validateThreshold(9), isNotNull);
      expect(SmartSettings.validateThreshold(10), isNull);
      expect(SmartSettings.validateThreshold(90), isNull);
      expect(SmartSettings.validateThreshold(91), isNotNull);
    });

    test('CP-10 clasifica el suelo en seco, húmedo y saturado', () {
      // Act / Assert
      expect(humedad(34).level, MoistureLevel.dry);
      expect(humedad(35).level, MoistureLevel.moist);
      expect(humedad(79).level, MoistureLevel.moist);
      expect(humedad(80).level, MoistureLevel.saturated);
      expect(humedad(80).levelLabel, 'Saturado');
      expect(const MoistureReading(valid: false, percent: 0).level, isNull);
    });
  });
}
