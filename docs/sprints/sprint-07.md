# Sprint 07 — Riego inteligente por lluvia

- **Semana:** del 12/10/2026 al 16/10/2026
- **Rama / PR:** app y Cloud Function en `feature/sprint-07-riego-lluvia` (PR #21); firmware
  en `feature/sprint-07-firmware-lluvia`
- **Versión al cierre:** app `1.1.0+2` (se sube en la siguiente release) · firmware `v3.4`

## Objetivo del Sprint

Suspender el riego programado cuando el sensor detecta lluvia, para no desperdiciar agua
(HU-11).

## Criterios de aceptación de HU-11 (Product Owner)

1. Al llegar un **riego programado** y estar lloviendo, el riego se **pospone**. Se
   reintenta cada **15 min** hasta **2 h**.
2. Si al cabo de **2 h** sigue lloviendo, el riego se **cancela**.
3. Si deja de llover durante la espera, el riego sigue con la regla de **humedad** (omitir,
   mitad o completo), igual que en el Sprint 6.
4. **Prioridad:** lluvia → humedad → programación.
5. **Falso positivo:** el aspersor moja el sensor. Durante un riego propio y los **5 min**
   siguientes la lectura se ignora (cuenta como seco).
6. **Falla segura:** si el sensor de lluvia no da lectura válida, no se pospone por lluvia;
   se riega según la programación y la humedad, y se envía un aviso.
7. La detección tarda menos de **3 s** (antirrebote de 4 lecturas, una cada 500 ms).
8. El Dashboard muestra el clima (sol o lluvia). El historial explica "Pospuesto por lluvia"
   y "Cancelado por lluvia". En Android, un aviso cuando un riego se suspende.

### Limitación conocida

Una lluvia que empieza **durante** un riego propio no detiene el riego: en ese tiempo la
lectura se ignora para no confundir el agua del aspersor con lluvia. La detención en
caliente queda como mejora; el reporte del Sprint 7 la mencionó como cumplida, así que hay
que corregir ese punto en la Sprint Review.

## Contrato ESP32 ↔ app (firmware v3.4)

`GET /status` incluye el clima general y, por zona, si el riego está pospuesto:

```json
{
  "rain": { "valid": true, "raw": 1480, "raining": true },
  "zones": [ { "id": 1, "valve": false, "rainHold": true, "...": "..." } ]
}
```

Avisos a `deviceEvent` (Sprint 7):

| type | zona | Mensaje |
|---|---|---|
| `postpone` | 1–2 | Riego pospuesto por lluvia |
| `cancel` | 1–2 | Riego cancelado por lluvia (2 h) |
| `rainsensor` | 0 (general) | Sensor de lluvia sin lectura |

## Sprint Backlog

| ID | Tarea | Responsable(s) | Rama | Estado |
|---|---|---|---|---|
| SB7-01 | Sensor de lluvia: lectura, antirrebote y detección (`rain.h`) | Edgar Suárez, Esryil Vidales | `feature/sprint-07-riego-lluvia` | Implementado; falta prueba física |
| SB7-02 | Lógica de posponer, reintentar y cancelar (`rain_logic.h`, `startRainHold`) | Esryil Vidales, Kevin Colín | `feature/sprint-07-riego-lluvia` | Implementado; falta prueba física |
| SB7-03 | Tarjeta de clima, mensajes del historial y aviso de riego suspendido | Milton Becerra, Kevin Colín | `feature/sprint-07-riego-lluvia` | Implementado; falta prueba física |
| SB7-04 | Falla segura del sensor y falso positivo del aspersor | Kevin Colín, Esryil Vidales | `feature/sprint-07-riego-lluvia` | Implementado; falta prueba física |
| SB7-05 | Pruebas con valores simulados (21 en la PC + 13 en la app) y pruebas físicas | Kevin Colín, Edgar Suárez | `feature/sprint-07-riego-lluvia` | En progreso |

Acciones de mejora del Sprint 6 aplicadas: criterios escritos antes del Planning, pruebas
con valores simulados y tabla de prioridades (lluvia → humedad → programación).

## Pruebas

| Tipo | Qué se probó | Resultado |
|---|---|---|
| Unitarias (PC, C++) | `firmware/tests/rain_logic_test.cpp`: antirrebote, valores límite, falla segura, falso positivo y reintentos (21) | ✅ |
| Unitarias (CI) | App: modelo de lluvia y `/status` (13) | ✅ |
| Unitarias (CI) | Cloud Function: avisos de lluvia (17 en total) | ✅ |
| Compilación | Firmware v3.4 para ESP32 (90.8% de la flash) | ✅ |
| Hardware | Lluvia simulada con regadera | Pendiente |
| Hardware | **Lluvia real en exterior** | Pendiente: no llovió en la semana |

## Pendientes

- Validar con **lluvia real** en exterior, con el sensor junto a la maceta (tarea de arrastre
  que se cerró en el Sprint 8, SB8-06).
- Calibrar `RAIN_WET_RAW` (en `rain_logic.h`) con el sensor real.
- Desplegar la función `deviceEvent` (plan Blaze) para que lleguen los avisos reales.
