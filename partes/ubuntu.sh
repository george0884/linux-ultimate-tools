#@ partes/ubuntu.sh — lo propio del script de Ubuntu y el orden de todo el script.
#@ Las líneas "#@parte pieza: nombres" se reemplazan por esas funciones de partes/<pieza>.sh al correr "bash armar.sh".
#@ Las líneas "#@" no pasan al script final.
#!/bin/bash

# ============================================================
# Script: Ubuntu Ultimate Tools
# Descripción: Transforma cualquier sabor de Ubuntu en un sistema minimalista
#              con optimizaciones de rendimiento extremo
# Versión: 7.0 - MENÚS UNIFORMES Y ESTÉTICA CUIDADA
# Autor: Old The One Deluxe (@george0884)
# Licencia: GNU AGPL v3 o posterior (ver archivo LICENSE)
# Créditos del software que instala o usa: ver CREDITOS.md
# SPDX-License-Identifier: AGPL-3.0-or-later
# ============================================================

# ============================================================
# CONFIGURACIÓN INICIAL
# ============================================================

LOG_FILE="$HOME/ubuntu-ultimate-tools.log"
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")

# Estado guardado entre ejecuciones (lo usa "Revertir")
STATE_DIR="$HOME/.local/share/ubuntu-ultimate-tools"
REMOVED_LIST="$STATE_DIR/paquetes-eliminados.txt"
INSTALLED_LIST="$STATE_DIR/paquetes-instalados.txt"
# De dónde salió y cuándo se instaló cada programa externo: paquete|fecha|origen
INSTALL_ORIGIN="$STATE_DIR/origen-instalados.txt"
SHORTCUTS_BACKUP="$STATE_DIR/accesos-directos"

# Colores base (uniformes por menú)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Variables de estado
SELECTED_APPS=()
SELECTED_OPTIONAL=()
#@parte comun: log log_info log_success log_error log_warning log_title

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    UBUNTU ULTIMATE TOOLS                         ║"
    echo "║              Transformación y Optimización Extrema               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    local version
    version=$(os_release_value VERSION_ID)
    echo -e "${GREEN}🐧 Detectado: ${FLAVOR_NAME}${version:+ $version} · ${DESKTOP_NAME}${NC}"
    echo -e "${YELLOW}📁 Log activo: $LOG_FILE${NC}\n"
}

# Modo automático (perfiles): sin pausas ni preguntas; las confirmaciones responden "no"
AUTO_MODE=false
ASSUME_YES=false
ACTIVE_PROFILE=""
#@parte comun: clear pause confirm run progress_wanted progress_draw run_with_progress set_terminal_title run_visible

# Las salidas que el script interpreta se piden en inglés: con el sistema en español,
# apt-cache escribe "Candidato:" o "Depende:" en lugar de "Candidate:" o "Depends:",
# y free escribe "Mem.:" en lugar de "Mem:".
apt-cache() { LC_ALL=C command apt-cache "$@"; }
#@parte apt: free

# Sin preguntas: ante un archivo de configuración modificado se conserva el del usuario
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
APT_LISTS_FRESH=false
#@parte apt: apt_update apt_install apt_purge apt_install_recorded forget_installed record_installed install_origin installed_pkgs purge_and_record flavor_meta_pkgs

SYSCTL_FILE="/etc/sysctl.d/99-ubuntu-ultimate-tools.conf"
BBR_MODULES_FILE="/etc/modules-load.d/ubuntu-ultimate-tools-bbr.conf"
#@parte comun: set_sysctl datos_whiptail_colors checklist_tool checklist_select

# ============================================================
# SABOR DE UBUNTU Y ESCRITORIO
# ============================================================

FLAVOR=""          # kubuntu, ubuntu, xubuntu, lubuntu, mate, budgie, cinnamon, unity, studio, edubuntu, kylin, server
FLAVOR_NAME=""     # Nombre para mostrar (Kubuntu, Xubuntu...)
FLAVOR_META=""     # Meta-paquete del sabor (kubuntu-desktop...)
DESKTOP=""         # kde, gnome, xfce, lxqt, mate, budgie, cinnamon, unity, ukui, none
DESKTOP_NAME=""    # Nombre del escritorio para mostrar

# sabor|nombre|meta-paquete|escritorio|nombre del escritorio|paquete que lo identifica si ya no está el meta-paquete
# El orden importa: Ubuntu Studio y Edubuntu instalan también otros meta-paquetes.
FLAVORS=(
    "studio|Ubuntu Studio|ubuntustudio-desktop|kde|KDE Plasma|ubuntustudio-default-settings"
    "edubuntu|Edubuntu|edubuntu-desktop|gnome|GNOME|edubuntu-default-settings"
    "kubuntu|Kubuntu|kubuntu-desktop|kde|KDE Plasma|plasma-workspace"
    "xubuntu|Xubuntu|xubuntu-desktop|xfce|Xfce|xfce4-session"
    "lubuntu|Lubuntu|lubuntu-desktop|lxqt|LXQt|lxqt-session"
    "mate|Ubuntu MATE|ubuntu-mate-desktop|mate|MATE|mate-session-manager"
    "budgie|Ubuntu Budgie|ubuntu-budgie-desktop|budgie|Budgie|budgie-desktop"
    "cinnamon|Ubuntu Cinnamon|ubuntucinnamon-desktop|cinnamon|Cinnamon|cinnamon"
    "unity|Ubuntu Unity|ubuntu-unity-desktop|unity|Unity|unity"
    "kylin|Ubuntu Kylin|ubuntukylin-desktop|ukui|UKUI|ukui-session-manager"
    "ubuntu|Ubuntu|ubuntu-desktop|gnome|GNOME|gnome-shell"
    "ubuntu|Ubuntu|ubuntu-desktop-minimal|gnome|GNOME|gnome-shell"
)

# Detecta el sabor por su meta-paquete o, si se quitó (opción 12), por su escritorio
detect_flavor() {
    local entry meta marker found=""
    for entry in "${FLAVORS[@]}"; do
        IFS='|' read -r _ _ meta _ _ marker <<< "$entry"
        if installed_pkgs "$meta" | grep -qx -- "$meta"; then found=$entry; break; fi
    done
    # Si se quitó con la opción 12, queda anotado: así un Ubuntu mínimo no se confunde con el completo
    if [ -z "$found" ] && [ -s "$REMOVED_LIST" ]; then
        for entry in "${FLAVORS[@]}"; do
            IFS='|' read -r _ _ meta _ _ _ <<< "$entry"
            if grep -qx -- "$meta" "$REMOVED_LIST"; then found=$entry; break; fi
        done
    fi
    if [ -z "$found" ]; then
        for entry in "${FLAVORS[@]}"; do
            IFS='|' read -r _ _ _ _ _ marker <<< "$entry"
            if installed_pkgs "$marker" | grep -qx -- "$marker"; then found=$entry; break; fi
        done
    fi
    if [ -n "$found" ]; then
        IFS='|' read -r FLAVOR FLAVOR_NAME FLAVOR_META DESKTOP DESKTOP_NAME _ <<< "$found"
    else
        FLAVOR=server FLAVOR_NAME="Ubuntu Server" FLAVOR_META="" DESKTOP=none DESKTOP_NAME="sin escritorio"
    fi
}
#@parte comun: has_desktop desktop_only

# ------------------------------------------------------------
# Apps que se pueden eliminar. Salen de los meta-paquetes de cada sabor,
# SIN las piezas del escritorio (gestor de archivos, configuración, panel,
# sesión, ventanas, red, sonido, energía, notificaciones, portales...).
# Solo se muestran las que están instaladas.
# ------------------------------------------------------------

# Comunes a varios sabores
APPS_COMMON=(
    "libreoffice-core|📄 LibreOffice completo (quita todas sus apps)"
    "libreoffice-writer|📝 LibreOffice Writer (textos)"
    "libreoffice-calc|📊 LibreOffice Calc (hojas de cálculo)"
    "libreoffice-impress|📽️ LibreOffice Impress (presentaciones)"
    "libreoffice-draw|✏️ LibreOffice Draw (dibujo)"
    "libreoffice-math|➗ LibreOffice Math (fórmulas)"
    "thunderbird|📧 Thunderbird (correo)"
    "evolution|📧 Evolution (correo y calendario)"
    "geary|📧 Geary (correo)"
    "transmission-gtk|📥 Transmission (torrent)"
    "transmission-qt|📥 Transmission (torrent)"
    "ktorrent|📥 KTorrent (torrent)"
    "rhythmbox|🎵 Rhythmbox (música)"
    "lollypop|🎵 Lollypop (música)"
    "gnome-music|🎵 Música de GNOME"
    "elisa|🎵 Elisa (música)"
    "juk|🎵 JuK (música)"
    "cantata|🎵 Cantata (música MPD)"
    "goodvibes|📻 Goodvibes (radio por internet)"
    "gpodder|🎙️ gPodder (podcasts)"
    "totem|🎬 Vídeos de GNOME (Totem)"
    "showtime|🎬 Showtime (vídeos)"
    "celluloid|🎬 Celluloid (vídeos)"
    "parole|🎬 Parole (vídeos)"
    "vlc|🎬 VLC (multimedia)"
    "haruna|🎬 Haruna (vídeos)"
    "dragonplayer|🎬 Dragon Player (vídeos)"
    "mpv|🎬 mpv (multimedia ligero)"
    "shotwell|🖼️ Shotwell (fotos)"
    "gthumb|🖼️ gThumb (imágenes)"
    "gimp|🎨 GIMP (editor de imágenes)"
    "drawing|🎨 Drawing (dibujo simple)"
    "kolourpaint|🎨 KolourPaint (dibujo simple)"
    "cheese|📷 Cheese (cámara web)"
    "gnome-snapshot|📷 Cámara de GNOME"
    "guvcview|📷 guvcview (cámara web)"
    "webcamoid|📷 Webcamoid (cámara web)"
    "kamoso|📷 Kamoso (cámara web)"
    "remmina|🖥️ Remmina (escritorio remoto)"
    "krdc|🖥️ KRDC (escritorio remoto)"
    "vino|🖥️ Vino (compartir el escritorio por VNC)"
    "simple-scan|🖨️ Escáner de documentos"
    "skanlite|🖨️ Skanlite (escáner)"
    "skanpage|🖨️ Skanpage (escáner multipágina)"
    "deja-dup|💾 Déjà Dup (copias de seguridad)"
    "baobab|💾 Analizador de uso del disco"
    "gnome-disk-utility|💾 Discos (formatear y crear imágenes)"
    "partitionmanager|💾 Gestor de particiones de KDE"
    "gdebi|📦 GDebi (instalar paquetes .deb)"
    "synaptic|📦 Synaptic (gestor de paquetes)"
    "usb-creator-gtk|💿 Crear un USB de arranque"
    "usb-creator-kde|💿 Crear un USB de arranque"
    "k3b|💿 K3b (grabar CD/DVD)"
    "xfburn|💿 Xfburn (grabar CD/DVD)"
    "hexchat|💬 HexChat (IRC)"
    "quassel|💬 Quassel (IRC)"
    "konversation|💬 Konversation (IRC)"
    "neochat|💬 NeoChat (chat Matrix)"
    "onboard|⌨️ Onboard (teclado en pantalla)"
    "magnus|🔍 Magnus (lupa de pantalla)"
    "kmag|🔍 KMag (lupa de pantalla)"
    "gucharmap|🔣 Mapa de caracteres"
    "gnome-characters|🔣 Caracteres de GNOME"
    "kcharselect|🔣 Mapa de caracteres de KDE"
    "gnome-font-viewer|🔤 Visor de tipografías"
    "font-manager|🔤 Gestor de tipografías"
    "gnome-calendar|📆 Calendario de GNOME"
    "gnome-clocks|⏰ Relojes de GNOME"
    "gnome-weather|🌤️ Tiempo de GNOME"
    "gnome-maps|🗺️ Mapas de GNOME"
    "gnome-contacts|📇 Contactos de GNOME"
    "gnome-dictionary|📖 Diccionario de GNOME"
    "endeavour|✅ Endeavour (tareas)"
    "gnome-logs|📋 Registros del sistema (GNOME)"
    "ksystemlog|📋 Registros del sistema (KDE)"
    "yelp|❓ Ayuda de GNOME"
    "khelpcenter|❓ Centro de ayuda de KDE"
    "apport-gtk|🐞 Reporte de errores de Ubuntu"
    "apport-kde|🐞 Reporte de errores de Ubuntu"
    "seahorse|🔐 Contraseñas y claves (Seahorse)"
    "htop|📊 htop (monitor en la terminal)"
    "stacer|📊 Stacer (optimizador y monitor)"
    "git-cola|🧰 git-cola (interfaz gráfica de Git)"
    "xterm|💻 XTerm (terminal básica adicional)"
    "tilda|💻 Tilda (terminal desplegable)"
    "catfish|🔎 Catfish (buscador de archivos)"
    "kfind|🔎 KFind (buscador de archivos)"
    "gigolo|🌐 Gigolo (carpetas remotas)"
    "mugshot|👤 Mugshot (datos del usuario)"
    "xfce4-dict|📖 Diccionario de Xfce"
    "convertall|📐 ConvertAll (conversor de unidades)"
    "aisleriot|🃏 Solitarios (AisleRiot)"
    "gnome-mines|💣 Buscaminas de GNOME"
    "gnome-sudoku|🔢 Sudoku de GNOME"
    "gnome-mahjongg|🀄 Mahjongg de GNOME"
    "gnome-2048|🎲 2048 de GNOME"
    "gnome-chess|♟️ Ajedrez de GNOME"
    "sgt-launcher|🧩 Rompecabezas de Simon Tatham"
    "2048-qt|🎲 2048"
    "kmahjongg|🀄 Mahjongg de KDE"
    "kmines|💣 Buscaminas de KDE"
    "kpat|🃏 Solitarios de KDE"
    "ksudoku|🔢 Sudoku de KDE"
)

# Por escritorio
# shellcheck disable=SC2034  # se usa por referencia en flavor_app_list
APPS_KDE=(
    "akregator|📰 Akregator (lector RSS)"
    "kaddressbook|📇 KAddressBook (contactos)"
    "kalarm|⏰ KAlarm (alarmas y recordatorios)"
    "kate|📝 Kate (editor de texto avanzado)"
    "kwrite|📝 KWrite (editor de texto)"
    "kmail|📧 KMail (correo)"
    "knotes|📋 KNotes (notas adhesivas)"
    "kontact|📅 Kontact (suite de correo, agenda y contactos)"
    "korganizer|📆 KOrganizer (calendario)"
    "kmouth|🗣️ KMouth (sintetizador de voz)"
    "kdf|💾 KDiskFree (uso de disco)"
    "kgpg|🔐 KGpg (claves GPG)"
    "kdeconnect|📱 KDE Connect (sincronizar con el móvil)"
    "kdenlive|🎬 Kdenlive (editor de vídeo)"
    "kompare|📊 Kompare (comparar archivos)"
    "kremotecontrol|🎮 Control remoto"
    "kruler|📏 KRuler (regla en pantalla)"
    "kteatime|🍵 KTeaTime (temporizador para el té)"
    "ktimer|⏱️ KTimer (temporizador)"
    "kwalletmanager|👛 Gestor de la cartera de contraseñas (la cartera sigue funcionando)"
    "kcalc|🧮 KCalc (calculadora)"
    "ark|🗜️ Ark (archivos comprimidos)"
    "okular|📖 Okular (visor de PDF)"
    "gwenview|🖼️ Gwenview (visor de imágenes)"
    "kde-spectacle|📸 Spectacle (capturas de pantalla)"
    "spectacle|📸 Spectacle (capturas de pantalla)"
    "plasma-systemmonitor|📊 Monitor del sistema"
    "kinfocenter|ℹ️ Centro de información"
    "qapt-deb-installer|📦 Instalador de paquetes .deb"
    "plasma-discover|🛒 Discover (tienda de aplicaciones)"
    "plasma-welcome|👋 Bienvenida de Plasma"
    "kubuntu-docs|📚 Documentación de Kubuntu"
    "kubuntu-web-shortcuts|🌐 Accesos web de Kubuntu"
    "kio-extras|⚠️ Protocolos KIO extra (miniaturas, móvil y red en Dolphin)"
    "kscreen|⚠️ Configuración de pantallas (sin ella no podrás cambiar la resolución)"
    "konsole|⚠️ Konsole (terminal: quítala solo si usas otra, como Alacritty)"
)
# shellcheck disable=SC2034  # se usa por referencia en flavor_app_list
APPS_GNOME=(
    "eog|🖼️ Visor de imágenes (Eye of GNOME)"
    "loupe|🖼️ Visor de imágenes (Loupe)"
    "evince|📖 Visor de documentos PDF"
    "papers|📖 Visor de documentos (Papers)"
    "gnome-text-editor|📝 Editor de texto"
    "gnome-calculator|🧮 Calculadora"
    "gnome-system-monitor|📊 Monitor del sistema"
    "file-roller|🗜️ Archivos comprimidos"
    "gnome-power-manager|🔋 Estadísticas de energía"
    "gnome-bluetooth-sendto|📶 Enviar archivos por Bluetooth"
    "gnome-shell-extension-manager|🧩 Gestor de extensiones"
    "gnome-browser-connector|🧩 Extensiones de GNOME desde el navegador"
)
# shellcheck disable=SC2034  # se usa por referencia en flavor_app_list
APPS_XFCE=(
    "mousepad|📝 Mousepad (editor de texto)"
    "ristretto|🖼️ Ristretto (visor de imágenes)"
    "atril|📖 Atril (visor de PDF)"
    "engrampa|🗜️ Engrampa (archivos comprimidos)"
    "mate-calc|🧮 Calculadora"
    "xfce4-screenshooter|📸 Capturas de pantalla"
    "xfce4-taskmanager|📊 Administrador de tareas"
    "menulibre|🗂️ Editor del menú"
)
# shellcheck disable=SC2034  # se usa por referencia en flavor_app_list
APPS_LXQT=(
    "featherpad|📝 FeatherPad (editor de texto)"
    "kcalc|🧮 KCalc (calculadora)"
    "okular|📖 Okular (visor de PDF)"
    "noblenote|📋 NobleNote (notas)"
    "qps|📊 Qps (monitor de procesos)"
    "qtpass|🔐 QtPass (contraseñas)"
    "screengrab|📸 ScreenGrab (capturas de pantalla)"
    "qlipper|📋 Qlipper (historial del portapapeles)"
    "redshift-qt|🌙 Redshift (luz nocturna)"
    "lxqt-archiver|🗜️ Archivos comprimidos"
)
# shellcheck disable=SC2034  # se usa por referencia en flavor_app_list
APPS_MATE=(
    "atril|📖 Atril (visor de PDF)"
    "eom|🖼️ Eye of MATE (visor de imágenes)"
    "pluma|📝 Pluma (editor de texto)"
    "mate-calc|🧮 Calculadora"
    "engrampa|🗜️ Engrampa (archivos comprimidos)"
    "mate-system-monitor|📊 Monitor del sistema"
    "mate-utils|🧰 Utilidades de MATE (capturas, diccionario, búsqueda)"
    "mate-user-guide|❓ Guía de MATE"
    "ubuntu-mate-guide|❓ Guía de Ubuntu MATE"
    "gufw|🛡️ Gufw (cortafuegos gráfico)"
    "redshift-gtk|🌙 Redshift (luz nocturna)"
)
# shellcheck disable=SC2034  # se usa por referencia en flavor_app_list
APPS_BUDGIE=(
    "gedit|📝 Gedit (editor de texto)"
    "atril|📖 Atril (visor de PDF)"
    "mate-calc|🧮 Calculadora"
    "mate-system-monitor|📊 Monitor del sistema"
)
# shellcheck disable=SC2034  # se usa por referencia en flavor_app_list
APPS_CINNAMON=(
    "gedit|📝 Gedit (editor de texto)"
    "evince|📖 Visor de documentos PDF"
    "file-roller|🗜️ Archivos comprimidos"
    "gnome-calculator|🧮 Calculadora"
    "gnome-system-monitor|📊 Monitor del sistema"
    "gnome-screenshot|📸 Capturas de pantalla"
    "gnome-software|🛒 Centro de software"
    "gnome-power-manager|🔋 Estadísticas de energía"
)
# shellcheck disable=SC2034  # se usa por referencia en flavor_app_list
APPS_UNITY=(
    "pluma|📝 Pluma (editor de texto)"
    "eom|🖼️ Eye of MATE (visor de imágenes)"
    "atril|📖 Atril (visor de PDF)"
    "file-roller|🗜️ Archivos comprimidos"
    "mate-calc|🧮 Calculadora"
    "mate-system-monitor|📊 Monitor del sistema"
    "gnome-screenshot|📸 Capturas de pantalla"
    "activity-log-manager|🕵️ Registro de actividad (privacidad)"
)

# Apps del sabor actual + comunes, sin repetir paquetes
flavor_app_list() {
    local -n desk_list
    case $DESKTOP in
        kde) desk_list=APPS_KDE ;;
        gnome) desk_list=APPS_GNOME ;;
        xfce) desk_list=APPS_XFCE ;;
        lxqt) desk_list=APPS_LXQT ;;
        mate) desk_list=APPS_MATE ;;
        budgie) desk_list=APPS_BUDGIE ;;
        cinnamon) desk_list=APPS_CINNAMON ;;
        unity) desk_list=APPS_UNITY ;;
        *) printf '%s\n' "${APPS_COMMON[@]}"; return 0 ;;
    esac
    printf '%s\n' "${desk_list[@]}" "${APPS_COMMON[@]}" | awk -F'|' '!seen[$1]++'
}

# Juegos (perfil productividad) y extras que sobran en un sistema mínimo (perfil minimalista).
# Solo se quitan los que estén instalados.
GAME_PKGS=(aisleriot gnome-mines gnome-sudoku gnome-mahjongg gnome-2048 gnome-chess sgt-launcher
    2048-qt kmahjongg kmines kpat ksudoku)
MINIMAL_PKGS=("${GAME_PKGS[@]}" kmail kontact korganizer kaddressbook kalarm knotes akregator
    konversation hexchat quassel neochat ktorrent transmission-gtk transmission-qt k3b xfburn
    dragonplayer juk kmouth kteatime ktimer mugshot plasma-welcome kubuntu-docs kubuntu-web-shortcuts
    mate-user-guide ubuntu-mate-guide goodvibes gpodder)

remove_games() { remove_apps_with_progress "${GAME_PKGS[@]}"; }
remove_minimal_extras() { remove_apps_with_progress "${MINIMAL_PKGS[@]}"; }

# Qué es cada paquete (así "python3-uno" o "libreoffice-core-nogui" no asustan)
pkg_summary() { dpkg-query -W -f='${binary:Summary}' "$1" 2>/dev/null; }
#@parte comun: print_pkgs_described

# Piezas sin las que el escritorio o el sistema dejan de funcionar: si quitar una app
# las arrastraría por dependencias, esa app no se quita
CORE_PKGS=(plasma-desktop plasma-workspace kwin-x11 kwin-wayland systemsettings dolphin sddm
    gnome-shell gnome-session mutter nautilus gnome-control-center gdm3
    xfce4-session xfce4-panel xfwm4 xfdesktop4 thunar lightdm
    lxqt-session lxqt-panel openbox pcmanfm-qt
    mate-session-manager mate-panel marco caja
    budgie-desktop nemo cinnamon cinnamon-session unity unity-session ukui-session-manager
    network-manager pipewire wireplumber pulseaudio xorg xserver-xorg-core xwayland
    sudo systemd policykit-1 polkitd ubuntu-minimal ubuntu-standard grub-common linux-generic
    python3 python3-minimal perl perl-base bash coreutils apt dpkg libc6)
#@parte comun: desktop_file_owners

# Nunca se ofrecen: piezas del escritorio, la terminal (la que estás usando) ni paneles de configuración
DETECT_SKIP_PKGS=(konsole gnome-terminal gnome-console kgx xfce4-terminal qterminal mate-terminal lxterminal
    terminator tilix xterm kitty sudo policykit-1 polkitd)
#@parte comun: detected_app_entries flatpak_app_entries remove_flatpak_apps system_app_pkgs

select_apps_to_remove() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🚮 ELIMINAR APLICACIONES                      ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${CYAN}🖥️ Apps de ${FLAVOR_NAME} (${DESKTOP_NAME}) y comunes a todos los Ubuntu${NC}\n"
    local apps=()
    mapfile -t apps < <(flavor_app_list)

    # Solo se ofrecen las que están instaladas
    local installed=() entries=() app
    mapfile -t installed < <(installed_pkgs "${apps[@]%%|*}")
    for app in "${apps[@]}"; do
        printf '%s\n' "${installed[@]}" | grep -qx -- "${app%%|*}" && entries+=("$app")
    done
    local known=${#entries[@]} detected=() flatpaks=()
    echo -e "${CYAN}🔎 Buscando el resto de las apps instaladas (las del menú y las de Flatpak)...${NC}"
    local unowned=()
    mapfile -t detected < <(detected_app_entries "${entries[@]%%|*}" | sort -t'|' -k2,2f)
    mapfile -t unowned < <(printf '%s\n' "${detected[@]}" | sed -n 's/^-|//p')
    mapfile -t detected < <(printf '%s\n' "${detected[@]}" | grep -v '^-|' | grep -v '^$')
    if [ ${#unowned[@]} -gt 0 ]; then
        echo -e "${YELLOW}ℹ Estas apps del menú no vienen de ningún paquete (se instalaron a mano), así que no se${NC}"
        echo -e "${YELLOW}  pueden quitar desde aquí: $(printf '%s, ' "${unowned[@]}" | sed 's/, $//')${NC}"
        sleep 3
    fi
    mapfile -t flatpaks < <(flatpak_app_entries | sort -t'|' -k2,2f)
    entries+=("${detected[@]}" "${flatpaks[@]}")
    # Herramientas del sistema o de la distro: se marcan (se pueden quitar, pero con aviso)
    local sys_pkgs=() n
    mapfile -t sys_pkgs < <(system_app_pkgs)
    for n in "${!entries[@]}"; do
        printf '%s\n' "${sys_pkgs[@]}" | grep -qx -- "${entries[$n]%%|*}" \
            && entries[n]="${entries[$n]%%|*}|SYS::${entries[$n]#*|}"
    done
    if [ ${#entries[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ No se encontraron aplicaciones para quitar${NC}"
        pause
        return 0
    fi

    SELECTED_APPS=()
    if checklist_select "Eliminar aplicaciones" "Marca las que quieres ELIMINAR: $known conocidas, ${#detected[@]} detectadas en el menú (🔎), ${#flatpaks[@]} de Flatpak (📦)" "${entries[@]}"; then
        SELECTED_APPS=("${CHOSEN[@]}")
    fi
    clear

    if [ ${#SELECTED_APPS[@]} -gt 0 ]; then
        echo ""
        echo -e "${CYAN}📋 Se eliminarán las siguientes aplicaciones:${NC}"
        for app in "${SELECTED_APPS[@]}"; do
            echo -e "  ${CYAN}•${NC} $app"
        done
        echo ""

        local sys_chosen=()
        mapfile -t sys_chosen < <(printf '%s\n' "${SELECTED_APPS[@]}" | grep -xF -f <(printf '%s\n' "${sys_pkgs[@]}" | grep .))
        if [ ${#sys_chosen[@]} -gt 0 ]; then
            echo -e "${RED}⚠ Marcaste ${#sys_chosen[@]} herramienta(s) del sistema o de tu distribución: ${sys_chosen[*]}${NC}"
            echo -e "${RED}  Quítalas solo si sabes que no las usas (por ejemplo, la configuración de tu tarjeta gráfica).${NC}\n"
        fi
        if confirm "${CYAN}⚠️ ¿Confirmar eliminación de estas ${#SELECTED_APPS[@]} aplicaciones?${NC}"; then
            # Las de Flatpak se quitan con flatpak; el resto, con el gestor de paquetes
            local pkgs=() fps=()
            for app in "${SELECTED_APPS[@]}"; do
                if [[ "$app" == flatpak:* ]]; then fps+=("${app#flatpak:}"); else pkgs+=("$app"); fi
            done
            [ ${#pkgs[@]} -gt 0 ] && remove_apps_with_progress "${pkgs[@]}"
            [ ${#fps[@]} -gt 0 ] && remove_flatpak_apps "${fps[@]}"
            echo -e "${GREEN}✓ Eliminación completada${NC}"
        else
            echo -e "${YELLOW}ℹ Eliminación cancelada${NC}"
            SELECTED_APPS=()
        fi
    else
        echo -e "${YELLOW}ℹ No seleccionaste ninguna aplicación${NC}"
    fi

    pause
}
#@parte apt: remove_flavor_meta

enable_backports() {
    # El PPA de backports es de Kubuntu: en los demás sabores no existe
    if [ "$FLAVOR" != kubuntu ]; then
        log_warning "KDE Rolling Release es solo para Kubuntu (este sistema es ${FLAVOR_NAME})"
        return 0
    fi
    if grep -rqs 'kubuntu-ppa/backports' /etc/apt/sources.list /etc/apt/sources.list.d/; then
        echo -e "  ${GREEN}✓ KDE Rolling Release (backports) ya está activo${NC}"
        return 0
    fi
    run "No se pudo agregar ppa:kubuntu-ppa/backports" sudo add-apt-repository -y ppa:kubuntu-ppa/backports \
        && apt_update force && log_success "Se cambió a KDE Rolling Release (actualiza el sistema para aplicarlo)"
}
#@parte apt: disable_mandb enable_mandb

configure_system() {
    clear
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔩 CONFIGURAR SISTEMA                         ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [ -z "$FLAVOR_META" ]; then
        echo -e "\n${YELLOW}ℹ ${FLAVOR_NAME}: no hay meta-paquete de escritorio${NC}"
    else
    echo -e "\n${GREEN}1. Meta-paquete ${FLAVOR_META}${NC}"
    echo -e "   ${GREEN}📝 Descripción:${NC} Es el paquete que agrupa todas las apps de ${FLAVOR_NAME}"
    echo -e "   ${GREEN}✓ Si lo eliminas:${NC} Podrás desinstalar apps sin que se reinstalen"
    echo ""
    if confirm "${GREEN}¿Eliminar ${FLAVOR_META}? (recomendado)${NC}"; then
        remove_flavor_meta
    else
        echo -e "${YELLOW}ℹ Se mantiene ${FLAVOR_META}${NC}"
    fi
    fi

    if [ "$FLAVOR" = kubuntu ]; then
    echo ""
    echo -e "${GREEN}2. Cambio a KDE Rolling Release (solo para Kubuntu)${NC}"
    echo -e "   ${GREEN}📝 Descripción:${NC} Cambia los repositorios a versión Rolling Release"
    echo -e "   ${GREEN}✓ Beneficio:${NC} Te dará las últimas versiones de KDE Plasma"
    echo ""
    if confirm "${GREEN}¿Cambiar a KDE Rolling Release? (recomendado)${NC}"; then
        enable_backports
    else
        echo -e "${YELLOW}ℹ Se mantienen repositorios estándar${NC}"
    fi
    fi

    echo ""
    echo -e "${GREEN}3. Indexación de manuales (man-db)${NC}"
    echo -e "   ${GREEN}📝 Descripción:${NC} Tras cada instalación se reindexan los manuales de terminal"
    echo -e "   ${GREEN}✓ Si la desactivas:${NC} Instalar y desinstalar es bastante más rápido"
    echo ""
    if [ ! -e /var/lib/man-db/auto-update ]; then
        echo -e "${GREEN}✓ Ya está desactivada${NC}"
        if confirm "${GREEN}¿Volver a activarla?${NC}"; then
            enable_mandb
        fi
    elif confirm "${GREEN}¿Desactivar la indexación de manuales? (recomendado)${NC}"; then
        disable_mandb
    fi

    pause
}
#@parte comun: optimize_gpu_menu

optimize_nvidia() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🟢 OPTIMIZACIÓN NVIDIA                        ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    if ! command -v nvidia-smi &> /dev/null; then
        echo -e "${YELLOW}⚠ Driver NVIDIA no detectado. Instalando el recomendado para tu GPU...${NC}"
        install_recommended_drivers || return 1
    else
        echo -e "${PURPLE}🔧 Activando modo persistente del driver...${NC}"
        run "No se pudo activar el modo persistente" sudo nvidia-smi -pm 1
    fi

    if confirm "${PURPLE}¿Instalar CUDA Toolkit? (varios GB, solo para desarrollo/IA)${NC}"; then
        echo -e "${PURPLE}📦 Instalando CUDA Toolkit...${NC}"
        apt_install_recorded nvidia-cuda-toolkit && log_success "CUDA Toolkit instalado"
    fi

    echo ""
    echo -e "${GREEN}✓ ¡OPTIMIZACIÓN NVIDIA COMPLETADA!${NC}"
    echo -e "${YELLOW}⚠ Reinicia el sistema para aplicar todos los cambios${NC}"
}

optimize_amd() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔴 OPTIMIZACIÓN AMD                           ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    echo -e "${PURPLE}🔧 Actualizando drivers AMD...${NC}"
    apt_update
    apt_install mesa-utils mesa-vulkan-drivers libgl1-mesa-dri || return 1

    echo -e "${PURPLE}🔧 Activando overclocking y control de fans...${NC}"
    echo 'options amdgpu ppfeaturemask=0xffffffff' | sudo tee /etc/modprobe.d/amd_ppfeaturemask.conf > /dev/null
    run "No se pudo regenerar initramfs" sudo update-initramfs -u

    echo -e "${PURPLE}🔧 Instalando CoreCtrl para control gráfico...${NC}"
    apt_install_recorded corectrl

    echo ""
    echo -e "${GREEN}✓ ¡OPTIMIZACIÓN AMD COMPLETADA!${NC}"
    echo -e "${YELLOW}⚠ Reinicia el sistema para aplicar todos los cambios${NC}"
}

optimize_intel() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔵 OPTIMIZACIÓN INTEL                         ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    echo -e "${PURPLE}🔧 Actualizando driver Intel...${NC}"
    apt_update
    apt_install intel-media-va-driver intel-gpu-tools va-driver-all vainfo || return 1

    echo -e "${PURPLE}🔧 Activando GuC/HuC para códecs...${NC}"
    echo 'options i915 enable_guc=3' | sudo tee /etc/modprobe.d/i915_guc.conf > /dev/null
    run "No se pudo regenerar initramfs" sudo update-initramfs -u

    echo ""
    echo -e "${GREEN}✓ ¡OPTIMIZACIÓN INTEL COMPLETADA!${NC}"
    echo -e "${YELLOW}⚠ Reinicia el sistema para aplicar todos los cambios${NC}"
}

auto_detect_gpu() {
    echo -e "${PURPLE}🔄 Detectando GPU...${NC}"
    # Solo dispositivos de vídeo: evita confundir la CPU/chipset AMD o Intel con la GPU
    local gpus
    gpus=$(lspci 2>/dev/null | grep -Ei 'vga|3d controller|display controller')
    if grep -qi nvidia <<< "$gpus"; then
        echo -e "${GREEN}🟢 GPU NVIDIA detectada${NC}"
        optimize_nvidia
    elif grep -Eqi 'amd|ati|radeon' <<< "$gpus"; then
        echo -e "${GREEN}🔴 GPU AMD detectada${NC}"
        optimize_amd
    elif grep -qi intel <<< "$gpus"; then
        echo -e "${GREEN}🔵 GPU Intel detectada${NC}"
        optimize_intel
    else
        echo -e "${YELLOW}⚠ No se detectó ninguna GPU compatible${NC}"
    fi
}

# ============================================================
# OPCIÓN 14: OPTIMIZACIÓN DE KERNEL (COLOR: AZUL)
# ============================================================

optimize_kernel_menu() {
    while true; do
        clear
        echo -e "${BLUE}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    🐧 OPTIMIZACIÓN DEL KERNEL                    ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "${BLUE}🐧 Kernel en uso: ${BOLD}$(uname -r)${NC}"
        echo -e "\n${BLUE}📋 Opciones de optimización del kernel:${NC}\n"
        echo -e "  ${BLUE}1)${NC} Kernel Liquorix (basado en Zen, máximo rendimiento, gaming)"
        echo -e "  ${BLUE}2)${NC} Kernel XanMod (rendimiento balanceado, desktop)"
        echo -e "  ${BLUE}3)${NC} Kernel oficial Ubuntu: LTS, HWE o versión específica (recomendado)"
        echo -e "  ${BLUE}4)${NC} Kernel oficial + Livepatch (Ubuntu Pro)"
        echo -e "  ${BLUE}5)${NC} Ajustes avanzados de kernel"
        echo -e "\n  ${BLUE}0)${NC} 🔙 Volver"
        echo ""
        read -r -p "📌 Opción (0-5): " kernel_option

        case $kernel_option in
            1) install_liquorix_kernel ;;
            2) install_xanmod_kernel ;;
            3) optimize_standard_kernel ;;
            4) install_standard_livepatch_kernel ;;
            5) advanced_kernel_tweaks ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
        return 0
    done
}

# ------------------------------------------------------------
# Utilidades para cambiar de kernel
# ------------------------------------------------------------

# Kernels de terceros que gestiona el script
CUSTOM_KERNELS=("liquorix" "xanmod")
KERNEL_CLEANUP_FILE="$STATE_DIR/kernels-pendientes.txt"
GRUB_TEMP_PIN_FILE="$STATE_DIR/grub-fijado-temporal"
KERNEL_PENDING_CLEANUP=false
XANMOD_KEYRING="/etc/apt/keyrings/xanmod-archive-keyring.gpg"
XANMOD_LIST="/etc/apt/sources.list.d/xanmod-release.list"
#@parte apt: kernel_versions
#@parte arranque: secure_boot_enabled

# Comprobaciones antes de instalar un kernel de terceros
check_custom_kernel_requirements() {
    if [ "$(dpkg --print-architecture)" != "amd64" ]; then
        log_error "Este kernel solo está disponible para arquitectura amd64"
        return 1
    fi

    if secure_boot_enabled; then
        log_error "Secure Boot está activado"
        echo -e "${YELLOW}  Liquorix y XanMod no están firmados: con Secure Boot el equipo NO arrancará con ellos.${NC}"
        echo -e "${YELLOW}  Desactiva Secure Boot en la BIOS/UEFI o usa el kernel oficial (opción 3).${NC}"
        return 1
    fi

    if [ -z "$(kernel_versions generic)" ]; then
        log_warning "No hay un kernel oficial (generic) instalado como respaldo"
        if ! confirm "${BLUE}¿Continuar de todos modos?${NC}"; then
            return 1
        fi
    fi

    local boot_free
    boot_free=$(df --output=avail -m /boot 2>/dev/null | tail -1 | tr -d ' ')
    if [ -n "$boot_free" ] && [ "$boot_free" -lt 300 ]; then
        log_warning "Poco espacio libre en /boot (${boot_free} MB); la instalación podría fallar"
    fi
    return 0
}
#@parte apt: purge_kernel_pkgs

# Elimina por completo un kernel de terceros (imágenes, headers y su repositorio)
remove_kernel_family() {
    local family="$1" pkgs
    mapfile -t pkgs < <(installed_pkgs "linux-*${family}*")

    if [ ${#pkgs[@]} -gt 0 ]; then
        purge_kernel_pkgs "${pkgs[@]}" || return 1
        log_success "Kernel ${family} eliminado"
    fi

    case $family in
        liquorix)
            if ls /etc/apt/sources.list.d/*damentz*liquorix* &> /dev/null; then
                run "No se pudo quitar el PPA de Liquorix" sudo add-apt-repository --remove -y ppa:damentz/liquorix
            fi
            ;;
        xanmod)
            sudo rm -f "$XANMOD_LIST" "$XANMOD_KEYRING"
            ;;
    esac
    return 0
}

# Cambia GRUB_DEFAULT en /etc/default/grub
GRUB_DEFAULT_BACKUP="/etc/default/grub.ubuntu-ultimate-tools.orig"
#@parte arranque: backup_grub_config set_grub_default grub_line_id grub_entry_path ensure_grub_saved
#@parte apt: grub_select x86_64_level

finish_custom_kernel() {
    local family="$1" label="$2" version
    version=$(kernel_versions "$family" | tail -1)
    if [ -z "$version" ] || [ ! -e "/boot/vmlinuz-$version" ]; then
        log_error "El kernel $label no quedó instalado en /boot"
        return 1
    fi

    grub_select "$version"

    echo ""
    log_success "Kernel $label instalado: $version"
    echo -e "${YELLOW}⚠ Reinicia para usar el nuevo kernel${NC}"
    echo -e "${BLUE}📋 Si no arranca, elige el kernel 'generic' en 'Opciones avanzadas' de GRUB${NC}"
    echo -e "${BLUE}   (mantén Shift o pulsa Esc al encender) y vuelve con la opción 3.${NC}"
}

# ------------------------------------------------------------
# Instalación de kernels
# ------------------------------------------------------------

install_liquorix_kernel() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🐧 KERNEL LIQUORIX                            ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    check_custom_kernel_requirements || return 1

    echo -e "${BLUE}[1/4] Agregando repositorio Liquorix...${NC}"
    run "No se pudo agregar el PPA de Liquorix" sudo add-apt-repository -y ppa:damentz/liquorix || return 1
    apt_update force || return 1

    echo -e "${BLUE}[2/4] Instalando kernel Liquorix (puede tardar varios minutos)...${NC}"
    apt_install linux-image-liquorix-amd64 linux-headers-liquorix-amd64 || return 1

    echo -e "${BLUE}[3/4] Eliminando XanMod si existe...${NC}"
    remove_kernel_family xanmod

    echo -e "${BLUE}[4/4] Configurando GRUB...${NC}"
    finish_custom_kernel liquorix "Liquorix"
}

install_xanmod_kernel() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🐧 KERNEL XANMOD                              ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    echo -e "${YELLOW}ℹ El kernel Zen no existe para Ubuntu; XanMod es la alternativa equivalente${NC}\n"

    check_custom_kernel_requirements || return 1

    local level codename package tmp_key
    level=$(x86_64_level)
    if [ -z "$level" ]; then
        log_error "Tu CPU no soporta x86-64-v2, requerido por XanMod"
        return 1
    fi
    package="linux-xanmod-x64v${level}"
    # shellcheck disable=SC1091
    codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo -e "${BLUE}📋 CPU compatible con x86-64-v${level} → paquete ${package}${NC}\n"

    echo -e "${BLUE}[1/5] Agregando repositorio XanMod...${NC}"
    command -v wget &> /dev/null || apt_install wget || return 1
    tmp_key=$(mktemp)
    if ! run "No se pudo descargar la clave de XanMod" wget -qO "$tmp_key" https://dl.xanmod.org/archive.key; then
        rm -f "$tmp_key"
        return 1
    fi
    sudo install -d -m 0755 /etc/apt/keyrings
    run "Clave de XanMod inválida" sudo gpg --dearmor --yes -o "$XANMOD_KEYRING" "$tmp_key"
    rm -f "$tmp_key"
    echo "deb [signed-by=$XANMOD_KEYRING] http://deb.xanmod.org $codename main" | sudo tee "$XANMOD_LIST" > /dev/null
    apt_update force || return 1

    if ! apt-cache policy "$package" 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        log_error "XanMod no tiene el paquete $package para esta versión de Ubuntu ($codename)"
        remove_kernel_family xanmod
        return 1
    fi

    echo -e "${BLUE}[2/5] Instalando kernel XanMod (puede tardar varios minutos)...${NC}"
    apt_install "$package" || return 1

    echo -e "${BLUE}[3/5] Eliminando Liquorix si existe...${NC}"
    remove_kernel_family liquorix

    echo -e "${BLUE}[4/5] Eliminando kernel Zen antiguo si existe...${NC}"
    local zen_pkgs
    mapfile -t zen_pkgs < <(installed_pkgs 'linux-*zen*')
    [ ${#zen_pkgs[@]} -gt 0 ] && apt_purge "${zen_pkgs[@]}"

    echo -e "${BLUE}[5/5] Configurando GRUB...${NC}"
    finish_custom_kernel xanmod "XanMod"
}
#@parte apt: available_pkgs

# Versión del kernel a la que apunta un metapaquete instalado (p. ej. linux-image-generic)
meta_kernel_version() {
    dpkg-query -W -f='${Depends}' "$1" 2>/dev/null | grep -oE 'linux-image-(unsigned-)?[0-9][^ ,]*' | head -1 \
        | sed -E 's/^linux-image-(unsigned-)?//'
}
#@parte apt: os_release_value

# Borra todos los paquetes de una versión concreta del kernel oficial
purge_official_kernel_version() {
    local base="${1%-generic}" pkgs
    mapfile -t pkgs < <(installed_pkgs "linux-*-${base}" "linux-*-${base}-*")
    [ ${#pkgs[@]} -gt 0 ] && purge_kernel_pkgs "${pkgs[@]}"
}

# Muestra los kernels oficiales disponibles y deja la elección en OFFICIAL_VERSION
choose_specific_kernel_version() {
    local versions v i=0 mark choice running
    running=$(uname -r)
    mapfile -t versions < <(apt-cache pkgnames linux-image- 2>/dev/null \
        | grep -E '^linux-image-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-generic$' \
        | sed 's/^linux-image-//' | sort -V | tail -15)
    if [ ${#versions[@]} -eq 0 ]; then
        log_error "No se encontraron versiones del kernel oficial en los repositorios"
        return 1
    fi

    echo -e "\n${BLUE}📋 Versiones disponibles (las 15 más recientes):${NC}\n"
    for v in "${versions[@]}"; do
        i=$((i + 1))
        mark=""
        [ -e "/boot/vmlinuz-$v" ] && mark=" ${GREEN}(instalado)${NC}"
        [ "$v" = "$running" ] && mark=" ${GREEN}(en uso)${NC}"
        echo -e "  ${BLUE}[$(printf '%2s' "$i")]${NC} $v$mark"
    done
    echo -e "\n  ${BLUE}[ 0]${NC} 🔙 Volver"
    echo ""
    read -r -p "📌 Número de versión: " choice
    if [ -z "$choice" ] || [ "$choice" = 0 ]; then
        echo -e "${YELLOW}ℹ No se cambió nada${NC}"
        return 1
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#versions[@]} ]; then
        log_error "Opción inválida"
        return 1
    fi
    OFFICIAL_VERSION="${versions[$((choice - 1))]}"
}

# Pregunta qué kernel oficial usar; deja el resultado en OFFICIAL_KIND (ga|hwe|specific)
choose_official_kernel() {
    local allow_specific="$1" release hwe_available=false option
    release=$(os_release_value VERSION_ID)
    [ -n "$(available_pkgs "linux-generic-hwe-$release")" ] && hwe_available=true

    echo -e "${BLUE}📋 ¿Qué kernel oficial quieres usar?${NC}\n"
    echo -e "  ${BLUE}1)${NC} LTS / GA (linux-generic): el kernel con el que salió Ubuntu $release, máxima estabilidad"
    if $hwe_available; then
        echo -e "  ${BLUE}2)${NC} HWE (linux-generic-hwe-$release): más reciente, mejor soporte para hardware nuevo"
    else
        echo -e "  ${BLUE}2)${NC} HWE ${YELLOW}(no disponible: solo existe en versiones LTS)${NC}"
    fi
    $allow_specific && echo -e "  ${BLUE}3)${NC} Versión específica (elegir de la lista)"
    echo -e "\n  ${BLUE}0)${NC} 🔙 Volver"
    echo ""
    read -r -p "📌 Opción: " option

    OFFICIAL_VERSION=""
    case $option in
        0) return 1 ;;
        1) OFFICIAL_KIND="ga" ;;
        2)
            if ! $hwe_available; then
                log_error "El kernel HWE no está disponible en esta versión"
                return 1
            fi
            OFFICIAL_KIND="hwe" ;;
        3)
            $allow_specific || { log_error "Opción inválida"; return 1; }
            OFFICIAL_KIND="specific"
            choose_specific_kernel_version || return 1 ;;
        *) log_error "Opción inválida"; return 1 ;;
    esac
}

# Instala el kernel oficial elegido y elimina los de terceros. Devuelve 1 si falla.
switch_to_official_kernel() {
    local kind="$1" version="$2" release pkgs=() family v
    release=$(os_release_value VERSION_ID)
    KERNEL_PENDING_CLEANUP=false

    echo -e "\n${BLUE}[1/5] Instalando kernel oficial...${NC}"
    apt_update || return 1
    case $kind in
        ga) pkgs=(linux-generic) ;;
        hwe) pkgs=("linux-generic-hwe-$release") ;;
        specific)
            mapfile -t pkgs < <(available_pkgs "linux-image-$version" "linux-headers-$version" "linux-modules-extra-$version")
            if [ ${#pkgs[@]} -eq 0 ]; then
                log_error "La versión $version no está disponible"
                return 1
            fi ;;
    esac
    apt_install "${pkgs[@]}" || return 1

    case $kind in
        ga) version=$(meta_kernel_version linux-image-generic) ;;
        hwe) version=$(meta_kernel_version "linux-image-generic-hwe-$release") ;;
    esac
    if [ -z "$version" ] || [ ! -e "/boot/vmlinuz-$version" ]; then
        log_error "No se encontró el kernel oficial en /boot; no se eliminarán los demás kernels"
        return 1
    fi
    log_success "Kernel oficial disponible: $version"

    echo -e "${BLUE}[2/5] Eliminando kernels de terceros (Liquorix/XanMod)...${NC}"
    for family in "${CUSTOM_KERNELS[@]}"; do
        remove_kernel_family "$family" || return 1
    done

    echo -e "${BLUE}[3/5] Quitando la otra línea de kernel oficial (LTS/HWE)...${NC}"
    local metas=()
    case $kind in
        ga) mapfile -t metas < <(installed_pkgs 'linux-*generic-hwe-*') ;;
        hwe) mapfile -t metas < <(installed_pkgs linux-generic linux-image-generic linux-headers-generic) ;;
    esac
    [ ${#metas[@]} -gt 0 ] && apt_purge "${metas[@]}"
    if [ "$kind" != "specific" ]; then
        # Versiones de otra serie (p. ej. 6.14 de HWE si se eligió la 6.8 LTS)
        for v in $(kernel_versions generic); do
            [ "${v%%-*}" != "${version%%-*}" ] && purge_official_kernel_version "$v"
        done
    fi

    echo -e "${BLUE}[4/5] Limpiando kernels antiguos...${NC}"
    if confirm "${BLUE}¿Dejar SOLO el kernel $version y borrar las demás versiones oficiales?${NC}"; then
        for v in $(kernel_versions generic); do
            [ "$v" != "$version" ] && purge_official_kernel_version "$v"
        done
    fi
    run "Falló la limpieza de kernels antiguos" sudo env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" autoremove --purge

    echo -e "${BLUE}[5/5] Configurando GRUB...${NC}"
    rm -f "$GRUB_TEMP_PIN_FILE"
    if [ "$kind" = "specific" ]; then
        grub_select "$version" || return 1
        echo -e "${YELLOW}ℹ Las actualizaciones pueden instalar kernels nuevos, pero GRUB seguirá arrancando $version${NC}"
    elif $KERNEL_PENDING_CLEANUP; then
        # El kernel anterior sigue instalado hasta reiniciar: fijar el elegido mientras tanto
        grub_select "$version" || return 1
        mkdir -p "$STATE_DIR"
        touch "$GRUB_TEMP_PIN_FILE"
    else
        grub_select 0 || return 1
    fi
    return 0
}
#@parte apt: cleanup_pending_kernels

optimize_standard_kernel() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🐧 KERNEL OFICIAL UBUNTU                      ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    choose_official_kernel true || return 1
    switch_to_official_kernel "$OFFICIAL_KIND" "$OFFICIAL_VERSION" || return 1

    echo -e "${BLUE}🔧 Aplicando optimizaciones de rendimiento...${NC}"
    set_sysctl vm.swappiness 10
    set_sysctl vm.vfs_cache_pressure 50

    echo ""
    log_success "Kernel oficial de Ubuntu configurado"
    echo -e "${YELLOW}⚠ Reinicia el sistema para usar el nuevo kernel${NC}"
    echo -e "${BLUE}📋 Para verificar: uname -r${NC}"
}

install_standard_livepatch_kernel() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔰 KERNEL CON LIVEPATCH                       ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    if ! grep -q 'LTS' /etc/os-release; then
        log_warning "Livepatch solo funciona en versiones LTS de Ubuntu"
    fi
    if ! command -v snap &> /dev/null; then
        log_warning "Livepatch necesita Snap; reinstálalo con la opción 9 del menú principal"
    fi

    # Livepatch solo da soporte a los kernels oficiales LTS (GA) y HWE
    choose_official_kernel false || return 1
    switch_to_official_kernel "$OFFICIAL_KIND" || return 1

    echo -e "${BLUE}🔧 Instalando Ubuntu Pro client...${NC}"
    local pro_pkg="ubuntu-pro-client"
    apt-cache show "$pro_pkg" &> /dev/null || pro_pkg="ubuntu-advantage-tools"
    apt_install "$pro_pkg" || return 1

    set_sysctl vm.swappiness 10

    if command -v pro &> /dev/null; then
        echo -e "${YELLOW}📋 Para habilitar Livepatch, necesitas un token de Ubuntu Pro${NC}"
        echo -e "${BLUE}🔑 Obtén tu token gratuito en: https://ubuntu.com/pro/dashboard${NC}"
        if confirm "¿Tienes un token para habilitar Livepatch ahora?"; then
            local pro_token
            read -r -p "🔑 Ingresa tu token (Enter = omitir): " pro_token
            if [ -n "$pro_token" ]; then
                if run "No se pudo vincular Ubuntu Pro" sudo pro attach "$pro_token"; then
                    # 'pro attach' suele activar Livepatch por sí solo
                    if pro status 2>/dev/null | grep -Eq '^livepatch +yes +enabled' || \
                       run "No se pudo habilitar Livepatch" sudo pro enable livepatch; then
                        log_success "Livepatch habilitado correctamente"
                    fi
                fi
            fi
        else
            echo -e "${YELLOW}⚠ Livepatch no habilitado. Configúralo después con: sudo pro attach [token]${NC}"
        fi
    fi

    echo ""
    log_success "Kernel oficial configurado"
    echo -e "${YELLOW}⚠ Reinicia el sistema para usar el nuevo kernel${NC}"
}
#@parte comun: enable_trim
#@parte apt: advanced_kernel_tweaks
#@parte comun: datos_swapfile zram_swap_active disk_swap_active swapfile_active swap_summary ram_swappiness_auto apply_ram_tweaks suggest_swap_gb create_swapfile remove_swapfile swappiness_manual ram_status optimize_ram_menu
#@parte apt: enable_zram


# ============================================================
# OPCIÓN 1: ACTUALIZACIÓN DEL SISTEMA (COLOR: VERDE)
# ============================================================

do_system_update() {
    echo -e "${GREEN}[1/4] Actualizando lista de paquetes...${NC}"
    run_visible "Falló 'apt update'" sudo apt-get update || return 1
    APT_LISTS_FRESH=true

    echo -e "${GREEN}[2/4] Actualizando paquetes del sistema...${NC}"
    run_visible "Falló la actualización" sudo env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" full-upgrade || return 1

    echo -e "${GREEN}[3/4] Eliminando paquetes huérfanos...${NC}"
    run "Falló autoremove" sudo env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" autoremove --purge

    echo -e "${GREEN}[4/4] Limpiando caché de paquetes...${NC}"
    run "Falló autoclean" sudo apt-get autoclean -y
    log_success "Sistema actualizado"
}

system_update() {
    clear
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔄 ACTUALIZAR SISTEMA                         ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "\n${GREEN}📋 Se ejecutará:${NC}"
    echo -e "  • sudo apt update"
    echo -e "  • sudo apt full-upgrade -y"
    echo -e "  • sudo apt autoremove -y"
    echo -e "  • sudo apt autoclean -y"
    echo ""

    if ! confirm "${GREEN}¿Actualizar el sistema?${NC}"; then
        return 0
    fi

    do_system_update
    echo ""
    echo -e "${GREEN}✓ ¡SISTEMA ACTUALIZADO COMPLETAMENTE!${NC}"
    pause
}
#@parte comun: tokyo_color_group write_tokyo_night_colors write_tokyo_night_konsole

THEME_BACKUP="$STATE_DIR/tema-anterior.txt"
#@parte comun: save_theme_value theme_value kde_color_scheme install_tokyo_night_theme gnome_dark_mode
#@parte apt: install_custom_software

# ------------------------------------------------------------
# Desarrollo: compilar APK (SDK de Android), Android Studio y Flatpak
# ------------------------------------------------------------

ANDROID_SDK="$HOME/Android/Sdk"            # La misma carpeta que usa Android Studio
ANDROID_ENV="$HOME/.config/ubuntu-ultimate-tools/android-sdk.sh"
ANDROID_ENV_MARK="# Ubuntu Ultimate Tools: Android SDK"
ANDROID_STUDIO_DIR="/opt/android-studio"
ANDROID_STUDIO_STATE="$STATE_DIR/android-studio.txt"   # "google" o "snap"
ANDROID_STUDIO_DESKTOP="$HOME/.local/share/applications/android-studio.desktop"
FLATPAK_SDK_LIST="$STATE_DIR/flatpak-sdk.txt"
#@parte comun: android_tools_installed
#@parte apt: android_studio_installed
#@parte comun: enough_space check_sum

# JDK que usa Gradle: el 21 si existe en tu Ubuntu, si no el 17
install_jdk() {
    local jdk
    jdk=$(available_pkgs openjdk-21-jdk-headless openjdk-17-jdk-headless | head -n1)
    if [ -z "$jdk" ]; then
        log_error "No hay JDK 17 ni 21 en tus repositorios"
        return 1
    fi
    apt_install_recorded "$jdk" || return 1
    JAVA_HOME_DIR=$(dirname "$(dirname "$(dpkg -L "$jdk" 2>/dev/null | grep -m1 '/bin/javac$')")")
    [ -x "$JAVA_HOME_DIR/bin/javac" ] || { log_error "No se encontró el JDK instalado"; return 1; }
}

# Variables para la terminal: ANDROID_HOME, JAVA_HOME y las herramientas en el PATH
write_android_env() {
    mkdir -p "$(dirname "$ANDROID_ENV")"
    cat > "$ANDROID_ENV" << ENV
# Creado por Ubuntu Ultimate Tools: herramientas para compilar APK
export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="\$ANDROID_HOME"
export JAVA_HOME="\${JAVA_HOME:-$JAVA_HOME_DIR}"
_uut_bt=\$(ls -d "\$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -n1)
export PATH="\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\${_uut_bt:+\$_uut_bt:}\$PATH"
unset _uut_bt
ENV
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.profile"; do
        [ -f "$rc" ] || continue
        grep -qF "$ANDROID_ENV_MARK" "$rc" && continue
        echo "[ -f \"$ANDROID_ENV\" ] && . \"$ANDROID_ENV\"  $ANDROID_ENV_MARK" >> "$rc"
    done
}
#@parte comun: android_sdk_packages

install_android_tools() {
    echo -e "${BLUE}🤖 Herramientas para compilar APK (sin Android Studio)${NC}"
    echo -e "${CYAN}  Java (JDK) + SDK de Android de Google + adb. Unos 3 GB en $ANDROID_SDK${NC}"
    enough_space "$HOME" 4 || return 1
    apt_update
    install_jdk || return 1
    # Reglas para que Linux reconozca el celular por USB (adb sin sudo) y unzip para el SDK
    apt_install_recorded android-sdk-platform-tools-common unzip || return 1
    getent group plugdev > /dev/null && ! id -nG | grep -qw plugdev \
        && run "No se pudo dar permiso al USB" sudo usermod -aG plugdev "$USER"

    if ! android_tools_installed; then
        local xml url sum tmp
        echo -e "${BLUE}⬇ Buscando la última versión de las herramientas de Google...${NC}"
        # La misma lista que usa sdkmanager: dice el archivo y su suma de comprobación
        xml=$(wget -qO- https://dl.google.com/android/repository/repository2-3.xml 2>> "$LOG_FILE")
        read -r sum url < <(awk '
            /<remotePackage path="cmdline-tools;latest">/ { on = 1 }
            on && /<checksum/ { c = $0; gsub(/.*">|<\/checksum>.*/, "", c) }
            on && /<url>/ { u = $0; gsub(/.*<url>|<\/url>.*/, "", u); if (u ~ /linux/) { print c, u; exit } }
            on && /<\/remotePackage>/ { on = 0 }' <<< "$xml")
        if [[ ! "$url" =~ ^commandlinetools-linux-[0-9]+_latest\.zip$ ]]; then
            log_error "No se pudo consultar la versión de las herramientas de Google (¿sin internet?)"
            return 1
        fi
        tmp=$(mktemp -d)
        echo -e "${BLUE}⬇ Descargando $url...${NC}"
        if ! wget -q --show-progress -O "$tmp/tools.zip" "https://dl.google.com/android/repository/$url" \
            || ! check_sum "$tmp/tools.zip" "$sum"; then
            log_error "La descarga de las herramientas de Google falló o llegó dañada"
            rm -rf "$tmp"
            return 1
        fi
        mkdir -p "$ANDROID_SDK/cmdline-tools"
        rm -rf "$ANDROID_SDK/cmdline-tools/latest"
        if ! unzip -q "$tmp/tools.zip" -d "$tmp" || ! mv "$tmp/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest"; then
            log_error "No se pudieron descomprimir las herramientas de Google"
            rm -rf "$tmp"
            return 1
        fi
        rm -rf "$tmp"
    fi

    export JAVA_HOME="$JAVA_HOME_DIR"
    local sdkm="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" pkgs
    # Las licencias del SDK son de Google: las lee y las acepta el usuario, el script no lo hace por él
    if [ ! -s "$ANDROID_SDK/licenses/android-sdk-license" ]; then
        if $AUTO_MODE; then
            log_error "Las licencias del SDK de Android deben aceptarse a mano: usa esta opción desde el menú"
            return 1
        fi
        echo -e "${YELLOW}📜 Licencias del SDK de Android (de Google, no de este script)${NC}"
        echo "   A continuación se muestra cada licencia. Léela y escribe 'y' para aceptarla"
        echo "   o 'N' para rechazarla. Sin aceptarlas no se puede instalar el SDK."
        echo "   Texto completo: https://developer.android.com/studio/terms"
        "$sdkm" --sdk_root="$ANDROID_SDK" --licenses < /dev/tty
        if [ ! -s "$ANDROID_SDK/licenses/android-sdk-license" ]; then
            log_error "No se aceptaron las licencias del SDK de Android: no se instala nada"
            return 1
        fi
        log_success "Licencias del SDK aceptadas por ti"
    fi
    read -r -a pkgs <<< "$(android_sdk_packages)"
    if [ ${#pkgs[@]} -lt 3 ]; then
        log_error "No se pudo leer la lista de paquetes del SDK (detalles en $LOG_FILE)"
        return 1
    fi
    echo -e "${BLUE}⬇ Instalando ${pkgs[*]}...${NC}"
    run_visible "No se pudo instalar el SDK de Android" "$sdkm" --sdk_root="$ANDROID_SDK" "${pkgs[@]}" || return 1
    # Si ya estaba instalado, se actualiza todo lo que tenga versión nueva (también el NDK)
    echo -e "${BLUE}🔄 Actualizando los paquetes del SDK que ya tenías...${NC}"
    run "No se pudo actualizar el SDK" "$sdkm" --sdk_root="$ANDROID_SDK" --update
    write_android_env
    mkdir -p "$STATE_DIR"
    log_success "Listo para compilar APK (Android ${pkgs[1]#platforms;android-}, ${pkgs[2]})"
    cat << 'GUIA'

  📖 CÓMO COMPILAR UN APK (abre una terminal NUEVA para que tome las variables)
     cd carpeta-de-tu-proyecto
     ./gradlew assembleDebug        → app/build/outputs/apk/debug/app-debug.apk
     ./gradlew assembleRelease      → APK para publicar (hay que firmarlo)

  🧩 PROYECTOS CON VARIANTES (por ejemplo, Telegram y sus derivados):
     ./gradlew tasks                → lista todo lo que se puede compilar
     ./gradlew :modulo:tasks        → solo las de un módulo (busca assemble...)
     El APK queda en <módulo>/build/outputs/apk/<variante>/

  ⚙️ NDK Y CMAKE (proyectos con código C/C++): no hace falta instalarlos a mano.
     Como las licencias ya están aceptadas, Gradle baja solo la versión exacta
     que pide el proyecto (ndkVersion) la primera vez que compilas.

  🔄 ACTUALIZAR: vuelve a usar esta opción (actualiza el SDK). Tu proyecto:
     git pull  y compila de nuevo.

  🔑 FIRMAR (para compartir o publicar): crea tu clave UNA vez y guárdala bien;
     si la pierdes no podrás actualizar tu app:
     keytool -genkey -v -keystore mi-clave.jks -alias mi-app -keyalg RSA -validity 10000
     apksigner sign --ks mi-clave.jks app-release-unsigned.apk

  📱 PROBAR EN TU CELULAR: activa "Depuración USB" (Ajustes → Opciones de
     desarrollador), conéctalo y: adb install app-debug.apk
     (cierra sesión y vuelve a entrar la primera vez para el permiso del USB)
GUIA
}
#@parte comun: check_kvm
#@parte apt: install_android_studio_google

install_android_studio_snap() {
    if ! command -v snap &> /dev/null || [ -f /etc/apt/preferences.d/nosnap.pref ]; then
        log_error "Snap no está instalado en este sistema (opción 9 para reinstalarlo, o usa la versión de Google)"
        return 1
    fi
    echo -e "${BLUE}⬇ Instalando el snap de Android Studio (más de 1 GB)...${NC}"
    run_visible "No se pudo instalar el snap de Android Studio" sudo snap install android-studio --classic || return 1
    mkdir -p "$STATE_DIR"
    echo snap > "$ANDROID_STUDIO_STATE"
    log_success "Android Studio instalado (snap: se actualiza solo)"
}
#@parte apt: install_android_studio remove_android install_flatpak
#@parte comun: flatpak_latest_branch
#@parte apt: install_flatpak_builder
#@parte comun: remove_flatpak_sdks

# ------------------------------------------------------------
# Respaldos: antes de borrar algo que no se puede recuperar
# ------------------------------------------------------------

BACKUP_DIR="$HOME/respaldos-ubuntu-ultimate-tools"
#@parte comun: make_backup

# ------------------------------------------------------------
# Docker: compilar con el Dockerfile de un proyecto (SDK, NDK... ya listos adentro)
# ------------------------------------------------------------

DOCKER_PKGS=(docker.io docker-buildx docker-compose-v2)
#@parte comun: docker_installed

install_docker() {
    echo -e "${BLUE}🐳 DOCKER - compilar con el Dockerfile de un proyecto${NC}"
    echo -e "${CYAN}  Un Dockerfile es una receta: Docker arma un \"contenedor\" con todo lo que el proyecto${NC}"
    echo -e "${CYAN}  necesita (SDK, NDK, versiones exactas...) sin instalarlo en tu sistema.${NC}"
    echo -e "${CYAN}  Sirve también en un VPS sin escritorio.${NC}\n"

    # Otras instalaciones de Docker chocan con la de Ubuntu
    if [ -n "$(installed_pkgs docker-ce)" ]; then
        log_info "Ya tienes Docker de docker.com (docker-ce): no se instala el de Ubuntu"
    elif snap list docker &> /dev/null; then
        log_error "Tienes Docker en snap: chocaría con el de Ubuntu. Quítalo antes con: sudo snap remove docker"
        return 1
    else
        # Si había configuración de un Docker anterior, se respalda antes de tocar nada
        sudo test -d /etc/docker && make_backup docker-config /etc/docker
        apt_update
        local pkgs=()
        mapfile -t pkgs < <(available_pkgs "${DOCKER_PKGS[@]}")
        if ! printf '%s\n' "${pkgs[@]}" | grep -qx docker.io; then
            log_error "Tu Ubuntu no tiene el paquete docker.io"
            return 1
        fi
        apt_install_recorded "${pkgs[@]}" || return 1
    fi
    run "No se pudo iniciar Docker" sudo systemctl enable --now docker.service docker.socket || return 1
    log_success "Docker instalado y en marcha"

    # Usar docker sin sudo: cómodo, pero ese grupo equivale a ser administrador
    if ! id -nG | grep -qw docker; then
        echo -e "\n${YELLOW}ℹ Para usar docker sin escribir sudo, tu usuario entra al grupo 'docker'.${NC}"
        echo -e "${YELLOW}  Ojo: quien está en ese grupo tiene poder de administrador en la PC. En tu PC o${NC}"
        echo -e "${YELLOW}  en tu VPS personal está bien; en un servidor compartido, mejor usar sudo docker.${NC}"
        if confirm "${BLUE}¿Usar docker sin sudo?${NC}"; then
            run "No se pudo agregar al grupo docker" sudo usermod -aG docker "$USER" \
                && log_success "Listo (cierra sesión y vuelve a entrar, o en un VPS sal y vuelve a conectarte)"
        fi
    fi
    cat << 'GUIA'

  📖 COMPILAR UN PROYECTO QUE TRAE DOCKERFILE (por ejemplo, una app de Android)
     cd carpeta-del-proyecto
     docker build -t mi-compilador .                    → arma el contenedor (la 1.ª vez tarda)
     docker run --rm -v "$PWD":/home/source mi-compilador → compila (la ruta /home/source
                                                           la indica el README del proyecto)
     El APK queda en la carpeta del proyecto, como si lo hubieras compilado sin Docker.

  🔄 ACTUALIZAR: git pull y vuelve a ejecutar los 2 comandos.
  🧹 LIBERAR ESPACIO: docker system df  (ver)  ·  docker system prune  (borrar lo que sobra)
GUIA
}
#@parte comun: docker_usage remove_docker
#@parte apt: docker_remove_programs docker_nuclear dev_nuclear

# ------------------------------------------------------------
# Instalar un escritorio (como tasksel), a prueba de errores:
# - solo en Ubuntu (no en derivadas como Mint, Pop!_OS o Zorin, cuyo escritorio es parte de la distro)
# - se simula antes con apt: si fuera a QUITAR un solo paquete, no se instala nada
# - si ya hay un escritorio, se conserva su gestor de inicio de sesión
# - queda anotado lo que se instaló para poder quitarlo (opción 10)
# ------------------------------------------------------------
DESKTOP_STATE="$STATE_DIR/escritorio-instalado.txt"
DESKTOP_PKGS_LIST="$STATE_DIR/escritorio-paquetes.txt"
NETPLAN_NM_FILE="/etc/netplan/90-ultimate-tools-networkmanager.yaml"

# clave|nombre|paquetes (alternativas con /)|sin recomendados|gestor de sesión|sesión que instala|RAM mínima (MB)
DESKTOP_CHOICES=(
    "kde|KDE Plasma completo (como Kubuntu)|kubuntu-desktop||sddm|plasma|2048"
    "kde-min|KDE Plasma mínimo (liviano: Plasma, Dolphin, Konsole y red)|plasma-desktop sddm sddm-theme-breeze konsole dolphin plasma-nm plasma-pa kscreen network-manager|norec|sddm|plasma|1536"
    "gnome|GNOME (como Ubuntu)|ubuntu-desktop-minimal||gdm3|ubuntu|2048"
    "xfce|Xfce (como Xubuntu, liviano)|xubuntu-desktop-minimal/xubuntu-core||lightdm|xfce|1024"
    "lxqt|LXQt (como Lubuntu, el más liviano)|lubuntu-desktop||sddm|lxqt|1024"
    "mate|MATE (clásico)|ubuntu-mate-core/ubuntu-mate-desktop||lightdm|mate|1024"
    "budgie|Budgie|ubuntu-budgie-desktop-minimal/ubuntu-budgie-desktop||lightdm|budgie-desktop|1536"
    "cinnamon|Cinnamon (estilo Windows)|ubuntucinnamon-desktop-minimal/ubuntucinnamon-desktop||lightdm|cinnamon|1536"
)

# Sesiones gráficas ya instaladas (nombres de archivo sin .desktop)
installed_sessions() {
    local f
    for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
        [ -e "$f" ] && basename "$f" .desktop
    done | sort -u
}

# Gestor de inicio de sesión configurado (gdm3, sddm, lightdm...), vacío si no hay
current_display_manager() {
    local dm
    [ -s /etc/X11/default-display-manager ] && dm=$(basename "$(cat /etc/X11/default-display-manager)")
    if [ -z "$dm" ] && [ -e /etc/systemd/system/display-manager.service ]; then
        dm=$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)
    fi
    echo "$dm"
}

# Convierte "1.234 kB", "567 MB" o "2,5 GB" (salida de apt) a MB
apt_size_to_mb() {
    awk '{n = $1; gsub(/,/, "", n); u = $2
          if (u == "kB") n /= 1024; else if (u == "GB") n *= 1024; else if (u == "B") n /= 1048576
          printf "%d\n", n + 0.5}' <<< "$1"
}

# Red: en Server la maneja systemd-networkd y el escritorio la ve "no administrada"
netplan_uses_networkd() {
    command -v netplan &> /dev/null || return 1
    [ -e "$NETPLAN_NM_FILE" ] && return 1
    ! sudo grep -rqs 'renderer: *NetworkManager' /etc/netplan/
}

switch_netplan_to_nm() {
    echo -e "\n${BLUE}🌐 Red: Ubuntu Server usa systemd-networkd; el escritorio necesita NetworkManager${NC}"
    echo -e "${CYAN}   Sin el cambio internet sigue andando, pero el ícono de red y el Wi-Fi no se pueden manejar.${NC}"
    if [ -n "$SSH_CONNECTION" ]; then
        echo -e "${YELLOW}⚠ Estás conectado por SSH: no se cambia la red desde aquí (podrías perder la conexión).${NC}"
        echo -e "${YELLOW}  Hazlo desde el equipo mismo: opción 7 → Instalar un ESCRITORIO de nuevo, o en la terminal:${NC}"
        echo -e "${YELLOW}  sudo netplan try   (tras crear $NETPLAN_NM_FILE con 'renderer: NetworkManager')${NC}"
        return 0
    fi
    confirm "${BLUE}¿Pasar la red a NetworkManager? (se prueba 60 s y vuelve atrás sola si algo falla)${NC}" || return 0
    local backup
    backup="/etc/netplan.antes-escritorio-$(date +%Y%m%d-%H%M%S)"
    sudo cp -a /etc/netplan "$backup" && log_info "Copia de la red en $backup"
    printf 'network:\n  version: 2\n  renderer: NetworkManager\n' | sudo tee "$NETPLAN_NM_FILE" > /dev/null
    sudo chmod 600 "$NETPLAN_NM_FILE"
    if ! sudo netplan generate >> "$LOG_FILE" 2>&1; then
        sudo rm -f "$NETPLAN_NM_FILE"
        log_error "La configuración de red no es válida: no se cambió nada"
        return 1
    fi
    echo -e "${YELLOW}👉 Si sigues teniendo internet, pulsa ENTER antes de 60 s para confirmar.${NC}"
    echo -e "${YELLOW}   Si no pulsas nada, la red vuelve sola a como estaba.${NC}"
    if sudo netplan try --timeout 60; then
        echo "netplan=$NETPLAN_NM_FILE" >> "$DESKTOP_STATE"
        log_success "La red ahora la maneja NetworkManager"
    else
        sudo rm -f "$NETPLAN_NM_FILE"
        sudo netplan apply >> "$LOG_FILE" 2>&1
        log_warning "No se confirmó el cambio: la red sigue como estaba"
    fi
}

install_escritorio() { install_desktop; }

install_desktop() {
    clear
    echo -e "${BLUE}${BOLD}🖥️ INSTALAR UN ESCRITORIO${NC}\n"

    # 1. Solo Ubuntu de verdad: en las derivadas el escritorio es parte de la distro
    if [ "$(os_release_value ID)" != ubuntu ]; then
        log_warning "$(os_release_value NAME) es una distro derivada: su escritorio es parte de ella."
        echo -e "${YELLOW}  Instalar otro podría romperla, así que el script no lo hace.${NC}"
        return 1
    fi
    if is_live_session; then
        log_warning "Esto es un Live USB: el escritorio se instala en el sistema ya instalado"
        return 1
    fi
    if [ -s "$DESKTOP_STATE" ]; then
        echo -e "${YELLOW}ℹ Ya instalaste un escritorio con el script: $(grep '^nombre=' "$DESKTOP_STATE" | cut -d= -f2-)${NC}"
        echo -e "${YELLOW}  Para cambiarlo, primero quítalo en la opción 10 → Quitar el escritorio.${NC}"
        netplan_uses_networkd && switch_netplan_to_nm
        return 0
    fi

    # 2. El sistema de paquetes tiene que estar sano antes de tocar nada
    if [ -n "$(sudo dpkg --audit 2>/dev/null)" ] || ! sudo apt-get check >> "$LOG_FILE" 2>&1; then
        log_error "Hay paquetes a medio instalar o rotos: arréglalo antes con la opción 1 (Actualizar)"
        return 1
    fi

    # 3. ¿Ya hay escritorio?
    local sessions old_dm
    sessions=$(installed_sessions | tr '\n' ' ')
    old_dm=$(current_display_manager)
    if [ -n "$sessions" ]; then
        echo -e "${YELLOW}⚠ Este sistema YA tiene escritorio (sesiones: ${sessions% }).${NC}"
        echo -e "${YELLOW}  Se puede agregar otro al lado, pero no se quita ni se cambia nada del actual:${NC}"
        echo -e "${YELLOW}  si apt quisiera quitar algo, se cancela.${NC}"
        [ -n "$old_dm" ] && echo -e "${YELLOW}  Se mantiene tu pantalla de inicio de sesión ($old_dm).${NC}"
        confirm "${YELLOW}¿Agregar otro escritorio igualmente?${NC}" || return 0
    fi

    # 4. Elegir
    local entry key name pkgs norec dm session minram entries=() ram
    ram=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    for entry in "${DESKTOP_CHOICES[@]}"; do
        IFS='|' read -r key name _ _ _ session _ <<< "$entry"
        if [[ " $sessions " == *" $session "* ]]; then
            entries+=("$key|$name (ya instalado)")
        else
            entries+=("$key|$name")
        fi
    done
    echo -e "${CYAN}Tu equipo tiene ${ram} MB de RAM.${NC}"
    echo -e "${GREEN}🛡 Antes de instalar se simula: si apt quisiera quitar algo, no se instala nada.${NC}"
    echo -e "${GREEN}   Se quita en la opción 10 → 11 (solo lo que trajo).${NC}\n"
    local i=1 choice
    for entry in "${entries[@]}"; do
        printf "  ${CYAN}%d)${NC} %s\n" "$i" "${entry#*|}"
        i=$((i + 1))
    done
    echo -e "  ${CYAN}0)${NC} Volver"
    read -r -p "🔢 Escritorio (0-${#entries[@]}): " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#entries[@]} ] || return 0
    entry=${DESKTOP_CHOICES[$((choice - 1))]}
    IFS='|' read -r key name pkgs norec dm session minram <<< "$entry"
    if [[ " $sessions " == *" $session "* ]]; then
        echo -e "${GREEN}✓ $name ya está instalado${NC}"
        return 0
    fi
    if [ "$ram" -lt "$minram" ]; then
        log_warning "$name pide al menos $minram MB de RAM y tienes $ram MB: irá lento (mejor Xfce o LXQt)"
        confirm "${YELLOW}¿Seguir igualmente?${NC}" || return 0
    fi

    # 5. Paquetes: se usa la primera alternativa que existe en esta versión de Ubuntu
    apt_update
    local list=() p alt
    for p in $pkgs; do
        if [[ "$p" == */* ]]; then
            alt=""
            for alt in ${p//\// }; do [ -n "$(available_pkgs "$alt")" ] && break; alt=""; done
            [ -n "$alt" ] || { log_error "Esta versión de Ubuntu no tiene ${p//\// ni }"; return 1; }
            list+=("$alt")
        else
            [ -n "$(available_pkgs "$p")" ] || { log_error "Esta versión de Ubuntu no tiene $p"; return 1; }
            list+=("$p")
        fi
    done
    local opts=()
    [ "$norec" = norec ] && opts+=(--no-install-recommends)

    # 6. Simulación: nada de quitar paquetes, y tiene que entrar en el disco
    local sim removed new size_mb free_mb
    if ! sim=$(LC_ALL=C apt-get -s install "${opts[@]}" "${list[@]}" 2>&1); then
        log_error "apt no puede instalar $name sin conflictos (detalles en $LOG_FILE)"
        echo "$sim" >> "$LOG_FILE"
        return 1
    fi
    removed=$(awk '/^Remv / {print $2}' <<< "$sim")
    if [ -n "$removed" ]; then
        log_error "Instalar $name quitaría estos paquetes, así que NO se instala nada:"
        printf "  ${RED}•${NC} %s\n" $removed
        return 1
    fi
    new=$(awk '/^Inst / {print $2}' <<< "$sim")
    size_mb=$(LC_ALL=C sudo apt-get install --assume-no "${opts[@]}" "${list[@]}" 2>/dev/null \
        | sed -n 's/^After this operation, \(.*\) of additional disk space.*/\1/p')
    size_mb=$(apt_size_to_mb "${size_mb:-0 MB}")
    free_mb=$(df -Pm / | awk 'NR == 2 {print $4}')
    echo -e "\n${BLUE}📋 $name${NC}"
    echo -e "   Paquetes nuevos: $(wc -w <<< "$new")   Espacio: ~${size_mb} MB   Libre en /: ${free_mb} MB"
    echo -e "   ${GREEN}✓ No se quita ningún paquete del sistema${NC}"
    if [ "$free_mb" -lt $((size_mb + 1024)) ]; then
        log_error "No hay espacio suficiente (hace falta ~$((size_mb + 1024)) MB contando un margen de 1 GB)"
        return 1
    fi
    [ -n "$SSH_CONNECTION" ] && echo -e "${YELLOW}ℹ Estás por SSH: si se corta, la instalación se interrumpe. Mejor usar tmux o screen.${NC}"
    confirm "${BLUE}¿Instalar $name?${NC}" || return 0

    # 7. Si ya había pantalla de inicio de sesión, se queda la misma
    [ -n "$old_dm" ] && echo "$old_dm shared/default-x-display-manager select $old_dm" | sudo debconf-set-selections

    mkdir -p "$STATE_DIR"
    run_visible "No se pudo instalar $name" sudo env DEBIAN_FRONTEND=noninteractive \
        apt-get install "${APT_OPTS[@]}" "${opts[@]}" "${list[@]}" || {
        echo "$new" > "$DESKTOP_PKGS_LIST.parcial"
        log_error "Quedó a medias: vuelve a intentarlo o usa la opción 1 para reparar"
        return 1
    }
    echo "$new" > "$DESKTOP_PKGS_LIST"
    {
        echo "clave=$key"
        echo "nombre=$name"
        echo "fecha=$(date '+%Y-%m-%d %H:%M')"
        echo "arranque_anterior=$(systemctl get-default 2>/dev/null)"
        echo "gestor_anterior=$old_dm"
    } > "$DESKTOP_STATE"

    # 8. Inicio gráfico (solo si antes no había escritorio)
    if [ -z "$old_dm" ]; then
        run "No se pudo activar el inicio gráfico" sudo systemctl set-default graphical.target
        [ -n "$dm" ] && sudo systemctl enable "$dm" >> "$LOG_FILE" 2>&1
    fi
    netplan_uses_networkd && switch_netplan_to_nm
    log_success "$name instalado. Reinicia para entrar al escritorio (opción 21)."
    echo -e "${CYAN}ℹ Al reiniciar, el script lo detecta y muestra las opciones de escritorio.${NC}"
    echo -e "${CYAN}  Se quita en la opción 10 → Quitar el escritorio instalado por el script.${NC}"
}

# Quita solo los paquetes que trajo el escritorio, y vuelve el arranque y la red a como estaban
remove_installed_desktop() {
    if [ ! -s "$DESKTOP_STATE" ] || [ ! -s "$DESKTOP_PKGS_LIST" ]; then
        echo -e "${YELLOW}ℹ El script no instaló ningún escritorio${NC}"
        return 0
    fi
    local name prev_target netplan_file pkgs=() sim removed extra
    name=$(grep '^nombre=' "$DESKTOP_STATE" | cut -d= -f2-)
    prev_target=$(grep '^arranque_anterior=' "$DESKTOP_STATE" | cut -d= -f2-)
    netplan_file=$(grep '^netplan=' "$DESKTOP_STATE" | cut -d= -f2-)
    # shellcheck disable=SC2046  # lista de paquetes: se separa a propósito
    mapfile -t pkgs < <(installed_pkgs $(cat "$DESKTOP_PKGS_LIST"))
    echo -e "${RED}🖥️ Quitar $name ($(grep '^fecha=' "$DESKTOP_STATE" | cut -d= -f2-)): ${#pkgs[@]} paquetes que trajo el script${NC}"
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo -e "${YELLOW}⚠ Estás dentro de un escritorio: lo más seguro es hacerlo desde una terminal de texto (Ctrl+Alt+F3)${NC}"
    fi
    if [ ${#pkgs[@]} -gt 0 ]; then
        sim=$(LC_ALL=C apt-get -s purge "${pkgs[@]}" 2>/dev/null)
        removed=$(awk '/^(Purg|Remv) / {print $2}' <<< "$sim")
        extra=$(grep -vxF -f <(printf '%s\n' "${pkgs[@]}") <<< "$removed")
        if [ -n "$extra" ]; then
            log_error "Quitarlo arrastraría paquetes que ya tenías antes, así que no se quita:"
            printf "  ${RED}•${NC} %s\n" $extra
            return 1
        fi
    fi
    confirm "${RED}¿Quitar $name? (tus archivos y configuraciones personales no se tocan)${NC}" || return 0
    if [ ${#pkgs[@]} -gt 0 ]; then
        apt_purge "${pkgs[@]}" || return 1
    fi
    [ -n "$prev_target" ] && run "No se pudo restaurar el modo de arranque" sudo systemctl set-default "$prev_target"
    if [ -n "$netplan_file" ] && [ -e "$netplan_file" ]; then
        sudo rm -f "$netplan_file"
        if [ -n "$SSH_CONNECTION" ]; then
            log_warning "La red vuelve a systemd-networkd al reiniciar (no se aplica ahora por estar en SSH)"
        else
            run "No se pudo aplicar la red" sudo netplan apply && log_success "La red vuelve a systemd-networkd"
        fi
    fi
    rm -f "$DESKTOP_STATE" "$DESKTOP_PKGS_LIST"
    log_success "$name quitado. Reinicia para terminar (opción 21)."
}

# ------------------------------------------------------------
# Quitar escritorios EXTRA (los que no instaló el script), a prueba de errores:
# - nunca el escritorio original del sabor ni el que está abierto
# - solo se quita lo que ese escritorio dejó de usar (no lo que ya sobraba antes)
# - si se llevara algo que usa otro escritorio, la red, el sonido o la pantalla de inicio, no se quita nada
# ------------------------------------------------------------
REMOVED_DESKTOPS_LIST="$STATE_DIR/escritorios-quitados.txt"

# clave|nombre|proceso cuando está abierto|paquetes principales (el primero instalado lo identifica)
EXTRA_DESKTOPS=(
    "kde|KDE Plasma|plasmashell|plasma-workspace kubuntu-desktop plasma-desktop kwin-x11 kwin-wayland"
    "gnome|GNOME|gnome-shell|gnome-shell ubuntu-desktop ubuntu-desktop-minimal gnome-session mutter"
    "xfce|Xfce|xfce4-session|xfce4-session xubuntu-desktop xubuntu-desktop-minimal xubuntu-core xfce4-panel xfwm4 xfdesktop4"
    "lxqt|LXQt|lxqt-session|lxqt-session lubuntu-desktop lxqt-panel"
    "mate|MATE|mate-session|mate-session-manager ubuntu-mate-desktop ubuntu-mate-core mate-panel marco"
    "budgie|Budgie|budgie-panel|budgie-desktop ubuntu-budgie-desktop ubuntu-budgie-desktop-minimal budgie-core"
    "cinnamon|Cinnamon|cinnamon|cinnamon ubuntucinnamon-desktop ubuntucinnamon-desktop-minimal cinnamon-session cinnamon-core"
)

# Lo que nunca se quita al sacar un escritorio
DESKTOP_KEEP_PKGS=(network-manager pipewire wireplumber pulseaudio xorg xserver-xorg-core xwayland
    sudo systemd dbus policykit-1 polkitd ubuntu-minimal ubuntu-standard grub-common linux-generic)

remove_extra_desktop() {
    clear
    echo -e "${RED}${BOLD}🖥️ QUITAR OTROS ESCRITORIOS${NC}\n"
    echo -e "${CYAN}Solo se ofrecen escritorios extra: nunca el original de ${FLAVOR_NAME} ni el que está abierto.${NC}"
    echo -e "${CYAN}Se simula antes: si se llevara algo que usa otro escritorio, no se quita nada.${NC}\n"

    local entry key name proc pkgs main script_key offer=() kept=() p
    script_key=$(grep '^clave=' "$DESKTOP_STATE" 2>/dev/null | cut -d= -f2-)
    script_key=${script_key%-min}
    for entry in "${EXTRA_DESKTOPS[@]}"; do
        IFS='|' read -r key name proc pkgs <<< "$entry"
        main=${pkgs%% *}
        installed_pkgs "$main" | grep -qx -- "$main" || continue
        if [ "$key" = "$DESKTOP" ]; then
            echo -e "  ${GREEN}🔒 $name: es el escritorio original de ${FLAVOR_NAME}${NC}"
            kept+=("$entry")
        elif pgrep -x "$proc" &> /dev/null; then
            echo -e "  ${GREEN}🔒 $name: está abierto ahora (ciérralo o entra en otro escritorio)${NC}"
            kept+=("$entry")
        elif [ "$key" = "$script_key" ]; then
            echo -e "  ${YELLOW}ℹ $name: lo instaló el script, se quita en 10 → 11${NC}"
            kept+=("$entry")
        else
            offer+=("$entry")
        fi
    done
    if [ ${#offer[@]} -eq 0 ]; then
        echo -e "\n${YELLOW}ℹ No hay escritorios extra para quitar${NC}"
        return 0
    fi

    echo ""
    local i=1 choice
    for entry in "${offer[@]}"; do
        IFS='|' read -r _ name _ _ <<< "$entry"
        printf "  ${RED}%d)${NC} %s\n" "$i" "$name"
        i=$((i + 1))
    done
    echo -e "  ${RED}0)${NC} Volver"
    read -r -p "🔢 Escritorio a quitar (0-${#offer[@]}): " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#offer[@]} ] || return 0
    IFS='|' read -r key name proc pkgs <<< "${offer[$((choice - 1))]}"

    # Paquetes principales que están instalados
    local targets=() before=() after=() rm_set=() dm protect=() hit=() extra=()
    # shellcheck disable=SC2086  # lista de paquetes: se separa a propósito
    mapfile -t targets < <(installed_pkgs $pkgs)
    # Lo que ya sobraba antes no es de este escritorio: no se toca
    mapfile -t before < <(LC_ALL=C apt-get -s autoremove 2>/dev/null | awk '/^(Purg|Remv) / {print $2}')
    if ! mapfile -t after < <(LC_ALL=C apt-get -s purge --autoremove "${targets[@]}" 2>/dev/null \
        | awk '/^(Purg|Remv) / {print $2}') || [ ${#after[@]} -eq 0 ]; then
        log_error "apt no puede calcular cómo quitar $name: no se cambió nada"
        return 1
    fi
    dm=$(current_display_manager)
    for p in "${after[@]}"; do
        printf '%s\n' "${before[@]}" | grep -qx -- "$p" && continue
        [ -n "$dm" ] && [ "$p" = "$dm" ] && continue    # la pantalla de inicio en uso se queda
        rm_set+=("$p")
    done

    # Lo que no se puede llevar: red, sonido, gráficos, sistema y los demás escritorios
    protect=("${DESKTOP_KEEP_PKGS[@]}")
    for entry in "${kept[@]}"; do
        IFS='|' read -r _ _ _ p <<< "$entry"
        # shellcheck disable=SC2206  # lista de paquetes: se separa a propósito
        protect+=($p)
    done
    mapfile -t hit < <(printf '%s\n' "${rm_set[@]}" | grep -xF -f <(printf '%s\n' "${protect[@]}"))
    if [ ${#hit[@]} -gt 0 ]; then
        log_error "Quitar $name se llevaría piezas que usa el sistema u otro escritorio, así que no se quita nada:"
        printf "  ${RED}•${NC} %s\n" "${hit[@]}"
        return 1
    fi
    # Comprobación final: apt no puede quitar nada fuera de la lista
    mapfile -t extra < <(LC_ALL=C apt-get -s purge "${rm_set[@]}" 2>/dev/null | awk '/^(Purg|Remv) / {print $2}' \
        | grep -vxF -f <(printf '%s\n' "${rm_set[@]}"))
    if [ ${#extra[@]} -gt 0 ]; then
        log_error "Quitar $name arrastraría programas que ya tenías, así que no se quita nada:"
        printf "  ${RED}•${NC} %s\n" "${extra[@]}"
        return 1
    fi

    echo -e "\n${RED}📋 Se quitarán ${#rm_set[@]} paquetes de $name:${NC}"
    printf '%s\n' "${rm_set[@]}" | head -40 | tr '\n' ' ' | fold -s -w 94 | sed 's/^/   /'; echo
    [ ${#rm_set[@]} -gt 40 ] && echo -e "   ${YELLOW}... y $(( ${#rm_set[@]} - 40 )) más (lista completa en $LOG_FILE)${NC}"
    printf '%s\n' "${rm_set[@]}" >> "$LOG_FILE"
    [ -n "$dm" ] && echo -e "   ${GREEN}✓ Se mantiene tu pantalla de inicio de sesión ($dm)${NC}"
    echo -e "   ${GREEN}✓ Tus archivos y configuraciones personales no se tocan${NC}"
    confirm "${RED}¿Quitar $name?${NC}" || { echo -e "${YELLOW}ℹ Cancelado: no se quitó nada${NC}"; return 0; }

    apt_purge "${rm_set[@]}" || return 1
    mkdir -p "$STATE_DIR"
    echo "$(date '+%Y-%m-%d %H:%M')|$name|${rm_set[*]}" >> "$REMOVED_DESKTOPS_LIST"
    log_success "$name quitado (${#rm_set[@]} paquetes). Para volver a tenerlo: opción 7 → Instalar un ESCRITORIO."
}
#@parte apt: migrate_snap_profiles install_firefox_deb firefox_mozilla_installed remove_mozilla_repo firefox_nosnap_installed install_firefox

BRAVE_KEYRING="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
BRAVE_LIST="/etc/apt/sources.list.d/brave-browser-release.list"
#@parte apt: brave_installed install_brave

# Chromium sin Snap
CHROMIUM_FLATPAK=org.chromium.Chromium
#@parte apt: chromium_flatpak_installed chromium_deb_installed chromium_installed install_chromium_flatpak

install_chromium() {
    echo -e "${BLUE}🌐 Chromium (la base libre de Chrome, sin cuenta de Google ni Snap)${NC}"
    if chromium_installed; then
        echo -e "  ${GREEN}✓ Chromium ya está instalado${NC}"
        return 0
    fi
    # En Ubuntu el paquete chromium de apt solo instala el snap: se usa Flathub
    echo -e "${CYAN}ℹ En Ubuntu, apt solo trae Chromium como Snap: se instala desde Flathub${NC}"
    install_chromium_flatpak
}

# ============================================================
# OPCIÓN 7: SOFTWARE OPCIONAL (COLOR: AZUL)
# ============================================================

# ------------------------------------------------------------
# Más navegadores: Microsoft Edge, Tor Browser y SeaMonkey
# ------------------------------------------------------------
EDGE_KEYRING="/usr/share/keyrings/microsoft-edge.gpg"
EDGE_LIST="/etc/apt/sources.list.d/microsoft-edge.list"
#@parte apt: setup_edge_repo

# Tor Browser: torbrowser-launcher (repositorios oficiales) baja el navegador del sitio de Tor y
# verifica su firma; se actualiza solo. Si la distro no lo tiene (Debian sin contrib), desde Flathub.
TOR_FLATPAK=org.torproject.torbrowser-launcher
#@parte apt: tor_installed install_tor

# SeaMonkey (navegador, correo, editor HTML y chat de la comunidad de Mozilla): no está en los
# repositorios de ninguna distribución, se baja la versión oficial a /opt/seamonkey
SEAMONKEY_DIR="/opt/seamonkey"
SEAMONKEY_PAGE="https://www.seamonkey-project.org/releases/"
#@parte comun: seamonkey_installed install_seamonkey remove_seamonkey
#@parte apt: install_torbrowser_launcher

select_optional_software() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    📦 SOFTWARE OPCIONAL                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local software=(
        "escritorio|🖥️ Instalar un ESCRITORIO (KDE Plasma, GNOME, Xfce, LXQt...)"
        "firefox|🦊 Firefox (el de Mozilla, sin Snap)"
        "google-chrome-stable|🌐 Google Chrome"
        "chromium|🌐 Chromium (Chrome libre, desde Flathub, sin Snap)"
        "brave|🦁 Brave (con bloqueo de anuncios)"
        "microsoft-edge-stable|🌐 Microsoft Edge (navegador de Microsoft)"
        "torbrowser-launcher|🧅 Tor Browser (navegación anónima por la red Tor)"
        "seamonkey|🐒 SeaMonkey (navegador, correo y editor HTML)"
        "telegram-desktop|📱 Telegram"
        "discord|🎮 Discord"
        "filezilla|📁 Cliente FTP/SFTP"
        "telnet|📞 Telnet (cliente: conectarse a otros equipos o probar puertos)"
        "code|📝 Visual Studio Code"
        "virtualbox|🖥️ VirtualBox"
        "python3|🐍 Python 3"
        "python3-pip|📦 PIP"
        "python3-venv|📦 Entornos virtuales"
        "git|📚 Git"
        "curl|🌐 CURL"
        "wget|⬇️ Wget"
        "htop|📊 HTOP"
        "fastfetch|🖥️ Fastfetch"
        "timeshift|⏰ Timeshift"
        "gparted|💾 GParted"
        "vim|⌨️ Vim"
        "steam|🎮 Steam (con Proton para juegos de Windows)"
        "proton-ge|🍷 Proton-GE (Proton de la comunidad, más compatible)"
        "spotify|🎵 Spotify"
        "obs-studio|🎥 OBS Studio"
        "emojier|😊 Selector de emojis"
        "qrca|📱 Generador de códigos QR"
        "android-tools|🤖 Compilar APK: Java + SDK Android + adb (~3 GB)"
        "android-studio|🤖 Android Studio con emulador (Google o Snap, ~10 GB)"
        "flatpak|📦 Flatpak + Flathub: instalar apps Flatpak"
        "flatpak-builder|🛠️ Compilar Flatpaks: flatpak-builder + el SDK que elijas"
        "docker|🐳 Docker + Compose (compilar con el Dockerfile)"
    )

    # Se marca lo que ya está instalado para no reinstalarlo por error
    local installed=() entries=() app pkg
    mapfile -t installed < <(installed_pkgs "${software[@]%%|*}" spotify-client kdeplasma-addons)
    steam_installed && installed+=(steam)
    [ -n "$(ls -d "$(steam_dir)"/compatibilitytools.d/GE-Proton* 2>/dev/null)" ] && installed+=(proton-ge)
    android_tools_installed && installed+=(android-tools)
    android_studio_installed && installed+=(android-studio)
    docker_installed && installed+=(docker)
    firefox_nosnap_installed && installed+=(firefox)
    brave_installed && installed+=(brave)
    tor_installed && installed+=(torbrowser-launcher)
    seamonkey_installed && installed+=(seamonkey)
    chromium_installed && installed+=(chromium)
    [ -s "$DESKTOP_STATE" ] && installed+=(escritorio)
    for app in "${software[@]}"; do
        pkg=${app%%|*}
        case $pkg in
            spotify) pkg=spotify-client ;;
            emojier) pkg=kdeplasma-addons ;;
        esac
        if printf '%s\n' "${installed[@]}" | grep -qx -- "$pkg"; then
            entries+=("${app} (ya instalado)")
        else
            entries+=("$app")
        fi
    done

    SELECTED_OPTIONAL=()
    if checklist_select "Software opcional" "Marca los programas que quieres INSTALAR" "${entries[@]}"; then
        SELECTED_OPTIONAL=("${CHOSEN[@]}")
    fi
    clear

    if [ ${#SELECTED_OPTIONAL[@]} -gt 0 ]; then
        echo -e "${BLUE}📋 Se instalarán:${NC}"
        printf "  ${BLUE}•${NC} %s\n" "${SELECTED_OPTIONAL[@]}"
        echo ""
    else
        echo -e "${YELLOW}ℹ No seleccionaste ningún programa${NC}"
    fi

    if [ ${#SELECTED_OPTIONAL[@]} -gt 0 ]; then
        echo ""
        if confirm "${BLUE}¿Instalar los ${#SELECTED_OPTIONAL[@]} programas seleccionados?${NC}"; then
            install_optional_with_progress "${SELECTED_OPTIONAL[@]}"
        fi
    fi

    pause
}
#@parte apt: core_pkgs_removed_by

remove_apps_with_progress() {
    local installed=() safe=() app core extra=()

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    mapfile -t installed < <(installed_pkgs "$@")
    if ! $AUTO_MODE; then
        for app in "$@"; do
            printf '%s\n' "${installed[@]}" | grep -qx -- "$app" || echo -e "  ${YELLOW}⚠ No instalado: $app${NC}"
        done
    fi

    # Ninguna app se quita si arrastra el escritorio, la sesión, la red, el sonido...
    for app in "${installed[@]}"; do
        core=$(core_pkgs_removed_by "$app" | tr '\n' ' ')
        if [ -n "$core" ]; then
            echo -e "  ${RED}🛡 No se quita $app: arrastraría piezas esenciales del sistema (${core% })${NC}"
        else
            safe+=("$app")
        fi
    done
    installed=("${safe[@]}")

    # Lo que apt quitaría además por dependencias
    if [ ${#installed[@]} -gt 0 ]; then
        mapfile -t extra < <(LC_ALL=C apt-get -s purge "${installed[@]}" 2>/dev/null \
            | awk '/^(Purg|Remv) / {print $2}' | grep -vxF -f <(printf '%s\n' "${installed[@]}"))
        if [ ${#extra[@]} -gt 0 ]; then
            echo -e "${YELLOW}⚠ También se quitarán porque dependen de ellas:${NC}"
            print_pkgs_described "${extra[@]}"
            if ! $AUTO_MODE && ! confirm "${CYAN}¿Continuar igualmente?${NC}"; then
                echo -e "${YELLOW}ℹ Cancelado: no se eliminó nada${NC}"
                return 0
            fi
        fi
    fi

    if [ ${#installed[@]} -gt 0 ]; then
        echo -e "${CYAN}🗑 Eliminando ${#installed[@]} aplicaciones en una sola operación...${NC}"
        if purge_and_record "${installed[@]}"; then
            for app in "${installed[@]}"; do
                echo -e "  ${GREEN}✓ Eliminado: $app${NC}"
            done
        else
            log_warning "Reintentando una por una..."
            for app in "${installed[@]}"; do
                if purge_and_record "$app" > /dev/null; then
                    echo -e "  ${GREEN}✓ Eliminado: $app${NC}"
                else
                    echo -e "  ${RED}✗ No se pudo eliminar: $app${NC}"
                fi
            done
        fi
    fi

    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    $AUTO_MODE || echo -e "${CYAN}ℹ Para quitar los íconos del escritorio o del panel usa la opción 6${NC}"
    echo ""
}
#@parte apt: setup_spotify_repo

# Instala todo en una sola operación de apt. Los .deb externos (VSCode, Chrome,
# Discord) se descargan en paralelo mientras se actualiza la lista de paquetes.
install_optional_with_progress() {
    local repo=() deb_names=() deb_urls=() pids=() debs=() failed=() app i
    local repo_changed=false tmp want_steam=false want_ge=false want_extra=()
    tmp=$(mktemp -d)
    chmod 755 "$tmp"

    echo -e "${BLUE}📦 Instalando software...${NC}"
    command -v wget &> /dev/null || { apt_update; apt_install wget; }

    for app in "$@"; do
        case $app in
            "code") deb_names+=(code); deb_urls+=("https://go.microsoft.com/fwlink/?LinkID=760868") ;;
            "fastfetch")
                # No está en los repositorios de Ubuntu 24.04 y anteriores: .deb oficial del proyecto
                if [ -n "$(available_pkgs fastfetch)" ]; then
                    repo+=(fastfetch)
                else
                    local ff_arch
                    ff_arch=$(dpkg --print-architecture)
                    [ "$ff_arch" = "arm64" ] && ff_arch=aarch64
                    deb_names+=(fastfetch)
                    deb_urls+=("https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-$ff_arch.deb")
                fi ;;
            "google-chrome-stable") deb_names+=(google-chrome-stable); deb_urls+=("https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb") ;;
            "discord") deb_names+=(discord); deb_urls+=("https://discord.com/api/download?platform=linux&format=deb") ;;
            "spotify")
                if setup_spotify_repo; then
                    repo+=(spotify-client)
                    repo_changed=true
                else
                    failed+=(spotify)
                fi ;;
            "emojier") repo+=(kdeplasma-addons) ;;
            "microsoft-edge-stable")
                if setup_edge_repo; then
                    repo+=(microsoft-edge-stable)
                    repo_changed=true
                else
                    failed+=(microsoft-edge)
                fi ;;
            # Necesitan pasos propios (32 bits, verificación): se instalan al final
            "steam") want_steam=true ;;
            "proton-ge") want_ge=true ;;
            # Descargas grandes con pasos propios: van al final, en este orden
            "android-tools"|"android-studio"|"flatpak"|"flatpak-builder"|"docker"|"firefox"|"brave"|"chromium"|"torbrowser-launcher"|"seamonkey"|"escritorio") want_extra+=("$app") ;;
            *) repo+=("$app") ;;
        esac
    done

    for i in "${!deb_urls[@]}"; do
        echo -e "${BLUE}  ⬇ Descargando ${deb_names[$i]}...${NC}"
        wget -qO "$tmp/${deb_names[$i]}.deb" "${deb_urls[$i]}" >> "$LOG_FILE" 2>&1 &
        pids+=($!)
    done

    if $repo_changed; then
        apt_update force
    else
        apt_update
    fi

    # Paquetes que no existen en tus repositorios: se avisan sin romper el resto
    if [ ${#repo[@]} -gt 0 ]; then
        local available=() missing
        mapfile -t available < <(available_pkgs "${repo[@]}" | sort -u)
        for app in "${repo[@]}"; do
            if ! printf '%s\n' "${available[@]}" | grep -qx -- "$app"; then
                log_error "No disponible en tus repositorios: $app"
                failed+=("$app")
            fi
        done
        repo=("${available[@]}")
    fi

    for i in "${!pids[@]}"; do
        if wait "${pids[$i]}" && [ -s "$tmp/${deb_names[$i]}.deb" ]; then
            chmod 644 "$tmp/${deb_names[$i]}.deb"
            debs+=("$tmp/${deb_names[$i]}.deb")
        else
            log_error "No se pudo descargar ${deb_names[$i]}"
            failed+=("${deb_names[$i]}")
        fi
    done

    local all=("${repo[@]}" "${debs[@]}")
    if [ ${#all[@]} -gt 0 ]; then
        echo -e "${BLUE}📦 Instalando ${#all[@]} paquetes en una sola operación...${NC}"
        if apt_install_recorded "${all[@]}"; then
            for app in "${all[@]}"; do
                echo -e "  ${GREEN}✓ Instalado: $(basename "$app" .deb)${NC}"
            done
        else
            log_warning "Reintentando uno por uno..."
            for app in "${all[@]}"; do
                if apt_install_recorded "$app" > /dev/null; then
                    echo -e "  ${GREEN}✓ Instalado: $(basename "$app" .deb)${NC}"
                else
                    failed+=("$(basename "$app" .deb)")
                fi
            done
        fi
    fi
    rm -rf "$tmp"

    if $want_steam; then install_steam || failed+=(steam); fi
    if $want_ge; then install_proton_ge || failed+=(proton-ge); fi
    for app in escritorio firefox brave chromium torbrowser-launcher seamonkey android-tools android-studio flatpak flatpak-builder docker; do
        [[ " ${want_extra[*]} " == *" $app "* ]] || continue
        # flatpak-builder ya instala Flatpak si hace falta
        [ "$app" = flatpak ] && [[ " ${want_extra[*]} " == *" flatpak-builder "* ]] && continue
        echo ""
        "install_${app//-/_}" || failed+=("$app")
    done

    if [ ${#failed[@]} -gt 0 ]; then
        log_error "No se pudieron instalar: ${failed[*]}"
        return 1
    fi
}

# ============================================================
# OPCIÓN 11: REVERTIR CAMBIOS (COLOR: ROJO)
# ============================================================

# Vuelve a las versiones de los repositorios oficiales los paquetes que vinieron
# de un PPA ya eliminado (quitar el PPA no baja las versiones por sí solo)
downgrade_orphaned_ppa_pkgs() {
    local targets=() line pkg inst cand
    # shellcheck disable=SC2046  # listas de paquetes: se separan a propósito
    while read -r line; do
        read -r pkg inst cand <<< "$line"
        dpkg --compare-versions "$inst" gt "$cand" && targets+=("$pkg=$cand")
    done < <(apt-cache policy $(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' | awk '$1 ~ /^.i/ {print $2}') 2>/dev/null \
        | awk '/^[^ ]/ {p = $1; sub(/:$/, "", p)}
               /^  Installed:/ {i = $2}
               /^  Candidate:/ && $2 != "(none)" && $2 != i {print p, i, $2}')

    if [ ${#targets[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No hay paquetes que bajar de versión${NC}"
        return 0
    fi
    echo -e "  ${RED}↓ Bajando ${#targets[@]} paquetes a la versión oficial (puede tardar)...${NC}"
    apt_install --allow-downgrades "${targets[@]}" && log_success "Paquetes de backports revertidos"
}

# Instala los paquetes que falten; si el lote falla, los intenta uno a uno
install_missing_pkgs() {
    local available=() missing=() failed=() p
    # shellcheck disable=SC2046  # listas de paquetes: se separan a propósito
    mapfile -t available < <(available_pkgs $(printf '%s\n' "$@" | sort -u) | sort -u)
    [ ${#available[@]} -gt 0 ] && mapfile -t missing < <(comm -23 \
        <(printf '%s\n' "${available[@]}") <(installed_pkgs "${available[@]}" | sort -u))

    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ Todos los paquetes de ${FLAVOR_NAME} ya están instalados${NC}"
        return 0
    fi
    echo -e "  ${RED}📦 Instalando ${#missing[@]} paquetes: ${missing[*]}${NC}"
    if apt_install "${missing[@]}"; then
        log_success "Paquetes reinstalados"
        return 0
    fi

    log_warning "Reintentando los paquetes uno a uno..."
    for p in "${missing[@]}"; do
        apt_install "$p" > /dev/null || failed+=("$p")
    done
    if [ ${#failed[@]} -gt 0 ]; then
        log_error "No se pudieron reinstalar: ${failed[*]}"
        return 1
    fi
    log_success "Paquetes reinstalados"
}
#@parte comun: restore_theme

# Quita el repositorio de Mozilla (Firefox .deb) y vuelve al Firefox de Ubuntu
restore_ubuntu_firefox() {
    sudo rm -f /etc/apt/sources.list.d/mozilla.list /etc/apt/preferences.d/mozilla \
        /etc/apt/keyrings/packages.mozilla.org.asc
    forget_installed firefox
    apt_update force
    # El paquete de Ubuntu instala el snap; los marcadores de ~/.mozilla se importan al abrirlo
    if installed_pkgs firefox | grep -qx firefox; then
        apt_install --allow-downgrades firefox && log_success "Firefox de Ubuntu reinstalado"
    fi
}

revert_changes() {
    clear
    echo -e "${RED}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                ⏪ REVERTIR A DISTRIBUCIÓN ORIGINAL               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}🐧 Distribución detectada: ${FLAVOR_NAME} (${DESKTOP_NAME})${NC}"

    local removed_count=0 backports=false mozilla=false keep_firefox=false
    [ -f "$REMOVED_LIST" ] && removed_count=$(wc -l < "$REMOVED_LIST")
    grep -rqs 'kubuntu-ppa/backports' /etc/apt/sources.list /etc/apt/sources.list.d/ && backports=true
    [ -f /etc/apt/sources.list.d/mozilla.list ] && mozilla=true

    echo -e "\n${RED}📋 Esto hará:${NC}"
    $backports && echo -e "  • Quitar KDE Rolling Release (PPA backports) y volver Plasma a la versión oficial"
    echo -e "  • Desbloquear y reinstalar Snap y las apps snap que se quitaron"
    $mozilla && echo -e "  • Volver al Firefox de Ubuntu (se pregunta antes)"
    if [ -n "$FLAVOR_META" ]; then
        echo -e "  • Reinstalar ${FLAVOR_META} y todas las apps de ${FLAVOR_NAME}"
    fi
    [ "$removed_count" -gt 0 ] && echo -e "  • Reinstalar los $removed_count paquetes eliminados con este script"
    if has_desktop; then
        echo -e "  • Restaurar los accesos directos del escritorio y del panel"
        echo -e "  • Restaurar el tema del escritorio (si el script lo cambió)"
    fi
    echo -e "  • Volver a los valores de fábrica los ajustes del script (RAM, DNS, ZRAM, energía...)"
    echo -e "\n${YELLOW}ℹ No cambia el kernel (opción 14) ni el arranque (opción 19). Los programas que instaló${NC}"
    echo -e "${YELLOW}  el script se quitan desde la opción 10.${NC}"
    echo ""

    if ! confirm "${RED}⚠ ¿Revertir a la distribución original (${FLAVOR_NAME})?${NC}"; then
        return 0
    fi
    if $mozilla && ! confirm "${YELLOW}¿Volver al Firefox de Ubuntu (snap)? Si dices que no, sigues con el de Mozilla (.deb)${NC}"; then
        keep_firefox=true
    fi

    echo -e "${RED}[1/6] Repositorios...${NC}"
    if $backports; then
        run "No se pudo quitar el PPA backports" sudo add-apt-repository --remove -y ppa:kubuntu-ppa/backports
        apt_update force
        downgrade_orphaned_ppa_pkgs
    else
        echo -e "  ${GREEN}✓ KDE Rolling Release no está activo${NC}"
        apt_update
    fi

    echo -e "${RED}[2/6] Desbloqueando Snap...${NC}"
    # La eliminación nuclear (opción 5) bloquea snapd; hay que desbloquearlo antes
    sudo apt-mark unhold snapd >> "$LOG_FILE" 2>&1
    sudo rm -f /etc/apt/preferences.d/nosnap.pref
    if $mozilla && ! $keep_firefox; then
        restore_ubuntu_firefox
    fi

    echo -e "${RED}[3/6] Reinstalando paquetes de ${FLAVOR_NAME}...${NC}"
    local pkgs=()
    if [ -n "$FLAVOR_META" ]; then
        mapfile -t pkgs < <(flavor_meta_pkgs)
        pkgs+=("$FLAVOR_META")
    fi
    pkgs+=(snapd)
    [ -f "$REMOVED_LIST" ] && mapfile -t -O "${#pkgs[@]}" pkgs < "$REMOVED_LIST"
    # Con el Firefox de Mozilla, no se reinstala el de Ubuntu (que lo cambiaría por el snap)
    if $keep_firefox; then
        mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vx firefox)
    fi
    if install_missing_pkgs "${pkgs[@]}"; then
        rm -f "$REMOVED_LIST"
    fi
    run "No se pudo iniciar snapd" sudo systemctl enable --now snapd.socket

    echo -e "${RED}[4/6] Reinstalando apps snap...${NC}"
    if $keep_firefox; then restore_removed_snaps firefox; else restore_removed_snaps; fi

    echo -e "${RED}[5/6] Restaurando escritorio...${NC}"
    if has_desktop; then
        restore_desktop_shortcuts
        restore_panel_launchers
        restore_theme
    else
        echo -e "  ${GREEN}✓ Sin escritorio: no hay accesos ni tema que restaurar${NC}"
    fi

    echo -e "${RED}[6/6] Restaurando ajustes y limpiando configuraciones...${NC}"
    restore_all_tweaks
    rm -rf ~/.config/alacritty
    rm -f "$HOME/.config/environment.d/90-mangohud.conf"

    echo ""
    echo -e "${GREEN}✓ ${FLAVOR_NAME} revertido a su estado original${NC}"
    echo -e "${YELLOW}⚠ Reinicia para completar${NC}"
    pause
}

# ============================================================
# OPCIÓN 5: ELIMINACIÓN NUCLEAR DE SNAP (COLOR: ROJO)
# ============================================================

REMOVED_SNAPS="$STATE_DIR/snaps-eliminados.txt"

# Anota las apps snap instaladas ("nombre" o "nombre classic") para poder reinstalarlas
record_removed_snaps() {
    local list
    # Solo apps: los runtimes (temas, bibliotecas de GNOME/KDE, mesa...) llegan solos con ellas
    list=$(snap list 2>/dev/null | awk 'NR>1 && $NF !~ /base|core|snapd/ && $1 !~ /^(gtk-common-themes|gtk2-common-themes|gnome-[0-9]|kf[56]-|mesa-|bare$)/ {
        print $1 ($NF ~ /classic/ ? " classic" : "")}')
    [ -n "$list" ] || return 0
    mkdir -p "$STATE_DIR"
    echo "$list" >> "$REMOVED_SNAPS"
    sort -u -o "$REMOVED_SNAPS" "$REMOVED_SNAPS"
}

# Reinstala las apps snap que quitó la eliminación nuclear (opción 5 o perfil minimalista).
# Los argumentos son snaps que no se reinstalan (p. ej. firefox si se queda el de Mozilla).
restore_removed_snaps() {
    local name mode failed=() wanted=() skip=" $* "
    if [ -s "$REMOVED_SNAPS" ]; then
        mapfile -t wanted < "$REMOVED_SNAPS"
    elif [[ "$FLAVOR" == ubuntu || "$FLAVOR" == edubuntu ]]; then
        # Versiones anteriores del script no las anotaban: las que trae Ubuntu de fábrica
        wanted=(snap-store firmware-updater snapd-desktop-integration)
    fi
    if [ ${#wanted[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No hay apps snap que reinstalar${NC}"
        return 0
    fi
    command -v snap &> /dev/null || { log_warning "Snap no está instalado: no se reinstalan sus apps"; return 1; }
    sudo snap wait system seed.loaded >> "$LOG_FILE" 2>&1
    for name in "${wanted[@]}"; do
        read -r name mode <<< "$name"
        [[ "$skip" == *" $name "* ]] && continue
        if snap list "$name" &> /dev/null; then
            echo -e "  ${GREEN}✓ $name ya está instalado${NC}"
        elif sudo snap install "$name" ${mode:+--classic} >> "$LOG_FILE" 2>&1; then
            echo -e "  ${GREEN}✓ Reinstalado: $name${NC}"
        else
            failed+=("$name")
        fi
    done
    if [ ${#failed[@]} -gt 0 ]; then
        log_error "No se pudieron reinstalar los snaps: ${failed[*]}"
        return 1
    fi
    rm -f "$REMOVED_SNAPS"
}

do_snap_removal() {
    echo -e "${RED}☢️ Iniciando eliminación nuclear de Snap...${NC}\n"

    # Al borrar el snap se pierden marcadores y contraseñas: se copian antes a la ruta normal
    migrate_snap_profiles

    # Los snaps se eliminan mientras snapd sigue activo: sin el demonio 'snap remove' no funciona
    echo -e "${RED}[1/11] Eliminando paquetes snap de aplicaciones...${NC}"
    record_removed_snaps
    local snap_name
    for snap_name in $(snap list 2>/dev/null | awk 'NR>1 && $NF !~ /base|core|snapd/ {print $1}'); do
        run "No se pudo eliminar el snap $snap_name" sudo snap remove --purge "$snap_name"
    done

    echo -e "${RED}[2/11] Eliminando snaps del sistema (bases y runtimes)...${NC}"
    # Se repite porque unas bases dependen de otras (p. ej. gtk-common-themes → core)
    local _
    for _ in 1 2 3; do
        for snap_name in $(snap list 2>/dev/null | awk 'NR>1 && $1 != "snapd" {print $1}'); do
            sudo snap remove --purge "$snap_name" >> "$LOG_FILE" 2>&1
        done
    done
    sudo snap remove --purge snapd >> "$LOG_FILE" 2>&1

    echo -e "${RED}[3/11] Deteniendo servicios snap...${NC}"
    sudo systemctl stop snapd.socket snapd.service >> "$LOG_FILE" 2>&1
    sudo systemctl disable snapd.socket snapd.service >> "$LOG_FILE" 2>&1

    echo -e "${RED}[4/11] Terminando procesos snap...${NC}"
    sudo pkill -x snapd 2>/dev/null

    echo -e "${RED}[5/11] Desmontando directorios loop...${NC}"
    for mnt in $(mount | grep -E 'snap|/snap/' | awk '{print $3}'); do
        sudo umount "$mnt" 2>/dev/null
    done

    echo -e "${RED}[6/11] Eliminando paquetes snapd...${NC}"
    local snap_pkgs
    mapfile -t snap_pkgs < <(installed_pkgs snapd gnome-software-plugin-snap snapd-xdg-open plasma-discover-backend-snap)
    [ ${#snap_pkgs[@]} -gt 0 ] && purge_and_record "${snap_pkgs[@]}"
    run "Falló autoremove" sudo env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" autoremove --purge

    echo -e "${RED}[7/11] Bloqueando reinstalación...${NC}"
    echo 'Package: snapd
Pin: release *
Pin-Priority: -1' | sudo tee /etc/apt/preferences.d/nosnap.pref > /dev/null

    echo -e "${RED}[8/11] Eliminando directorios de Snap...${NC}"
    sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd 2>/dev/null
    sudo rm -rf /etc/systemd/system/snapd.* 2>/dev/null

    echo -e "${RED}[9/11] Eliminando configuraciones de usuario...${NC}"
    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            sudo rm -rf "$user_home/snap" "$user_home/.cache/snap" "$user_home/.config/snap" 2>/dev/null
        fi
    done
    sudo rm -rf ~/snap 2>/dev/null

    echo -e "${RED}[10/11] Eliminando binarios residuales...${NC}"
    sudo rm -rf /usr/bin/snap /usr/bin/snapctl /usr/lib/snapd 2>/dev/null

    echo -e "${RED}[11/11] Limpieza final...${NC}"
    run "Falló autoclean" sudo apt-get autoclean -y

}

nuclear_snap_removal() {
    clear
    echo -e "${RED}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    💥 ELIMINACIÓN NUCLEAR DE SNAP                ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "\n${RED}${BOLD}⚠️ ⚠️ ⚠️  ADVERTENCIA  ⚠️ ⚠️ ⚠️${NC}"
    echo -e "${RED}Esta acción es IRREVERSIBLE y eliminará COMPLETAMENTE Snap${NC}\n"
    echo -e "${RED}📋 Lo que se eliminará:${NC}"
    echo -e "  • Todos los paquetes snap instalados"
    echo -e "  • El servicio snapd y su demonio"
    echo -e "  • Todos los directorios de Snap"
    echo -e "  • Configuraciones y cachés"
    echo ""

    if ! confirm "${RED}¿Estás ABSOLUTAMENTE seguro de eliminar Snap para siempre?${NC}"; then
        echo -e "${YELLOW}❌ Eliminación nuclear cancelada${NC}"
        pause
        return 1
    fi

    if ! confirm "${RED}ÚLTIMA ADVERTENCIA: ¿Confirmar eliminación TOTAL de Snap?${NC}"; then
        echo -e "${YELLOW}❌ Eliminación nuclear cancelada${NC}"
        pause
        return 1
    fi

    do_snap_removal

    echo -e "${CYAN}ℹ Sin Snap, Ubuntu no trae Firefox. Puedes instalarlo como .deb del repositorio de Mozilla.${NC}"
    echo -e "${CYAN}  Si lo instalas y después no lo quieres: opción 10 → Quitar programas.${NC}"
    if confirm "${BLUE}¿Instalar Firefox .deb (repositorio oficial de Mozilla)?${NC}"; then
        install_firefox_deb
    fi
    echo ""
    echo -e "${GREEN}✓ ¡ELIMINACIÓN NUCLEAR DE SNAP COMPLETADA!${NC}"
    echo -e "${YELLOW}⚠ Snap ha sido borrado y bloqueado (la opción 9 permite reinstalarlo)${NC}"
    pause
}

# ============================================================
# OPCIÓN 9: REINSTALAR SNAP (COLOR: VERDE)
# ============================================================

reinstall_snap() {
    clear
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔄 REINSTALAR SNAP                            ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "\n${YELLOW}⚠ Esta opción reinstalará Snap en el sistema${NC}\n"
    echo -e "${GREEN}📋 Lo que se reinstalará:${NC}"
    echo -e "  • snapd (servicio de Snap)"
    echo -e "  • ubuntu-advantage-tools (Ubuntu Pro)"
    echo -e "  • Directorios necesarios"
    echo ""

    if ! confirm "¿Reinstalar Snap?"; then
        return 0
    fi

    echo -e "${GREEN}🔄 Reinstalando Snap...${NC}\n"

    echo -e "${GREEN}[1/5] Eliminando bloqueos previos...${NC}"
    sudo apt-mark unhold snapd 2>/dev/null
    sudo rm -f /etc/apt/preferences.d/nosnap.pref 2>/dev/null

    echo -e "${GREEN}[2/5] Instalando snapd...${NC}"
    apt_update
    if ! apt_install snapd; then
        pause
        return 1
    fi

    echo -e "${GREEN}[3/5] Instalando Ubuntu Pro client...${NC}"
    apt_install ubuntu-advantage-tools

    echo -e "${GREEN}[4/5] Creando directorios necesarios...${NC}"
    sudo mkdir -p /snap /var/snap /var/lib/snapd

    echo -e "${GREEN}[5/5] Iniciando servicios...${NC}"
    run "No se pudo iniciar snapd" sudo systemctl enable --now snapd.socket snapd.service
    if [ -s "$REMOVED_SNAPS" ] && confirm "${GREEN}¿Reinstalar también las apps snap que se quitaron ($(wc -l < "$REMOVED_SNAPS"))?${NC}"; then
        restore_removed_snaps
    fi

    echo ""
    echo -e "${GREEN}✓ Snap reinstalado correctamente${NC}"
    echo -e "${BLUE}📦 Para instalar Firefox Snap: sudo snap install firefox${NC}"
    echo -e "${BLUE}🔑 Para Ubuntu Pro: sudo pro attach [token] (gratuito en ubuntu.com/pro/dashboard)${NC}"
    pause
}
#@parte arranque: datos_boot_root boot_os_value boot_has_cmd on_target boot_detect boot_find_esp boot_find_efi_id grub_available grub_required grub_uses_bls grub_update grub_set_default grub_editenv_list grub_probe grub_packages boot_pkg_supported
#@parte apt: boot_pkg_installed boot_pkg_install boot_pkg_reinstall
#@parte arranque: boot_pkg_remove boot_grubd_owned grub_install_uefi grub_install_bios is_live_session boot_option_ok boot_option_reason boot_option boot_section grub_repair_menu boot_report grub_diagnostic grub_normal_repair grub_reinstall_to_disk grub_guide_header guide_my_commands grub_prompt_guide grub_rescue_guide grub_live_guide datos_rescue_mnt linux_partitions unlock_encrypted_partitions rescue_umount rescue_grub_install

grub_live_repair() {
    grub_guide_header "🚑 REPARAR GRUB DESDE LIVE USB"

    if ! is_live_session; then
        log_warning "Esto no parece una sesión Live USB"
        echo -e "${YELLOW}  Esta opción es para cuando el sistema no arranca: inicia desde un USB de instalación${NC}"
        echo -e "${YELLOW}  de tu distribución (modo \"Probar\" o Live), abre una terminal y ejecuta este script.${NC}"
        echo -e "${YELLOW}  Si el sistema arranca, usa la opción 2 (RÁPIDA) o 3 (COMPLETA).${NC}\n"
        if ! confirm "${PURPLE}¿Continuar de todos modos?${NC}"; then
            return 0
        fi
    fi

    local uefi=false
    [ -d /sys/firmware/efi ] && uefi=true
    if $uefi; then
        echo -e "${PURPLE}🖥️ Modo de arranque: UEFI${NC}"
    else
        echo -e "${PURPLE}🖥️ Modo de arranque: BIOS (Legacy)${NC}"
    fi
    echo -e "${YELLOW}ℹ El USB debe haber arrancado en el mismo modo que el sistema instalado${NC}\n"

    unlock_encrypted_partitions

    local parts=() part i=0 choice root_dev root_fs disk
    mapfile -t parts < <(linux_partitions)
    if [ ${#parts[@]} -eq 0 ]; then
        log_error "No se encontraron particiones de Linux"
        echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
        read -r
        return 1
    fi
    echo -e "${PURPLE}💾 Particiones de Linux encontradas:${NC}\n"
    for part in "${parts[@]}"; do
        i=$((i + 1))
        IFS='|' read -r root_dev disk root_fs choice <<< "$part"
        printf "  ${PURPLE}[%s]${NC} %-22s %8s  %-6s %s\n" "$i" "$root_dev" "$disk" "$root_fs" "$choice"
    done
    echo -e "\n  ${PURPLE}[0]${NC} 🔙 Volver"
    echo ""
    read -r -p "📌 ¿Cuál es la partición del sistema (la raíz /)? " choice
    if [ -z "$choice" ] || [ "$choice" = 0 ]; then
        echo -e "${YELLOW}ℹ No se cambió nada${NC}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#parts[@]} ]; then
        log_error "Opción inválida"
        sleep 1
        return 1
    fi
    IFS='|' read -r root_dev _ root_fs _ <<< "${parts[$((choice - 1))]}"
    # Disco físico que contiene la partición (atravesando LVM/LUKS)
    disk="/dev/$(lsblk -rnso NAME,TYPE "$root_dev" | awk '$2 == "disk" {print $1; exit}')"

    echo -e "\n${PURPLE}[1/5] Montando $root_dev...${NC}"
    rescue_umount
    sudo mkdir -p "$RESCUE_MNT"
    if [ "$root_fs" = "btrfs" ]; then
        # Ubuntu, Debian, Arch y Manjaro usan el subvolumen @; Fedora, "root"
        sudo mount -o subvol=@ "$root_dev" "$RESCUE_MNT" 2>> "$LOG_FILE" \
            || sudo mount -o subvol=root "$root_dev" "$RESCUE_MNT" 2>> "$LOG_FILE" \
            || run "No se pudo montar $root_dev" sudo mount "$root_dev" "$RESCUE_MNT" || return 1
    else
        run "No se pudo montar $root_dev" sudo mount "$root_dev" "$RESCUE_MNT" || return 1
    fi
    if [ ! -f "$RESCUE_MNT/etc/fstab" ] || [ ! -d "$RESCUE_MNT/boot" ]; then
        log_error "$root_dev no contiene un sistema instalado (no tiene /etc/fstab ni /boot)"
        rescue_umount
        echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
        read -r
        return 1
    fi

    boot_detect "$RESCUE_MNT"
    echo -e "${GREEN}🐧 Sistema encontrado: $BOOT_DISTRO${NC}"
    if [ "$BOOT_FAMILY" = otra ]; then
        log_warning "No conozco esta distribución: se intentará igual con los comandos estándar de GRUB"
    fi

    echo -e "${PURPLE}[2/5] Montando /boot y la partición EFI...${NC}"
    local mp spec esp
    # Particiones separadas según el fstab del sistema instalado (primero /boot)
    for mp in /boot /boot/efi /efi; do
        spec=$(awk -v m="$mp" '$1 !~ /^#/ && $2 == m {print $1; exit}' "$RESCUE_MNT/etc/fstab")
        if [ -n "$spec" ]; then
            sudo mkdir -p "$RESCUE_MNT$mp"
            run "No se pudo montar $mp ($spec)" sudo mount "$spec" "$RESCUE_MNT$mp" || { rescue_umount; return 1; }
            log_success "$mp montado ($spec)"
        fi
    done
    boot_detect "$RESCUE_MNT"   # con la EFI montada se sabe qué carpeta usa la distro
    if $uefi && [ "$(findmnt -no FSTYPE "$RESCUE_MNT$ESP_DIR" 2>/dev/null)" != vfat ]; then
        esp=$(lsblk -lnpo NAME,PARTTYPE | awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" || $2 == "0xef" {print $1; exit}')
        if [ -z "$esp" ]; then
            log_error "No se encontró la partición EFI (FAT32, tipo 'EFI System')"
            rescue_umount
            return 1
        fi
        sudo mkdir -p "$RESCUE_MNT$ESP_DIR"
        run "No se pudo montar la partición EFI $esp" sudo mount "$esp" "$RESCUE_MNT$ESP_DIR" || { rescue_umount; return 1; }
        log_success "Partición EFI montada en $ESP_DIR ($esp)"
        boot_detect "$RESCUE_MNT"
    fi

    echo -e "${PURPLE}[3/5] Preparando el entorno chroot...${NC}"
    local d
    for d in dev dev/pts proc sys run; do
        run "No se pudo montar /$d" sudo mount --bind "/$d" "$RESCUE_MNT/$d" || { rescue_umount; return 1; }
    done
    $uefi && sudo mount -t efivarfs efivarfs "$RESCUE_MNT/sys/firmware/efi/efivars" 2>> "$LOG_FILE"

    if ! $uefi; then
        echo -e "\n${PURPLE}💿 Discos:${NC}"
        lsblk -dpno NAME,SIZE,MODEL | grep -v loop | sed 's/^/  /'
        read -r -p "📌 Disco donde instalar GRUB [Enter = $disk]: " d
        [ -n "$d" ] && disk="$d"
        if [ ! -b "$disk" ]; then
            log_error "El disco $disk no existe"
            rescue_umount
            return 1
        fi
    fi

    echo -e "\n${PURPLE}📋 Resumen:${NC}"
    echo -e "  • Sistema: $BOOT_DISTRO en $root_dev ($root_fs)"
    $uefi && echo -e "  • Modo: UEFI (partición EFI en $ESP_DIR, carpeta $EFI_ID)" || echo -e "  • Modo: BIOS, GRUB en $disk"
    echo -e "  • Menú: ${GRUB_REGEN[*]}"
    if ! grub_available; then
        log_error "El sistema instalado no tiene GRUB (¿usa systemd-boot?): no se puede reparar con esta opción"
        rescue_umount
        return 1
    fi
    if ! confirm "${PURPLE}¿Reinstalar GRUB ahora?${NC}"; then
        rescue_umount
        return 0
    fi

    echo -e "${PURPLE}[4/5] Reinstalando GRUB...${NC}"
    local ok=0
    if ! rescue_grub_install "$uefi" "$disk"; then
        ok=1
        local grub_pkgs
        read -r -a grub_pkgs <<< "$(grub_packages "$($uefi && echo uefi || echo bios)")"
        if [ ${#grub_pkgs[@]} -gt 0 ] \
            && confirm "${PURPLE}¿Reinstalar los paquetes de GRUB (${grub_pkgs[*]}) y reintentar? (necesita internet)${NC}"; then
            # Sin esto, el gestor de paquetes no resuelve nombres dentro del chroot
            [ -f "$RESCUE_MNT/etc/resolv.conf" ] && [ ! -L "$RESCUE_MNT/etc/resolv.conf" ] \
                && sudo mount --bind /etc/resolv.conf "$RESCUE_MNT/etc/resolv.conf" 2>> "$LOG_FILE"
            run_visible "No se pudieron reinstalar los paquetes de GRUB" boot_pkg_reinstall "${grub_pkgs[@]}" \
                && rescue_grub_install "$uefi" "$disk" && ok=0
        fi
    fi

    if [ $ok -eq 0 ]; then
        run_visible "No se pudo regenerar el menú" grub_update
        ok=$?
    fi

    echo -e "${PURPLE}[5/5] Desmontando...${NC}"
    rescue_umount

    echo ""
    if [ $ok -eq 0 ]; then
        log_success "GRUB reparado. Quita el USB y reinicia"
        if confirm "${PURPLE}¿Reiniciar ahora?${NC}"; then
            sudo reboot
        fi
    else
        log_error "La reparación no terminó. Revisa: $LOG_FILE"
    fi
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}
#@parte arranque: set_grub_var grub_menu_entries grub_default_entry_menu

GRUB_OTHERS_FIRST="/etc/grub.d/09_ubuntu_ultimate_tools_otros_primero"
#@parte arranque: others_visible grub_os_prober_toggle uefi_boot_order_menu esp_check_repair esp_fsck

# ------------------------------------------------------------
# Personalizar el menú de GRUB (sin programas externos)
# ------------------------------------------------------------

GRUB_LOOK_FILE="/etc/grub.d/42_ubuntu_ultimate_tools_apariencia"
#@parte arranque: regen_grub grub_scripts grub_scripts_hidden grub_scripts_chmod

# --- Ocultar entradas sueltas -------------------------------------------------
# Cada script de GRUB con entradas ocultas se desactiva (sin permiso de ejecución) y
# en su lugar corre "<script>_ubuntu_ultimate_tools", que lo ejecuta y filtra su salida con
# grub-filtro.awk según la lista de títulos ocultos.
UUT_ETC="/etc/ubuntu-ultimate-tools"
GRUB_HIDDEN_LIST="$UUT_ETC/grub-ocultas"
GRUB_FILTER_AWK="$UUT_ETC/grub-filtro.awk"

write_grub_filter() {
    sudo install -d -m 0755 "$UUT_ETC"
    sudo tee "$GRUB_FILTER_AWK" > /dev/null << 'EOF'
# Ubuntu Ultimate Tools: quita del menú de GRUB las entradas cuyo título está en la lista
# (líneas "script|título"). Una entrada ocupa desde su línea "menuentry" hasta la
# llave que la cierra. En su lugar queda "true" (no hace nada): si la entrada
# estaba sola dentro de un "if ... then ... fi", un bloque vacío es un error de
# sintaxis y update-grub falla.
BEGIN {
    while ((getline line < list) > 0) {
        sub(/^[^|]*\|/, "", line)
        if (line != "") hide[line] = 1
    }
    close(list)
}
skip > 0 { skip += gsub(/\{/, "{") - gsub(/\}/, "}"); next }
/^[ \t]*menuentry / {
    t = $0
    sub(/^[ \t]*menuentry[ \t]+['"]/, "", t)
    sub(/['"].*/, "", t)
    if (t in hide) {
        match($0, /^[ \t]*/)
        print substr($0, 1, RLENGTH) "true"
        skip = gsub(/\{/, "{") - gsub(/\}/, "}")
        if (skip < 0) skip = 0
        next
    }
}
{ print }
EOF
}

# Envoltorio que reemplaza a un script de GRUB y filtra sus entradas
write_grub_filter_wrapper() {
    local orig="$1"
    sudo tee "${orig}_ubuntu_ultimate_tools" > /dev/null << EOF
#!/bin/sh
# Ubuntu Ultimate Tools: genera las entradas de ${orig##*/} sin las ocultas (ver $GRUB_HIDDEN_LIST)
ORIG='$orig'
[ -f "\$ORIG" ] || exit 0
# Si una actualización volvió a activar el original, este filtro se aparta (sin duplicados)
[ -x "\$ORIG" ] && exit 0
sh "\$ORIG" | awk -v list='$GRUB_HIDDEN_LIST' -f '$GRUB_FILTER_AWK'
EOF
    sudo chmod +x "${orig}_ubuntu_ultimate_tools"
    sudo chmod -x "$orig"
}

remove_grub_filter_wrapper() {
    local orig="$1"
    sudo rm -f "${orig}_ubuntu_ultimate_tools"
    [ -f "$orig" ] && sudo chmod +x "$orig"
}
#@parte arranque: grub_cfg_entries

grub_hide_entries() {
    # Con Grub Customizer activo sus *_proxy duplican las entradas y aplican sus
    # propias reglas: hay que deshacerlo antes de filtrar
    if [ -d /etc/grub.d/proxifiedScripts ]; then
        echo -e "${YELLOW}⚠ Grub Customizer está activo: genera cada entrada dos veces y aplica sus propias${NC}"
        echo -e "${YELLOW}  reglas, así que primero hay que deshacer sus cambios (se guarda una copia).${NC}\n"
        undo_grub_customizer || return 1
        [ -d /etc/grub.d/proxifiedScripts ] && return 0
        echo ""
    fi
    local entries=() tags=() line src shown title i=0 hidden=()
    on() { if "$@"; then echo "|ON"; fi; }
    if grub_uses_bls; then
        echo -e "${YELLOW}ℹ En ${BOOT_DISTRO} los kernels van en formato BLS: no aparecen en esta lista y no se ocultan.${NC}"
        echo -e "${YELLOW}  Sí se pueden ocultar Windows, otros sistemas, memtest y la configuración UEFI.${NC}\n"
    fi
    [ -f "$GRUB_HIDDEN_LIST" ] && mapfile -t hidden < "$GRUB_HIDDEN_LIST"

    # Grupos completos
    entries+=("recuperacion|[Grupo] Todos los modos de recuperación$(on grep -q '^GRUB_DISABLE_RECOVERY=true' /etc/default/grub)")
    tags+=("recuperacion|")
    if grub_scripts_hidden memtest86+; then
        entries+=("memtest|[Grupo] Toda la prueba de memoria (memtest86+)|ON"); tags+=("memtest|")
    fi
    if grub_scripts_hidden uefi-firmware; then
        entries+=("uefi|[Grupo] Configuración de la UEFI|ON"); tags+=("uefi|")
    fi

    # Cada entrada del menú actual (las de recuperación van en su grupo)
    while IFS='|' read -r src shown title; do
        [[ "$src" == *ubuntu_ultimate_tools_otros_primero* || "$src" == *_ubuntu_ultimate_tools ]] && src=${src%_ubuntu_ultimate_tools}
        [[ "${title,,}" == *recovery* || "${title,,}" == *recuperaci* ]] && continue
        i=$((i + 1))
        entries+=("e$i|$shown")
        tags+=("e$i|$src|$title")
    done < <(grub_cfg_entries)
    # Y las que ya están ocultas (no salen en el menú actual)
    for line in "${hidden[@]}"; do
        [ -n "$line" ] || continue
        i=$((i + 1))
        entries+=("e$i|${line#*|} (oculta)|ON")
        tags+=("e$i|$line")
    done

    CHECKLIST_NOTAGS=true checklist_select "Ocultar entradas" \
        "Marca TODAS las entradas que quieres OCULTAR del menú (las ya ocultas aparecen marcadas)" \
        "${entries[@]}" || return 0
    clear
    local chosen=" ${CHOSEN[*]} " tag new_hidden=() scripts=() script title_only kubuntu_left=0 kubuntu_total=0

    if [[ "$chosen" == *" recuperacion "* ]]; then set_grub_var GRUB_DISABLE_RECOVERY true; else set_grub_var GRUB_DISABLE_RECOVERY false; fi
    [[ "$chosen" != *" memtest "* ]] && grub_scripts_hidden memtest86+ && grub_scripts_chmod +x memtest86+
    [[ "$chosen" != *" uefi "* ]] && grub_scripts_hidden uefi-firmware && grub_scripts_chmod +x uefi-firmware

    for tag in "${tags[@]}"; do
        [[ "$tag" == e* ]] || continue
        IFS='|' read -r _ script title_only <<< "$tag"
        if [[ "$script" == */10_linux ]]; then
            kubuntu_total=$((kubuntu_total + 1))
            [[ "$chosen" == *" ${tag%%|*} "* ]] || kubuntu_left=$((kubuntu_left + 1))
        fi
        [[ "$chosen" == *" ${tag%%|*} "* ]] && new_hidden+=("$script|$title_only")
    done
    if [ "$kubuntu_total" -gt 0 ] && [ "$kubuntu_left" -eq 0 ]; then
        log_error "No puedes ocultar todas las entradas de ${BOOT_DISTRO}: no podrías arrancarlo. No se cambió nada."
        return 1
    fi

    local previous=""
    [ -f "$GRUB_HIDDEN_LIST" ] && previous=$(cat "$GRUB_HIDDEN_LIST")
    write_grub_filter
    printf '%s\n' "${new_hidden[@]}" | sed '/^$/d' | sort -u | sudo tee "$GRUB_HIDDEN_LIST" > /dev/null
    # Filtro solo en los scripts que tienen algo oculto
    mapfile -t scripts < <(printf '%s\n' "${new_hidden[@]}" | cut -d'|' -f1 | sed '/^$/d' | sort -u)
    local wrapper orig
    for wrapper in /etc/grub.d/*_ubuntu_ultimate_tools; do
        [ -f "$wrapper" ] || continue
        orig=${wrapper%_ubuntu_ultimate_tools}
        printf '%s\n' "${scripts[@]}" | grep -qxF "$orig" || remove_grub_filter_wrapper "$orig"
    done
    for script in "${scripts[@]}"; do
        [[ "$script" == *ubuntu_ultimate_tools_otros_primero ]] && continue
        [ -f "$script" ] && write_grub_filter_wrapper "$script"
    done
    # "Otros sistemas primero" llama a os-prober por su cuenta: también usa el filtro
    [ -f "$GRUB_OTHERS_FIRST" ] && write_others_first_script

    if regen_grub; then
        log_success "Menú actualizado: ${#new_hidden[@]} entradas ocultas"
        return 0
    fi
    # Seguro: si el menú nuevo no se pudo generar, se vuelve a la lista anterior
    log_warning "Se deshace este último cambio para que el menú siga funcionando"
    printf '%s\n' "$previous" | sed '/^$/d' | sudo tee "$GRUB_HIDDEN_LIST" > /dev/null
    regen_grub && log_success "Menú de arranque como estaba antes de este cambio"
    return 1
}

write_others_first_script() {
    sudo tee "$GRUB_OTHERS_FIRST" > /dev/null << 'EOF'
#!/bin/sh
# Ubuntu Ultimate Tools: muestra los otros sistemas (Windows, otras distros) antes que Ubuntu.
# El script de os-prober puede estar en su sitio o movido por Grub Customizer; si no
# está, no hace nada (nunca debe hacer fallar update-grub).
GRUB_DISABLE_OS_PROBER=false
export GRUB_DISABLE_OS_PROBER
for script in /etc/grub.d/30_os-prober /etc/grub.d/proxifiedScripts/os-prober; do
    if [ -f "$script" ]; then
        if [ -f /etc/ubuntu-ultimate-tools/grub-filtro.awk ]; then
            sh "$script" | awk -v list=/etc/ubuntu-ultimate-tools/grub-ocultas -f /etc/ubuntu-ultimate-tools/grub-filtro.awk
        else
            sh "$script"
        fi
        exit 0
    fi
done
exit 0
EOF
    sudo chmod +x "$GRUB_OTHERS_FIRST"
}
#@parte arranque: grub_others_first_toggle grub_remember_last_toggle

# Colores del menú (nombres de color de GRUB: texto/fondo; "black" deja ver el fondo)
grub_set_colors() {
    local color_text="$1" color_selected="$2"
    sudo tee "$GRUB_LOOK_FILE" > /dev/null << EOF
#!/bin/sh
# Ubuntu Ultimate Tools: colores del menú de GRUB
cat << 'COLORES'
set color_normal=light-gray/black
set menu_color_normal=$color_text
set menu_color_highlight=$color_selected
COLORES
EOF
    sudo chmod +x "$GRUB_LOOK_FILE"
}

grub_appearance_menu() {
    local option file ext
    echo -e "  ${PURPLE}1)${NC} Colores Tokyo Night (azul y lila)"
    echo -e "  ${PURPLE}2)${NC} Colores alto contraste (blanco y negro)"
    echo -e "  ${PURPLE}3)${NC} Colores verde terminal"
    echo -e "  ${PURPLE}4)${NC} Colores originales de tu distribución"
    echo -e "  ${PURPLE}5)${NC} Imagen de fondo (PNG o JPG)"
    echo -e "  ${PURPLE}6)${NC} Quitar la imagen de fondo"
    echo -e "  ${PURPLE}7)${NC} Resolución del menú"
    echo -e "\n  ${PURPLE}0)${NC} 🔙 Volver"
    echo ""
    read -r -p "📌 Opción: " option
    case $option in
        1) grub_set_colors light-blue/black black/light-magenta ;;
        2) grub_set_colors white/black black/white ;;
        3) grub_set_colors light-green/black black/light-green ;;
        4) sudo rm -f "$GRUB_LOOK_FILE" ;;
        5)
            read -r -p "🖼 Ruta de la imagen (puedes arrastrarla desde Dolphin; Enter = volver): " file
            if [ -z "$file" ] || [ "$file" = 0 ]; then
                echo -e "${YELLOW}ℹ No se cambió nada${NC}"
                return 0
            fi
            file=${file//\'/}
            file=${file/#\~/$HOME}
            ext=$(tr '[:upper:]' '[:lower:]' <<< "${file##*.}")
            if [ ! -f "$file" ] || [[ ! "$ext" =~ ^(png|jpg|jpeg|tga)$ ]]; then
                log_error "No es una imagen PNG, JPG o TGA: $file"
                return 1
            fi
            # Dentro de /boot/grub, donde GRUB la puede leer al arrancar
            sudo rm -f "$GRUB_DIR"/ubuntu-ultimate-tools-fondo.*
            sudo cp "$file" "$GRUB_DIR/ubuntu-ultimate-tools-fondo.$ext"
            set_grub_var GRUB_BACKGROUND "\"$GRUB_DIR/ubuntu-ultimate-tools-fondo.$ext\""
            ;;
        6)
            backup_grub_config
            sudo sed -i '/^GRUB_BACKGROUND=/d' /etc/default/grub
            sudo rm -f "$GRUB_DIR"/ubuntu-ultimate-tools-fondo.*
            ;;
        7)
            echo -e "  1) Automática  2) 1920x1080  3) 1366x768  4) 1280x1024  5) 1024x768  0) Volver"
            read -r -p "📌 Resolución: " option
            case $option in
                1) set_grub_var GRUB_GFXMODE auto ;;
                2) set_grub_var GRUB_GFXMODE 1920x1080 ;;
                3) set_grub_var GRUB_GFXMODE 1366x768 ;;
                4) set_grub_var GRUB_GFXMODE 1280x1024 ;;
                5) set_grub_var GRUB_GFXMODE 1024x768 ;;
                *) echo -e "${YELLOW}ℹ No se cambió nada${NC}"; return 0 ;;
            esac
            ;;
        *) echo -e "${YELLOW}ℹ No se cambió nada${NC}"; return 0 ;;
    esac
    regen_grub && log_success "Apariencia del menú actualizada (se ve al reiniciar)"
    if grep -q '^GRUB_TIMEOUT_STYLE=hidden' /etc/default/grub; then
        echo -e "${YELLOW}ℹ El menú está oculto al arrancar: dale unos segundos con la opción 6 para verlo${NC}"
    fi
}
#@parte arranque: datos_boot_verbose_state boot_strip_quiet grub_effective_var boot_verbose_active grub_quote boot_verbose_on boot_verbose_off boot_verbose_menu grub_kernel_params_menu

# Deshace los cambios de Grub Customizer en /etc/grub.d sin usar el programa:
# cada script original de un paquete vuelve a su nombre (desde su copia renumerada,
# desde proxifiedScripts o reinstalando el paquete) y se quita todo lo demás.
# Antes se guarda una copia completa de /etc/grub.d.
undo_grub_customizer() {
    if [ ! -d /etc/grub.d/proxifiedScripts ]; then
        echo -e "${GREEN}✓ Grub Customizer no modificó /etc/grub.d${NC}"
        return 0
    fi
    echo -e "${PURPLE}Grub Customizer cambió los scripts de GRUB: los renumeró, los movió a${NC}"
    echo -e "${PURPLE}proxifiedScripts y puso los suyos (*_proxy). Esto los deja como los instala ${BOOT_DISTRO}.${NC}\n"
    confirm "${PURPLE}¿Deshacer los cambios de Grub Customizer?${NC}" || return 0

    local backup
    backup="/etc/grub.d.antes-de-deshacer-grub-customizer-$(date +%Y%m%d-%H%M%S)"
    run "No se pudo hacer la copia de seguridad" sudo cp -a /etc/grub.d "$backup" || return 1
    log_success "Copia de seguridad: $backup"

    # Scripts que instalan los paquetes (grub-common, memtest86+, fwupd...)
    local owned=() owners=() pkgs=() path name candidate missing_pkgs=()
    mapfile -t owners < <(boot_grubd_owned)
    mapfile -t owned < <(printf '%s\n' "${owners[@]}" | awk 'NF == 2 {print $2}' | sort -u)
    # Seguro: sin la lista de los originales no se toca nada (se borraría todo)
    if ! printf '%s\n' "${owned[@]}" | grep -q '/00_header$' \
        || ! printf '%s\n' "${owned[@]}" | grep -q '/10_linux$'; then
        log_error "No se pudo saber qué scripts instalan los paquetes de ${BOOT_DISTRO}: no se cambió nada"
        return 1
    fi
    for path in "${owned[@]}"; do
        [ -f "$path" ] && continue
        name=${path##*/}
        name=${name#[0-9][0-9]_}
        candidate=""
        for candidate in /etc/grub.d/[0-9][0-9]_"$name" /etc/grub.d/proxifiedScripts/"$name"; do
            # Nunca otro original con el mismo nombre (40_custom y 41_custom son distintos)
            [ -f "$candidate" ] && ! printf '%s\n' "${owned[@]}" | grep -qxF "$candidate" && break
            candidate=""
        done
        if [ -n "$candidate" ]; then
            sudo mv "$candidate" "$path"
            sudo chmod +x "$path"
            echo -e "  ${GREEN}✓ ${path##*/} vuelve a su lugar${NC}"
        else
            mapfile -t pkgs < <(printf '%s\n' "${owners[@]}" | awk -v f="$path" '$2 == f {print $1}')
            missing_pkgs+=("${pkgs[@]}")
        fi
    done

    # Todo lo que no es de un paquete ni de este script: proxies, copias, bin/, backup/...
    local entry keep
    for entry in /etc/grub.d/* /etc/grub.d/.script_sources.txt; do
        [ -e "$entry" ] || continue
        keep=false
        printf '%s\n' "${owned[@]}" | grep -qxF "$entry" && keep=true
        [[ "${entry##*/}" == *ubuntu_ultimate_tools* || "${entry##*/}" == README ]] && keep=true
        $keep || sudo rm -rf "$entry"
    done

    # Los que no tenían copia se recuperan reinstalando su paquete (repone los archivos que faltan)
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        mapfile -t missing_pkgs < <(printf '%s\n' "${missing_pkgs[@]}" | sort -u)
        echo -e "${PURPLE}📦 Recuperando del paquete: ${missing_pkgs[*]}${NC}"
        run "No se pudieron recuperar los scripts originales" boot_pkg_reinstall "${missing_pkgs[@]}"
    fi

    if regen_grub; then
        log_success "Cambios de Grub Customizer deshechos"
    else
        log_error "${GRUB_REGEN[0]} sigue fallando: la copia de /etc/grub.d está en $backup"
        return 1
    fi
    if boot_pkg_installed grub-customizer | grep -qx grub-customizer \
        && confirm "${PURPLE}¿Desinstalar Grub Customizer para que no vuelva a cambiar el menú?${NC}"; then
        run "No se pudo desinstalar Grub Customizer" boot_pkg_remove grub-customizer && forget_installed grub-customizer
    fi
}

grub_restore_original() {
    if [ ! -f "$GRUB_DEFAULT_BACKUP" ] && [ ! -f "$GRUB_LOOK_FILE" ] && [ ! -f "$GRUB_OTHERS_FIRST" ] \
        && [ ! -f "$GRUB_HIDDEN_LIST" ] && ! boot_verbose_active; then
        echo -e "${GREEN}✓ El menú de GRUB no tiene cambios del script${NC}"
        return 0
    fi
    confirm "${PURPLE}¿Volver el menú de GRUB a como estaba antes de usar el script?${NC}" || return 0
    # Primero se deshace el arranque detallado (incluye los parámetros de cada kernel en Fedora)
    boot_verbose_active && boot_verbose_off
    if [ -f "$GRUB_DEFAULT_BACKUP" ]; then
        sudo cp -p "$GRUB_DEFAULT_BACKUP" /etc/default/grub && sudo rm -f "$GRUB_DEFAULT_BACKUP"
    fi
    sudo rm -f "$GRUB_LOOK_FILE" "$GRUB_OTHERS_FIRST" $GRUB_DIR/ubuntu-ultimate-tools-fondo.*
    local wrapper
    for wrapper in /etc/grub.d/*_ubuntu_ultimate_tools; do
        [ -f "$wrapper" ] && remove_grub_filter_wrapper "${wrapper%_ubuntu_ultimate_tools}"
    done
    sudo rm -f "$GRUB_HIDDEN_LIST" "$GRUB_FILTER_AWK"
    grub_scripts_chmod +x memtest86+
    grub_scripts_chmod +x uefi-firmware
    regen_grub && run "No se pudo fijar el kernel por defecto" grub_set_default 0 \
        && log_success "Menú de GRUB restaurado"
}
#@parte arranque: grub_customize_menu remove_refind uefi_distro_first grub_full_repair datos_rescue_card rescue_card_collect

# La tarjeta en texto plano (para guardar, imprimir o fotografiar)
rescue_card_text() {
    local mode=BIOS
    [ -d /sys/firmware/efi ] && mode=UEFI
    echo "================================================================"
    echo " TARJETA DE RESCATE DEL ARRANQUE - $(os_release_value PRETTY_NAME)"
    echo " Generada el $(date '+%d/%m/%Y') con Ubuntu Ultimate Tools"
    echo "================================================================"
    echo ""
    echo " Partición de arranque: $rc_dev ($rc_fstype, $rc_size) - modo $mode"
    $rc_crypt || echo " GRUB la llama: ($rc_drive)$($rc_approx && echo "  (calculado: si falla, prueba hd0, hd1, hd2...)")"
    echo " Su UUID (identificador único): $rc_uuid"
    echo ""
    if $rc_crypt; then
        echo " ATENCIÓN: /boot está en un disco cifrado. Desde 'grub>' o"
        echo " 'grub rescue>' no se puede arrancar a mano: usa un Live USB y"
        echo " este script, opción 19 -> 10 (reparación automática)."
        echo ""
    else
        echo "----------------------------------------------------------------"
        echo " A) SI AL ENCENDER VES  grub>"
        echo "----------------------------------------------------------------"
        echo " Escribe estas 2 líneas (Enter después de cada una):"
        echo ""
        $rc_lvm && echo "    insmod lvm"
        echo "    search --no-floppy --fs-uuid --set=root $rc_uuid"
        echo "    configfile $rc_grubpath/grub.cfg"
        echo ""
        echo " Aparece el menú de siempre: elige tu sistema."
        echo " Si dice 'no such device' o no aparece el menú, arranca directo:"
        echo ""
        echo "    search --no-floppy --fs-uuid --set=root $rc_uuid"
        echo "    linux $rc_kernel $rc_root ro"
        echo "    initrd $rc_initrd"
        echo "    boot"
        echo ""
        echo "----------------------------------------------------------------"
        echo " B) SI VES  grub rescue>"
        echo "----------------------------------------------------------------"
        echo " Escribe estas 4 líneas:"
        echo ""
        echo "    set prefix=($rc_drive)$rc_grubpath"
        echo "    set root=($rc_drive)"
        echo "    insmod normal"
        echo "    normal"
        echo ""
        echo " Si dice 'no such partition' o 'unknown filesystem', el número"
        echo " cambió (por ejemplo, porque hay un USB conectado). Escribe:"
        echo "    ls"
        echo " y prueba con cada partición hasta que una muestre archivos:"
        echo "    ls (hd0,${rc_drive#*,})$rc_grubpath"
        echo "    ls (hd1,${rc_drive#*,})$rc_grubpath      ...y así"
        echo " Usa esa en las 4 líneas de arriba."
        echo ""
    fi
    echo "----------------------------------------------------------------"
    echo " C) CUANDO VUELVAS A ENTRAR AL SISTEMA"
    echo "----------------------------------------------------------------"
    echo " Arréglalo de forma permanente: este script, opción 19 -> 2"
    echo " (reparación rápida) o 19 -> 3 (reparación completa)."
    echo ""
    echo "----------------------------------------------------------------"
    echo " D) SI NADA DE ESTO FUNCIONA"
    echo "----------------------------------------------------------------"
    echo " Arranca con un USB de instalación de tu distribución (modo Live),"
    echo " abre este script desde el pendrive y usa la opción 19 -> 10."
    echo "    bash /media/\$USER/<pendrive>/ubuntu-ultimate-tools.sh"
    echo "================================================================"
}
#@parte arranque: rescue_card_write mounted_usb_drives

# Copia la tarjeta y el script a un pendrive (para usarlos desde un Live USB)
rescue_copy_to_usb() {
    local drives=() i=0 d choice dir
    mapfile -t drives < <(mounted_usb_drives)
    if [ ${#drives[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ No hay ningún pendrive conectado. Conéctalo, ábrelo en el gestor de archivos${NC}"
        echo -e "${YELLOW}  (así queda montado) y vuelve a esta opción.${NC}"
        return 0
    fi
    echo -e "${PURPLE}💾 Pendrives conectados:${NC}"
    for d in "${drives[@]}"; do
        i=$((i + 1))
        echo -e "  ${PURPLE}$i)${NC} ${d%%|*} (${d#*|})"
    done
    echo -e "  ${PURPLE}0)${NC} 🔙 No copiar"
    read -r -p "📌 ¿En cuál copiar? " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#drives[@]} ]; then
        echo -e "${YELLOW}ℹ No se copió nada${NC}"
        return 0
    fi
    dir=${drives[$((choice - 1))]%%|*}
    if cp "$RESCUE_CARD" "$dir/" 2>> "$LOG_FILE" && cp "$SCRIPT_PATH" "$dir/ubuntu-ultimate-tools.sh" 2>> "$LOG_FILE"; then
        sync
        log_success "Copiados en $dir: el script y la tarjeta de rescate"
        echo -e "${CYAN}ℹ Desde el Live USB: bash /media/\$USER/$(basename "$dir")/ubuntu-ultimate-tools.sh → 18 → 10${NC}"
    else
        log_error "No se pudo copiar al pendrive (¿está lleno o protegido contra escritura?)"
    fi
}
#@parte arranque: rescue_card_menu rescue_card_refresh

# ------------------------------------------------------------
# Arranque de respaldo UEFI: \EFI\BOOT\BOOTX64.EFI es la ruta que el firmware
# prueba cuando no tiene (o perdió) la entrada de Ubuntu. Con el "fallback" de
# shim (fbx64.efi), además vuelve a crear la entrada de Ubuntu solo.
# ------------------------------------------------------------

UEFI_FALLBACK_MARK="$UUT_ETC/arranque-respaldo"
UEFI_FALLBACK_HOOK="/etc/apt/apt.conf.d/99ubuntu-ultimate-tools-arranque-respaldo"
UEFI_FALLBACK_HOOK_PACMAN="/etc/pacman.d/hooks/99-ubuntu-ultimate-tools-arranque-respaldo.hook"
UEFI_FALLBACK_TOOL="/usr/local/sbin/ubuntu-ultimate-tools-arranque-respaldo"
UEFI_FALLBACK_BACKUP="$UUT_ETC/efi-boot-anterior"

# El programa que copia los archivos: lo usa el script y lo llama el gestor de paquetes
# (apt o pacman) después de cada actualización, para que la copia nunca quede vieja.
write_uefi_fallback_tool() {
    sudo install -d -m 755 "$UUT_ETC" /usr/local/sbin
    sed -e "s|__ESP__|$ESP_DIR|" -e "s|__ID__|$EFI_ID|" << 'TOOL' | sudo tee "$UEFI_FALLBACK_TOOL" > /dev/null
#!/bin/sh
# Ubuntu Ultimate Tools: mantiene el arranque de respaldo UEFI (\EFI\BOOT) igual al de
# la distribución (\EFI\__ID__). Solo toca \EFI\BOOT si lo puso el script.
MARK=/etc/ubuntu-ultimate-tools/arranque-respaldo
ESP="__ESP__"
[ -d /sys/firmware/efi ] && [ -f "$MARK" ] && mountpoint -q "$ESP" || exit 0
SRC=$(find "$ESP/EFI" -maxdepth 1 -iname "__ID__" | head -n1)
DST=$(find "$ESP/EFI" -maxdepth 1 -iname boot | head -n1)
[ -n "$SRC" ] || exit 0
[ -n "$DST" ] || { DST="$ESP/EFI/BOOT"; mkdir -p "$DST"; }
CUR=$(find "$DST" -maxdepth 1 -iname bootx64.efi | head -n1)
# Si otro sistema reemplazó el archivo, no se toca
if [ -n "$CUR" ] && [ "$(sha256sum < "$CUR" | cut -d' ' -f1)" != "$(cat "$MARK")" ]; then
    [ "${1:-}" = "--forzar" ] || exit 0
fi
if [ -f "$SRC/shimx64.efi" ]; then
    # Con Secure Boot: shim firmado, GRUB y MokManager
    cp "$SRC/shimx64.efi" "$DST/BOOTX64.EFI" || exit 0
    for f in grubx64.efi mmx64.efi; do [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DST/$f"; done
    # fbx64.efi vuelve a crear la entrada de la distro en el firmware si se borró
    for f in /usr/lib/shim/fbx64.efi.signed /usr/lib/shim/fbx64.efi; do
        [ -f "$f" ] && { cp "$f" "$DST/fbx64.efi"; break; }
    done
elif [ -f "$SRC/grubx64.efi" ]; then
    # Sin shim (Arch, Manjaro): GRUB solo, que sabe dónde está su menú
    cp "$SRC/grubx64.efi" "$DST/BOOTX64.EFI" || exit 0
else
    exit 0
fi
[ -f "$SRC/grub.cfg" ] && cp "$SRC/grub.cfg" "$DST/grub.cfg"
sha256sum < "$DST/BOOTX64.EFI" | cut -d' ' -f1 > "$MARK"
exit 0
TOOL
    sudo chmod 755 "$UEFI_FALLBACK_TOOL"
    case $BOOT_FAMILY in
        debian)
            echo "DPkg::Post-Invoke { \"$UEFI_FALLBACK_TOOL || true\"; };" | sudo tee "$UEFI_FALLBACK_HOOK" > /dev/null ;;
        arch)
            sudo install -d -m 755 "$(dirname "$UEFI_FALLBACK_HOOK_PACMAN")"
            sudo tee "$UEFI_FALLBACK_HOOK_PACMAN" > /dev/null << HOOK
# Ubuntu Ultimate Tools: actualiza el arranque de respaldo UEFI cuando cambia GRUB
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = grub
Target = shim*

[Action]
Description = Actualizando el arranque de respaldo UEFI...
When = PostTransaction
Exec = $UEFI_FALLBACK_TOOL
HOOK
            ;;
    esac
}
#@parte arranque: uefi_fallback_state install_uefi_fallback remove_uefi_fallback uefi_fallback_menu
#@parte comun: shutdown_menu datos_plasma_appletsrc desktop_dir stop_plasmashell start_plasmashell taskmanager_applets remove_desktop_shortcuts

GNOME_FAVORITES_BACKUP="$SHORTCUTS_BACKUP/gnome-favoritas"
#@parte comun: remove_gnome_favorites restore_gnome_favorites remove_panel_launchers restore_desktop_shortcuts restore_panel_launchers remove_shortcuts_menu

# ============================================================
# OPCIÓN 16: RED, DNS Y DRIVERS (COLOR: AZUL)
# ============================================================

RESOLVED_DNS_CONF="/etc/systemd/resolved.conf.d/99-ubuntu-ultimate-tools-dns.conf"
NM_WIFI_CONF="/etc/NetworkManager/conf.d/99-ubuntu-ultimate-tools-wifi.conf"

# nombre|servidores (IPv4 e IPv6, con el nombre para DNS cifrado)|descripción
DNS_PROVIDERS=(
    "cloudflare|1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com|Cloudflare: el más rápido en casi todo el mundo, privado"
    "cloudflare-seguro|1.1.1.2#security.cloudflare-dns.com 1.0.0.2#security.cloudflare-dns.com 2606:4700:4700::1112#security.cloudflare-dns.com 2606:4700:4700::1002#security.cloudflare-dns.com|Cloudflare + bloqueo de malware"
    "google|8.8.8.8#dns.google 8.8.4.4#dns.google 2001:4860:4860::8888#dns.google 2001:4860:4860::8844#dns.google|Google Public DNS: muy estable"
    "quad9|9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net|Quad9: bloquea dominios maliciosos, sin registros"
    "adguard|94.140.14.14#dns.adguard-dns.com 94.140.15.15#dns.adguard-dns.com 2a10:50c0::ad1:ff#dns.adguard-dns.com 2a10:50c0::ad2:ff#dns.adguard-dns.com|AdGuard: bloquea anuncios y rastreadores"
)
#@parte comun: dns_provider_field

current_dns() {
    if [ -f "$RESOLVED_DNS_CONF" ]; then
        sed -n 's/^# Proveedor: //p' "$RESOLVED_DNS_CONF"
    else
        echo "automático (el del router)"
    fi
}

# Aplica el DNS globalmente con systemd-resolved (usado por Ubuntu) y DNS cifrado
# cuando el servidor lo permite. Si después no resuelve nombres, se deshace solo.
set_dns() {
    local name="$1" servers
    servers=$(dns_provider_field "$name" 2) || { log_error "Proveedor DNS desconocido: $name"; return 1; }
    if ! systemctl is-active --quiet systemd-resolved; then
        log_error "systemd-resolved no está activo; no se puede cambiar el DNS de forma segura"
        return 1
    fi

    sudo install -d -m 0755 /etc/systemd/resolved.conf.d
    # Domains=~. hace que se use este DNS para todo, en lugar del que da el router
    printf '# Proveedor: %s\n[Resolve]\nDNS=%s\nDomains=~.\nDNSOverTLS=opportunistic\n' "$name" "$servers" \
        | sudo tee "$RESOLVED_DNS_CONF" > /dev/null
    run "No se pudo reiniciar systemd-resolved" sudo systemctl restart systemd-resolved || return 1

    sleep 1
    if getent hosts ubuntu.com > /dev/null; then
        log_success "DNS cambiado a $name (cifrado si el servidor lo permite)"
    else
        log_error "Con $name no se resuelven nombres: se vuelve al DNS automático"
        reset_dns
        return 1
    fi
}

reset_dns() {
    sudo rm -f "$RESOLVED_DNS_CONF"
    run "No se pudo reiniciar systemd-resolved" sudo systemctl restart systemd-resolved \
        && log_success "DNS automático restaurado"
}
#@parte comun: measure_dns set_fastest_dns bbr_algorithm enable_bbr disable_bbr disable_wifi_powersave enable_wifi_powersave

# Drivers privados recomendados por Ubuntu (NVIDIA, Wi-Fi Broadcom, etc.)
install_recommended_drivers() {
    echo -e "${BLUE}🔍 Buscando drivers recomendados para tu hardware...${NC}"
    apt_update
    apt_install ubuntu-drivers-common || return 1
    local list
    list=$(ubuntu-drivers list 2>/dev/null)
    if [ -z "$list" ]; then
        log_success "Tu hardware no necesita drivers adicionales"
        return 0
    fi
    echo -e "${BLUE}📋 Drivers disponibles:${NC}"
    sed 's/^/  • /' <<< "$list"
    run_visible "No se pudieron instalar los drivers" sudo ubuntu-drivers install \
        && log_success "Drivers recomendados instalados (requiere reinicio)"
}
#@parte apt: update_firmware
#@parte comun: network_menu is_laptop current_power_profile power_profiles_available set_gaming_power
#@parte apt: set_power_profile install_tlp
#@parte comun: enable_power_saving baloo_cmd disable_baloo gnome_indexer_unit indexer_disabled disable_indexer enable_indexer enable_baloo
#@parte apt: install_gaming_tools

MANGOHUD_CONF="$HOME/.config/MangoHud/MangoHud.conf"
MANGOHUD_ENV="$HOME/.config/environment.d/90-mangohud.conf"

# Deja MangoHud mostrando y grabando los FPS (SysMonitorPro lee esos registros).
# Sin configuración, MangoHud no graba nada y solo actúa en juegos lanzados con 'mangohud'.
configure_mangohud() {
    mkdir -p "$(dirname "$MANGOHUD_CONF")" "$HOME/mangohud-logs"
    if [ ! -f "$MANGOHUD_CONF" ]; then
        cat > "$MANGOHUD_CONF" << EOF
# Creado por Ubuntu Ultimate Tools
fps
frametime
cpu_stats
cpu_temp
gpu_stats
gpu_temp
toggle_hud=Shift_R+F12
toggle_logging=Shift_L+F2
output_folder=$HOME/mangohud-logs
autostart_log=1
EOF
        log_success "MangoHud configurado: $MANGOHUD_CONF"
    else
        # Configuración propia: solo se añade lo necesario para grabar los FPS
        local key value added=false
        cp "$MANGOHUD_CONF" "$MANGOHUD_CONF.bak"
        for key in output_folder autostart_log toggle_logging; do
            grep -q "^${key}=" "$MANGOHUD_CONF" && continue
            case $key in
                output_folder) value="$HOME/mangohud-logs" ;;
                autostart_log) value=1 ;;
                toggle_logging) value="Shift_L+F2" ;;
            esac
            echo "${key}=${value}" >> "$MANGOHUD_CONF"
            added=true
        done
        if $added; then
            log_success "MangoHud: registro de FPS activado (copia en $MANGOHUD_CONF.bak)"
        else
            rm -f "$MANGOHUD_CONF.bak"
        fi
    fi

    # Global: todos los juegos Vulkan y Proton/DXVK usan MangoHud sin tocar Steam.
    # En el perfil 'gaming' se activa directamente; en el menú se pregunta.
    if [ -f "$MANGOHUD_ENV" ]; then
        log_info "MangoHud ya está activo en todos los juegos Vulkan/Proton"
    elif [ "$ACTIVE_PROFILE" = "gaming" ] || confirm "${YELLOW}¿Activar MangoHud en todos los juegos Vulkan/Proton (sin configurar cada juego)?${NC}"; then
        mkdir -p "$(dirname "$MANGOHUD_ENV")"
        echo "MANGOHUD=1" > "$MANGOHUD_ENV"
        log_success "MangoHud activo en todos los juegos Vulkan/Proton (tras cerrar sesión y volver a entrar)"
    fi
    log_info "Juegos OpenGL o nativos sin Vulkan: abrirlos con 'mangohud juego' o en Steam 'mangohud %command%'"
    log_info "Shift derecho + F12 oculta el panel en el juego · Shift izquierdo + F2 pausa/reanuda la grabación"
}

# ------------------------------------------------------------
# Steam y Proton
# ------------------------------------------------------------

# Instalador oficial de Valve (si no se descarga, se usa el de Ubuntu)
STEAM_DEB_URLS=(
    "https://cdn.fastly.steamstatic.com/client/installer/steam.deb"
    "https://repo.steampowered.com/steam/archive/stable/steam_latest.deb"
)
PROTON_GE_LIST="$STATE_DIR/proton-ge.txt"
#@parte apt: steam_installed steam_dir steam_supported steam_i386_libs

install_steam() {
    steam_supported || return 1
    if steam_installed; then
        echo -e "  ${GREEN}✓ Steam ya está instalado${NC}"
        enable_steam_play
        return 0
    fi

    echo -e "${BLUE}🎮 Instalando Steam...${NC}"
    # Steam y los juegos de Windows usan librerías de 32 bits
    if ! dpkg --print-foreign-architectures | grep -qx i386; then
        run "No se pudo activar la arquitectura de 32 bits" sudo dpkg --add-architecture i386 || return 1
        log_success "Arquitectura de 32 bits (i386) activada"
    fi
    command -v wget &> /dev/null || { apt_update; apt_install wget; }

    local tmp url deb=""
    tmp=$(mktemp -d)
    chmod 755 "$tmp"
    for url in "${STEAM_DEB_URLS[@]}"; do
        if wget -qO "$tmp/steam.deb" "$url" >> "$LOG_FILE" 2>&1 \
            && [ "$(dpkg-deb -f "$tmp/steam.deb" Package 2>/dev/null)" = steam-launcher ]; then
            chmod 644 "$tmp/steam.deb"
            deb="$tmp/steam.deb"
            break
        fi
    done

    apt_update force
    if [ -n "$deb" ]; then
        apt_install_recorded "$deb" || { rm -rf "$tmp"; return 1; }
        # El instalador agrega el repositorio de Valve: de ahí salen sus librerías
        apt_update force
    elif [ -n "$(available_pkgs steam-installer)" ]; then
        log_warning "No se pudo descargar el instalador de Valve: se usa el paquete de Ubuntu"
        apt_install_recorded steam-installer || { rm -rf "$tmp"; return 1; }
    else
        log_error "No se pudo descargar Steam y tu Ubuntu no tiene el paquete (activa el repositorio multiverse)"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    steam_i386_libs || log_warning "Faltan librerías de 32 bits: Steam las pedirá al abrirlo"
    log_success "Steam instalado (Proton viene incluido)"
    enable_steam_play
}
#@parte comun: enable_steam_play steam_play_vdf
#@parte apt: install_proton_ge
#@parte comun: remove_proton_ge power_menu

# ============================================================
# OPCIÓN 18: PERFILES AUTOMÁTICOS (COLOR: PÚRPURA)
# ============================================================

PROFILES=(
    "productividad|Oficina y uso diario: herramientas, RAM, DNS rápido, sin juegos"
    "gaming|Juegos: Steam + Proton, drivers, kernel Liquorix, GameMode, red de baja latencia"
    "ahorro|Ahorro de energía: TLP en portátiles, sin indexador, ZRAM"
    "desarrollo|Programación: git, compiladores, Python, VSCode, SDK de Android para APK"
    "minimalista|Mínimo: sin meta-paquete, apps extra ni Snap; Firefox .deb de Mozilla"
)

# Pasos de cada perfil: "Descripción|función [argumentos]"
profile_steps() {
    case $1 in
        productividad) cat << 'EOF'
Desactivar indexación de manuales (apt más rápido)|disable_mandb
Actualizar el sistema|do_system_update
Quitar juegos preinstalados|remove_games
Instalar herramientas (git, htop, fastfetch, timeshift, vim...)|install_optional_with_progress git curl wget htop fastfetch timeshift vim
Optimizar RAM (swappiness y caché)|apply_ram_tweaks
Activar ZRAM|enable_zram
Activar TRIM semanal para SSD|enable_trim
Usar el DNS más rápido (medido)|set_fastest_dns
Activar TCP BBR|enable_bbr
EOF
        ;;
        gaming) cat << 'EOF'
Desactivar indexación de manuales (apt más rápido)|disable_mandb
Actualizar el sistema|do_system_update
Instalar drivers recomendados (GPU, Wi-Fi...)|install_recommended_drivers
Kernel Liquorix (se omite si Secure Boot está activo)|install_liquorix_kernel
Instalar GameMode y MangoHud|install_gaming_tools
Instalar Steam y activar Proton para todos los juegos|install_steam
Instalar Proton-GE (más compatible con algunos juegos)|install_proton_ge
Optimizar RAM (swappiness y caché)|apply_ram_tweaks
Activar ZRAM|enable_zram
Perfil de energía: rendimiento máximo (o GameMode al jugar)|set_gaming_power
Desactivar el indexador de archivos|disable_indexer
Wi-Fi sin ahorro de energía (menos latencia)|disable_wifi_powersave
Activar TCP BBR|enable_bbr
Usar el DNS más rápido (medido)|set_fastest_dns
EOF
        ;;
        ahorro) cat << 'EOF'
Desactivar indexación de manuales (apt más rápido)|disable_mandb
Actualizar el sistema|do_system_update
Ahorro de energía (TLP en portátil, perfil de ahorro en PC)|enable_power_saving
Desactivar el indexador de archivos|disable_indexer
Activar ZRAM (menos escrituras en disco)|enable_zram
Optimizar RAM (swappiness y caché)|apply_ram_tweaks
Activar TRIM semanal para SSD|enable_trim
EOF
        ;;
        desarrollo) cat << 'EOF'
Desactivar indexación de manuales (apt más rápido)|disable_mandb
Actualizar el sistema|do_system_update
Instalar herramientas (git, build-essential, Python, VSCode...)|install_optional_with_progress git curl wget vim htop build-essential python3-pip python3-venv code
Herramientas para compilar APK (Java, SDK de Android, adb)|install_android_tools
Más archivos vigilados para IDEs (inotify)|set_sysctl fs.inotify.max_user_watches 524288
Optimizar RAM (swappiness y caché)|apply_ram_tweaks
Activar ZRAM|enable_zram
Activar TRIM semanal para SSD|enable_trim
Activar TCP BBR|enable_bbr
Usar el DNS más rápido (medido)|set_fastest_dns
EOF
        ;;
        minimalista) cat << 'EOF'
Desactivar indexación de manuales (apt más rápido)|disable_mandb
Actualizar el sistema|do_system_update
Quitar el meta-paquete del sabor (las apps se conservan)|remove_flavor_meta
Quitar apps preinstaladas (juegos, correo y agenda, IRC, torrent...)|remove_minimal_extras
Eliminar Snap por completo (se conservan los perfiles de Firefox)|do_snap_removal
Instalar Firefox .deb de Mozilla|install_firefox_deb
Activar KDE Rolling Release (solo para Kubuntu)|enable_backports
Actualizar con los paquetes más nuevos|do_system_update
Desactivar el indexador de archivos|disable_indexer
Activar ZRAM|enable_zram
EOF
        ;;
    esac
}

list_profiles() {
    local entry
    echo -e "${PURPLE}📋 Perfiles disponibles:${NC}\n"
    for entry in "${PROFILES[@]}"; do
        printf "  ${PURPLE}%-14s${NC} %s\n" "${entry%%|*}" "${entry#*|}"
    done
}

run_profile() {
    local name="$1" steps=() line desc cmd i=0 ok=0 results=() start
    mapfile -t steps < <(profile_steps "$name")
    if [ ${#steps[@]} -eq 0 ]; then
        log_error "Perfil desconocido: $name"
        list_profiles
        return 1
    fi

    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    printf "║                    🚀 PERFIL: %-35s║\n" "${name^^}"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${PURPLE}📋 Se aplicará lo siguiente:${NC}\n"
    for line in "${steps[@]}"; do
        i=$((i + 1))
        echo -e "  ${PURPLE}$(printf '%2s' "$i").${NC} ${line%%|*}"
    done
    echo ""

    if ! $ASSUME_YES; then
        local response
        echo -e -n "${PURPLE}¿Aplicar el perfil $name? Puede tardar varios minutos (s/n): ${NC}"
        read -r response
        [[ "$response" =~ ^([sSyY]|[sS][iI]|[sS]í|[sS]Í)$ ]] || return 0
    fi

    # Durante el perfil no hay preguntas: las confirmaciones internas responden "no"
    local was_auto=$AUTO_MODE
    AUTO_MODE=true
    ACTIVE_PROFILE="$name"
    start=$(date +%s)
    i=0
    for line in "${steps[@]}"; do
        i=$((i + 1))
        desc=${line%%|*}
        read -r -a cmd <<< "${line#*|}"
        log_title "[$i/${#steps[@]}] $desc"
        if "${cmd[@]}"; then
            results+=("${GREEN}✓${NC} $desc")
            ok=$((ok + 1))
        else
            results+=("${RED}✗${NC} $desc")
        fi
    done
    AUTO_MODE=$was_auto
    ACTIVE_PROFILE=""

    echo ""
    echo -e "${PURPLE}${BOLD}📊 Resumen del perfil $name ($(( ($(date +%s) - start) / 60 )) min):${NC}\n"
    printf '  %b\n' "${results[@]}"
    echo ""
    if [ "$ok" -eq ${#steps[@]} ]; then
        log_success "Perfil $name aplicado por completo"
    else
        log_warning "$ok de ${#steps[@]} pasos completados. Detalles en: $LOG_FILE"
    fi
    echo -e "${YELLOW}⚠ Reinicia para aplicar todos los cambios${NC}"
    [ "$ok" -eq ${#steps[@]} ]
}

profiles_menu() {
    local i entry choice
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🚀 PERFILES AUTOMÁTICOS                       ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${PURPLE}Aplican varias optimizaciones de una vez, sin preguntas intermedias.${NC}\n"
    i=0
    for entry in "${PROFILES[@]}"; do
        i=$((i + 1))
        printf "  ${PURPLE}%s)${NC} %-14s %s\n" "$i" "${entry%%|*}" "${entry#*|}"
    done
    echo -e "\n  ${PURPLE}0)${NC} 🔙 Volver"
    echo -e "\n${YELLOW}💡 También desde terminal: ./ubuntu-ultimate-tools.sh --perfil gaming${NC}\n"
    read -r -p "📌 Opción: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#PROFILES[@]} ]; then
        entry=${PROFILES[$((choice - 1))]}
        run_profile "${entry%%|*}"
        pause
    fi
}

# ============================================================
# OPCIÓN 10: DESHACER OPTIMIZACIONES (COLOR: ROJO)
# ============================================================

# Programas que el script puede instalar. Sirve para ofrecer también los que se
# instalaron antes de que existiera el registro. No incluye paquetes del sistema
# que Ubuntu ya trae (python3, curl, wget): quitarlos podría romper otras cosas.
SCRIPT_PROGRAMS=(microsoft-edge-stable torbrowser-launcher telnet filezilla code virtualbox google-chrome-stable telegram-desktop python3-pip
    python3-venv git htop fastfetch timeshift gparted vim discord spotify-client obs-studio
    qrca build-essential alacritty gamemode mangohud steam-launcher steam-installer flatpak flatpak-builder
    openjdk-21-jdk-headless openjdk-17-jdk-headless android-sdk-platform-tools-common docker.io docker-buildx docker-compose-v2 brave-browser tlp tlp-rdw zram-tools corectrl
    nvidia-cuda-toolkit grub-customizer boot-repair refind)
#@parte apt: remove_installed_programs
#@parte comun: sysctl_default restore_sysctl_defaults
#@parte apt: disable_zram remove_tlp

# Muestra qué ajustes del script están activos. Devuelve 1 si no hay ninguno.
show_tweaks_status() {
    local changed=0 cmd
    changed_line() { echo -e "  ${YELLOW}⚙ $1${NC}"; changed=$((changed + 1)); }
    factory_line() { echo -e "  ${GREEN}✓ $1${NC}"; }

    echo -e "${YELLOW}📋 Estado actual de los ajustes:${NC}\n"
    if [ -s "$SYSCTL_FILE" ]; then
        changed_line "Ajustes del sistema cambiados:"
        sed 's/^/      /' "$SYSCTL_FILE"
    else
        factory_line "Ajustes del sistema (RAM, inotify, BBR): de fábrica"
    fi
    if [ -f "$RESOLVED_DNS_CONF" ]; then changed_line "DNS: $(current_dns)"; else factory_line "DNS: automático (el del router)"; fi
    if [ -f "$NM_WIFI_CONF" ]; then changed_line "Wi-Fi: ahorro de energía desactivado"; else factory_line "Wi-Fi: de fábrica"; fi
    if installed_pkgs zram-tools | grep -qx zram-tools; then changed_line "ZRAM: instalado"; else factory_line "ZRAM: no instalado"; fi
    if installed_pkgs tlp | grep -qx tlp; then
        changed_line "Energía: TLP instalado"
    elif command -v powerprofilesctl &> /dev/null && [ "$(powerprofilesctl get 2>/dev/null)" != "balanced" ]; then
        changed_line "Energía: perfil $(powerprofilesctl get 2>/dev/null)"
    else
        factory_line "Energía: equilibrado"
    fi
    if indexer_disabled; then
        changed_line "Indexador de archivos: desactivado"
    else
        factory_line "Indexador de archivos: activo (o no hay)"
    fi
    if [ -e /var/lib/man-db/auto-update ]; then factory_line "Indexación de manuales: activa"; else changed_line "Indexación de manuales: desactivada"; fi
    echo ""
    [ "$changed" -gt 0 ]
}

# Todo lo que el script cambia en la configuración, sin desinstalar programas
restore_all_tweaks() {
    echo -e "${YELLOW}🔧 Ajustes del sistema (RAM, inotify, BBR...)${NC}"
    restore_sysctl_defaults
    echo -e "${YELLOW}🌐 DNS y Wi-Fi${NC}"
    if [ -f "$RESOLVED_DNS_CONF" ]; then reset_dns; else echo -e "  ${GREEN}✓ El DNS ya es el automático${NC}"; fi
    if [ -f "$NM_WIFI_CONF" ]; then enable_wifi_powersave; else echo -e "  ${GREEN}✓ El ahorro del Wi-Fi ya está como de fábrica${NC}"; fi
    echo -e "${YELLOW}💾 ZRAM${NC}"
    disable_zram
    echo -e "${YELLOW}🔋 Energía${NC}"
    if installed_pkgs tlp | grep -qx tlp; then
        confirm "${YELLOW}¿Quitar TLP y volver al selector de energía del escritorio?${NC}" && remove_tlp
    elif command -v powerprofilesctl &> /dev/null; then
        set_power_profile balanced
    fi
    echo -e "${YELLOW}🔎 Indexadores${NC}"
    local cmd
    if indexer_disabled; then
        enable_indexer
    else
        echo -e "  ${GREEN}✓ El indexador de archivos ya está activo (o no hay)${NC}"
    fi
    if [ -e /var/lib/man-db/auto-update ]; then
        echo -e "  ${GREEN}✓ La indexación de manuales ya está activa${NC}"
    else
        enable_mandb
    fi
}

undo_menu() {
    while true; do
        clear
        echo -e "${RED}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    🩹 DESHACER OPTIMIZACIONES                    ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "  ${RED} 1)${NC} 📦 Ver y quitar PROGRAMAS instalados por el script"
        echo -e "  ${RED} 2)${NC} 🔧 Restaurar ajustes del sistema (RAM, inotify, BBR...) a sus valores de fábrica"
        echo -e "  ${RED} 3)${NC} 💾 Desactivar ZRAM"
        echo -e "  ${RED} 4)${NC} 🔋 Quitar TLP y volver al selector de energía del escritorio"
        echo -e "  ${RED} 5)${NC} 📋 Ver qué AJUSTES están cambiados y restaurarlos todos (no toca programas)"
        echo -e "  ${RED} 6)${NC} 🍷 Quitar Proton-GE"
        echo -e "  ${RED} 7)${NC} 🤖 Quitar Android Studio y/o el SDK de Android"
        echo -e "  ${RED} 8)${NC} 📦 Quitar los SDK de Flatpak (KDE, GNOME, Freedesktop)"
        echo -e "  ${RED} 9)${NC} 🐳 Quitar Docker (conservando tus datos, o eliminación nuclear)"
        echo -e "  ${RED}10)${NC} 💥 ELIMINACIÓN NUCLEAR de todo lo de desarrollo (Android, Flatpak SDK, Docker)"
        echo -e "         con respaldos antes de borrar"
        echo -e "  ${RED}11)${NC} 🖥️ Quitar el escritorio instalado por el script"
        echo -e "  ${RED}12)${NC} 🖥️ Quitar OTROS escritorios (no el original ni el que está abierto)"
        echo -e "  ${RED}13)${NC} 📝 Quitar el registro de auditoría (auditd)"
        echo -e "\n  ${RED} 0)${NC} 🔙 Volver"
        echo -e "\n${YELLOW}ℹ Otros cambios se deshacen en su menú: kernel (14), distribución original (11),${NC}"
        echo -e "${YELLOW}  Snap (9), accesos directos (6), DNS/BBR/Wi-Fi (16), energía e indexador (17)${NC}\n"
        read -r -p "📌 Opción (0-13): " undo_option

        case $undo_option in
            1) remove_installed_programs ;;
            2) restore_sysctl_defaults ;;
            3) disable_zram ;;
            4) remove_tlp ;;
            6) remove_proton_ge ;;
            7) remove_android ;;
            8) remove_flatpak_sdks ;;
            9) remove_docker ;;
            10) dev_nuclear ;;
            11) remove_installed_desktop ;;
            12) remove_extra_desktop ;;
            13) disable_audit ;;
            5)
                if ! show_tweaks_status; then
                    echo -e "${GREEN}✓ No hay ajustes cambiados: todo está como de fábrica${NC}"
                elif confirm "${RED}¿Restaurar a fábrica los ajustes marcados con ⚙?${NC}"; then
                    restore_all_tweaks
                else
                    echo -e "${YELLOW}ℹ Cancelado: no se cambió nada${NC}"
                fi
                ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
    done
}
#@parte comun: datos_info_quiet info_title cpu_temperature info_summary
#@parte apt: info_fastfetch

# Ejecuta inxi: el instalado o el paquete oficial de Ubuntu, usado sin instalar
info_inxi() {
    local flags="$1" tmp
    if command -v inxi &> /dev/null; then
        # shellcheck disable=SC2086  # varias opciones
        inxi $flags
        return
    fi
    $INFO_QUIET && return 0
    echo -e "${CYAN}ℹ inxi no está instalado. Se puede ver sin instalar: se descarga el paquete oficial de${NC}"
    echo -e "${CYAN}  Ubuntu (~350 KB) a una carpeta temporal y se borra al terminar.${NC}"
    confirm "${CYAN}¿Verlo sin instalar?${NC}" || return 0
    tmp=$(mktemp -d)
    apt_update
    if (cd "$tmp" && run "No se pudo descargar inxi" apt-get download inxi) \
        && dpkg-deb -x "$tmp"/inxi_*.deb "$tmp/x"; then
        # shellcheck disable=SC2086  # varias opciones
        perl "$tmp/x/usr/bin/inxi" $flags
    fi
    rm -rf "$tmp"
}
#@parte comun: info_cpu_ram info_gpu
#@parte apt: info_disks
#@parte comun: info_temps info_network info_battery info_usb info_diagnostics
#@parte apt: info_script_changes

# Informe completo en texto, sin preguntas ni descargas
info_full_report() {
    local was=$INFO_QUIET
    INFO_QUIET=true
    echo "Informe de Ubuntu Ultimate Tools · $(date '+%Y-%m-%d %H:%M')"
    info_summary
    info_cpu_ram
    info_gpu
    info_disks
    info_temps
    info_network
    info_battery
    info_usb
    info_diagnostics
    info_script_changes
    if command -v inxi &> /dev/null; then
        info_title "INXI"
        inxi -Fxxz -c 0 2>/dev/null | sed 's/^/  /'
    fi
    INFO_QUIET=$was
}
#@parte comun: privacy_filter info_search info_save_report

# Prueba rápida: velocidad del disco del usuario y de internet
info_benchmark() {
    local file free out
    info_title "VELOCIDAD DEL DISCO (carpeta personal)"
    free=$(df -Pm "$HOME" | awk 'NR == 2 {print $4}')
    if [ "${free:-0}" -lt 2048 ]; then
        echo "  No hay espacio libre suficiente para la prueba (hace falta 2 GB)"
    else
        file="$HOME/.prueba-velocidad-uut"
        out=$(LC_ALL=C dd if=/dev/zero of="$file" bs=1M count=1024 oflag=direct conv=fdatasync 2>&1 | tail -1)
        echo "  Escritura: ${out##*, }"
        out=$(LC_ALL=C dd if="$file" of=/dev/null bs=1M iflag=direct 2>&1 | tail -1)
        echo "  Lectura:   ${out##*, }"
        rm -f "$file"
    fi

    info_title "INTERNET"
    local avg start end bytes=50000000
    avg=$(LC_ALL=C ping -c 4 -q 1.1.1.1 2>/dev/null | awk -F'/' '/^rtt/ {print $5}')
    echo "  Latencia (ping a 1.1.1.1): ${avg:+$avg ms}${avg:-sin respuesta}"
    start=$(date +%s.%N)
    if wget -qO /dev/null "https://speed.cloudflare.com/__down?bytes=$bytes" 2>> "$LOG_FILE"; then
        end=$(date +%s.%N)
        awk -v b="$bytes" -v t="$(awk -v a="$start" -v z="$end" 'BEGIN {print z - a}')" \
            'BEGIN {printf "  Descarga: %.0f Mb/s (50 MB desde Cloudflare)\n", b * 8 / t / 1000000}'
    else
        echo "  Descarga: no se pudo medir (¿hay conexión a internet?)"
    fi
    echo "  (Valores aproximados: repítela si el equipo estaba ocupado)"
}

# ------------------------------------------------------------
# Auditoría de seguridad
# - Lynis (CISOfy, GPL-3.0): revisa la seguridad del sistema y da un puntaje con sugerencias.
#   Se puede usar sin instalar: se baja el paquete oficial de la distro (firmado) a una carpeta
#   temporal y se borra al terminar.
# - auditd (Linux Audit, GPL-2.0): registra cambios en usuarios, sudo, SSH, hora, módulos...
#   Las reglas son propias de este script, sin "-e 2" (no se bloquean) y se quitan cuando quieras.
# Idea inspirada en Linux-Security-Policy de Jeff Starke (Starke427): no se usa su código
# porque su repositorio no tiene licencia.
# ------------------------------------------------------------
AUDIT_RULES_FILE="/etc/audit/rules.d/60-ultimate-tools.rules"
SECURITY_DIR="$HOME/auditoria-seguridad"
#@parte auditoria: lynis_summary
#@parte apt: security_audit_lynis
#@parte auditoria: audit_rules_active

# Reglas del script: solo vigila rutas que existen y llamadas que existen en este procesador
build_audit_rules() {
    local p arch
    echo "## Ubuntu Ultimate Tools: registro de auditoría (se quita desde el menú 2 → 5)"
    echo "## Reglas propias del script (AGPL-3.0-or-later). Sin -e 2: no se bloquean hasta reiniciar."
    for p in "/etc/passwd:identidad" "/etc/group:identidad" "/etc/shadow:identidad" "/etc/gshadow:identidad" \
        "/etc/security/opasswd:identidad" "/etc/sudoers:sudo" "/etc/sudoers.d:sudo" \
        "/etc/ssh/sshd_config:ssh" "/etc/ssh/sshd_config.d:ssh" "/etc/localtime:hora" \
        "/etc/hosts:red" "/etc/hostname:red" "/etc/netplan:red" "/etc/crontab:tareas" "/etc/cron.d:tareas" \
        "/var/spool/cron:tareas" "/etc/systemd/system:servicios" "/etc/apt/sources.list:repositorios" \
        "/etc/apt/sources.list.d:repositorios" "/etc/pacman.conf:repositorios" "/etc/pacman.d:repositorios" "/var/log/faillog:sesiones" "/var/log/lastlog:sesiones"; do
        [ -e "${p%%:*}" ] && echo "-w ${p%%:*} -p wa -k ${p#*:}"
    done
    for p in /usr/bin/kmod /usr/sbin/insmod /usr/sbin/rmmod /usr/sbin/modprobe; do
        [ -e "$p" ] && [ ! -L "$p" ] && echo "-w $p -p x -k modulos"
    done
    arch=$(uname -m)
    if [ "$arch" = x86_64 ] || [ "$arch" = aarch64 ]; then
        echo "-a always,exit -F arch=b64 -S init_module -S finit_module -S delete_module -k modulos"
        echo "-a always,exit -F arch=b64 -S mount -S umount2 -F auid>=1000 -F auid!=4294967295 -k montajes"
        echo "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k hora"
    fi
}
#@parte apt: enable_audit
#@parte auditoria: show_audit_events
#@parte apt: disable_audit
#@parte auditoria: datos_linaudit_git linaudit_cleanup
LINAUDIT_BIN="/usr/local/bin/linaudit"
LINAUDIT_STATE="$STATE_DIR/linaudit.txt"
LINAUDIT_MIN_RUST="1.85"
#@parte auditoria: version_ge linaudit_need_cc linaudit_get_cargo linaudit_build linaudit_run security_audit_linaudit remove_linaudit security_menu
#@parte comun: info_htop

sysinfo_menu() {
    local option level
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    📊 INFORMACIÓN DEL SISTEMA                    ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo -e "${CYAN}👀 Vistas rápidas:${NC}"
        echo -e "  ${CYAN} 1)${NC} Resumen rápido (sin internet ni instalar nada)"
        echo -e "  ${CYAN} 2)${NC} Fastfetch (el instalado o uno temporal)"
        echo -e "  ${CYAN} 3)${NC} inxi: informe completo (el instalado o uno temporal)"
        echo -e "\n${CYAN}🔩 Hardware en detalle:${NC}"
        echo -e "  ${CYAN} 4)${NC} CPU y memoria RAM (cada módulo y ranuras libres)"
        echo -e "  ${CYAN} 5)${NC} Tarjeta gráfica y driver en uso"
        echo -e "  ${CYAN} 6)${NC} Discos, espacio y salud (SMART)"
        echo -e "  ${CYAN} 7)${NC} Temperaturas y ventiladores"
        echo -e "  ${CYAN} 8)${NC} Red: IP, Wi-Fi, velocidad del enlace y DNS"
        echo -e "  ${CYAN} 9)${NC} Batería: salud y ciclos"
        echo -e "  ${CYAN}10)${NC} USB y periféricos"
        echo -e "\n${CYAN}🩺 Estado del sistema:${NC}"
        echo -e "  ${CYAN}11)${NC} Diagnóstico: servicios fallidos, errores, arranque y procesos"
        echo -e "  ${CYAN}12)${NC} Qué cambió este script"
        echo -e "  ${CYAN}16)${NC} Procesos en vivo con htop (qué consume CPU y memoria)"
        echo -e "\n${CYAN}🧰 Herramientas:${NC}"
        echo -e "  ${CYAN}13)${NC} Buscar en toda la información"
        echo -e "  ${CYAN}14)${NC} Guardar informe completo para compartir (sin datos personales)"
        echo -e "  ${CYAN}15)${NC} Prueba de rendimiento (disco e internet)"
        echo -e "\n  ${CYAN} 0)${NC} 🔙 Volver"
        echo ""
        read -r -p "📌 Opción (0-16): " option
        case $option in
            1) info_summary ;;
            2) info_fastfetch ;;
            3)
                read -r -p "  Nivel: 1) normal  2) muy detallado [1]: " level
                if [ "$level" = 2 ]; then info_inxi "-Fxxx"; else info_inxi "-F"; fi ;;
            4) info_cpu_ram ;;
            5) info_gpu ;;
            6) info_disks ;;
            7) info_temps ;;
            8) info_network ;;
            9) info_battery ;;
            10) info_usb ;;
            11) info_diagnostics ;;
            12) info_script_changes ;;
            13) info_search ;;
            14) info_save_report ;;
            15) info_benchmark ;;
            16) info_htop ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
    done
}

# ============================================================
# MIGRACIÓN DESDE "KUBUNTU LITE"
# ============================================================

# Las versiones anteriores se llamaban "Kubuntu Lite" y guardaban su configuración con
# ese nombre. La primera vez se renombra todo (sin cambiar su contenido) para que el
# script siga reconociendo lo que ya se configuró. Si no hay nada viejo, no hace nada.
migrate_from_kubuntu_lite() {
    local old new pair f ext orig moved=false grub_changed=false
    local pairs=(
        "/etc/kubuntu-lite|$UUT_ETC"
        "/etc/sysctl.d/99-kubuntu-lite.conf|$SYSCTL_FILE"
        "/etc/modules-load.d/kubuntu-lite-bbr.conf|$BBR_MODULES_FILE"
        "/etc/NetworkManager/conf.d/99-kubuntu-lite-wifi.conf|$NM_WIFI_CONF"
        "/etc/systemd/resolved.conf.d/99-kubuntu-lite-dns.conf|$RESOLVED_DNS_CONF"
        "/etc/default/grub.kubuntu-lite.orig|$GRUB_DEFAULT_BACKUP"
        "/etc/grub.d/09_kubuntu_lite_otros_primero|$GRUB_OTHERS_FIRST"
        "/etc/grub.d/42_kubuntu_lite_apariencia|$GRUB_LOOK_FILE"
    )

    # Archivos del usuario
    rm -f "$HOME/kubuntu-lite.log"
    if [ -d "$HOME/.local/share/kubuntu-lite" ] && [ ! -e "$STATE_DIR" ]; then
        mkdir -p "$(dirname "$STATE_DIR")"
        mv "$HOME/.local/share/kubuntu-lite" "$STATE_DIR" && moved=true
    fi

    # Archivos del sistema
    for pair in "${pairs[@]}"; do
        old=${pair%%|*}
        new=${pair#*|}
        if [ -e "$old" ] && [ ! -e "$new" ]; then
            sudo mv "$old" "$new" && moved=true
            [[ "$new" == /etc/grub.d/* || "$new" == "$GRUB_DEFAULT_BACKUP" ]] && grub_changed=true
        fi
    done

    # Fondo de GRUB: archivo y ruta en /etc/default/grub
    for f in /boot/grub/kubuntu-lite-fondo.*; do
        [ -f "$f" ] || continue
        ext=${f##*.}
        sudo mv "$f" "/boot/grub/ubuntu-ultimate-tools-fondo.$ext"
        sudo sed -i '/^GRUB_BACKGROUND=/s|kubuntu-lite-fondo\.|ubuntu-ultimate-tools-fondo.|' /etc/default/grub
        moved=true
        grub_changed=true
    done

    # Filtros de entradas ocultas: llevan las rutas dentro, se escriben de nuevo
    for f in /etc/grub.d/*_kubuntu_lite; do
        [ -f "$f" ] || continue
        orig=${f%_kubuntu_lite}
        sudo rm -f "$f"
        [ -f "$orig" ] && write_grub_filter_wrapper "$orig"
        moved=true
        grub_changed=true
    done

    $moved || return 0
    # Los que llevan rutas dentro se reescriben con las nuevas
    [ -f "$GRUB_FILTER_AWK" ] && write_grub_filter
    [ -f "$GRUB_OTHERS_FIRST" ] && write_others_first_script
    log_success "Configuración de \"Kubuntu Lite\" pasada a \"Ubuntu Ultimate Tools\""
    if $grub_changed; then
        regen_grub || log_warning "Revisa el menú de GRUB en la opción 19"
    fi
}

# ============================================================
# MENÚ PRINCIPAL (COLOR: CIAN)
# ============================================================

# Ubuntu y sus derivadas (Kubuntu, Mint, Pop!_OS...) usan todo el script; en las demás
# distribuciones solo está el menú de arranque, que funciona en cualquier Linux con GRUB
ubuntu_based() {
    [[ " $(os_release_value ID) $(os_release_value ID_LIKE) " == *" ubuntu "* ]]
}

BOOT_ONLY=false

boot_only_menu() {
    while true; do
        print_header
        echo -e "${CYAN}ℹ En ${BOOT_DISTRO} está disponible el menú de arranque (GRUB y EFI), que sirve en${NC}"
        echo -e "${CYAN}  Ubuntu, Debian, Arch, Manjaro, Fedora y openSUSE, y descargar sistemas y crear un USB.${NC}"
        echo -e "${CYAN}  El resto del script es para Ubuntu.${NC}\n"
        echo -e "${CYAN}📌 ¿Qué deseas hacer?${NC}\n"
        echo -e "  ${CYAN}19)${NC} 🔧 ARRANQUE: reparar y personalizar GRUB/EFI"
        echo ""
        echo -e "  ${CYAN}20)${NC} 💿 DESCARGAR SISTEMAS (ISO) Y CREAR USB DE INSTALACIÓN"
        echo ""
        echo -e "  ${CYAN}21)${NC} 🔌 Apagar / Reiniciar sistema"
        echo -e "\n  ${CYAN} 0)${NC} ❌ Salir"
        echo ""
        read -r -p "🔢 Opción (19, 20, 21 o 0): " option
        case $option in
            19|1) ( MENU_SUBSHELL=1; grub_repair_menu ) ;;
            20) ( MENU_SUBSHELL=1; create_usb_menu; pause ) ;;
            21|2) ( MENU_SUBSHELL=1; shutdown_menu ) ;;
            0)
                echo -e "\n${GREEN}✅ ¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Opción inválida${NC}"
                sleep 1
                ;;
        esac
    done
}
#@parte usb: datos_usb_distros usb_download_dir usb_norm_sums usb_pick_from_sums usb_first_hash usb_hash_of usb_hash_name usb_check_signature usb_index_names usb_sorted usb_resolve_download usb_choose_distro usb_download_iso usb_write_sum_file usb_pick_local_iso usb_entry_pattern usb_official_sum_for usb_sum_lookup usb_known_sum usb_verify_local_iso usb_check_iso usb_candidates usb_pick_device usb_unmount_dev create_usb_menu datos_ventoy_dir ventoy_get_tool ventoy_has ventoy_need_partitioner ventoy_part_label ventoy_find_part ventoy_run ventoy_candidates ventoy_pick_and_mount ventoy_list_images ventoy_write_json ventoy_conf_set ventoy_alias_for ventoy_install ventoy_add ventoy_guess_name ventoy_manage ventoy_persistence_kind ventoy_persistence ventoy_update ventoy_menu

main_menu() {
    $BOOT_ONLY && boot_only_menu
    while true; do
        print_header
        echo -e "${CYAN}📌 ¿Qué deseas hacer?${NC}\n"
        echo -e "  ${CYAN} 1)${NC} 🔄 ACTUALIZAR SISTEMA (update/upgrade/clean)"
        echo -e "  ${CYAN} 2)${NC} 🛡️ AUDITORÍA DE SEGURIDAD (Lynis y registro de auditoría)"
        echo -e "  ${CYAN} 3)${NC} 📊 Información del sistema y hardware"
        echo ""
        echo -e "  ${CYAN} 4)${NC} 🚮 Eliminar aplicaciones preinstaladas"
        echo -e "  ${CYAN} 5)${NC} 💥 ELIMINACIÓN NUCLEAR DE SNAP"
        echo -e "  ${CYAN} 6)${NC} 🧹 Quitar accesos directos (escritorio y panel)"
        echo ""
        if has_desktop; then
            echo -e "  ${CYAN} 7)${NC} 📦 Instalar software opcional"
        else
            echo -e "  ${CYAN} 7)${NC} 📦 Instalar software opcional o un ESCRITORIO (KDE, GNOME, Xfce...)"
        fi
        echo -e "  ${CYAN} 8)${NC} 💻 Instalar Alacritty (terminal GPU) y temas"
        echo -e "  ${CYAN} 9)${NC} 📥 Reinstalar Snap"
        echo -e "  ${CYAN}10)${NC} 🩹 Deshacer optimizaciones / quitar programas"
        echo -e "  ${CYAN}11)${NC} ⏪ Revertir a distribución original"
        echo ""
        if [ "$FLAVOR" = kubuntu ]; then
            echo -e "  ${CYAN}12)${NC} 🔩 Configurar sistema (meta-paquete, manuales, Rolling Release solo Kubuntu)"
        else
            echo -e "  ${CYAN}12)${NC} 🔩 Configurar sistema (meta-paquete y manuales)"
        fi
        echo -e "  ${CYAN}13)${NC} 🎮 Optimizar GPU (NVIDIA/AMD/Intel)"
        echo -e "  ${CYAN}14)${NC} 🐧 Optimizar Kernel (Liquorix/XanMod/Estándar)"
        echo -e "  ${CYAN}15)${NC} 💾 Optimizar Memoria RAM (automático)"
        echo -e "  ${CYAN}16)${NC} 🌐 Red, DNS y drivers"
        echo -e "  ${CYAN}17)${NC} 🔋 Energía y rendimiento"
        echo -e "  ${CYAN}18)${NC} 🚀 PERFILES AUTOMÁTICOS (gaming, productividad...)"
        echo -e "  ${CYAN}19)${NC} 🔧 ARRANQUE: reparar y personalizar GRUB/EFI"
        echo ""
        echo -e "  ${CYAN}20)${NC} 💿 DESCARGAR SISTEMAS (ISO) Y CREAR USB DE INSTALACIÓN"
        echo ""
        echo -e "  ${CYAN}21)${NC} 🔌 Apagar / Reiniciar sistema"
        echo -e "\n  ${CYAN} 0)${NC} ❌ Salir"
        echo ""
        read -r -p "🔢 Opción (0-21): " option

        case $option in
            1) ( MENU_SUBSHELL=1; system_update ) ;;
            2) ( MENU_SUBSHELL=1; security_menu ) ;;
            3) ( MENU_SUBSHELL=1; sysinfo_menu ) ;;
            4) ( MENU_SUBSHELL=1; select_apps_to_remove ) ;;
            5) ( MENU_SUBSHELL=1; nuclear_snap_removal ) ;;
            6) ( MENU_SUBSHELL=1; remove_shortcuts_menu ) ;;
            7) ( MENU_SUBSHELL=1; select_optional_software ) ;;
            8) ( MENU_SUBSHELL=1; install_custom_software ) ;;
            9) ( MENU_SUBSHELL=1; reinstall_snap ) ;;
            10) ( MENU_SUBSHELL=1; undo_menu ) ;;
            11) ( MENU_SUBSHELL=1; revert_changes ) ;;
            12) ( MENU_SUBSHELL=1; configure_system ) ;;
            13) ( MENU_SUBSHELL=1; optimize_gpu_menu ) ;;
            14) ( MENU_SUBSHELL=1; optimize_kernel_menu ) ;;
            15) ( MENU_SUBSHELL=1; optimize_ram_menu ) ;;
            16) ( MENU_SUBSHELL=1; network_menu ) ;;
            17) ( MENU_SUBSHELL=1; power_menu ) ;;
            18) ( MENU_SUBSHELL=1; profiles_menu ) ;;
            19) ( MENU_SUBSHELL=1; grub_repair_menu ) ;;
            20) ( MENU_SUBSHELL=1; create_usb_menu; pause ) ;;
            21) ( MENU_SUBSHELL=1; shutdown_menu ) ;;
            0)
                echo -e "\n${GREEN}✅ ¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Opción inválida${NC}"
                sleep 1
                ;;
        esac
    done
}
#@parte comun: datos_notice_version

first_run_notice() {
    [ "$(sed -n 's/^version=//p' "$NOTICE_FILE" 2>/dev/null)" = "$NOTICE_VERSION" ] && return 0
    $NOTICE_OK && { notice_save; return 0; }
    echo -e "${CYAN}${BOLD}📜 AVISO ANTES DEL PRIMER USO${NC}\n"
    echo -e "${BOLD}Ubuntu Ultimate Tools${NC} es software libre bajo la licencia ${BOLD}GNU AGPL-3.0${NC} (archivo LICENSE)."
    echo -e "  • Puedes usarlo, estudiarlo, modificarlo y compartirlo. Si distribuyes una versión modificada,"
    echo -e "    o la ofreces como servicio en red, debes publicar su código con la misma licencia."
    echo -e "  • Se ofrece ${BOLD}SIN GARANTÍA${NC} de ningún tipo (secciones 15 y 16 de la licencia)."
    echo -e "  • ${YELLOW}⚠ Este script MODIFICA TU SISTEMA:${NC} quita programas, cambia el arranque (GRUB),"
    echo -e "    instala kernels y drivers... Casi todo se puede deshacer (opciones 10 y 11 del menú),"
    echo -e "    pero conviene tener una copia de seguridad de tus archivos."
    echo -e "  • Créditos y licencias de todo el software que usa: CREDITOS.md"
    echo -e "\n${CYAN}No necesitas aceptar la licencia para usar el script: esto solo confirma que entiendes lo que hace.${NC}"
    echo -e "${CYAN}Este aviso aparece una sola vez.${NC}\n"
    if [ ! -t 0 ]; then
        echo -e "${YELLOW}ℹ Para usarlo sin terminal interactiva (por ejemplo en servidores o tareas programadas),${NC}"
        echo -e "${YELLOW}  agrega --entiendo después de leer este aviso.${NC}"
        exit 1
    fi
    local answer
    read -r -p "¿Entiendes y quieres continuar? (s/n): " answer
    if [[ "$answer" =~ ^([sSyY]|[sS][iIíÍ])$ ]]; then
        notice_save
        echo ""
    else
        echo -e "\n${YELLOW}De acuerdo: no se cambió nada. Puedes volver cuando quieras.${NC}"
        exit 0
    fi
}
#@parte comun: notice_save

SCRIPT_FAMILY=ubuntu
#@parte comun: right_script_family offer_right_script

# ============================================================
# INICIO
# ============================================================

usage() {
    cat << EOF
Uso: $0 [opciones]

  (sin opciones)          Menú interactivo
  -p, --perfil NOMBRE     Aplica un perfil automáticamente
  -y, --si                No pedir confirmación antes de aplicar el perfil
  -l, --perfiles          Lista los perfiles disponibles
  -h, --ayuda             Muestra esta ayuda
      --entiendo          No mostrar el aviso del primer uso (si ya lo leíste)

Ejemplos:
  $0 --perfil gaming
  $0 --perfil productividad --si
EOF
}

PROFILE=""
NOTICE_OK=false
while [ $# -gt 0 ]; do
    case $1 in
        -p|--perfil)
            PROFILE="$2"
            if [ -z "$PROFILE" ]; then
                echo -e "${RED}❌ Falta el nombre del perfil${NC}"
                list_profiles
                exit 1
            fi
            shift ;;
        -y|--si) ASSUME_YES=true ;;
        -l|--perfiles) list_profiles; exit 0 ;;
        -h|--ayuda) usage; exit 0 ;;
        --entiendo) NOTICE_OK=true ;;
        *) echo -e "${RED}❌ Opción desconocida: $1${NC}\n"; usage; exit 1 ;;
    esac
    shift
done

if [ -n "$PROFILE" ] && [ -z "$(profile_steps "$PROFILE")" ]; then
    echo -e "${RED}❌ Perfil desconocido: $PROFILE${NC}\n"
    list_profiles
    exit 1
fi

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}❌ No ejecutes este script como root (no uses sudo)${NC}"
    exit 1
fi

set_terminal_title "Ubuntu Ultimate Tools · $(os_release_value PRETTY_NAME)"

# Antes de pedir la contraseña o tocar nada
first_run_notice
offer_right_script

echo "=== Ubuntu Ultimate Tools - $(date) ===" > "$LOG_FILE"

# Pide la contraseña una sola vez y la mantiene activa mientras corre el script
echo -e "${YELLOW}🔑 Se necesitan permisos de administrador${NC}"
if ! sudo -v; then
    echo -e "${RED}❌ No se pudo obtener sudo${NC}"
    exit 1
fi
while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 60; done 2>/dev/null &

migrate_from_kubuntu_lite
boot_detect
if ubuntu_based; then
    detect_flavor
    boot_detect   # otra vez, ahora con el nombre del sabor
    cleanup_pending_kernels
else
    BOOT_ONLY=true
    FLAVOR_NAME="$BOOT_DISTRO" DESKTOP_NAME="modo arranque"
    if [ -n "$PROFILE" ]; then
        echo -e "${RED}❌ Los perfiles son solo para Ubuntu y sus sabores (este sistema es $BOOT_DISTRO)${NC}"
        exit 1
    fi
fi

if [ -n "$PROFILE" ]; then
    run_profile "$PROFILE"
    exit $?
fi

main_menu
