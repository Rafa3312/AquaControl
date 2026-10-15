# Agente del Pipeline CI — AquaControl

Agente que **observa** el pipeline de integración continua del repositorio en
GitHub Actions, lo **muestra de forma gráfica** etapa por etapa y, cuando algo
falla, **diagnostica** la causa y **recomienda** cómo corregirla.

Es una sola página (`index.html`) sin dependencias ni instalación.

## Cómo abrirlo

Doble clic en `tools/pipeline-agent/index.html` (se abre en el navegador).

## Modos

| Modo | Qué hace |
|---|---|
| **En vivo (GitHub)** | Consulta la API pública de GitHub Actions del repo (`Rafa3312/AquaControl`), sigue la ejecución más reciente y anima cada etapa en tiempo real. Se puede filtrar por rama o elegir una ejecución del historial. |
| **Simulación** | Reproduce los escenarios del material: sin errores, falla en pruebas, falla en lint y falla del Quality Gate. Útil para explicar el recorrido sin esperar al CI. |

> Sin token, GitHub permite 60 peticiones por hora. Para grabar o dejarlo
> abierto mucho tiempo, crea un token *fine-grained* de solo lectura
> (GitHub → Settings → Developer settings → Fine-grained tokens, acceso
> "Public repositories (read-only)") y pégalo en el campo **Token**. Solo se
> guarda en la pestaña (`sessionStorage`).

## Etapas que representa

Ordenadas de menor a mayor costo, siguiendo el principio *fail fast*:

| Etapa | Fuente en el repo |
|---|---|
| Commit / Push | Evento que dispara los workflows |
| Convenciones | `commitlint.yml` → jobs `commitlint`, `pr-title` (corre en paralelo) |
| Entorno | `ci.yml` → `build-and-test`: Checkout, Set up Flutter |
| Dependencias | `flutter pub get` |
| Lint · Análisis | `flutter analyze` |
| Pruebas unitarias | `flutter test` |
| Build · Artefacto | `flutter build apk --debug` + subida del APK |
| SAST · Quality Gate | `ci.yml` → job `sonarqube` (SonarQube Cloud) |

## Cómo "razona" el agente

1. **Percepción:** lee las ejecuciones, jobs, pasos y anotaciones de error de
   GitHub Actions y los traduce a las 8 etapas del pipeline.
2. **Razonamiento:** detecta la primera etapa fallida, marca como *bloqueadas*
   las posteriores (fail fast) y busca la causa con una base de conocimiento
   por etapa y patrones sobre los mensajes del log (por ejemplo, `Expected:` /
   `Actual:` → assert fallido; `can't be assigned` → error de tipos).
3. **Acción:** muestra el diagnóstico (qué pasó, causa, evidencia, cómo
   corregirlo e impacto), registra cada evento en la bitácora, calcula tiempo
   estimado restante, tasa de éxito y etapa más lenta, y opcionalmente lo
   anuncia por voz.
