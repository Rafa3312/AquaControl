/**
 * ============================================================
 *  Registro de riegos en la memoria del ESP32  (Sprint 8, HU-14)
 *  Sin dependencias de Arduino: se prueba en la PC (firmware/tests).
 * ============================================================
 *
 *  Cada riego (completado, reducido, omitido, pospuesto, cancelado o con
 *  falla) se guarda aquí con su hora local. Cuando hay Internet, el
 *  programador envía los registros pendientes a la Cloud Function
 *  deviceHistory y los marca como enviados.
 *
 *  - Memoria circular de HIST_CAPACITY registros: si se llena sin haber
 *    podido sincronizar, se pierde el más antiguo (y se cuenta en "lost").
 *  - Sin duplicados: el servidor identifica cada riego por su hora, zona y
 *    resultado; si un lote se reenvía tras una desconexión, no se cuenta dos
 *    veces. Aquí solo se marca "sent" cuando el servidor respondió bien.
 *  - La hora es la local del RTC (UTC-6): "at" son los segundos desde 1970
 *    de los campos de la hora local (DateTime::unixtime() del RTC).
 * ============================================================
 */
#pragma once
#include <stdint.h>

#define HIST_CAPACITY       48           // ~1 mes con 2 riegos al día en 1 zona
#define HIST_MAX_BATCH      10           // registros por envío
#define HIST_MIN_VALID_AT   1577836800UL // 2020-01-01: antes = RTC sin ajustar
#define HIST_MIN_SECONDS    5            // un encendido menor a esto no es un riego
#define HIST_VERSION        1

enum HistOutcome : uint8_t {
  HO_DONE, HO_REDUCED, HO_SKIPPED, HO_POSTPONED, HO_CANCELLED, HO_FAILED
};
enum HistReason : uint8_t {
  HR_NONE, HR_WET, HR_NEAR, HR_DRY, HR_SENSOR, HR_RAIN, HR_VALVE
};

struct HistRecord {
  uint32_t at;        // hora local de inicio (segundos desde 1970 de la hora local)
  uint16_t seconds;   // lo que realmente regó
  uint8_t  zone;      // 1..ZONE_COUNT
  uint8_t  outcome;   // HistOutcome
  uint8_t  reason;    // HistReason
  uint8_t  manual;    // 1 = riego manual
  uint8_t  sent;      // 1 = el servidor ya lo recibió
  uint8_t  pad;
};

struct HistLog {
  uint16_t count;     // registros guardados (0..HIST_CAPACITY)
  uint16_t head;      // posición del más antiguo
  uint16_t lost;      // registros perdidos sin enviar por memoria llena
  uint16_t pad;
  HistRecord rec[HIST_CAPACITY];
};

// Nombres que entienden la Cloud Function y la app (histOutcomeName/histReasonName).
inline const char* histOutcomeName(uint8_t o) {
  switch (o) {
    case HO_DONE:      return "done";
    case HO_REDUCED:   return "reduced";
    case HO_SKIPPED:   return "skipped";
    case HO_POSTPONED: return "postponed";
    case HO_CANCELLED: return "cancelled";
    default:           return "failed";
  }
}

inline const char* histReasonName(uint8_t r) {
  switch (r) {
    case HR_WET:    return "wet";
    case HR_NEAR:   return "near";
    case HR_DRY:    return "dry";
    case HR_SENSOR: return "sensor";
    case HR_RAIN:   return "rain";
    case HR_VALVE:  return "valve";
    default:        return "none";
  }
}

inline void histInit(HistLog& log) {
  log.count = 0; log.head = 0; log.lost = 0; log.pad = 0;
}

// Un registro leído de la memoria no volátil solo se acepta si es coherente.
inline bool histSane(const HistLog& log) {
  return log.count <= HIST_CAPACITY && log.head < HIST_CAPACITY;
}

inline HistRecord& histAt(HistLog& log, uint16_t i) {          // i = 0 es el más antiguo
  return log.rec[(log.head + i) % HIST_CAPACITY];
}
inline const HistRecord& histAt(const HistLog& log, uint16_t i) {
  return log.rec[(log.head + i) % HIST_CAPACITY];
}

// Agrega un riego. Devuelve false si no se guardó (hora inválida, zona
// inválida o un encendido demasiado corto para ser un riego).
inline bool histAdd(HistLog& log, uint32_t at, uint8_t zone, uint8_t outcome,
                    uint8_t reason, uint32_t seconds, bool manual) {
  if (at < HIST_MIN_VALID_AT) return false;
  if (zone < 1) return false;
  bool watered = (outcome == HO_DONE || outcome == HO_REDUCED);
  if (watered && seconds < HIST_MIN_SECONDS) return false;
  if (!watered) seconds = 0;
  if (seconds > 65535UL) seconds = 65535UL;

  if (log.count == HIST_CAPACITY) {          // llena: se pierde el más antiguo
    if (!histAt(log, 0).sent) log.lost++;
    log.head = (log.head + 1) % HIST_CAPACITY;
    log.count--;
  }
  HistRecord& r = histAt(log, log.count);
  r.at = at; r.seconds = (uint16_t)seconds; r.zone = zone;
  r.outcome = outcome; r.reason = reason; r.manual = manual ? 1 : 0;
  r.sent = 0; r.pad = 0;
  log.count++;
  return true;
}

inline uint16_t histPending(const HistLog& log) {
  uint16_t n = 0;
  for (uint16_t i = 0; i < log.count; i++) if (!histAt(log, i).sent) n++;
  return n;
}

// Guarda en idx[] las posiciones (0 = más antiguo) de hasta max registros sin
// enviar, del más antiguo al más nuevo. Devuelve cuántos.
inline uint16_t histCollect(const HistLog& log, uint16_t* idx, uint16_t max) {
  uint16_t n = 0;
  for (uint16_t i = 0; i < log.count && n < max; i++) {
    if (!histAt(log, i).sent) idx[n++] = i;
  }
  return n;
}

inline void histMarkSent(HistLog& log, uint16_t i) {
  if (i < log.count) histAt(log, i).sent = 1;
}
