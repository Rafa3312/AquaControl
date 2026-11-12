/**
 * ============================================================
 *  Lógica del riego por lluvia  (Sprint 7, SB7-02 y SB7-04)
 *  Sin dependencias de Arduino: se prueba en la PC (firmware/tests).
 * ============================================================
 *
 *  Prioridad al disparar un riego programado (criterios del PO):
 *    1. LLUVIA   -> si llueve, se pospone el riego y se reintenta
 *                   cada 15 min hasta 2 h. Si al cabo de 2 h sigue
 *                   lloviendo, se cancela.
 *    2. HUMEDAD  -> si ya no llueve, se aplica la regla de humedad
 *                   (omitir / mitad / completo).
 *    3. PROGRAMA -> si no hay sensor de lluvia o no falla, se riega
 *                   lo programado.
 *
 *  Falso positivo: el aspersor moja el sensor. Durante un riego propio
 *  y los 5 min siguientes la lectura se ignora (cuenta como seco).
 *
 *  Falla segura: si el sensor de lluvia no da lectura válida, no se
 *  puede posponer por lluvia: se riega según la programación y la
 *  humedad, y se envía el aviso "rainsensor".
 *
 *  Limitación conocida: una lluvia que empieza DURANTE un riego propio
 *  no detiene el riego, porque en ese tiempo la lectura se ignora.
 * ============================================================
 */
#pragma once
#include <stdint.h>

#define RAIN_WET_RAW          2600   // lectura <= esto = mojado (calibrar)
#define RAIN_VALID_MIN        100    // menos: sensor en corto o con pull-down
#define RAIN_VALID_MAX        4090   // más: sin señal (sensor desconectado)
#define RAIN_STABLE_COUNT     4      // lecturas seguidas para cambiar de estado
#define RAIN_SAMPLE_MS        500    // 4 x 500 ms = 2 s hasta detectar (< 3 s)
#define RAIN_OWN_IGNORE_MS    (5UL * 60UL * 1000UL)
#define RAIN_RETRY_MS         (15UL * 60UL * 1000UL)
#define RAIN_MAX_WAIT_MS      (2UL * 60UL * 60UL * 1000UL)

// Estado del sensor después del antirrebote.
struct RainFilter {
  bool     valid;     // la última lectura está en rango
  bool     raining;   // estado estable (ya filtrado)
  uint16_t raw;
  uint8_t  wetRun;    // lecturas mojadas seguidas
  uint8_t  dryRun;    // lecturas secas seguidas
};

// Retención de un riego programado que se pospuso por lluvia.
struct RainHold {
  bool          active;
  uint16_t      minutes;       // duración original del riego
  unsigned long startedMs;     // cuándo se pospuso
  unsigned long nextCheckMs;   // próximo reintento
};

enum RainVerdict : uint8_t { RAIN_RESUME, RAIN_WAIT, RAIN_CANCEL };

inline bool rainRawValid(uint16_t raw) {
  return raw >= RAIN_VALID_MIN && raw <= RAIN_VALID_MAX;
}

// Antirrebote: solo cambia de estado tras RAIN_STABLE_COUNT lecturas iguales.
// Una lectura inválida no cambia el estado; se reporta como falla.
inline void rainFilterStep(RainFilter& f, uint16_t raw) {
  f.raw   = raw;
  f.valid = rainRawValid(raw);
  if (!f.valid) { f.wetRun = 0; f.dryRun = 0; return; }
  if (raw <= RAIN_WET_RAW) {
    if (f.wetRun < 255) f.wetRun++;
    f.dryRun = 0;
  } else {
    if (f.dryRun < 255) f.dryRun++;
    f.wetRun = 0;
  }
  if (f.wetRun >= RAIN_STABLE_COUNT) f.raining = true;
  if (f.dryRun >= RAIN_STABLE_COUNT) f.raining = false;
}

// Lluvia que cuenta para decidir. Se ignora mientras riega la propia
// zona y durante RAIN_OWN_IGNORE_MS después (falso positivo del aspersor).
inline bool rainEffective(const RainFilter& f, bool irrigating, unsigned long msSinceWatering) {
  if (!f.valid || irrigating) return false;
  if (msSinceWatering < RAIN_OWN_IGNORE_MS) return false;
  return f.raining;
}

// raining: lluvia efectiva ahora. waitedMs: tiempo ya pospuesto (0 al disparar).
inline RainVerdict rainVerdict(bool raining, unsigned long waitedMs) {
  if (!raining) return RAIN_RESUME;
  if (waitedMs >= RAIN_MAX_WAIT_MS) return RAIN_CANCEL;
  return RAIN_WAIT;
}
