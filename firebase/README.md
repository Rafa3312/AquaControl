# Firebase — AquaControl

Reglas de seguridad de Firestore y las Cloud Functions de AquaControl: los avisos de
riego (Sprint 5, HU-8) y el historial de riegos con sus estadísticas (Sprint 8, HU-14 y HU-16).

```
firebase/
├── firestore.rules            Reglas por usuario, zona, token FCM e historial
├── firestore.indexes.json     Política TTL: borra el historial a los 12 meses
├── test/                      Reglas e integración del historial (emulador)
└── functions/
    ├── index.js               deviceEvent (avisos + push) y deviceHistory (historial)
    ├── lib/notifications.js   Validación y textos de los avisos (lógica pura)
    ├── lib/history.js         Validación, fecha local y resúmenes del historial (lógica pura)
    ├── lib/history_store.js   Guardado idempotente del historial (sin duplicados)
    ├── scripts/seed-history.js  Datos de prueba de varios meses
    └── test/
```

## Flujo de un aviso

1. El ESP32 enciende, apaga o detecta una falla en una zona.
2. Envía `POST /deviceEvent` por HTTPS con su token de vinculación (`Authorization: Bearer`).
3. La función compara el token con `devices/{uid}.token`, guarda el aviso en
   `users/{uid}/notifications` y, si el usuario dio su consentimiento, envía el push
   a sus tokens en `users/{uid}/fcmTokens`.

## Flujo del historial (Sprint 8)

1. El ESP32 guarda cada riego en su memoria y, con Internet, envía lotes a `POST /deviceHistory`
   (mismo token Bearer).
2. La función valida el lote y guarda cada riego en `users/{uid}/history/{id}` y suma el
   resumen del día en `users/{uid}/dailyStats/{AAAA-MM-DD}` (fecha **local**, UTC-6). El `id`
   es `<hora>_<zona>_<resultado>`: un reenvío no duplica ni suma dos veces.
3. La app lee el historial y los resúmenes; solo la función puede escribirlos (reglas).
4. Cada documento lleva `expireAt` y la política TTL de `firestore.indexes.json` los borra a
   los 12 meses.

Datos de prueba de varios meses (no toca datos reales con el emulador):

```bash
cd firebase/functions
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/seed-history.js <uid> --months=6
```

## Pruebas locales

Requieren **Node 22** y **Java 21** (el emulador de Firestore no acepta versiones anteriores).

```bash
cd firebase/functions && npm install && npm test      # 27 pruebas de las Cloud Functions
cd firebase && npm install && npm run test:rules       # 25 pruebas de reglas + 4 de integración del historial (emulador)
```

En CI corren en el job `firestore-rules` de `.github/workflows/ci.yml`.

## Despliegue

Las Cloud Functions requieren el plan **Blaze** del proyecto (con alerta de presupuesto).

```bash
cd firebase
npx firebase-tools login
npx firebase-tools deploy --only firestore,functions --project <id-del-proyecto>
```

`firestore` despliega las reglas y la política TTL del historial. Al terminar, copia la URL
de `deviceEvent` en `EVENT_URL` y la de `deviceHistory` en `HISTORY_URL` de
`firmware/AquaControl_v3_secure/AquaControl_v3_secure.ino` y vuelve a cargar el firmware en
el ESP32.

## Limitación conocida

En iOS, FCM necesita una clave APNs de una cuenta de Apple Developer de paga; las
notificaciones push quedan pendientes (Sprint 6). La app muestra los avisos en la
pantalla "Notificaciones" en ambas plataformas.
