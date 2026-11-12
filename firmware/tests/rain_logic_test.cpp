// Pruebas de la lógica del riego por lluvia (Sprint 7, SB7-05) con valores
// simulados. Sin Arduino: se compila y corre en la PC.
//
//   g++ -std=c++17 -Wall -I ../AquaControl_v3_secure rain_logic_test.cpp -o rain_test
//   ./rain_test
#include <cstdio>
#include "rain_logic.h"

static int passed = 0;
static int failed = 0;

#define CHECK(cond, name)                                  \
  do {                                                     \
    if (cond) { passed++; }                                \
    else { failed++; std::printf("FALLA: %s\n", name); }   \
  } while (0)

// Lee n muestras iguales y devuelve el filtro resultante.
static RainFilter feed(RainFilter f, uint16_t raw, int n) {
  for (int i = 0; i < n; i++) rainFilterStep(f, raw);
  return f;
}

static RainFilter fresh() { RainFilter f{}; f.valid = true; return f; }

int main() {
  const unsigned long MIN = 60UL * 1000UL;
  const unsigned long LONG_AGO = 24UL * 60UL * MIN;  // nunca regó hoy

  // ── Antirrebote y detección (SB7-01) ────────────────────────────────────
  CHECK(!feed(fresh(), 1500, 3).raining,
        "CP-01 tres lecturas mojadas no bastan (antirrebote)");

  RainFilter wet = feed(fresh(), 1500, RAIN_STABLE_COUNT);
  CHECK(wet.raining, "CP-02 cuatro lecturas mojadas seguidas detectan lluvia");
  CHECK(RAIN_STABLE_COUNT * RAIN_SAMPLE_MS < 3000,
        "CP-03 la detección tarda menos de 3 s (4 x 500 ms)");

  RainFilter dry = feed(wet, 3900, RAIN_STABLE_COUNT);
  CHECK(!dry.raining, "CP-04 cuatro lecturas secas seguidas quitan la lluvia");

  RainFilter flicker = fresh();
  for (int i = 0; i < 10; i++) rainFilterStep(flicker, (i % 2) ? 1500 : 3900);
  CHECK(!flicker.raining, "CP-05 una lectura que oscila no cambia el estado");

  // ── Valores límite de la calibración ────────────────────────────────────
  CHECK(feed(fresh(), RAIN_WET_RAW, RAIN_STABLE_COUNT).raining,
        "CP-06 valor límite: lectura igual a RAIN_WET_RAW cuenta como mojado");
  CHECK(!feed(fresh(), RAIN_WET_RAW + 1, RAIN_STABLE_COUNT).raining,
        "CP-07 valor límite: una unidad arriba de RAIN_WET_RAW es seco");

  // ── Falla segura del sensor (SB7-04) ────────────────────────────────────
  RainFilter cut = feed(fresh(), 0, RAIN_STABLE_COUNT);       // desconectado
  CHECK(!cut.valid, "CP-08 lectura 0 (sensor desconectado) es inválida");
  CHECK(!rainEffective(cut, false, LONG_AGO),
        "CP-09 con sensor inválido nunca se pospone por lluvia");

  RainFilter shorted = feed(fresh(), 4095, RAIN_STABLE_COUNT); // sin señal
  CHECK(!shorted.valid, "CP-10 lectura 4095 (sin señal) es inválida");

  // Una lectura inválida no borra la lluvia ya detectada (no cambia estado)
  RainFilter glitch = wet;
  rainFilterStep(glitch, 0);
  CHECK(glitch.raining && !glitch.valid,
        "CP-11 una lectura inválida no cambia el estado estable");

  // ── Falso positivo del aspersor (SB7-04) ────────────────────────────────
  CHECK(!rainEffective(wet, true, LONG_AGO),
        "CP-12 mientras la zona riega se ignora la lectura");
  CHECK(!rainEffective(wet, false, 2UL * MIN),
        "CP-13 durante 5 min tras regar se ignora (aspersor mojó el sensor)");
  CHECK(rainEffective(wet, false, RAIN_OWN_IGNORE_MS),
        "CP-14 valor límite: a los 5 min ya cuenta la lluvia real");

  // ── Decisión: posponer, reintentar y cancelar (SB7-02) ──────────────────
  CHECK(rainVerdict(false, 0) == RAIN_RESUME,
        "CP-15 sin lluvia el riego sigue (regla de humedad)");
  CHECK(rainVerdict(true, 0) == RAIN_WAIT,
        "CP-16 con lluvia al disparar, el riego se pospone");
  CHECK(rainVerdict(true, RAIN_RETRY_MS) == RAIN_WAIT,
        "CP-17 reintento a los 15 min, sigue lloviendo: espera");
  CHECK(rainVerdict(true, RAIN_MAX_WAIT_MS - 1) == RAIN_WAIT,
        "CP-18 valor límite: a 2 h menos 1 ms todavía espera");
  CHECK(rainVerdict(true, RAIN_MAX_WAIT_MS) == RAIN_CANCEL,
        "CP-19 valor límite: a las 2 h con lluvia se cancela");
  CHECK(rainVerdict(false, RAIN_RETRY_MS * 3) == RAIN_RESUME,
        "CP-20 si dejó de llover a mitad de la espera, el riego se reanuda");

  // Total de reintentos antes de cancelar: 2 h / 15 min = 8 esperas
  CHECK(RAIN_MAX_WAIT_MS / RAIN_RETRY_MS == 8,
        "CP-21 son 8 reintentos de 15 min en 2 h");

  std::printf("\n%d pruebas pasaron, %d fallaron\n", passed, failed);
  return failed == 0 ? 0 : 1;
}
