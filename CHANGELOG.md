# Registro de cambios

Todas las versiones de **Linux Ultimate Tools** (antes Ubuntu Ultimate Tools y Kubuntu Transformer). Los números siguen
[Versionado Semántico](https://semver.org/lang/es/): **MAYOR** cuando cambia el alcance del proyecto o algo deja de
funcionar como antes, **MENOR** cuando se agregan opciones, **PARCHE** cuando solo se arreglan errores.

Los tres scripts (`ubuntu-`, `debian-` y `arch-ultimate-tools.sh`) comparten la misma versión. Para ver cuál tienes:

```bash
./ubuntu-ultimate-tools.sh --version
```

## Resumen

| Versión | Fecha | Hito | Cambios | Líneas agregadas | Líneas quitadas |
|---|---|---|---:|---:|---:|
| [3.5.2](#352--2026-11-28) | 2026-11-28 | KDE neon y actualización sin caché | 2 | | |
| [3.5.1](#351--2026-11-28) | 2026-11-28 | Actualizar KDE neon | 2 | | |
| [3.5.0](#350--2026-11-28) | 2026-11-28 | Kernel de kernel.org | 4 | | |
| [3.4.0](#340--2026-11-27) | 2026-11-27 | Quitar periféricos y actualización al iniciar | 8 | | |
| [3.3.0](#330--2026-11-27) | 2026-11-27 | Pruebas y reinstalar controladores | 8 | | |
| [3.2.0](#320--2026-11-27) | 2026-11-27 | Temas, periféricos y versionado | 7 | 3.025 | 284 |
| [3.1.0](#310--2026-11-26) | 2026-11-26 | Descargar sistemas, Ventoy y código en piezas | 14 | 24.386 | 727 |
| [3.0.0](#300--2026-11-24) | 2026-11-24 | Linux Ultimate Tools | 20 | 5.932 | 692 |
| [2.1.0](#210--2026-11-20) | 2026-11-20 | Debian y Arch (beta) | 8 | 15.431 | 710 |
| [2.0.0](#200--2026-11-15) | 2026-11-15 | Ubuntu Ultimate Tools | 10 | 3.898 | 648 |
| [1.1.0](#110--2026-11-09) | 2026-11-09 | Menú de arranque | 8 | 1.146 | 133 |
| [1.0.0](#100--2026-11-01) | 2026-11-01 | Primera versión completa (Kubuntu) | 8 | 3.065 | 590 |
| [0.1.0](#010--2026-05-22) | 2026-05-22 | Kubuntu Transformer | 8 | 2.270 | 0 |
| **Total** | | | **107** | **59.153** | **3.784** |

Hoy: **3 scripts** (Ubuntu, Debian y Arch), **23 opciones** en el menú principal, más de **40 sistemas** para descargar y
el código en **8 piezas** (`partes/`) que `armar.sh` une.

## [3.5.2] — 2026-11-28

**KDE neon y actualización sin caché.** Arreglos de la prueba en una PC real con KDE neon.

2 cambios

- Arreglo: la actualización al iniciar baja del último commit exacto de GitHub; antes, en los 5 minutos después de publicar una versión, GitHub podía entregar la anterior (se actualizaba a la 3.5.0 en vez de la 3.5.1)
- Arreglo: KDE neon se reconoce como "KDE neon" (con su edición, p. ej. Testing Edition) y no como Kubuntu: no se le ofrece el PPA KDE Rolling Release de Kubuntu y su meta-paquete es `neon-desktop`

## [3.5.1] — 2026-11-28

**Actualizar KDE neon.** Arreglos de la opción 1 probada en una PC real con KDE neon.

2 cambios

- Arreglo: KDE neon se actualiza con su comando oficial (`pkcon refresh` y `pkcon update`); con `apt full-upgrade` fallaba porque quería volver a versiones anteriores de paquetes que neon fija
- Arreglo: si la actualización falla ya no dice "¡Sistema actualizado completamente!": avisa que no terminó y dónde ver el error

## [3.5.0] — 2026-11-28

**Kernel de kernel.org.** En el menú del kernel (14) de Ubuntu, la opción 6 muestra los 3 estables más nuevos y el
de prueba, como en la portada de kernel.org, y los instala.

4 cambios

- Kernel → 6: los 3 estables más nuevos (estable y largo plazo) y el de prueba (rc) de kernel.org, con cuál está instalado y en uso
- Se instalan las compilaciones para Ubuntu de kernel.ubuntu.com, comprobadas con sus sumas SHA-256; si Ubuntu aún no compiló la última, se ofrece la más nueva de esa serie
- Si los headers no se pueden instalar, el kernel se instala sin ellos y avisa; GRUB queda arrancando el nuevo y el oficial de respaldo
- Kernel → 6 → Quitar: borra un kernel de kernel.org que no esté en uso

## [3.4.0] — 2026-11-27

**Quitar periféricos y actualización al iniciar.** El menú de periféricos (23) tiene la opción 10 para quitar lo
que ya no usas, y los tres scripts buscan al abrirse si hay una versión nueva en el repositorio.

8 cambios

- Al abrirse, cada script busca una versión nueva en el repositorio oficial; si la hay, muestra qué cambió y ofrece actualizarse y volver a abrirse
- La actualización se comprueba con las sumas SHA-256 publicadas (`SHA256SUMS`) antes de reemplazar nada, y la versión anterior queda de respaldo
- Sin internet sigue sin decir nada; se salta con `UT_SIN_ACTUALIZAR=1`; en una copia de git avisa que se use `git pull`
- Periféricos → 10 → 1: quitar impresoras configuradas (solo su configuración; con casillas y prueba de que se fue)
- Periféricos → 10 → 2: desvincular dispositivos Bluetooth
- Periféricos → 10 → 3: borrar las huellas registradas y dejar de pedirlas para iniciar sesión y `sudo`
- Periféricos → 10 → 4: desinstalar el soporte de periféricos que instaló el script (nunca lo que traía el sistema), avisando antes qué más se quitaría por dependencias
- Cada cosa quitada se comprueba (🧪 ✓ / ✗)

## [3.3.0] — 2026-11-27

**Pruebas y reinstalar controladores.** Cada instalación de periféricos y controladores se prueba sola y dice si
funciona; los controladores se pueden reinstalar desde los menús. Incluye los arreglos de la prueba en una PC real
(Debian 13 con una HP Ink Tank 110).

8 cambios

- Periféricos: prueba automática después de preparar cada uno (✓ funciona / ✗ falla y por qué): impresora habilitada y página de prueba que sale de la cola, escaneo de prueba, imagen de la cámara, Bluetooth encendido y dispositivos cerca, mando, huella registrada y tableta reconocidos
- Periféricos → 9: reinstalar los controladores de un periférico, reiniciar su servicio y volver a probar
- GPU (13 → 5) y Red (16 → 8): reinstalar los controladores de video, Wi-Fi, firmware y microcódigo instalados, recompilar DKMS, rehacer el arranque y probar
- Red → 6: después de instalar los drivers recomendados, prueba qué controlador usa cada placa (y si NVIDIA responde y el Wi-Fi aparece)
- Arreglo: los controladores USB de la placa ("xHCI Host Controller") ya no aparecen como mandos de juego
- Arreglo: las impresoras ya configuradas se reconocen con su controlador y estado, y se arreglan (controlador del modelo, hpcups para HP; habilitada y aceptando trabajos)
- Arreglo: las impresoras USB nuevas se agregan primero con el controlador de su modelo y después sin controlador
- Cómo ver la impresora en Chrome después de configurarla

## [3.2.0] — 2026-11-27

**Temas, periféricos y versionado.** Tema Tokyo Night completo para Plasma y GNOME (22), periféricos (23), htop a la vista, arreglos de descargas y número de versión con este registro de cambios.

7 cambios · +3.025 / −284 líneas

- Tema Tokyo Night para GNOME (opción 8)
- Tokyo Night en GNOME también para las apps Qt
- Opción 22: tema del escritorio Tokyo Night completo (Plasma y GNOME)
- Información del sistema: htop como opción 13, a la vista
- Descargas: arreglo de Zorin OS y openSUSE Leap
- Opción 23: periféricos, detectar e instalar
- Versionado (SemVer): versión en la cabecera y con `--version`, y este registro de cambios

## [3.1.0] — 2026-11-26

**Descargar sistemas, Ventoy y código en piezas.** Más de 40 distribuciones para descargar verificadas, Ventoy con persistencia, código compartido en `partes/` con `armar.sh` y revisión automática, perfil gaming-extremo, Wine y menús que vuelven al submenú correcto.

14 cambios · +24.386 / −727 líneas

- Crear USB: KDE neon y comprobación de las ISO que ya tienes
- Crear USB: las tres ediciones de KDE neon (User, Testing y Unstable)
- Crear USB: más de 30 sistemas para descargar, agrupados por base
- Descargar sistemas y crear USB: familia Red Hat, openSUSE Leap, Slackware, Gentoo, Void y NixOS
- Ventoy: varios sistemas en un solo pendrive, con persistencia (opción 20 → 4)
- Código en piezas: lo compartido por los tres scripts se escribe una sola vez
- Descargas: KDE neon en su carpeta nueva, Pop!_OS 24.04 y prueba de todas las distros
- Descargas: GoldenDog Linux en la familia Debian
- README: capturas del menú de auditoría y de linaudit
- Menú principal: la opción 2 nombra a linaudit junto a Lynis
- Perfil gaming-extremo al estilo CachyOS (Ubuntu) y Wine en el software opcional
- Menús: 0 vuelve al submenú de donde vino, no al principal
- Listas con casillas en Termux: dialog sin ratón y números en pantallas angostas
- Listas con casillas también en el celular

## [3.0.0] — 2026-11-24

**Linux Ultimate Tools.** Un repositorio para todas las distribuciones. Auditoría de seguridad (Lynis, auditd, linaudit), crear USB de instalación, barra de avance, detección de la distribución y de todas las apps, listas con casillas y salida con 0 en todas las preguntas.

20 cambios · +5.932 / −692 líneas

- Auditoría de seguridad: Lynis sin instalar y registro de auditoría con auditd
- Auditoría de seguridad como ítem propio (19) en los tres scripts
- linaudit de Alexia Michelle en Auditoría de seguridad (19 → 2), con compilación temporal
- Auditoría de seguridad pasa a la opción 2 del menú principal
- Arranque: opción para ver los mensajes al arrancar (quitar el splash)
- Arranque detallado (verbose): nombre correcto y restaurar la pantalla de carga
- Crear USB de instalación (opción 20), fácil y a prueba de errores
- Aviso del primer uso: licencia AGPL, sin garantía y que el script modifica el sistema
- Barra de avance al instalar, quitar y actualizar paquetes; nombre del script en la terminal
- Todas las preguntas tienen salida: 0 o Enter vuelve sin error
- Cada script detecta la distribución y ofrece el script correcto
- Eliminar aplicaciones detecta todas las apps instaladas, también Flatpak
- Apps detectadas: con descripción, herramientas de configuración y LibreOffice suelto
- Listas con casillas: línea del cursor resaltada y nada se sale del recuadro
- Listas con casillas: el renglón resaltado y el botón activo se leen en cualquier terminal
- Proyecto Linux Ultimate Tools: un repositorio para todas las distribuciones
- README revisado: números, repositorio público, betas y preguntas frecuentes
- Listas con casillas: se adaptan al agrandar o achicar la terminal
- Al quitar apps, cada dependencia dice qué es; Python, Perl, apt y dpkg protegidos
- Navegadores juntos (+Edge, Tor, SeaMonkey), telnet, swap, htop, salida 0 y ⚠ SISTEMA

## [2.1.0] — 2026-11-20

**Debian y Arch (beta).** Scripts beta para Debian y Arch con los mismos números de menú. Navegadores, licencia AGPL v3, instalar y quitar escritorios.

8 cambios · +15.431 / −710 líneas

- Versiones beta para Debian y Arch ([#20](https://github.com/george0884/linux-ultimate-tools/pull/20))
- Navegadores Firefox (sin Snap) y Brave en los tres scripts ([#21](https://github.com/george0884/linux-ultimate-tools/pull/21))
- Licencia AGPL v3, créditos del software usado y aceptación manual de las licencias del SDK de Android
- Firefox .deb: queda registrado y se puede quitar, con fecha y origen
- Chromium en software opcional (Ubuntu desde Flathub, Debian de sus repos)
- Instalar un escritorio (Ubuntu Server o agregar otro), a prueba de errores
- README, capturas y créditos: instalar un escritorio y Ubuntu Server
- Quitar otros escritorios (los que no instaló el script), a prueba de errores

## [2.0.0] — 2026-11-15

**Ubuntu Ultimate Tools.** Nuevo nombre y todos los sabores de Ubuntu. Información del sistema, Steam y Proton, Revertir, tarjeta de rescate, desarrollo (APK, Android Studio, Flatpak, Docker) y arranque compatible con otras distribuciones.

10 cambios · +3.898 / −648 líneas

- Ubuntu Ultimate Tools: nuevo nombre y compatibilidad con todos los sabores de Ubuntu ([#10](https://github.com/george0884/linux-ultimate-tools/pull/10))
- Información del sistema y hardware, Rolling Release solo Kubuntu y carpeta screenshots ([#11](https://github.com/george0884/linux-ultimate-tools/pull/11))
- README: quitar contenido viejo y ordenar las secciones ([#12](https://github.com/george0884/linux-ultimate-tools/pull/12))
- Steam y Proton (software opcional y perfil gaming) + Revertir a distribución original ([#13](https://github.com/george0884/linux-ultimate-tools/pull/13))
- Arranque: tarjeta de rescate, arranque de respaldo UEFI y guías personalizadas ([#14](https://github.com/george0884/linux-ultimate-tools/pull/14))
- Desarrollo: compilar APK, Android Studio, Flatpak y Docker, con respaldos y eliminación nuclear ([#15](https://github.com/george0884/linux-ultimate-tools/pull/15))
- Menú principal agrupado y alineación de todos los menús ([#16](https://github.com/george0884/linux-ultimate-tools/pull/16))
- Capturas: tarjeta de rescate con la opción 18 y perfiles sin cortes ([#17](https://github.com/george0884/linux-ultimate-tools/pull/17))
- Arranque (opción 18) compatible con Debian, Arch, Manjaro, Fedora y openSUSE ([#18](https://github.com/george0884/linux-ultimate-tools/pull/18))
- Menú de arranque: muestra solo las opciones que sirven en el equipo (UEFI, BIOS, Live USB, sin GRUB) ([#19](https://github.com/george0884/linux-ultimate-tools/pull/19))

## [1.1.0] — 2026-11-09

**Menú de arranque.** GRUB y EFI sin programas externos: sistema por defecto, otros sistemas, orden UEFI, ocultar entradas y reparación completa. 0 para volver en todos los menús.

8 cambios · +1.146 / −133 líneas

- Menú de arranque y EFI: sistema por defecto, os-prober, UEFI y herramientas ([#5](https://github.com/george0884/linux-ultimate-tools/pull/5))
- MangoHud configurado al instalar las herramientas de juego ([#4](https://github.com/george0884/linux-ultimate-tools/pull/4))
- Arranque sin programas externos: personalizar menú, reparación completa y menú ordenado ([#6](https://github.com/george0884/linux-ultimate-tools/pull/6))
- GRUB: mostrar en pantalla el error de update-grub
- GRUB: ocultar entradas sueltas, deshacer Grub Customizer y arreglo de "otros primero"
- GRUB: ocultar entradas ofrece deshacer Grub Customizer en el momento
- GRUB: ocultar UEFI y memtest sin romper update-grub, con vuelta atrás automática
- Menús: 0 para volver en todos los submenús y para salir en el principal ([#9](https://github.com/george0884/linux-ultimate-tools/pull/9))

## [1.0.0] — 2026-11-01

**Primera versión completa (Kubuntu).** Perfiles automáticos, red y DNS, energía, kernels, reparación de GRUB desde Live USB, tema Tokyo Night, deshacer y licencia libre.

8 cambios · +3.065 / −590 líneas

- Arreglar cambio de kernels, rollback y accesos directos ([#1](https://github.com/george0884/linux-ultimate-tools/pull/1))
- Perfiles automáticos, red/DNS/drivers, energía y apt más rápido ([#2](https://github.com/george0884/linux-ultimate-tools/pull/2))
- Reparación de GRUB desde Live USB y listas con barra espaciadora
- README para repositorio privado y menú con colores legibles
- Licencia GPL v3 y tema Tokyo Night incluido en el script
- Arreglos: idioma español en apt, BBR, fastfetch, GRUB y energía en gaming
- Deshacer optimizaciones, registro de programas y arreglo de GRUB/energía
- Deshacer: mostrar qué ajustes están cambiados y avisar al cancelar

## [0.1.0] — 2026-05-22

**Kubuntu Transformer.** Primer script para limpiar y transformar Kubuntu (`Kubuntu-clean.sh`).

8 cambios · +2.270 / −0 líneas

- Primer commit del repositorio
- Script `Kubuntu-clean.sh` para transformar el sistema
- README con los detalles de Kubuntu Transformer
- Nombre del autor en el README
- Script reorganizado y mejorado
- Opciones del menú principal
- Mensaje de salida
- Mensaje de salida
