import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/models/irrigation_notification.dart';

/// Pruebas de los tipos de aviso del riego por lluvia (Sprint 7, HU-11).
void main() {
  group('IrrigationNotification con avisos de lluvia', () {
    test('CP-01 "postpone" es un aviso informativo, no una falla', () {
      // Arrange
      final data = {'type': 'postpone', 'zone': 2, 'zoneName': 'Huerto'};

      // Act
      final n = IrrigationNotification.fromMap('p1', data);

      // Assert
      expect(n.kind, NotificationKind.postpone);
      expect(n.title, 'Riego pospuesto por lluvia · Huerto');
      expect(n.isFailure, isFalse);
    });

    test('CP-02 "cancel" se cancela tras 2 h de lluvia', () {
      // Arrange
      final data = {'type': 'cancel', 'zone': 1, 'zoneName': 'Jardín'};

      // Act
      final n = IrrigationNotification.fromMap('c1', data);

      // Assert
      expect(n.kind, NotificationKind.cancel);
      expect(n.title, 'Riego cancelado por lluvia · Jardín');
      expect(n.isFailure, isFalse);
    });

    test('CP-03 "rainsensor" (zona 0, sensor general) sí es una falla', () {
      // Arrange: el aviso general llega sin zona válida
      final data = {'type': 'rainsensor', 'zone': 0, 'zoneName': 'Sensor de lluvia'};

      // Act
      final n = IrrigationNotification.fromMap('r1', data);

      // Assert
      expect(n.kind, NotificationKind.rainSensor);
      expect(n.title, 'Sensor de lluvia sin lectura');
      expect(n.isFailure, isTrue);
    });

    test('CP-04 sin título en el dato, el título por defecto del tipo de lluvia', () {
      // Act
      final postponed = IrrigationNotification.fromMap('p2', {'type': 'postpone', 'zone': 1});
      final cancelled = IrrigationNotification.fromMap('c2', {'type': 'cancel', 'zone': 1});
      final sensor = IrrigationNotification.fromMap('r2', {'type': 'rainsensor'});

      // Assert
      expect(postponed.title, 'Riego pospuesto por lluvia · Zona 1');
      expect(cancelled.title, 'Riego cancelado por lluvia · Zona 1');
      expect(sensor.title, 'Sensor de lluvia sin lectura');
    });
  });
}
