/**
 * ============================================================
 *  Sensor de lluvia  (Sprint 7, SB7-01)
 * ============================================================
 *
 *  Conexión: módulo de lluvia con salida analógica (AO)
 *    VCC -> 3V3   GND -> GND   AO -> GPIO36 (VP, solo entrada)
 *    Resistencia de 10 kΩ de AO a GND: si el sensor se desconecta,
 *    la entrada queda en 0 y el programador lo detecta como falla.
 *
 *  Calibración: en seco el AO da una lectura alta (~3800-4000) y
 *  mojado baja (~1000-1500). Ajustar RAIN_WET_RAW en rain_logic.h.
 *
 *  Instalación: el sensor va FUERA del alcance del aspersor (ver
 *  docs/sprints/sprint-07.md). Así no se moja con el propio riego.
 * ============================================================
 */
#pragma once
#include <Arduino.h>
#include "rain_logic.h"

#define RAIN_PIN 36

// Promedio de 4 lecturas del ADC para quitar ruido.
inline uint16_t rainRead() {
  uint32_t sum = 0;
  for (uint8_t i = 0; i < 4; i++) {
    sum += analogRead(RAIN_PIN);
    delay(2);
  }
  return (uint16_t)(sum / 4);
}
