# Sprint 08 — Historial de riegos y estadísticas de consumo

- **Semana:** del 19/10/2026 al 23/10/2026
- **Rama / PR:** `feature/sprint-08-historial-estadisticas` → `develop`
- **Versión al cierre:** app `1.2.0+3` (se sube en la siguiente release) · firmware `v3.5`

## Objetivo del Sprint

Dar visibilidad histórica y estadística del uso del sistema: la app muestra el historial de
riegos (HU-14) y las estadísticas de consumo de agua por zona y periodo (HU-16).

## Criterios de aceptación (Product Owner)

### HU-14 — Historial de riegos

1. Reportes muestra una lista con **fecha y hora, zona, duración, estado y motivo** de cada
   riego.
2. Filtros de periodo **Hoy, Semana, Mes y Año** y filtro por **zona**.
3. Estados: Completado, Reducido, Omitido, Pospuesto, Cancelado y Falla. El motivo reutiliza
   las reglas ya hechas: humedad (Sprint 6), lluvia (Sprint 7), riego manual o programado.
4. El ESP32 **guarda cada riego en su memoria** y, cuando hay Internet, lo **sincroniza con
   Firestore sin duplicados**, incluso después de una desconexión.
5. Los registros se **eliminan a los 12 meses**.

### HU-16 — Estadísticas de consumo

6. Tarjetas de **agua total, riegos y tiempo total**, y una **gráfica de consumo** por periodo
   con filtro de zona.
7. El consumo es una **estimación**: minutos regados × caudal de la zona. El caudal por
   defecto es 8 L/min (nominal) y **se ajusta por zona** (1 a 30 L/min) con el valor medido con
   una cubeta. La app lo indica.
8. Solo cuentan los riegos que usaron agua (completados y reducidos). Los omitidos y cancelados
   se cuentan aparte como agua ahorrada.
9. **Fechas locales (UTC-6):** un riego de las 23:30 pertenece a su día, no al siguiente
   (error de fecha UTC del Sprint 3).
10. Las estadísticas se calculan con **resúmenes diarios**, no leyendo cada riego, para que un
    año no consuma miles de lecturas de Firestore.

### Periodos

| Filtro | Qué cubre | Barras de la gráfica |
|---|---|---|
| Hoy | el día local en curso | una por zona |
| Semana | los últimos 7 días (con hoy) | una por día |
| Mes | los últimos 30 días | una por día |
| Año | los últimos 12 meses naturales | una por mes |

## Contrato ESP32 ↔ Cloud Function (firmware v3.5)

El firmware guarda hasta **48 riegos** (memoria circular, NVS) y los envía por lotes de 10 a
`POST /deviceHistory` con el mismo token Bearer de la vinculación:

```json
{
  "uid": "…", "device": "A1B2C3",
  "records": [
    { "at": 1792000800, "zone": 1, "outcome": "done", "reason": "dry", "seconds": 600, "manual": false }
  ]
}
```

- `at`: segundos desde 1970 **de los campos de la hora local del RTC** (no UTC). La función
  saca de ahí la fecha local sin depender de la zona horaria del servidor.
- `outcome`: `done`, `reduced`, `skipped`, `postponed`, `cancelled`, `failed`.
- `reason`: `none`, `wet`, `near`, `dry`, `sensor`, `rain`, `valve`.
- Respuesta: `{"ok": true, "saved": 3, "duplicates": 0}`.

**Sin duplicados:** cada riego tiene el identificador `<at>_<zona>_<resultado>`. Si el ESP32
reenvía un lote (por ejemplo porque no recibió la respuesta), los riegos que ya existen se
cuentan como `duplicates` y **no se suman otra vez** al consumo. El firmware solo marca un
riego como enviado cuando el servidor responde 2xx; ante un 4xx de datos inválidos descarta el
lote para no bloquear los demás, y ante 401, 403, 429 o sin red reintenta a los 5 min.

`GET /status` agrega `"history": {"stored": 12, "pending": 0, "lost": 0}`.

## Datos en Firestore

| Ruta | Qué guarda | Quién escribe |
|---|---|---|
| `users/{uid}/history/{at}_{zona}_{resultado}` | un riego: `startAt`, `date`, `zone`, `outcome`, `reason`, `seconds`, `manual`, `expireAt` | solo la Cloud Function |
| `users/{uid}/dailyStats/{AAAA-MM-DD}` | resumen del día por zona: `runs`, `seconds`, `skipped`, `expireAt` | solo la Cloud Function |
| `users/{uid}/zones/{id}.flowLpm` | caudal medido de la zona (1 a 30 L/min) | el usuario |

- **Reglas:** el dueño lee su historial y sus resúmenes; **nadie** puede crearlos, cambiarlos ni
  borrarlos desde la app (así no se falsea el consumo). `flowLpm` se valida entre 1 y 30.
- **Retención de 12 meses:** cada documento lleva `expireAt` (365 días) y
  `firestore.indexes.json` declara la política TTL de ese campo en `history` y `dailyStats`.
  Se activa al desplegar (`firebase deploy --only firestore`).
- **Invitados:** el acceso compartido (HU-17) llega en el Sprint 10; hoy solo lee el dueño. Al
  agregar invitados habrá que extender estas reglas.

## Sprint Backlog

| ID | Tarea | Responsable(s) | Estado |
|---|---|---|---|
| SB8-01 | Historial de riegos en la app: lista con fecha, zona, duración, estado y motivo; filtros Hoy, Semana, Mes y Año | Milton Becerra, Kevin Colín | Implementado (`reports_tab.dart`, `history_provider.dart`) |
| SB8-02 | Firmware: registro de cada riego en la memoria del ESP32 y sincronización con Firestore | Esryil Vidales, Edgar Suárez | Implementado (`history_log.h`, v3.5); falta prueba física y `HISTORY_URL` |
| SB8-03 | Estadísticas de consumo por zona y periodo: tarjetas y gráfica | Milton Becerra, Kevin Colín | Implementado (`water_stats.dart`) |
| SB8-04 | Seguridad y privacidad del historial: reglas de Firestore y retención de 12 meses | Kevin Colín | Implementado (reglas, `expireAt`, TTL); falta desplegar |
| SB8-05 | Pruebas del historial y las estadísticas; comparación de litros con una medición real | Kevin Colín, Edgar Suárez | Pruebas automáticas hechas; falta la medición con cubeta |
| SB8-06 | Arrastre del Sprint 7: validar el sensor de lluvia con lluvia real en exterior | Edgar Suárez | Tarea del equipo con evidencia (log del 21/10, ver el reporte) |

Acciones de mejora del Sprint 7 aplicadas: datos de prueba de varios meses
(`firebase/functions/scripts/seed-history.js`), criterios escritos antes del Planning y la
validación con lluvia real como tarea de arrastre.

## Datos de prueba de varios meses

```bash
cd firebase/functions && npm install
# Con el emulador de Firestore (no toca datos reales):
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/seed-history.js <uid> --months=6
```

Genera unos 390 riegos de 6 meses (completados, reducidos, omitidos, cancelados por lluvia y
fallas, incluido un riego de las 23:30 los sábados) y sus resúmenes diarios. Es determinista:
la misma semilla produce siempre los mismos datos. Con el proyecto real hay que usar una cuenta
de prueba, porque escribe en el uid indicado.

## Pruebas

| Tipo | Qué se probó | Resultado |
|---|---|---|
| Unitarias (PC, C++) | `firmware/tests/history_log_test.cpp`: memoria circular, hora inválida, lotes, reenvío sin duplicados y tamaño en NVS (360 verificaciones) | ✅ |
| Unitarias (CI) | App: periodos, agregación, litros, límites de día y mes, 23:30 local, registro y caudal (`water_stats_test.dart`) | ✅ |
| Unitarias (CI) | App: `HistoryProvider` con Firestore simulado (filtros, caudal, datos inválidos) | ✅ |
| Widget (CI) | Reportes: historial, tarjetas, gráfica, filtros y diálogo de caudal | ✅ |
| Unitarias (CI) | Cloud Function: validación, fecha local, retención, resumen diario y datos de prueba (10 pruebas nuevas) | ✅ |
| Integración (CI) | Emulador de Firestore: guardado, resumen y **reenvío sin duplicados** (4 pruebas) | ✅ |
| Reglas (CI) | Historial y resúmenes solo lectura para el dueño; caudal de 1 a 30 L/min (7 pruebas nuevas) | ✅ |
| Compilación | Firmware v3.5 para ESP32 (90% de la flash, 1,191,252 bytes) | ✅ |
| Hardware | Registro y sincronización tras una desconexión real | Pendiente |
| Hardware | Caudal medido con cubeta y comparación de litros | Pendiente |

## Pendientes

- Desplegar `deviceHistory`, las reglas y la política TTL (plan Blaze), y llenar `HISTORY_URL`
  (y `EVENT_URL`) en el firmware.
- Probar en el ESP32 la sincronización tras desconectar el WiFi y que no se dupliquen registros.
- Medir el caudal real de cada zona con una cubeta y capturarlo en la app ("Ajustar caudal").
- Con las sesiones antiguas (firmware anterior a v3.5) el historial queda vacío hasta cargar v3.5.
- La lluvia que empieza **durante** un riego propio no lo detiene (limitación del Sprint 7).
