# Guía de Contribución — AquaControl

¿Primera vez? Empieza por [`docs/guia-colaboradores.md`](docs/guia-colaboradores.md):
instalación, configuración de Git con tu cuenta y el paso a paso de tu primer PR.

## Flujo de trabajo

Seguimos **Gitflow ligero** (elegido y justificado en `docs/Documento_CI_CD_AquaControl.docx` frente a GitHub Flow y Trunk-Based, y ya reflejado en las reglas de protección del repositorio):

1. `main`: rama estable y protegida. Solo recibe merges vía PR desde `develop` o `hotfix/*`. Cada merge a `main` se etiqueta con un tag semántico.
2. `develop`: rama de integración donde convergen las features antes de una release.
3. `feature/<nombre>`: nuevas funcionalidades, creada desde `develop`. PR obligatorio → `develop`. Para los avances semanales se usa `feature/sprint-XX-<tema>` (ver `docs/sprints/README.md`).
4. `hotfix/<nombre>`: correcciones urgentes, creada desde `main`. PR → `main` (con tag inmediato) y merge-back a `develop`.

## Commits

Usamos **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `ci:`), validado automáticamente por el workflow `commitlint` en cada Pull Request. El título del PR debe seguir el mismo formato (job `pr-title`).

## Versionado

- App: versionado semántico `vMAJOR.MINOR.PATCH` enlazado al build number interno — en `pubspec.yaml`: `version: 1.1.0+7` (el `+7` es el `versionCode`/build number, se incrementa en cada build subida a Firebase App Distribution o a la tienda).
- Firmware: versionado semántico independiente (ej. `AquaControl Firmware v3.1`), documentado junto al de la app en `/docs`.

## Pull Requests

- Requiere que los checks de CI (`build-and-test`, `commitlint`, y `pr-title` en `main`) estén en verde.
- Requiere al menos 1 aprobación en `main` de un integrante distinto al autor del PR.
- PR hacia `develop`: se integra con **Create a merge commit** para que cada commit conserve a su autor.
- PR hacia `main`: *Squash* o *Rebase* (historial lineal), y después back-merge de `main` a `develop` con merge commit.
- Usa la plantilla en `.github/pull_request_template.md`.

## Pruebas

Toda función de lógica pura (ej. validadores) debe incluir su prueba unitaria en `app/test/`, ejecutada automáticamente por el CI en cada PR.
