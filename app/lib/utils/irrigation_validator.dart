/// Resultado de validar un programa de riego.
class ProgramValidationResult {
  final bool isValid;
  final String? error;
  const ProgramValidationResult.valid() : isValid = true, error = null;
  const ProgramValidationResult.invalid(this.error) : isValid = false;
}

/// Función de lógica pura: no depende de Firebase, del ESP32 ni de la UI.
/// Valida que un programa de riego tenga al menos un día seleccionado y una
/// duración dentro de un rango seguro (1 a 120 minutos).
///
/// [selectedDays] días de la semana seleccionados (ej. ['Lun', 'Mié', 'Vie']).
/// [durationMinutes] duración del riego en minutos.
ProgramValidationResult validateIrrigationProgram({
  required List<String> selectedDays,
  required int durationMinutes,
}) {
  if (selectedDays.isEmpty) {
    return const ProgramValidationResult.invalid(
        'Selecciona al menos un día para el programa de riego.');
  }
  if (durationMinutes < 1 || durationMinutes > 120) {
    return const ProgramValidationResult.invalid(
        'La duración debe estar entre 1 y 120 minutos.');
  }
  return const ProgramValidationResult.valid();
}
