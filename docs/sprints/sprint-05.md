# Sprint 05 — Múltiples zonas y notificaciones

- **Semana:** del 28/09/2026 al 02/10/2026
- **Rama / PR:** `feature/sprint-05-zonas-notificaciones` → `develop`
- **Versión al cierre:** app `1.1.0+2` (se sube en la siguiente release) · firmware `v3.2`

## Objetivo del Sprint

Soportar múltiples zonas de riego y notificar al usuario sobre el estado de cada riego
(HU-7 y HU-8).

## Sprint Backlog

| Historia / tarea | Responsable | Estado |
|---|---|---|
| SB5-01 — Zonas en la app: modelo, pantalla "Zonas", selector en Dashboard y programación | Milton Becerra, Kevin Colín | Terminado |
| SB5-02 — Firmware de dos válvulas: relé por zona, comandos, estado y horarios por zona | Esryil Vidales, Edgar Suárez | Terminado |
| SB5-03 — Notificaciones de inicio, fin y falla: Cloud Function, FCM y pantalla "Notificaciones" | Kevin Colín, Milton Becerra | Parcial: el push en iOS pasa al Sprint 6 (SB6-06) |
| SB5-04 — Reglas de Firestore por zona y token FCM, y job de pruebas de reglas en CI | Kevin Colín | Terminado |
| SB5-05 — Pruebas unitarias de la app y pruebas de hardware con dos zonas | Kevin Colín, Edgar Suárez | Terminado |
| SB5-06 — Arrastre del Sprint 4: biometría en iOS | Milton Becerra, Uriel Romero | Terminado |

## Incremento entregado

- La app controla 2 zonas de forma independiente: pestaña **Zonas** (nombre editable y
  switch por zona), selector de zona en el Dashboard y zona en cada programación.
- Las programaciones guardadas antes de este sprint se asignan a la zona 1, igual en la
  app y en el firmware.
- Pantalla **Notificaciones** con avisos de inicio, fin y falla por zona; el push solo
  se activa si el usuario da su consentimiento.
- Si se reinstala la app, el emparejamiento se recupera desde Firestore y ya no pide
  buscar el dispositivo desde cero. La búsqueda del dispositivo tiene botón **Volver**.
- Módulos principales: `app/lib/models/zone.dart`, `app/lib/providers/zone_provider.dart`,
  `app/lib/providers/notification_provider.dart`, `app/lib/screens/zones/`,
  `app/lib/screens/notifications/`, `firmware/AquaControl_v3_secure/` (v3.2) y
  `firebase/` (reglas y función `deviceEvent`).

## Pruebas

| Tipo | Qué se probó | Resultado |
|---|---|---|
| Unitarias (CI) | `flutter test`: cliente HTTP, zonas, programaciones y duración (36 pruebas) | ✅ |
| Unitarias (CI) | Cloud Function: validación de eventos, mensajes y token (8 pruebas) | ✅ |
| Reglas (CI) | Reglas de Firestore en el emulador: dueño, zonas, tokens FCM (15 pruebas) | ✅ |
| Hardware | Firmware compilado para ESP32 (89% de la flash) y prueba con dos zonas | ✅ |
| Funcionales | APK debug en Android físico: zonas, renombrar zona, notificaciones | ✅ |

Evidencia: run del CI en verde del PR de este sprint.

## Pendientes conocidos

- La función `deviceEvent` y las reglas aún no se despliegan (la función necesita el
  plan Blaze); mientras tanto `EVENT_URL` va vacío en el firmware.
- Push en iOS: requiere la llave APNs de Apple, se decide en el Sprint 6 (SB6-06).
- `FAULT_DETECTION` está apagado hasta conectar los sensores de corriente.
- El firmware usa el 89% de la flash; si crece, usar el esquema de particiones
  "Minimal SPIFFS".

## Sprint Review

El PO aceptó el control por zonas y la pantalla de notificaciones; el push en iOS queda
como arrastre.

## Retrospectiva

- **Qué funcionó:** probar en un teléfono físico desde el segundo día y tener el job de
  reglas en el CI.
- **Qué mejorar:** decidir antes los temas que dependen de Apple (push en iOS).
- **Acciones para el siguiente sprint:** decisión sobre el push en iOS (Uriel),
  inventario y calibración del sensor de humedad (Edgar), criterios del riego
  inteligente antes del Planning (Rafael) y pruebas con valores de humedad simulados
  (Kevin).
