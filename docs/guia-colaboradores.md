# Guía para colaboradores — AquaControl

Paso a paso para tener el proyecto en tu computadora y subir tus cambios desde tu
propia cuenta de GitHub, para que cada commit quede a tu nombre y aparezcas en
**Insights → Contributors**.

> Resumen: aceptas la invitación → instalas lo necesario → configuras Git con el
> correo de tu GitHub → clonas → trabajas en tu rama → abres un PR hacia `develop`.

---

## 0. Lo que hace Rafael (una sola vez)

1. **Invitar a cada integrante:** en el repo, *Settings → Collaborators → Add people*
   y escribir el usuario de GitHub de cada uno.
2. **Mandar `google-services.json` por privado** (WhatsApp o Drive con acceso
   restringido). No está en el repo porque el repo es público.
3. **Rama por defecto = `develop`:** *Settings → General → Default branch*. Así los PR
   apuntan solos a `develop` y la lista de *Contributors* cuenta los commits en cuanto
   se integran (no hasta la release a `main`).

## 1. Antes de empezar

1. Ten tu cuenta de GitHub y **acepta la invitación**: llega por correo o entra a
   <https://github.com/Rafa3312/AquaControl/invitations>.
2. En GitHub ve a *Settings → Emails* y fíjate en tu correo **verificado**. Si tienes
   activado *Keep my email addresses private*, usa el correo que termina en
   `@users.noreply.github.com` que aparece ahí.

## 2. Instalar las herramientas

| Herramienta | Quién la necesita | Nota |
|---|---|---|
| [Git for Windows](https://git-scm.com/download/win) | Todos | Deja las opciones por defecto (incluye el *Credential Manager*). |
| [VS Code](https://code.visualstudio.com/) | Todos | Extensiones **Flutter** y **Dart** si vas a tocar la app. |
| Flutter **3.27.3** | App (Milton, Kevin) | La misma versión del CI. Descárgala del [archivo de versiones](https://docs.flutter.dev/release/archive), descomprime en `C:\src\flutter` y agrega `C:\src\flutter\bin` al PATH. |
| Android Studio | App | Para el SDK de Android y el emulador. Luego corre `flutter doctor`. |
| Arduino IDE 2 | Firmware (Esryil, Edgar) | Ver el paso 6. |
| Node 22 y Java 21 | Solo quien pruebe reglas o funciones de Firebase (Kevin) | Ver `firebase/README.md`. |

Uriel y Rafael, si solo van a tocar documentación, con Git y VS Code es suficiente.

## 3. Configurar Git (una sola vez)

```bash
git config --global user.name "Tu Nombre Apellido"
git config --global user.email "el-correo-de-tu-github"
```

Comprueba con `git config --global --list`. **Este paso es el que hace que el commit
cuente como tuyo:** si el correo no coincide con uno de tu cuenta, el commit sale con
un ícono gris y no apareces como colaborador.

## 4. Clonar el proyecto

Clónalo **fuera de OneDrive** y en una ruta sin espacios (Flutter y Gradle fallan o se
vuelven lentos en carpetas sincronizadas):

```bash
mkdir C:/dev
cd C:/dev
git clone https://github.com/Rafa3312/AquaControl.git
cd AquaControl
git checkout develop
```

La primera vez que hagas `push` se abre el navegador para iniciar sesión en GitHub:
entra con **tu** cuenta.

## 5. Correr la app

1. Copia el `google-services.json` que te pasó Rafael a `app/android/app/`.
2. Desde la carpeta del proyecto:

```bash
cd app
flutter pub get
flutter test
flutter run
```

Si Gradle falla diciendo que no encuentra el plugin de Android o menciona Java 8, usa
el Java que trae Android Studio:

```bash
flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
```

## 6. Compilar el firmware

1. Arduino IDE → *Archivo → Preferencias → Gestor de URLs adicionales de tarjetas*:
   `https://espressif.github.io/arduino-esp32/package_esp32_index.json`
2. *Gestor de tarjetas*: instala **esp32 by Espressif Systems 3.3.8**.
3. *Gestor de bibliotecas*: instala **RTClib** y **ArduinoJson** (versión 7).
4. Abre `firmware/AquaControl_v3_secure/AquaControl_v3_secure.ino`, elige la placa
   **ESP32 Dev Module** y dale a **Verificar (✓)**.
5. Si sale *Sketch too big*, cambia *Herramientas → Partition Scheme* a
   **Minimal SPIFFS**.

## 7. Flujo para cada cambio

Nunca se trabaja directo en `develop` ni en `main` (GitHub lo bloquea). Cada tarea va
en su propia rama:

```bash
git checkout develop
git pull
git checkout -b feature/sprint-06-tu-tema
```

Haz tus cambios y pruébalos (`flutter test` si tocaste la app, *Verificar* en Arduino si
tocaste el firmware). Luego:

```bash
git status
git add ruta/de/tus/archivos
git commit -m "feat(app): tarjeta de humedad en el Dashboard"
git push -u origin feature/sprint-06-tu-tema
```

En GitHub aparece el botón **Compare & pull request**:

1. *base:* `develop` ← *compare:* tu rama.
2. Título con el mismo formato del commit (`feat(app): ...`) y llena la plantilla.
3. Espera a que los checks estén en verde (`build-and-test`, `commitlint`, `pr-title`).
4. Para integrar usa **Create a merge commit** (no *Squash*): así tus commits llegan a
   `develop` con tu nombre.
5. Borra la rama con el botón *Delete branch*.

### Formato de los commits (Conventional Commits)

`tipo(alcance): descripción corta`, en español, sin punto final.

| Tipo | Cuándo | Ejemplo |
|---|---|---|
| `feat` | Algo nuevo | `feat(firmware): lectura del sensor de humedad` |
| `fix` | Corrección | `fix(app): el umbral no se guardaba al salir` |
| `test` | Pruebas | `test(app): decisión de riego con valores simulados` |
| `docs` | Documentación | `docs: decisión sobre el push en iOS` |
| `ci` | Pipeline | `ci: agrega pruebas de humedad al CI` |
| `chore` / `refactor` / `style` / `perf` | Mantenimiento | `refactor(app): separa el modelo de humedad` |

Alcances que usamos: `app`, `firmware`, `firebase`, `ci`, `docs`.

### Lo que nunca se sube

`google-services.json`, contraseñas de WiFi, tokens, llaves o `node_modules/`. El
`.gitignore` ya los excluye; si `git status` te muestra alguno, no lo agregues.

## 8. ¿Ya cuento como colaborador?

- En tu PR, cada commit debe mostrar **tu foto** de GitHub. Si sale un ícono gris con
  tu nombre, el correo del paso 3 no está en tu cuenta: agrégalo en *Settings → Emails*
  y verifícalo (los commits ya hechos se ligan solos).
- *Insights → Contributors* se actualiza unas horas después del merge.

## 9. Problemas comunes

| Error | Solución |
|---|---|
| `Permission to Rafa3312/AquaControl.git denied` | No has aceptado la invitación o Git guardó otra cuenta. Borra la credencial `git:https://github.com` en *Panel de control → Administrador de credenciales → Credenciales de Windows* y vuelve a hacer `push`. |
| `GH013: Repository rule violations` | Intentaste hacer `push` a `develop` o `main`. Crea tu rama (paso 7). |
| Falla `commitlint` o `pr-title` | El mensaje no sigue el formato. Corrige con `git commit --amend -m "feat(app): ..."` y `git push --force-with-lease` (solo en tu rama). |
| `File google-services.json is missing` | Falta el paso 5.1. |
| El PR dice que tu rama está desactualizada | `git pull origin develop` en tu rama, resuelve conflictos en VS Code, haz commit y `push`. |
| `flutter test` falla en tu compu pero no en el CI | Revisa que tengas Flutter 3.27.3 (`flutter --version`). |

Las reglas completas del flujo (ramas, versiones y releases) están en
[`CONTRIBUTING.md`](../CONTRIBUTING.md).
