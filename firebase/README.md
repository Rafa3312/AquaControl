# Firebase — AquaControl

Reglas de seguridad de Firestore y la Cloud Function que envía los avisos de
riego (Sprint 5, HU-8).

```
firebase/
├── firestore.rules            Reglas por usuario, zona y token FCM
├── test/                      Pruebas de las reglas (emulador)
└── functions/
    ├── index.js               deviceEvent: recibe avisos del ESP32 y envía el push (FCM)
    ├── lib/notifications.js   Validación y textos (lógica pura, con pruebas)
    └── test/
```

## Flujo de un aviso

1. El ESP32 enciende, apaga o detecta una falla en una zona.
2. Envía `POST /deviceEvent` por HTTPS con su token de vinculación (`Authorization: Bearer`).
3. La función compara el token con `devices/{uid}.token`, guarda el aviso en
   `users/{uid}/notifications` y, si el usuario dio su consentimiento, envía el push
   a sus tokens en `users/{uid}/fcmTokens`.

## Pruebas locales

Requieren **Node 22** y **Java 21** (el emulador de Firestore no acepta versiones anteriores).

```bash
cd firebase/functions && npm install && npm test      # 8 pruebas de la Cloud Function
cd firebase && npm install && npm run test:rules       # 15 pruebas de reglas en el emulador
```

En CI corren en el job `firestore-rules` de `.github/workflows/ci.yml`.

## Despliegue

Las Cloud Functions requieren el plan **Blaze** del proyecto (con alerta de presupuesto).

```bash
cd firebase
npx firebase-tools login
npx firebase-tools deploy --only firestore:rules,functions --project <id-del-proyecto>
```

Al terminar, copia la URL de `deviceEvent` que muestra el comando en
`EVENT_URL` de `firmware/AquaControl_v3_secure/AquaControl_v3_secure.ino` y vuelve a
cargar el firmware en el ESP32.

## Limitación conocida

En iOS, FCM necesita una clave APNs de una cuenta de Apple Developer de paga; las
notificaciones push quedan pendientes (Sprint 6). La app muestra los avisos en la
pantalla "Notificaciones" en ambas plataformas.
