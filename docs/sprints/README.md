# Avances por Sprint — AquaControl

Este repositorio es la **copia de seguimiento DevOps** del proyecto. El desarrollo
principal vive en `Proyectos/H2Control` (app Flutter + firmware ESP32) y aquí solo
entran los avances semanales de cada Sprint (planeación de *Desarrollo Móvil Integral*,
`Planeacion_Proyecto_Riego_Automatizado_V2.2.docx`): 12 Sprints de 1 semana.

## Flujo semanal (un Sprint = una rama = un PR)

```bash
# 1. Partir de develop actualizado
git checkout develop
git pull

# 2. Rama del sprint
git checkout -b feature/sprint-05-zonas-notificaciones
```

```powershell
# 3. Traer los avances del proyecto principal (solo lee H2Control, no lo modifica)
powershell -ExecutionPolicy Bypass -File scripts\sync-from-h2control.ps1
```

```bash
# 4. Documentar el sprint: copiar la plantilla y llenarla
cp docs/sprints/_plantilla.md docs/sprints/sprint-05.md

# 5. Commits con Conventional Commits, push y PR hacia develop
git add app firmware docs/sprints
git commit -m "feat(sprint-05): control de zonas y notificaciones"
git push -u origin feature/sprint-05-zonas-notificaciones
```

6. Abrir PR `feature/sprint-XX-…` → `develop` en GitHub (título también en formato
   Conventional Commits). Cuando el CI esté en verde, merge.
7. Al cerrar un hito (ej. MVP al final del Sprint 4, RC en el Sprint 12): PR
   `develop` → `main` y tag semántico (`v1.1.0`, …), subiendo también `version:` en
   `app/pubspec.yaml`.

## Estado de los Sprints

Actualiza la columna **Estado** (Pendiente / En curso / Terminado) y enlaza el
documento de cada sprint cuando lo cierres.

| Sprint | Objetivo | Historias | Estado | Doc |
|---|---|---|---|---|
| 1 | Bases técnicas y vinculación app–programador | #1 pairing, wireframes, arquitectura | Pendiente | — |
| 2 | Control manual del riego | #2 encendido/apagado, #6 estado del sistema | Pendiente | — |
| 3 | Programación automática de riegos | #3 crear, #4 editar/eliminar programas, horarios en firmware | Pendiente | — |
| 4 | Autenticación de usuario | #5 registro/login, #9 recuperar contraseña | Pendiente | — |
| 5 | Múltiples zonas y notificaciones | #7 zonas, #8 notificaciones | Pendiente | — |
| 6 | Riego por humedad del suelo | #10 sensor de humedad | Pendiente | — |
| 7 | Riego por condiciones climáticas | #11 sensor de lluvia | Pendiente | — |
| 8 | Historial y estadísticas | #14 historial, #16 consumo de agua | Pendiente | — |
| 9 | Confiabilidad ante fallas | #12 alertas de fallas, #13 modo offline | Pendiente | — |
| 10 | Uso compartido y cuenta | #15 preferencias, #17 compartir acceso, #19 respaldo | Pendiente | — |
| 11 | Experiencia de usuario | #18 onboarding, pruebas de usabilidad | Pendiente | — |
| 12 | Estabilización y entrega (RC) | Integración, regresión, UAT, manual | Pendiente | — |

## Línea base importada

Commit de reestructuración (`feature/estructura-monorepo`): se importó el estado
actual de la app (`version: 1.0.0+1`) con login/registro (Firebase Auth),
configuración de WiFi y vinculación del ESP32, pantalla principal con control
manual, programas de riego, reportes (oculto por feature flag) y perfil; además del
firmware `AquaControl_v3_secure`.

## Deuda técnica conocida

- `flutter analyze` reporta 6 *warnings* y 79 *infos* heredados del código base
  (principalmente `withOpacity` obsoleto y `prefer_const_constructors`). El CI hoy
  solo falla con **errores**; conforme se limpien, quitar `--no-fatal-warnings`
  de `.github/workflows/ci.yml`.
- El `widget_test.dart` por defecto de Flutter (contador) no aplica a esta app y no
  se copia; se debe sustituir por pruebas reales de widgets.
