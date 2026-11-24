# 🙏 Créditos y licencias del software usado

Ubuntu Ultimate Tools (y sus versiones beta para Debian y Arch) es software libre bajo la licencia
**GNU AGPL v3 o posterior** (ver [LICENSE](LICENSE)).

Los scripts **no incluyen código de otros proyectos**: instalan o descargan cada programa desde su
fuente oficial (repositorios de la distribución, repositorios del fabricante, Flathub o Snap Store).
Cada programa se rige por **su propia licencia**, que no cambia por usar este script. Esta lista es un
reconocimiento a sus autores; la licencia que vale siempre es la que publica cada proyecto.

**Cómo lo usa el script:**
- **Sistema**: lo usa o configura el script (ya viene con la distro o lo instala).
- **Instala**: lo instala desde los repositorios oficiales de la distro.
- **Externo**: lo descarga del sitio o repositorio del fabricante, Flathub o Snap Store.
- **Incluido**: hay algo de ese proyecto dentro del script.

## 🎨 Incluido en el script

| Proyecto | Autor | Licencia | Uso |
|---|---|---|---|
| [Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme) | enkia | MIT | Los colores del tema Tokyo Night para KDE salen de esta paleta |

## ⚙️ Sistema y arranque

| Proyecto | Licencia | Uso |
|---|---|---|
| [GRUB](https://www.gnu.org/software/grub/) | GPL-3.0-or-later | Sistema: menú de arranque, reparación y reinstalación |
| [os-prober](https://salsa.debian.org/installer-team/os-prober) | GPL-2.0-or-later | Sistema: detecta otros sistemas para el menú de arranque |
| [efibootmgr](https://github.com/rhboot/efibootmgr) | GPL-2.0-or-later | Sistema: entradas de arranque UEFI |
| [newt / whiptail](https://pagure.io/newt) | LGPL-2.0 | Sistema: los menús de casillas |
| [systemd](https://systemd.io/) (resolved, journald) | LGPL-2.1-or-later | Sistema: DNS cifrado, registros y servicios |
| [NetworkManager](https://networkmanager.dev/) | GPL-2.0-or-later | Sistema: DNS cuando no hay systemd-resolved |
| [zram-tools](https://github.com/highvoltage/zram-tools) | MIT | Instala: memoria ZRAM en Ubuntu y Debian |
| [zram-generator](https://github.com/systemd/zram-generator) | MIT | Instala: memoria ZRAM en Arch |
| [TLP](https://linrunner.de/tlp/) | GPL-2.0-or-later | Instala: ahorro de batería en portátiles |
| [power-profiles-daemon](https://gitlab.freedesktop.org/upower/power-profiles-daemon) | GPL-3.0-or-later | Sistema: se desactiva cuando se instala TLP |
| [Mesa](https://mesa3d.org/) | MIT | Instala: drivers gráficos libres y Vulkan |
| [Snap / snapd](https://snapcraft.io/) | GPL-3.0 | Sistema: quitar Snap o instalar apps Snap |
| [Flatpak](https://flatpak.org/) y [flatpak-builder](https://github.com/flatpak/flatpak-builder) | LGPL-2.1-or-later | Instala: apps de Flathub y compilar Flatpaks |
| [Flathub](https://flathub.org/) | Cada app tiene su licencia | Externo: fuente de apps cuando la distro no las tiene |
| [pacman](https://pacman.archlinux.page/) y pacman-contrib (paccache) | GPL-2.0-or-later | Sistema (Arch): paquetes y limpieza de caché |
| [Reflector](https://xyne.dev/projects/reflector/) | GPL-2.0 | Instala (Arch): espejos más rápidos |
| [pacman-mirrors](https://gitlab.manjaro.org/applications/pacman-mirrors) y [mhwd](https://gitlab.manjaro.org/applications/mhwd) | GPL-3.0 | Sistema (Manjaro): espejos, drivers y kernels |
| [nvidia-detect](https://packages.debian.org/nvidia-detect) | Proyecto Debian | Sistema (Debian): elige el driver de NVIDIA correcto |

## 🖥️ Escritorios (opción 7 → Instalar un escritorio)

El script solo instala los metapaquetes oficiales de Ubuntu; cada escritorio y sus apps tienen su licencia.

| Proyecto | Licencia | Uso |
|---|---|---|
| [KDE Plasma](https://kde.org/plasma-desktop/) (Kubuntu) | GPL-2.0-or-later / LGPL-2.1-or-later | Instala |
| [GNOME](https://www.gnome.org/) (Ubuntu) | GPL-2.0-or-later / LGPL-2.1-or-later | Instala |
| [Xfce](https://xfce.org/) (Xubuntu) | GPL-2.0-or-later / LGPL-2.0-or-later | Instala |
| [LXQt](https://lxqt-project.org/) (Lubuntu) | LGPL-2.1-or-later / GPL-2.0-or-later | Instala |
| [MATE](https://mate-desktop.org/) (Ubuntu MATE) | GPL-2.0-or-later / LGPL-2.0-or-later | Instala |
| [Budgie](https://buddiesofbudgie.org/) (Ubuntu Budgie) | GPL-2.0 / LGPL-2.1 | Instala |
| [Cinnamon](https://github.com/linuxmint/cinnamon) (Ubuntu Cinnamon) | GPL-2.0-or-later | Instala |
| [SDDM](https://github.com/sddm/sddm), [GDM](https://gitlab.gnome.org/GNOME/gdm), [LightDM](https://github.com/canonical/lightdm) | GPL-2.0-or-later / GPL-3.0 | Instala: pantalla de inicio de sesión |
| [Netplan](https://netplan.io/) | GPL-3.0 | Sistema: pasar la red a NetworkManager (`netplan try`) |
| [tasksel](https://salsa.debian.org/debian/tasksel) | GPL-2.0-or-later | Inspiración: el script no lo usa, hace lo mismo con protecciones |

## 🐧 Kernels

| Proyecto | Licencia | Uso |
|---|---|---|
| [Linux](https://kernel.org/) | GPL-2.0 | Kernels oficiales de cada distro |
| [Liquorix](https://liquorix.net/) | GPL-2.0 | Externo: kernel para juegos (PPA de damentz o repositorio oficial) |
| [XanMod](https://xanmod.org/) | GPL-2.0 | Externo: kernel para juegos (repositorio oficial) |

## 🎮 Juegos

| Proyecto | Autor | Licencia | Uso |
|---|---|---|---|
| [Steam](https://store.steampowered.com/) | Valve | **Privativo** | Externo/Instala |
| [Proton](https://github.com/ValveSoftware/Proton) | Valve | BSD-3-Clause (y licencias de Wine/DXVK) | Viene con Steam |
| [Proton-GE](https://github.com/GloriousEggroll/proton-ge-custom) | GloriousEggroll | BSD-3-Clause (y licencias de sus componentes) | Externo: descarga de GitHub |
| [GameMode](https://github.com/FeralInteractive/gamemode) | Feral Interactive | BSD-3-Clause | Instala |
| [MangoHud](https://github.com/flightlessmango/MangoHud) | flightlessmango | MIT | Instala |
| [CoreCtrl](https://gitlab.com/corectrl/corectrl) | Juan Palacios | GPL-3.0-or-later | Instala: control de gráficas AMD |

## 🌐 Navegadores

| Proyecto | Licencia | Uso |
|---|---|---|
| [Firefox](https://www.mozilla.org/firefox/) | MPL-2.0 | Externo: repositorio .deb oficial de Mozilla (en Arch, repos oficiales) |
| [Brave](https://brave.com/) | MPL-2.0 | Externo: repositorio oficial de Brave o Flathub |
| [Google Chrome](https://www.google.com/chrome/) | **Privativo** | Externo: paquete oficial de Google (en Arch, Flathub) |
| [Chromium](https://www.chromium.org/) | BSD-3-Clause | Instala en Debian y Arch (repos oficiales); en Ubuntu, Externo desde Flathub (sin Snap) |
| [Microsoft Edge](https://www.microsoft.com/edge) | **Privativo** (Microsoft) | Externo: repositorio oficial de Microsoft (en Arch, Flathub) |
| [Tor Browser](https://www.torproject.org/) y [torbrowser-launcher](https://github.com/torproject/torbrowser-launcher) | BSD-3-Clause (Tor) · MIT (lanzador) | Instala el lanzador de los repositorios oficiales (o Flathub); el lanzador baja Tor Browser y verifica su firma |
| [SeaMonkey](https://www.seamonkey-project.org/) | MPL-2.0 | Externo: descarga oficial en `/opt/seamonkey` |

## 📦 Programas opcionales

| Proyecto | Licencia | Uso |
|---|---|---|
| [FileZilla](https://filezilla-project.org/) | GPL-2.0-or-later | Instala |
| [Visual Studio Code](https://code.visualstudio.com/) | **Privativo** (Microsoft); Code - OSS es MIT | Externo: repositorio de Microsoft (en Arch, Code - OSS) |
| [VirtualBox](https://www.virtualbox.org/) | GPL-3.0 (el Extension Pack es privativo y no se instala) | Instala |
| [Telegram Desktop](https://github.com/telegramdesktop/tdesktop) | GPL-3.0 con excepción OpenSSL | Instala |
| [Python](https://www.python.org/) y [pip](https://pip.pypa.io/) | PSF-2.0 y MIT | Instala |
| [Git](https://git-scm.com/) | GPL-2.0 | Instala |
| [curl](https://curl.se/) | Licencia curl (tipo MIT) | Instala |
| [GNU Wget](https://www.gnu.org/software/wget/) | GPL-3.0-or-later | Instala |
| [htop](https://htop.dev/) | GPL-2.0-or-later | Instala (también desde Información del sistema → 16) |
| [telnet](https://packages.debian.org/telnet) / [GNU inetutils](https://www.gnu.org/software/inetutils/) | BSD-4-Clause / GPL-3.0-or-later | Instala |
| [fastfetch](https://github.com/fastfetch-cli/fastfetch) | MIT | Instala |
| [Timeshift](https://github.com/linuxmint/timeshift) | GPL-2.0-or-later | Instala |
| [GParted](https://gparted.org/) | GPL-2.0-or-later | Instala |
| [Vim](https://www.vim.org/) | Licencia Vim (compatible con GPL) | Instala |
| [Discord](https://discord.com/) | **Privativo** | Externo: paquete oficial de Discord (en Arch, repos oficiales) |
| [Spotify](https://www.spotify.com/) | **Privativo** | Externo: repositorio oficial de Spotify (en Arch, Flathub) |
| [OBS Studio](https://obsproject.com/) | GPL-2.0-or-later | Instala |
| [Emojier (KDE Plasma)](https://invent.kde.org/plasma/plasma-desktop) | GPL-2.0-or-later | Instala |
| [Qrca](https://invent.kde.org/utilities/qrca) | GPL-3.0-or-later | Instala |
| [Gufw](https://github.com/costales/gufw) | GPL-3.0 | Instala |

## 🛠️ Desarrollo

| Proyecto | Licencia | Uso |
|---|---|---|
| [OpenJDK](https://openjdk.org/) | GPL-2.0 con Classpath Exception | Instala |
| [Android SDK (command-line tools)](https://developer.android.com/tools) | **Términos de Google** ([Android SDK License](https://developer.android.com/studio/terms)) | Externo: lo descarga de Google; **el usuario lee y acepta las licencias** |
| [Android Studio](https://developer.android.com/studio) | **Términos de Google** | Externo: de Google o Snap Store |
| [Docker Engine](https://www.docker.com/) y [Docker Compose](https://github.com/docker/compose) | Apache-2.0 | Externo: repositorio oficial de Docker |

## 🔍 Información y diagnóstico

| Proyecto | Licencia | Uso |
|---|---|---|
| [inxi](https://github.com/smxi/inxi) | GPL-3.0-or-later | Instala |
| [smartmontools](https://www.smartmontools.org/) | GPL-2.0-or-later | Instala: salud de los discos |

## 🛡️ Auditoría de seguridad (opción 2)

| Proyecto | Autor | Licencia | Uso |
|---|---|---|---|
| [Lynis](https://github.com/CISOfy/lynis) | Michael Boelen / CISOfy | GPL-3.0 | Externo: paquete oficial de la distro, usado **sin instalar** en Ubuntu y Debian (carpeta temporal que se borra) o instalado (Arch: repositorios oficiales) |
| [linaudit](https://github.com/alexiarstein/linaudit) ([sitio](https://lexiworks.dev/linaudit)) | Alexia Michelle | AGPL-3.0-or-later | Externo: se compila desde su código oficial en una carpeta temporal (o se usa el paquete de la distro cuando exista); opcionalmente queda en `/usr/local/bin` |
| [Rust y rustup](https://www.rust-lang.org/) | The Rust Project Developers | MIT / Apache-2.0 | Externo: rustup oficial **temporal** solo para compilar linaudit si el Rust del sistema es anterior a 1.85 |
| [Linux Audit (auditd)](https://github.com/linux-audit/audit-userspace) | Red Hat y colaboradores | GPL-2.0-or-later (bibliotecas LGPL-2.1) | Instala: registro de auditoría con reglas **propias del script** |
| [Linux-Security-Policy](https://github.com/Starke427/Linux-Security-Policy) | Jeff Starke (Starke427) | **Sin licencia publicada** | **Inspiración**: la idea de combinar auditd y Lynis. No se copia ni se descarga su código ni sus reglas: un repositorio sin licencia no se puede redistribuir. Las reglas de auditd del script se escribieron desde cero para Ubuntu y Debian actuales |

## 💿 Crear USB de instalación (opción 20)

| Proyecto | Licencia | Uso |
|---|---|---|
| [GNU coreutils](https://www.gnu.org/software/coreutils/) (`dd`, `sha256sum`) | GPL-3.0-or-later | Sistema: grabar el pendrive y verificar las descargas |
| [util-linux](https://github.com/util-linux/util-linux) (`lsblk`, `findmnt`) | GPL-2.0-or-later | Sistema: detectar los pendrives y lo que tienen montado |
| [udisks](https://github.com/storaged-project/udisks) (`udisksctl`) | GPL-2.0-or-later | Sistema: desmontar y expulsar el pendrive |
| [curl](https://curl.se/) | Licencia curl | Sistema: descargar las ISO oficiales |

Las ISO se descargan de los sitios oficiales de cada distribución (Ubuntu, Debian, Arch Linux), con sus propias
licencias y marcas; el script no las modifica.

## 💾 Archivo swap (opción 15)

| Proyecto | Autor | Licencia | Uso |
|---|---|---|---|
| [create-swap](https://github.com/george0884/create-swap) | Old The One Deluxe (george0884), el mismo autor | GPL-3.0 (compatible con la AGPL-3.0 de este proyecto) | **Incluido** y mejorado: crear, cambiar y quitar el archivo swap |

## 🔒 Servicios de DNS

Cloudflare, AdGuard DNS y Quad9 son **servicios** de terceros, no software: el script solo configura
sus direcciones públicas. Cada uno tiene sus propios términos y política de privacidad.

## 🖥️ Drivers privativos

Los drivers de **NVIDIA** son privativos (los módulos del kernel "open" son MIT/GPL-2.0). El script los
instala desde los repositorios de cada distro; NVIDIA y la distro ponen sus condiciones.

## ™️ Marcas

Este proyecto **no está afiliado ni respaldado** por Canonical, el Proyecto Debian, Arch Linux,
Manjaro, KDE, GNOME, Mozilla, Brave, Google, Microsoft, Valve, NVIDIA, Docker, Spotify, Discord,
Telegram ni ningún otro proyecto mencionado. Ubuntu, Kubuntu, Debian, Arch Linux y los demás nombres y
logotipos son marcas de sus respectivos dueños y se usan solo para indicar compatibilidad.

¿Falta algún crédito o hay una licencia mal indicada? Abre un Issue y se corrige.
