/**
 * ============================================================
 *  Riego inteligente por humedad del suelo  (Sprint 6, SB6-02)
 * ============================================================
 *
 *  Antes de cada riego PROGRAMADO se mide la humedad de la zona
 *  y se decide (criterios del PO, docs/sprints/sprint-06.md):
 *
 *    humedad >= umbral                  -> OMITIR
 *    umbral - 15 <= humedad < umbral    -> MITAD (mínimo 1 min)
 *    humedad < umbral - 15              -> COMPLETO
 *    lectura inválida                   -> COMPLETO + aviso (falla segura)
 *    riego inteligente apagado          -> COMPLETO
 *
 *  La misma tabla está en la app (app/lib/models/smart_irrigation.dart).
 *
 *  Tiempo de absorción: el agua tarda unos 3 minutos en llegar
 *  al sensor. Si un riego programado cae dentro de los 3 minutos
 *  siguientes a que la zona se apagó, la decisión se pospone
 *  hasta que pase ese tiempo para no medir un suelo "seco" que
 *  en realidad ya está regado.
 * ============================================================
 */
#pragma once
#include <Arduino.h>
#include "moisture.h"

#define SMART_THRESHOLD_MIN      10
#define SMART_THRESHOLD_MAX      90
#define SMART_THRESHOLD_DEFAULT  60
#define SMART_REDUCE_BAND        15
#define SMART_ABSORPTION_MS      (3UL * 60UL * 1000UL)

// Motivo de la decisión; el nombre se envía a la app en /status.
enum SmartReason : uint8_t { SMART_OFF, SMART_SENSOR, SMART_WET, SMART_NEAR, SMART_DRY };

struct SmartConfig {
  bool    enabled;
  uint8_t threshold;   // % de humedad (SMART_THRESHOLD_MIN..MAX)
};

struct SmartDecision {
  SmartReason reason;
  uint16_t    minutes;   // 0 = se omite el riego
};

inline bool smartThresholdValid(int threshold) {
  return threshold >= SMART_THRESHOLD_MIN && threshold <= SMART_THRESHOLD_MAX;
}

inline SmartDecision smartDecide(const SmartConfig& cfg, const MoistureReading& r, uint16_t minutes) {
  if (!cfg.enabled) return {SMART_OFF, minutes};
  if (!r.valid)     return {SMART_SENSOR, minutes};
  if (r.percent >= cfg.threshold) return {SMART_WET, 0};
  if (r.percent + SMART_REDUCE_BAND >= cfg.threshold) {
    uint16_t half = minutes / 2;
    return {SMART_NEAR, (uint16_t)(half < 1 ? 1 : half)};
  }
  return {SMART_DRY, minutes};
}

// Nombres que entiende la app (SmartReason en smart_irrigation.dart).
inline const char* smartReasonName(SmartReason reason) {
  switch (reason) {
    case SMART_SENSOR: return "sensor";
    case SMART_WET:    return "wet";
    case SMART_NEAR:   return "near";
    case SMART_DRY:    return "dry";
    case SMART_OFF:
    default:           return "off";
  }
}
