# Decisión: notificaciones push en iOS

- **Tarea:** SB6-06 (arrastre del Sprint 5, HU-8)
- **Responsable:** Uriel Romero Martínez (Scrum Master)
- **Fecha:** 06/10/2026
- **Estado:** Aceptada

## Contexto

En el Sprint 5 las notificaciones de inicio, fin y falla del riego quedaron funcionando
en Android con Firebase Cloud Messaging (FCM). En iOS no se pudieron terminar porque FCM
necesita una llave APNs, y esa llave solo se genera con una cuenta del Apple Developer
Program, que cuesta 99 USD al año. El equipo no tiene esa cuenta y la app en iPhone solo
se instala para pruebas desde Xcode.

## Opciones que revisamos

| Opción | Ventaja | Problema |
|---|---|---|
| A. Pagar la cuenta de Apple Developer | Push real en iOS | Costo fuera del presupuesto del MVP |
| B. Revisar avisos cada cierto tiempo desde la app | No necesita APNs | iOS no deja correr la app en segundo plano para eso |
| C. Dejarlo como limitación del MVP | Sin costo y sin bloquear al equipo | En iPhone no llega el push |

## Decisión

Elegimos la **opción C**: el push en iOS queda documentado como **limitación del MVP**.

- En iPhone la pantalla **Notificaciones** sigue mostrando todos los avisos (incluidos los
  del riego inteligente), porque se leen de Firestore al abrir la app.
- El interruptor de notificaciones push en iOS muestra el mensaje *"Las notificaciones
  push en iOS aún no están disponibles"* (`NotificationProvider.supported`).
- En Android todo sigue igual.

## Consecuencias

- La HU-8 se da por terminada en Android y con la limitación anotada en iOS.
- Si el proyecto consigue una cuenta de Apple Developer, se retoma: subir la llave APNs a
  Firebase y probar en un iPhone físico. Se revisa en la Sprint Review del Sprint 12.
