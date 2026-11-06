/**
 * ============================================================
 *  Sensor capacitivo de humedad del suelo  (Sprint 6, SB6-01)
 *  Lectura, calibración y filtrado.
 * ============================================================
 *
 *  Conexión (un sensor por zona, en pines del ADC1; el ADC2 no
 *  funciona cuando el WiFi está encendido):
 *    VCC -> 3V3   GND -> GND   AOUT -> GPIO32 (zona 1) / GPIO33 (zona 2)
 *
 *  Calibración: el sensor capacitivo da una lectura MÁS ALTA
 *  cuanto MÁS SECO está el suelo.
 *    MOISTURE_RAW_DRY  -> lectura con el sensor en suelo seco  (0 %)
 *    MOISTURE_RAW_WET  -> lectura con el sensor en suelo mojado (100 %)
 *  Para calibrar: ver el valor "raw" en GET /status (o en el
 *  Monitor Serial) con el sensor en tierra seca y luego en tierra
 *  recién regada, y poner esos dos valores aquí.
 *
 *  Filtrado: se promedian MOISTURE_SAMPLES lecturas para quitar
 *  el ruido del ADC.
 *
 *  Lectura inválida: si el promedio queda fuera de
 *  [MOISTURE_RAW_MIN, MOISTURE_RAW_MAX] el sensor está
 *  desconectado o en corto; el riego inteligente lo trata como
 *  falla segura (riega lo programado y avisa).
 * ============================================================
 */
#pragma once
#include <Arduino.h>

#define MOISTURE_RAW_DRY          2900   // suelo seco    -> 0 %
#define MOISTURE_RAW_WET          1250   // suelo mojado  -> 100 %
#define MOISTURE_SAMPLES          10     // promedio de 10 muestras
#define MOISTURE_SAMPLE_DELAY_MS  3
#define MOISTURE_RAW_MIN          300    // menos: corto a GND
#define MOISTURE_RAW_MAX          3800   // más: sensor desconectado

struct MoistureReading {
  bool     valid;
  uint16_t raw;       // promedio del ADC (0..4095)
  uint8_t  percent;   // 0..100, solo si valid
};

// Resolución de 12 bits (0..4095) para todas las lecturas analógicas.
inline void moistureBegin() {
  analogReadResolution(12);
}

// Convierte la lectura cruda a porcentaje usando la calibración.
inline uint8_t moisturePercent(uint16_t raw) {
  if (raw >= MOISTURE_RAW_DRY) return 0;
  if (raw <= MOISTURE_RAW_WET) return 100;
  return (uint8_t)((uint32_t)(MOISTURE_RAW_DRY - raw) * 100 /
                   (MOISTURE_RAW_DRY - MOISTURE_RAW_WET));
}

// Lee el sensor conectado a [pin]: promedio de MOISTURE_SAMPLES muestras.
inline MoistureReading moistureRead(uint8_t pin) {
  uint32_t sum = 0;
  for (uint8_t i = 0; i < MOISTURE_SAMPLES; i++) {
    sum += analogRead(pin);
    delay(MOISTURE_SAMPLE_DELAY_MS);
  }
  MoistureReading r;
  r.raw     = (uint16_t)(sum / MOISTURE_SAMPLES);
  r.valid   = r.raw >= MOISTURE_RAW_MIN && r.raw <= MOISTURE_RAW_MAX;
  r.percent = r.valid ? moisturePercent(r.raw) : 0;
  return r;
}
