// Pruebas en la PC del registro de riegos (Sprint 8, HU-14).
//   g++ -std=c++17 -Wall -I ../AquaControl_v3_secure history_log_test.cpp -o history_log_test && ./history_log_test
#include <cstdio>
#include <cstring>
#include "history_log.h"

static int failures = 0;
static int total = 0;

#define CHECK(cond)                                                          \
  do {                                                                       \
    total++;                                                                 \
    if (!(cond)) { failures++; std::printf("FALLA línea %d: %s\n", __LINE__, #cond); } \
  } while (0)

static const uint32_t T0 = 1792000000UL;   // octubre de 2026 (hora local del RTC)

static void test_agrega_un_riego() {
  HistLog log; histInit(log);
  CHECK(histAdd(log, T0, 1, HO_DONE, HR_DRY, 600, false));
  CHECK(log.count == 1);
  CHECK(histAt(log, 0).at == T0);
  CHECK(histAt(log, 0).seconds == 600);
  CHECK(histAt(log, 0).sent == 0);
  CHECK(histPending(log) == 1);
}

static void test_rechaza_hora_invalida_del_rtc() {
  HistLog log; histInit(log);
  CHECK(!histAdd(log, 946684800UL, 1, HO_DONE, HR_NONE, 600, false));        // año 2000
  CHECK(!histAdd(log, HIST_MIN_VALID_AT - 1, 1, HO_DONE, HR_NONE, 600, false));
  CHECK(histAdd(log, HIST_MIN_VALID_AT, 1, HO_DONE, HR_NONE, 600, false));   // límite
  CHECK(log.count == 1);
}

static void test_encendido_muy_corto_no_es_un_riego() {
  HistLog log; histInit(log);
  CHECK(!histAdd(log, T0, 1, HO_DONE, HR_NONE, HIST_MIN_SECONDS - 1, true));
  CHECK(histAdd(log, T0, 1, HO_DONE, HR_NONE, HIST_MIN_SECONDS, true));
  CHECK(!histAdd(log, T0 + 10, 1, HO_REDUCED, HR_NEAR, 0, false));
  CHECK(log.count == 1);
}

static void test_omitidos_y_cancelados_guardan_cero_segundos() {
  HistLog log; histInit(log);
  CHECK(histAdd(log, T0, 1, HO_SKIPPED, HR_WET, 600, false));
  CHECK(histAdd(log, T0 + 1, 2, HO_CANCELLED, HR_RAIN, 480, false));
  CHECK(histAdd(log, T0 + 2, 1, HO_POSTPONED, HR_RAIN, 600, false));
  CHECK(histAdd(log, T0 + 3, 1, HO_FAILED, HR_VALVE, 30, false));
  for (uint16_t i = 0; i < log.count; i++) CHECK(histAt(log, i).seconds == 0);
}

static void test_segundos_se_limitan_a_16_bits() {
  HistLog log; histInit(log);
  CHECK(histAdd(log, T0, 1, HO_DONE, HR_NONE, 70000UL, true));
  CHECK(histAt(log, 0).seconds == 65535);
}

static void test_zona_cero_no_es_un_riego() {
  HistLog log; histInit(log);
  CHECK(!histAdd(log, T0, 0, HO_DONE, HR_NONE, 600, false));
}

static void test_memoria_circular_pierde_el_mas_antiguo_sin_enviar() {
  HistLog log; histInit(log);
  for (int i = 0; i < HIST_CAPACITY; i++) histAdd(log, T0 + i, 1, HO_DONE, HR_NONE, 600, false);
  CHECK(log.count == HIST_CAPACITY);
  CHECK(log.lost == 0);

  histAdd(log, T0 + 1000, 1, HO_DONE, HR_NONE, 600, false);   // uno más: se pierde el primero

  CHECK(log.count == HIST_CAPACITY);
  CHECK(log.lost == 1);
  CHECK(histAt(log, 0).at == T0 + 1);
  CHECK(histAt(log, HIST_CAPACITY - 1).at == T0 + 1000);
}

static void test_memoria_llena_no_cuenta_como_perdido_lo_ya_enviado() {
  HistLog log; histInit(log);
  for (int i = 0; i < HIST_CAPACITY; i++) histAdd(log, T0 + i, 1, HO_DONE, HR_NONE, 600, false);
  histMarkSent(log, 0);

  histAdd(log, T0 + 1000, 1, HO_DONE, HR_NONE, 600, false);

  CHECK(log.lost == 0);   // el más antiguo ya estaba en el servidor
}

static void test_collect_devuelve_los_pendientes_mas_antiguos_primero() {
  HistLog log; histInit(log);
  for (int i = 0; i < 5; i++) histAdd(log, T0 + i, 1, HO_DONE, HR_NONE, 600, false);
  histMarkSent(log, 1);

  uint16_t idx[HIST_MAX_BATCH];
  uint16_t n = histCollect(log, idx, HIST_MAX_BATCH);

  CHECK(n == 4);
  CHECK(idx[0] == 0 && idx[1] == 2 && idx[2] == 3 && idx[3] == 4);
}

static void test_collect_respeta_el_tamano_del_lote() {
  HistLog log; histInit(log);
  for (int i = 0; i < 25; i++) histAdd(log, T0 + i, 1, HO_DONE, HR_NONE, 600, false);

  uint16_t idx[HIST_MAX_BATCH];
  CHECK(histCollect(log, idx, HIST_MAX_BATCH) == HIST_MAX_BATCH);
  CHECK(histAt(log, idx[HIST_MAX_BATCH - 1]).at == T0 + HIST_MAX_BATCH - 1);
}

// Escenario de HU-14: se pierde la conexión, se acumulan riegos, vuelve el
// Internet y se envían en lotes sin repetir ni perder ninguno.
static void test_sincronizacion_tras_desconexion_sin_duplicados() {
  HistLog log; histInit(log);
  for (int i = 0; i < 23; i++) histAdd(log, T0 + i * 100, 1 + (i % 2), HO_DONE, HR_NONE, 600, false);

  uint32_t sentAt[64]; int sentCount = 0;
  uint16_t idx[HIST_MAX_BATCH];
  while (true) {
    uint16_t n = histCollect(log, idx, HIST_MAX_BATCH);
    if (n == 0) break;
    for (uint16_t k = 0; k < n; k++) {
      sentAt[sentCount++] = histAt(log, idx[k]).at;
      histMarkSent(log, idx[k]);
    }
  }

  CHECK(sentCount == 23);
  CHECK(histPending(log) == 0);
  for (int i = 0; i < sentCount; i++)
    for (int j = i + 1; j < sentCount; j++) CHECK(sentAt[i] != sentAt[j]);

  // Si el envío falla (sin marcar), el siguiente intento manda los mismos
  histAdd(log, T0 + 5000, 1, HO_DONE, HR_NONE, 600, false);
  uint16_t first[HIST_MAX_BATCH], second[HIST_MAX_BATCH];
  uint16_t a = histCollect(log, first, HIST_MAX_BATCH);
  uint16_t b = histCollect(log, second, HIST_MAX_BATCH);
  CHECK(a == 1 && b == 1 && first[0] == second[0]);
}

static void test_marcar_fuera_de_rango_no_hace_nada() {
  HistLog log; histInit(log);
  histAdd(log, T0, 1, HO_DONE, HR_NONE, 600, false);
  histMarkSent(log, 5);
  CHECK(histPending(log) == 1);
}

static void test_el_orden_se_conserva_despues_de_dar_la_vuelta() {
  HistLog log; histInit(log);
  for (int i = 0; i < HIST_CAPACITY + 10; i++) histAdd(log, T0 + i, 1, HO_DONE, HR_NONE, 600, false);
  for (uint16_t i = 1; i < log.count; i++) CHECK(histAt(log, i).at == histAt(log, i - 1).at + 1);
  CHECK(log.lost == 10);
}

static void test_valida_un_registro_leido_de_la_memoria() {
  HistLog log; histInit(log);
  CHECK(histSane(log));
  log.count = HIST_CAPACITY + 1;
  CHECK(!histSane(log));
  log.count = 3; log.head = HIST_CAPACITY;
  CHECK(!histSane(log));
}

static void test_nombres_que_entienden_la_nube_y_la_app() {
  CHECK(std::strcmp(histOutcomeName(HO_DONE), "done") == 0);
  CHECK(std::strcmp(histOutcomeName(HO_REDUCED), "reduced") == 0);
  CHECK(std::strcmp(histOutcomeName(HO_SKIPPED), "skipped") == 0);
  CHECK(std::strcmp(histOutcomeName(HO_POSTPONED), "postponed") == 0);
  CHECK(std::strcmp(histOutcomeName(HO_CANCELLED), "cancelled") == 0);
  CHECK(std::strcmp(histOutcomeName(HO_FAILED), "failed") == 0);
  CHECK(std::strcmp(histReasonName(HR_NONE), "none") == 0);
  CHECK(std::strcmp(histReasonName(HR_WET), "wet") == 0);
  CHECK(std::strcmp(histReasonName(HR_NEAR), "near") == 0);
  CHECK(std::strcmp(histReasonName(HR_DRY), "dry") == 0);
  CHECK(std::strcmp(histReasonName(HR_SENSOR), "sensor") == 0);
  CHECK(std::strcmp(histReasonName(HR_RAIN), "rain") == 0);
  CHECK(std::strcmp(histReasonName(HR_VALVE), "valve") == 0);
}

static void test_el_registro_cabe_en_la_memoria_no_volatil() {
  CHECK(sizeof(HistRecord) == 12);
  CHECK(sizeof(HistLog) == 8 + HIST_CAPACITY * 12);
  CHECK(sizeof(HistLog) < 1000);   // un blob de NVS admite bastante más
}

int main() {
  test_agrega_un_riego();
  test_rechaza_hora_invalida_del_rtc();
  test_encendido_muy_corto_no_es_un_riego();
  test_omitidos_y_cancelados_guardan_cero_segundos();
  test_segundos_se_limitan_a_16_bits();
  test_zona_cero_no_es_un_riego();
  test_memoria_circular_pierde_el_mas_antiguo_sin_enviar();
  test_memoria_llena_no_cuenta_como_perdido_lo_ya_enviado();
  test_collect_devuelve_los_pendientes_mas_antiguos_primero();
  test_collect_respeta_el_tamano_del_lote();
  test_sincronizacion_tras_desconexion_sin_duplicados();
  test_marcar_fuera_de_rango_no_hace_nada();
  test_el_orden_se_conserva_despues_de_dar_la_vuelta();
  test_valida_un_registro_leido_de_la_memoria();
  test_nombres_que_entienden_la_nube_y_la_app();
  test_el_registro_cabe_en_la_memoria_no_volatil();

  std::printf("%d verificaciones, %d fallas\n", total, failures);
  return failures == 0 ? 0 : 1;
}
