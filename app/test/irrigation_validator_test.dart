import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_app/utils/irrigation_validator.dart';

void main() {
  group('validateIrrigationProgram', () {
    test('es válido con días seleccionados y duración dentro de rango', () {
      final result = validateIrrigationProgram(
        selectedDays: ['Lun', 'Mié', 'Vie'],
        durationMinutes: 15,
      );
      expect(result.isValid, true);
      expect(result.error, isNull);
    });

    test('es inválido si no hay días seleccionados', () {
      final result = validateIrrigationProgram(
        selectedDays: [],
        durationMinutes: 15,
      );
      expect(result.isValid, false);
      expect(result.error, contains('al menos un día'));
    });

    test('es inválido si la duración está fuera de rango', () {
      final result = validateIrrigationProgram(
        selectedDays: ['Lun'],
        durationMinutes: 150,
      );
      expect(result.isValid, false);
      expect(result.error, contains('entre 1 y 120'));
    });
  });
}
