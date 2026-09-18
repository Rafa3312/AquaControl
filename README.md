# AquaControl (H2Control)

![CI](https://github.com/<tu-usuario>/aquacontrol/actions/workflows/ci.yml/badge.svg)

Aplicación móvil (Flutter + Firebase) para controlar y monitorear un sistema de riego automatizado mediante un microcontrolador ESP32 (firmware AquaControl v3.1).

## Descripción

- **App**: Flutter, Firebase Auth + Firestore, autenticación biométrica, control manual y programado del riego, descubrimiento del dispositivo por mDNS.
- **Firmware**: ESP32, portal cautivo SoftAP para WiFi, API REST con token Bearer, almacenamiento cifrado en NVS.

## Estructura del repositorio

```
/docs     -> Plan DevOps del Proyecto Móvil, guía de comunicación, backlog
/app      -> código Flutter
/ci       -> scripts auxiliares de build/CI
/.github  -> workflow de CI y plantillas de issue/PR
```

## Cómo construir y ejecutar

```bash
cd app
flutter pub get
flutter run
```

## CI

El workflow en `.github/workflows/ci.yml` corre `flutter analyze` y `flutter test` en cada push a `develop` y en cada Pull Request hacia `main`.

## Enlaces

- Plan DevOps del Proyecto Móvil: `docs/Plan_DevOps_AquaControl.docx`
- Backlog / Sprint 0: `docs/backlog.md`
- Board del proyecto: <enlace al GitHub Projects — agrégalo aquí>
- Servidor de comunicación (Discord): <enlace de invitación — agrégalo aquí>

## Ramas

- `main`: estable, protegida.
- `develop`: integración.
- `feature/*`: nuevas funciones (PR → develop).
- `hotfix/*`: correcciones urgentes (PR → main + tag).

Commits siguiendo [Conventional Commits](https://www.conventionalcommits.org/) y versionado semántico (`v0.1.0`, ...).
