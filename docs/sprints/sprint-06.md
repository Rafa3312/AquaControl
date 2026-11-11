# Sprint 06 — Riego inteligente por humedad del suelo

- **Semana:** del 05/10/2026 al 09/10/2026
- **Rama / PR:** base del sprint en `feature/sprint-06-riego-inteligente` → `develop`, y una
  rama por integrante (tabla del Sprint Backlog)
- **Versión al cierre:** app `1.1.0+2` (se sube en la siguiente release) · firmware `v3.3`

## Objetivo del Sprint

Incorporar riego inteligente basado en la humedad del suelo (HU-10): el sistema ajusta
automáticamente el riego programado según la humedad real del suelo.

## Criterios de aceptación de HU-10 (Product Owner)

1. Cada zona tiene su propio riego inteligente: se activa o apaga y tiene un umbral de
   humedad de **10% a 90%** (por defecto **60%**).
2. Antes de cada **riego programado** se mide la humedad y se decide:

   | Humedad medida (umbral 60%) | Qué hace | Mensaje en la app |
   |---|---|---|
   | 60% o más | Omite el riego | Omitido por humedad suficiente |
   | 45% a 59% | Riega la mitad (mínimo 1 min) | Reducido a la mitad por humedad |
   | Menos de 45% | Riega completo | Riego completo: suelo seco |
   | Lectura inválida | Riega lo programado y avisa | Sensor sin lectura: se riega lo programado |

3. Ejemplos con una programación de 10 min: 68% → no riega · 50% → 5 min · 30% → 10 min ·
   sensor desconectado → 10 min y aviso de falla.
4. El riego manual no cambia: el riego inteligente solo aplica a los riegos programados.
5. **Tiempo de absorción:** si un riego programado cae en los 3 minutos siguientes a que la
   zona se apagó, se espera a que pasen esos 3 minutos antes de medir.
6. Estado del suelo en el Dashboard: **seco** menos de 35%, **húmedo** de 35% a 79% y
   **saturado** 80% o más.
7. El umbral se valida en la app, en el firmware y en las reglas de Firestore.

## Contrato ESP32 ↔ app (firmware v3.3)

`GET /status`, dentro de cada zona:

```json
{
  "id": 1,
  "valve": false,
  "moisture": { "valid": true, "raw": 1820, "percent": 65 },
  "smart": { "enabled": true, "threshold": 60 },
  "lastSmart": { "reason": "wet", "percent": 65, "at": "06:00" }
}
```

`reason`: `off` (apagado), `sensor` (lectura inválida), `wet` (omitido), `near` (mitad),
`dry` (completo).

`POST /smart` con `{"zone": 1, "enabled": true, "threshold": 60}` → `{"ok": true, ...}`.
Responde 400 si la zona o el umbral no son válidos.

Avisos a la función `deviceEvent`: tipos nuevos `skip`, `reduce` y `sensor`, con
`moisture` y `threshold`.

## Sprint Backlog

| Tarea | Responsable | Rama | Estado |
|---|---|---|---|
| Criterios de HU-10, contrato, modelo y provider de la app, reglas de Firestore, Cloud Function y pruebas base | Rafael Sámano | `feature/sprint-06-riego-inteligente` | Terminado |
| SB6-01 Sensor de humedad: lectura, calibración y filtrado (`moisture.h`) | Edgar Suárez | `feature/sprint-06-sensor-humedad` | Terminado (PR #16) |
| SB6-02 y SB6-04 Lógica de ajuste en el firmware v3.3, umbral validado, absorción y falla segura | Esryil Vidales | `feature/sprint-06-logica-riego` | Pendiente de integrar: PR abierto desde esta rama |
| SB6-03 Tarjeta de humedad en el Dashboard y pantalla de configuración | Milton Becerra | `feature/sprint-06-humedad-app` | En revisión (PR #19; se conectó la tarjeta y la pantalla que faltaban) |
| SB6-05 Pruebas con valores de humedad simulados (10 pruebas) | Kevin Colín | `feature/sprint-06-pruebas-humedad` | Terminado (PR #18) |
| SB6-06 Decisión sobre el push en iOS | Uriel Romero | `feature/sprint-06-push-ios` | Terminado (PR #17) |

Orden de integración: Edgar antes que Esryil (el firmware v3.3 usa `moisture.h`); los
demás en cualquier orden.

## Pruebas

| Tipo | Qué se probó | Resultado |
|---|---|---|
| Unitarias (CI) | `flutter test`: provider del riego inteligente, humedad en `/status`, avisos nuevos (84 pruebas) | ✅ |
| Unitarias (CI) | Cloud Function: avisos `skip`, `reduce` y `sensor` (12 pruebas) | ✅ |
| Reglas (CI) | Umbral de 10% a 90% en Firestore (18 pruebas) | ✅ |
| Unitarias (CI) | Tabla de decisión con valores simulados (PR #18) | ✅ |
| Compilación | Firmware v3.3 con `moisture.h` y `smart_irrigation.h` (90% de la flash) | ✅ |
| Hardware | Suelo seco, húmedo y saturado con el sensor capacitivo | Pendiente |

## Pendientes conocidos

- Mientras no se cargue el firmware v3.3 la tarjeta muestra "Sin sensor conectado" y al
  guardar la configuración la app avisa que falta el firmware v3.3.
- La función `deviceEvent` y las reglas siguen sin desplegarse (plan Blaze).
