# AquaControl (H2Control)

![CI](https://github.com/Rafa3312/AquaControl/actions/workflows/ci.yml/badge.svg)

Aplicación móvil (Flutter + Firebase) para controlar y monitorear un sistema de riego automatizado mediante un microcontrolador ESP32 (firmware AquaControl v3.1).

## Descripción

- **App**: Flutter, Firebase Auth + Firestore, autenticación biométrica, control manual y programado del riego, descubrimiento del dispositivo por mDNS.
- **Firmware**: ESP32, portal cautivo SoftAP para WiFi, API REST con token Bearer, almacenamiento cifrado en NVS.

## Estructura del repositorio

```
/app       -> app Flutter completa (copia de Proyectos/H2Control/irrigation_app)
/firmware  -> firmware del ESP32 (AquaControl_v3_secure.ino)
/docs      -> Plan DevOps, Documento CI/CD, backlog y avances por sprint (docs/sprints)
/scripts   -> sync-from-h2control.ps1 (trae avances del proyecto principal),
              setup-branch-protection.sh (reglas de GitHub vía gh CLI)
/ci        -> scripts auxiliares de build/CI
/.github   -> workflows de CI, plantillas de issue/PR, CODEOWNERS, rulesets
CONTRIBUTING.md -> flujo Gitflow ligero, convención de commits y versionado
```

El validador puro (`app/lib/utils/irrigation_validator.dart`), su prueba
(`app/test/irrigation_validator_test.dart`) y el feature flag
(`app/lib/config/feature_flags.dart`) ya viven dentro del proyecto Flutter.

## Cómo construir y ejecutar

`google-services.json` **no se versiona** (el repo es público). Cópialo desde tu
proyecto de Firebase a `app/android/app/google-services.json` antes de compilar.

```bash
cd app
flutter pub get
flutter test
flutter run
```

## Avances por sprint

Cada semana se sincronizan los avances desde el proyecto principal y se documentan
en `docs/sprints/`. Ver el flujo completo en [`docs/sprints/README.md`](docs/sprints/README.md).

## CI

`.github/workflows/ci.yml` corre en cada push a `develop` y en cada Pull Request
hacia `develop` o `main`: `flutter pub get` → `flutter analyze` → `flutter test` →
build de APK debug (este último solo si existe el secreto `GOOGLE_SERVICES_JSON` en
**Settings > Secrets and variables > Actions**, con el contenido de
`google-services.json`).

## Reglas de CI/merge (automatizadas, no solo documentadas)

- `.github/workflows/commitlint.yml`: valida automáticamente que los commits y el título del PR sigan Conventional Commits (job `commitlint` + `pr-title`).
- `.github/rulesets/main-ruleset.json` y `develop-ruleset.json`: rulesets de GitHub listos para importar en **Settings > Rules > Rulesets > New ruleset > Import a ruleset**. Bloquean push directo, force-push y borrado, y exigen que `build-and-test`, `commitlint` (y `pr-title` en `main`) pasen antes de mergear.
- `scripts/setup-branch-protection.sh`: alternativa vía GitHub CLI. Ejecuta `gh auth login` y luego:
  ```bash
  ./scripts/setup-branch-protection.sh Rafa3312/AquaControl
  ```
  Esto aplica las mismas reglas por API en vez de la UI.

Criterio de merge resultante: PR hacia `main` o `develop` solo puede mergearse si `build-and-test` y `commitlint` están en verde (y `pr-title` además en `main`), y en `main` se requiere 1 aprobación.

## Feature flags

`app/lib/config/feature_flags.dart` controla la visibilidad de módulos en desarrollo
(hoy: la pestaña Reportes) sin necesidad de una nueva publicación. Demostrador
de la Parte F de la práctica de CI/CD; plan a futuro: migrar a Firebase Remote
Config (ver `docs/Documento_CI_CD_AquaControl.docx`, sección Parte E).

## Enlaces

- Plan DevOps del Proyecto Móvil: `docs/Plan_DevOps_AquaControl.docx`
- Documento de investigación CI/CD: `docs/Documento_CI_CD_AquaControl.docx`
- Backlog / Sprint 0: `docs/backlog.md`
- Avances por sprint: `docs/sprints/README.md`
- Board del proyecto: <enlace al GitHub Projects — agrégalo aquí>
- Servidor de comunicación (Discord): <enlace de invitación — agrégalo aquí>

## Ramas

- `main`: estable, protegida.
- `develop`: integración.
- `feature/*`: nuevas funciones (PR → develop).
- `hotfix/*`: correcciones urgentes (PR → main + tag).

Commits siguiendo [Conventional Commits](https://www.conventionalcommits.org/) y versionado semántico (`v0.1.0`, ...).
