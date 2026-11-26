#@ partes/arch.sh — lo propio del script de Arch y el orden de todo el script.
#@ Las líneas "#@parte pieza: nombres" se reemplazan por esas funciones de partes/<pieza>.sh al correr "bash armar.sh".
#@ Las líneas "#@" no pasan al script final.
#!/bin/bash

# ============================================================
# Script: Arch Ultimate Tools — VERSIÓN BETA
# Descripción: Limpia, optimiza y repara Arch Linux y derivadas (Manjaro, EndeavourOS...)
#              desde un solo menú. Hermano de ubuntu-ultimate-tools.sh.
# Versión: 0.1 BETA — probado con sistemas simulados; úsalo con cuidado y reporta errores
# Autor: Old The One Deluxe (@george0884)
# Licencia: GNU AGPL v3 o posterior (ver archivo LICENSE)
# Créditos del software que instala o usa: ver CREDITOS.md
# SPDX-License-Identifier: AGPL-3.0-or-later
# ============================================================

# ============================================================
# CONFIGURACIÓN INICIAL
# ============================================================

LOG_FILE="$HOME/arch-ultimate-tools.log"
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")

# Estado guardado entre ejecuciones (lo usa "Revertir")
STATE_DIR="$HOME/.local/share/arch-ultimate-tools"
REMOVED_LIST="$STATE_DIR/paquetes-eliminados.txt"
INSTALLED_LIST="$STATE_DIR/paquetes-instalados.txt"
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
    echo "║                 ARCH ULTIMATE TOOLS  ·  BETA                     ║"
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
free() { LC_ALL=C command free "$@"; }

# Sin preguntas: ante un archivo de configuración modificado se conserva el del usuario
APT_LISTS_FRESH=false

# ------------------------------------------------------------
# Paquetes con pacman. En Arch no se refresca la base de paquetes sin actualizar todo
# (instalar con "pacman -Sy" a medias rompe el sistema): si un paquete ya no está en
# los servidores, se ofrece actualizar el sistema completo y reintentar.
# ------------------------------------------------------------

PACMAN_LOCK="/var/lib/pacman/db.lck"

# Líneas del log escritas desde la marca (así se mira solo lo que dijo el último comando)
log_mark() { wc -l < "$LOG_FILE" 2>/dev/null || echo 0; }
log_since() { tail -n +"$(( $1 + 1 ))" "$LOG_FILE" 2>/dev/null; }

# Si pacman quedó bloqueado por un corte, se ofrece desbloquearlo (solo si no está corriendo)
pacman_unlock() {
    [ -e "$PACMAN_LOCK" ] || return 0
    if pgrep -x pacman &> /dev/null || pgrep -x pamac &> /dev/null || pgrep -x yay &> /dev/null || pgrep -x paru &> /dev/null; then
        log_error "Otro programa está instalando paquetes (pacman/pamac): espera a que termine"
        return 1
    fi
    log_warning "pacman quedó bloqueado (probablemente por una instalación cortada)"
    confirm "${YELLOW}¿Desbloquearlo? (no hay ninguna instalación en curso)${NC}" || return 1
    sudo rm -f "$PACMAN_LOCK"
}

# Compatibilidad: el resto del script llama así a "actualizar la lista de paquetes".
# En Arch no se hace por separado (ver arriba); solo se comprueba el bloqueo.
pkg_refresh() { pacman_unlock; }

pkg_install() {
    local args=() a
    for a in "$@"; do
        [[ "$a" == --allow-* ]] && continue   # opciones de apt que no existen en pacman
        args+=("$a")
    done
    [ ${#args[@]} -gt 0 ] || return 0
    pacman_unlock || return 1
    local mark
    mark=$(log_mark)
    if run "No se pudo instalar: ${args[*]}" sudo pacman -S --needed --noconfirm "${args[@]}"; then
        return 0
    fi
    # Base de paquetes vieja: los servidores ya no tienen esa versión (error 404)
    if log_since "$mark" | grep -qE 'failed retrieving file|error 404|could not find or read package'; then
        log_warning "Tu lista de paquetes está desactualizada: hay que actualizar el sistema antes de instalar"
        if confirm "${YELLOW}¿Actualizar todo el sistema ahora (pacman -Syu) y reintentar?${NC}"; then
            pacman_full_upgrade && run "No se pudo instalar: ${args[*]}" sudo pacman -S --needed --noconfirm "${args[@]}"
            return
        fi
    fi
    return 1
}

pkg_remove() { pacman_unlock && run "No se pudo eliminar: $*" sudo pacman -Rns --noconfirm "$@"; }

# Instala y anota en INSTALLED_LIST los paquetes que NO estaban instalados antes,
# para poder quitarlos después desde "Deshacer optimizaciones" (opción 10).
pkg_install_recorded() {
    local new=() arg
    for arg in "$@"; do
        [[ "$arg" == -* ]] && continue
        pkg_installed "$arg" | grep -qx -- "$arg" || new+=("$arg")
    done
    pkg_install "$@" || return 1
    if [ ${#new[@]} -gt 0 ]; then
        mkdir -p "$STATE_DIR"
        printf '%s\n' "${new[@]}" >> "$INSTALLED_LIST"
        sort -u -o "$INSTALLED_LIST" "$INSTALLED_LIST"
    fi
}

# Paquetes instalados de la lista (acepta comodines como 'linux*-headers')
pkg_installed() {
    local p all
    all=$(pacman -Qq 2>/dev/null)
    for p in "$@"; do
        if [[ "$p" == *[\*\?\[]* ]]; then
            # shellcheck disable=SC2053  # comparación con comodín a propósito
            while read -r q; do [[ "$q" == $p ]] && echo "$q"; done <<< "$all"
        else
            grep -qx -- "$p" <<< "$all" && echo "$p"
        fi
    done
}

# Paquetes de la lista que existen en los repositorios activos
pkg_available() {
    local p
    for p in "$@"; do
        pacman -Si -- "$p" &> /dev/null && echo "$p"
    done
}

# Lo que quitaría pacman (con sus dependencias que quedan sin uso). Falla si otro
# paquete instalado necesita alguno de ellos.
pkg_removal_set() { LC_ALL=C pacman -Rsp --print-format '%n' "$@" 2>/dev/null; }

# Elimina paquetes y anota todo lo que se fue (también dependencias) para poder revertir
purge_and_record() {
    local removed
    removed=$(pkg_removal_set "$@")
    pkg_remove "$@" || return 1
    if [ -n "$removed" ]; then
        mkdir -p "$STATE_DIR"
        echo "$removed" >> "$REMOVED_LIST"
        sort -u -o "$REMOVED_LIST" "$REMOVED_LIST"
    fi
}

# En Arch no hay meta-paquetes de escritorio que reinstalar
flavor_meta_pkgs() { return 0; }

# Piezas esenciales que se irían al quitar estos paquetes
core_pkgs_removed_by() {
    pkg_removal_set "$@" | grep -xF -f <(printf '%s\n' "${CORE_PKGS[@]}")
}

pkg_description() { LC_ALL=C pacman -Qi "$1" 2>/dev/null | sed -n 's/^Description *: //p'; }

# Paquetes huérfanos (dependencias que ya nadie usa)
pkg_orphans() { pacman -Qdtq 2>/dev/null; }

remove_orphans() {
    local orphans=()
    mapfile -t orphans < <(pkg_orphans)
    if [ ${#orphans[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No hay paquetes huérfanos${NC}"
        return 0
    fi
    run "No se pudieron quitar los paquetes huérfanos" sudo pacman -Rns --noconfirm "${orphans[@]}" \
        && log_success "Quitados ${#orphans[@]} paquetes huérfanos"
}

# Actualización completa, con las salidas para los fallos típicos de Arch
pacman_full_upgrade() {
    pacman_unlock || return 1
    local mark
    mark=$(log_mark)
    if run_visible "Falló la actualización" sudo pacman -Syu --noconfirm; then
        return 0
    fi
    # Firmas inválidas: el llavero de la distribución está viejo
    if log_since "$mark" | grep -qE 'invalid or corrupted package|signature from .* is unknown trust|PGP signature'; then
        log_warning "Las llaves de firma están viejas: se actualiza el llavero y se reintenta"
        local keyrings=(archlinux-keyring)
        [ -n "$(pkg_installed manjaro-keyring)" ] && keyrings+=(manjaro-keyring)
        [ -n "$(pkg_installed endeavouros-keyring)" ] && keyrings+=(endeavouros-keyring)
        run_visible "No se pudo actualizar el llavero" sudo pacman -Sy --needed --noconfirm "${keyrings[@]}" \
            && run_visible "Falló la actualización" sudo pacman -Su --noconfirm && return 0
    fi
    # Archivos que existen en el disco pero no son de ningún paquete
    if log_since "$mark" | grep -q 'exists in filesystem'; then
        log_error "Hay archivos que chocan con un paquete (\"exists in filesystem\")"
        echo -e "${YELLOW}  Revisa el log ($LOG_FILE): suele ser un programa instalado a mano en /usr.${NC}"
        echo -e "${YELLOW}  No se fuerza la instalación porque podría pisar archivos tuyos.${NC}"
    fi
    return 1
}

# ------------------------------------------------------------
# Flathub como alternativa a los repositorios oficiales. El AUR NO se usa: cualquiera
# puede subir paquetes y ya hubo casos con malware. Solo repositorios oficiales y Flathub.
# ------------------------------------------------------------

FLATPAK_APPS_LIST="$STATE_DIR/flatpak-apps.txt"

# Instala una app de Flathub (instala Flatpak si hace falta)
flathub_install() {
    local id="$1"
    command -v flatpak &> /dev/null && flatpak remotes 2>/dev/null | grep -qw flathub || install_flatpak || return 1
    run_visible "No se pudo instalar $id desde Flathub" sudo flatpak install -y --noninteractive flathub "$id" || return 1
    mkdir -p "$STATE_DIR"
    echo "$id" >> "$FLATPAK_APPS_LIST"
    sort -u -o "$FLATPAK_APPS_LIST" "$FLATPAK_APPS_LIST"
}

# Repositorio multilib (programas de 32 bits: Steam, Wine, drivers lib32)
multilib_enabled() { grep -q '^\[multilib\]' /etc/pacman.conf; }

enable_multilib() {
    if multilib_enabled; then
        echo -e "  ${GREEN}✓ multilib ya está activo${NC}"
        return 0
    fi
    sudo cp -p /etc/pacman.conf "/etc/pacman.conf.antes-de-arch-ultimate-tools" 2>/dev/null
    # Descomenta el bloque [multilib] y su línea Include
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    if ! multilib_enabled; then
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf > /dev/null
    fi
    # Activar un repositorio exige actualizar todo (pacman -Syu), nunca solo -Sy
    if pacman_full_upgrade; then
        log_success "multilib activado (Steam, Wine y drivers de 32 bits)"
    else
        log_error "Falló la actualización con multilib: se vuelve a la configuración anterior"
        sudo cp -p "/etc/pacman.conf.antes-de-arch-ultimate-tools" /etc/pacman.conf
        return 1
    fi
}

need_multilib() {
    multilib_enabled && return 0
    echo -e "${YELLOW}⚠ $1 necesita el repositorio multilib (programas de 32 bits), que viene apagado${NC}"
    confirm "${YELLOW}¿Activarlo ahora? (actualiza todo el sistema)${NC}" && enable_multilib
}

# Regenera la imagen de arranque (Arch usa mkinitcpio; EndeavourOS, dracut)
regen_initramfs() {
    if command -v mkinitcpio &> /dev/null; then
        run "No se pudo regenerar initramfs" sudo mkinitcpio -P
    elif command -v dracut &> /dev/null; then
        run "No se pudo regenerar initramfs" sudo dracut --regenerate-all --force
    elif command -v dracut-rebuild &> /dev/null; then
        run "No se pudo regenerar initramfs" sudo dracut-rebuild
    else
        log_warning "No se encontró mkinitcpio ni dracut: el cambio se aplica al instalar el próximo kernel"
    fi
}

# lspci (pciutils) no siempre viene en Arch
ensure_lspci() {
    command -v lspci &> /dev/null || pkg_install pciutils
}


# Quita paquetes del registro de instalados
forget_installed() {
    [ -f "$INSTALLED_LIST" ] || return 0
    local p
    for p in "$@"; do
        sed -i "/^${p//./\\.}\$/d" "$INSTALLED_LIST"
    done
}

SYSCTL_FILE="/etc/sysctl.d/99-arch-ultimate-tools.conf"
BBR_MODULES_FILE="/etc/modules-load.d/arch-ultimate-tools-bbr.conf"
#@parte comun: set_sysctl datos_whiptail_colors checklist_tool checklist_select

# ============================================================
# SABOR DE UBUNTU Y ESCRITORIO
# ============================================================

FLAVOR=""          # kde, gnome, xfce, cinnamon, mate, lxqt, budgie, server
FLAVOR_NAME=""     # Nombre para mostrar (Arch Linux, Manjaro Linux, EndeavourOS...)
FLAVOR_META=""     # Siempre vacío: Arch no tiene meta-paquetes de escritorio
DESKTOP=""         # kde, gnome, xfce, lxqt, mate, budgie, cinnamon, unity, ukui, none
DESKTOP_NAME=""    # Nombre del escritorio para mostrar

# escritorio|nombre|meta-paquete|escritorio|nombre del escritorio|paquete que lo identifica
# Arch no tiene meta-paquetes de escritorio: se reconoce por el paquete de la sesión
FLAVORS=(
    "kde|Arch Linux||kde|KDE Plasma|plasma-workspace"
    "gnome|Arch Linux||gnome|GNOME|gnome-shell"
    "xfce|Arch Linux||xfce|Xfce|xfce4-session"
    "cinnamon|Arch Linux||cinnamon|Cinnamon|cinnamon"
    "mate|Arch Linux||mate|MATE|mate-session-manager"
    "lxqt|Arch Linux||lxqt|LXQt|lxqt-session"
    "budgie|Arch Linux||budgie|Budgie|budgie-desktop"
)

# Detecta el sabor por su meta-paquete o, si se quitó (opción 12), por su escritorio
detect_flavor() {
    local entry meta marker found=""
    for entry in "${FLAVORS[@]}"; do
        IFS='|' read -r _ _ meta _ _ marker <<< "$entry"
        [ -n "$meta" ] && pkg_installed "$meta" | grep -qx -- "$meta" && { found=$entry; break; }
    done
    # Si se quitó con la opción 12, queda anotado: así un Ubuntu mínimo no se confunde con el completo
    if [ -z "$found" ] && [ -s "$REMOVED_LIST" ]; then
        for entry in "${FLAVORS[@]}"; do
            IFS='|' read -r _ _ meta _ _ _ <<< "$entry"
            [ -n "$meta" ] && grep -qx -- "$meta" "$REMOVED_LIST" && { found=$entry; break; }
        done
    fi
    if [ -z "$found" ]; then
        for entry in "${FLAVORS[@]}"; do
            IFS='|' read -r _ _ _ _ _ marker <<< "$entry"
            if pkg_installed "$marker" | grep -qx -- "$marker"; then found=$entry; break; fi
        done
    fi
    if [ -n "$found" ]; then
        IFS='|' read -r FLAVOR FLAVOR_NAME FLAVOR_META DESKTOP DESKTOP_NAME _ <<< "$found"
    else
        FLAVOR=server FLAVOR_NAME="Arch Linux" FLAVOR_META="" DESKTOP=none DESKTOP_NAME="sin escritorio"
    fi
    # Manjaro, EndeavourOS...: se muestra su nombre
    FLAVOR_NAME=$(os_release_value NAME)
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
    "libreoffice-fresh|📄 LibreOffice (versión más nueva)"
    "libreoffice-still|📄 LibreOffice (versión estable)"
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


# Qué es cada paquete (así un nombre suelto no asusta)
pkg_summary() { pkg_description "$1"; }
#@parte comun: print_pkgs_described

# Piezas sin las que el escritorio o el sistema dejan de funcionar: si quitar una app
# las arrastraría por dependencias, esa app no se quita
CORE_PKGS=(plasma-desktop plasma-workspace kwin systemsettings dolphin sddm
    gnome-shell gnome-session mutter nautilus gnome-control-center gdm
    xfce4-session xfce4-panel xfwm4 xfdesktop thunar lightdm
    lxqt-session lxqt-panel openbox pcmanfm-qt
    mate-session-manager mate-panel marco caja
    budgie-desktop nemo cinnamon cinnamon-session
    networkmanager pipewire wireplumber pulseaudio xorg-server xorg-xwayland
    sudo systemd polkit grub base linux linux-lts linux-zen linux-firmware pacman
    python perl bash coreutils glibc)
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

    echo -e "${CYAN}🖥️ Apps de ${FLAVOR_NAME} (${DESKTOP_NAME}) y comunes a todas las distribuciones${NC}\n"
    local apps=()
    mapfile -t apps < <(flavor_app_list)

    # Solo se ofrecen las que están instaladas
    local installed=() entries=() app
    mapfile -t installed < <(pkg_installed "${apps[@]%%|*}")
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

# ============================================================
# OPCIÓN 12: CONFIGURAR SISTEMA (COLOR: VERDE)
# ============================================================

# Lista de servidores (espejos) más rápidos. Arch/EndeavourOS: reflector; Manjaro: pacman-mirrors.
# Antes se guarda la lista actual; si algo falla, se vuelve a ella.
update_mirrors() {
    local list=/etc/pacman.d/mirrorlist
    if is_manjaro && command -v pacman-mirrors &> /dev/null; then
        run_visible "pacman-mirrors no pudo elegir servidores" sudo pacman-mirrors --fasttrack 5 || return 1
    else
        command -v reflector &> /dev/null || pkg_install_recorded reflector || return 1
        sudo cp -p "$list" "$list.antes-de-arch-ultimate-tools"
        if ! run_visible "reflector no pudo medir los servidores" sudo reflector --latest 20 --protocol https \
            --sort rate --save "$list" || [ ! -s "$list" ] || ! grep -q '^Server' "$list"; then
            log_error "Se vuelve a la lista de servidores anterior"
            sudo cp -p "$list.antes-de-arch-ultimate-tools" "$list"
            return 1
        fi
    fi
    log_success "Servidores actualizados: los más rápidos para tu conexión"
    log_info "Para usarlos se aplica con la próxima actualización (opción 1)"
}

# Descargas en paralelo y colores en pacman
tune_pacman_conf() {
    sudo cp -p /etc/pacman.conf "/etc/pacman.conf.antes-de-arch-ultimate-tools"
    sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/; s/^#Color$/Color/' /etc/pacman.conf
    grep -q '^ParallelDownloads' /etc/pacman.conf || sudo sed -i '/^\[options\]/a ParallelDownloads = 5' /etc/pacman.conf
    log_success "pacman: 5 descargas en paralelo y salida con colores"
}

configure_system() {
    clear
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔩 CONFIGURAR SISTEMA                         ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}🐧 $(os_release_value PRETTY_NAME)${NC}"

    echo -e "\n${GREEN}1. Repositorio multilib (programas de 32 bits)${NC}"
    echo -e "   ${GREEN}✓ Hace falta para:${NC} Steam, Wine y los drivers de 32 bits de los juegos"
    if multilib_enabled; then
        echo -e "   ${GREEN}✓ Ya está activo${NC}"
    elif confirm "${GREEN}¿Activar multilib? (actualiza todo el sistema)${NC}"; then
        enable_multilib
    fi

    echo -e "\n${GREEN}2. Descargas en paralelo${NC}"
    echo -e "   ${GREEN}✓ Beneficio:${NC} Las actualizaciones bajan varias veces más rápido"
    if grep -q '^ParallelDownloads' /etc/pacman.conf; then
        echo -e "   ${GREEN}✓ Ya están activas ($(sed -n 's/^ParallelDownloads *= *//p' /etc/pacman.conf))${NC}"
    elif confirm "${GREEN}¿Activarlas?${NC}"; then
        tune_pacman_conf
    fi

    echo -e "\n${GREEN}3. Servidores más rápidos${NC}"
    echo -e "   ${GREEN}📝 Descripción:${NC} Mide los servidores de paquetes y usa los más rápidos"
    if confirm "${GREEN}¿Buscar los servidores más rápidos? (tarda 1-2 minutos)${NC}"; then
        update_mirrors
    fi

    echo -e "\n${GREEN}4. Limpieza automática de la caché de paquetes${NC}"
    echo -e "   ${GREEN}✓ Beneficio:${NC} pacman guarda todas las versiones viejas; esto deja solo las 3 últimas"
    if systemctl is-enabled paccache.timer &> /dev/null; then
        echo -e "   ${GREEN}✓ Ya está activa${NC}"
    elif confirm "${GREEN}¿Activarla? (instala pacman-contrib)${NC}"; then
        pkg_install_recorded pacman-contrib && run "No se pudo activar paccache.timer" sudo systemctl enable --now paccache.timer \
            && log_success "Limpieza semanal de la caché activada"
    fi
    pause
}
#@parte comun: optimize_gpu_menu

is_manjaro() { [ "$(os_release_value ID)" = manjaro ] || command -v mhwd &> /dev/null; }

# Kernels instalados (linux, linux-lts, linux-zen... y los linuxNNN de Manjaro)
arch_kernel_pkgs() {
    pacman -Qq 2>/dev/null | grep -E '^linux([0-9]+|-lts|-zen|-hardened|-rt|-rt-lts)?$'
}

# Instala lo que exista en los repositorios y avisa de lo que no
install_available() {
    local have=() p missing=()
    for p in "$@"; do
        if [ -n "$(pkg_available "$p")" ]; then have+=("$p"); else missing+=("$p"); fi
    done
    [ ${#missing[@]} -gt 0 ] && log_warning "No están en tus repositorios (se omiten): ${missing[*]}"
    [ ${#have[@]} -gt 0 ] || return 1
    pkg_install_recorded "${have[@]}"
}

optimize_nvidia() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🟢 OPTIMIZACIÓN NVIDIA                        ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        log_success "El driver de NVIDIA ya está funcionando"
        run "No se pudo activar el modo persistente" sudo nvidia-smi -pm 1
    else
        install_nvidia_driver || return 1
    fi
    if confirm "${PURPLE}¿Instalar CUDA? (varios GB, solo para desarrollo/IA)${NC}"; then
        install_available cuda && log_success "CUDA instalado"
    fi
    echo -e "${YELLOW}⚠ Reinicia el sistema para aplicar todos los cambios${NC}"
}

# Driver de NVIDIA. Manjaro: su herramienta mhwd elige el correcto (de sus repositorios
# oficiales). Arch y derivadas: las tarjetas desde la serie 16/RTX usan los módulos abiertos
# (nvidia-open); las más viejas necesitan un driver que solo está en el AUR (no se usa).
install_nvidia_driver() {
    if is_manjaro && command -v mhwd &> /dev/null; then
        echo -e "${PURPLE}🔧 Manjaro: mhwd instala el driver recomendado para tu tarjeta...${NC}"
        run_visible "mhwd no pudo instalar el driver" sudo mhwd -a pci nonfree 0300 || return 1
        log_success "Driver de NVIDIA instalado con mhwd"
        return 0
    fi
    ensure_lspci
    local gpu kernels=() pkgs=() k
    gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d controller' | grep -i nvidia | head -1)
    echo -e "${PURPLE}🎮 $gpu${NC}"
    if ! grep -Eqi 'RTX|GTX 16|TU1[0-9]{2}|GA1[0-9]{2}|AD1[0-9]{2}|GB2[0-9]{2}|\bA[0-9]{3,4}\b|L40|H100' <<< "$gpu"; then
        log_warning "Parece una tarjeta anterior a la serie GTX 16/RTX: el driver actual de Arch ya no la soporta"
        echo -e "${YELLOW}  El driver para esa tarjeta solo está en el AUR, que el script no usa por seguridad. Sigue funcionando${NC}"
        echo -e "${YELLOW}  el driver libre (nouveau), que ya viene instalado. Si necesitas el de NVIDIA, puedes${NC}"
        echo -e "${YELLOW}  instalarlo a mano revisando antes el PKGBUILD, bajo tu responsabilidad.${NC}"
        return 1
    fi
    mapfile -t kernels < <(arch_kernel_pkgs)
    # Con solo el kernel "linux" alcanza nvidia-open; con otros kernels se compila (DKMS)
    if [ "${#kernels[@]}" -eq 1 ] && [ "${kernels[0]}" = linux ] && [ -n "$(pkg_available nvidia-open)" ]; then
        pkgs=(nvidia-open)
    else
        pkgs=(nvidia-open-dkms)
        for k in "${kernels[@]}"; do pkgs+=("$k-headers"); done
    fi
    pkgs+=(nvidia-utils nvidia-settings)
    multilib_enabled && pkgs+=(lib32-nvidia-utils)
    if secure_boot_enabled; then
        log_warning "Secure Boot está activo: el módulo de NVIDIA no está firmado y no va a cargar"
        echo -e "${YELLOW}  Desactiva Secure Boot en la BIOS, o firma los módulos (por ejemplo con sbctl).${NC}"
    fi
    pkg_install_recorded "${pkgs[@]}" || return 1
    log_success "Driver de NVIDIA instalado (${pkgs[0]})"
}

optimize_amd() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔴 OPTIMIZACIÓN AMD                           ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    local pkgs=(mesa vulkan-radeon libva-mesa-driver mesa-utils)
    multilib_enabled && pkgs+=(lib32-mesa lib32-vulkan-radeon)
    install_available "${pkgs[@]}" || return 1
    echo -e "${PURPLE}🔧 Activando overclocking y control de ventiladores...${NC}"
    echo 'options amdgpu ppfeaturemask=0xffffffff' | sudo tee /etc/modprobe.d/amd_ppfeaturemask.conf > /dev/null
    regen_initramfs
    install_available corectrl && log_success "CoreCtrl instalado (control gráfico de la GPU)"
    echo -e "${YELLOW}⚠ Reinicia el sistema para aplicar todos los cambios${NC}"
}

optimize_intel() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔵 OPTIMIZACIÓN INTEL                         ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    # intel-media-driver: Broadwell (2014) en adelante; libva-intel-driver: las más viejas
    local pkgs=(mesa vulkan-intel intel-media-driver libva-intel-driver libva-utils intel-gpu-tools)
    multilib_enabled && pkgs+=(lib32-mesa lib32-vulkan-intel)
    install_available "${pkgs[@]}" || return 1
    echo -e "${PURPLE}🔧 Activando GuC/HuC para códecs...${NC}"
    echo 'options i915 enable_guc=3' | sudo tee /etc/modprobe.d/i915_guc.conf > /dev/null
    regen_initramfs
    echo -e "${YELLOW}⚠ Reinicia el sistema para aplicar todos los cambios${NC}"
}

# Firmware y drivers: linux-firmware, sonido de portátiles (sof-firmware), microcódigo y GPU
install_recommended_drivers() {
    echo -e "${BLUE}🔍 Revisando firmware y drivers...${NC}"
    if is_manjaro && command -v mhwd &> /dev/null; then
        run_visible "mhwd no pudo instalar los drivers" sudo mhwd -a pci free 0300
    fi
    install_available linux-firmware sof-firmware
    install_microcode
    ensure_lspci
    if lspci 2>/dev/null | grep -Ei 'vga|3d controller' | grep -qi nvidia; then
        if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
            log_success "El driver de NVIDIA ya está funcionando"
        elif confirm "${BLUE}Hay una GPU NVIDIA: ¿instalar su driver?${NC}"; then
            install_nvidia_driver
        fi
    fi
    log_success "Firmware y drivers revisados"
}

# Microcódigo del procesador: corrige errores de la CPU; GRUB lo carga solo
install_microcode() {
    local ucode=""
    grep -q GenuineIntel /proc/cpuinfo && ucode=intel-ucode
    grep -q AuthenticAMD /proc/cpuinfo && ucode=amd-ucode
    [ -n "$ucode" ] || return 0
    if [ -n "$(pkg_installed "$ucode")" ]; then
        echo -e "  ${GREEN}✓ Microcódigo del procesador ($ucode) instalado${NC}"
        return 0
    fi
    pkg_install_recorded "$ucode" && log_success "Microcódigo $ucode instalado"
    grub_available && run "No se pudo regenerar el menú de GRUB" grub_update
}

auto_detect_gpu() {
    echo -e "${PURPLE}🔄 Detectando GPU...${NC}"
    ensure_lspci
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
        echo -e "${BLUE}📦 Instalados: $(arch_kernel_pkgs | tr '\n' ' ')${NC}\n"
        if is_manjaro && command -v mhwd-kernel &> /dev/null; then
            echo -e "  ${BLUE}1)${NC} Instalar otro kernel (Manjaro recomienda tener un LTS de respaldo)"
            echo -e "  ${BLUE}4)${NC} Quitar un kernel (nunca el que está en uso)"
        else
            echo -e "  ${BLUE}1)${NC} linux       - El normal de Arch, siempre actualizado"
            echo -e "  ${BLUE}2)${NC} linux-lts   - Largo plazo: el más estable, ideal como respaldo"
            echo -e "  ${BLUE}3)${NC} linux-zen   - Rendimiento y juegos (el equivalente a Liquorix/XanMod)"
            echo -e "  ${BLUE}4)${NC} Quitar un kernel (nunca el que está en uso ni el último)"
        fi
        echo -e "  ${BLUE}5)${NC} Microcódigo del procesador (intel-ucode / amd-ucode)"
        echo -e "  ${BLUE}6)${NC} Ajustes avanzados de kernel"
        echo -e "\n  ${BLUE}0)${NC} 🔙 Volver"
        echo ""
        read -r -p "📌 Opción (0-6): " kernel_option
        case $kernel_option in
            1) if is_manjaro && command -v mhwd-kernel &> /dev/null; then manjaro_install_kernel; else arch_install_kernel linux; fi ;;
            2) arch_install_kernel linux-lts ;;
            3) arch_install_kernel linux-zen ;;
            4) arch_remove_kernel ;;
            5) install_microcode ;;
            6) advanced_kernel_tweaks ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
        return 0
    done
}

# Paquete del kernel que está corriendo ahora
running_kernel_pkg() {
    pacman -Qqo "/usr/lib/modules/$(uname -r)/vmlinuz" 2>/dev/null
}

arch_install_kernel() {
    local k="$1"
    if is_manjaro && command -v mhwd-kernel &> /dev/null; then
        manjaro_install_kernel
        return
    fi
    echo -e "${BLUE}📦 Instalando $k y sus headers (para drivers como NVIDIA o VirtualBox)...${NC}"
    pkg_install_recorded "$k" "$k-headers" || return 1
    # El driver nvidia-open sin DKMS solo sirve para el kernel "linux"
    if [ "$k" != linux ] && [ -n "$(pkg_installed nvidia-open nvidia)" ]; then
        log_warning "Tu driver de NVIDIA solo funciona con el kernel 'linux': con $k hace falta nvidia-open-dkms"
        confirm "${BLUE}¿Cambiarlo por nvidia-open-dkms?${NC}" && pkg_install_recorded nvidia-open-dkms
    fi
    if grub_available; then
        run "No se pudo regenerar el menú de GRUB" grub_update
        arch_grub_default "$k"
    else
        log_info "Sin GRUB (systemd-boot): el kernel nuevo aparece solo en el menú de arranque"
    fi
    log_success "Kernel $k instalado. Reinicia para usarlo; el anterior queda como respaldo"
}

# Que GRUB arranque por defecto el kernel elegido ("…, with Linux linux-zen")
arch_grub_default() {
    local k="$1" path
    ensure_grub_saved
    [ $? -eq 1 ] && return 1
    path=$(grub_entry_path "with Linux $k'" "$GRUB_CFG")
    if [ -n "$path" ]; then
        run "No se pudo fijar el kernel por defecto" grub_set_default "$path" && log_success "GRUB arrancará por defecto: $k"
    else
        log_info "Elige $k en 'Opciones avanzadas' del menú de GRUB (o la opción 19 → 6)"
    fi
}

manjaro_install_kernel() {
    local list=() i=0 choice k
    mapfile -t list < <(LC_ALL=C mhwd-kernel -l 2>/dev/null | awk '/\* linux/ {print $2}')
    if [ ${#list[@]} -eq 0 ]; then
        log_error "mhwd-kernel no devolvió la lista de kernels (¿sin internet?)"
        return 1
    fi
    echo -e "${BLUE}📋 Kernels de Manjaro (los LTS son los más estables):${NC}"
    for k in "${list[@]}"; do
        i=$((i + 1))
        printf "  ${BLUE}%2s)${NC} %s%s\n" "$i" "$k" "$(arch_kernel_pkgs | grep -qx "$k" && echo ' (instalado)')"
    done
    read -r -p "📌 Kernel a instalar (0 = ninguno): " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#list[@]} ] || return 0
    k=${list[$((choice - 1))]}
    run_visible "mhwd-kernel no pudo instalar $k" sudo mhwd-kernel -i "$k" || return 1
    log_success "Kernel $k instalado (mhwd-kernel regeneró GRUB). Reinicia para usarlo"
}

arch_remove_kernel() {
    local kernels=() running i=0 choice k
    running=$(running_kernel_pkg)
    mapfile -t kernels < <(arch_kernel_pkgs | grep -vx -- "$running")
    if [ ${#kernels[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ Solo tienes el kernel que está en uso ($running): no se puede quitar${NC}"
        return 0
    fi
    echo -e "${BLUE}📋 Kernels que se pueden quitar (el que está en uso, ${running:-?}, queda):${NC}"
    for k in "${kernels[@]}"; do i=$((i + 1)); printf "  ${BLUE}%2s)${NC} %s\n" "$i" "$k"; done
    read -r -p "📌 Kernel a quitar (0 = ninguno): " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#kernels[@]} ] || return 0
    k=${kernels[$((choice - 1))]}
    confirm "${RED}¿Quitar $k?${NC}" || return 0
    if is_manjaro && command -v mhwd-kernel &> /dev/null; then
        run_visible "mhwd-kernel no pudo quitar $k" sudo mhwd-kernel -r "$k" || return 1
    else
        pkg_remove "$k" $(pkg_installed "$k-headers") || return 1
        grub_available && run "No se pudo regenerar el menú de GRUB" grub_update
    fi
    log_success "Kernel $k quitado"
}

# ------------------------------------------------------------
# Utilidades para cambiar de kernel
# ------------------------------------------------------------

# Kernels de terceros que gestiona el script
CUSTOM_KERNELS=("liquorix" "xanmod")
KERNEL_CLEANUP_FILE="$STATE_DIR/kernels-pendientes.txt"
GRUB_TEMP_PIN_FILE="$STATE_DIR/grub-fijado-temporal"
KERNEL_PENDING_CLEANUP=false
#@parte arranque: secure_boot_enabled

# Cambia GRUB_DEFAULT en /etc/default/grub
GRUB_DEFAULT_BACKUP="/etc/default/grub.arch-ultimate-tools.orig"
#@parte arranque: backup_grub_config set_grub_default grub_line_id grub_entry_path ensure_grub_saved

# ------------------------------------------------------------
# Instalación de kernels
# ------------------------------------------------------------

os_release_value() {
    # shellcheck disable=SC1091
    (. /etc/os-release && eval "echo \"\$$1\"")
}
#@parte comun: enable_trim

advanced_kernel_tweaks() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔧 AJUSTES AVANZADOS                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    echo -e "${YELLOW}⚠ ADVERTENCIA: Estos ajustes pueden afectar la seguridad${NC}\n"

    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=.*mitigations=off' /etc/default/grub; then
        echo -e "${YELLOW}ℹ Las mitigaciones de Spectre/Meltdown ya están deshabilitadas${NC}"
        if confirm "${BLUE}¿Volver a habilitarlas? (recomendado por seguridad)${NC}"; then
            sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/s/ *mitigations=off//' /etc/default/grub
            run "No se pudo regenerar el menú de GRUB" grub_update && log_success "Mitigaciones habilitadas (requiere reinicio)"
        fi
    elif confirm "${BLUE}¿Deshabilitar mitigaciones de Spectre/Meltdown? (+rendimiento, riesgo alto)${NC}"; then
        sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mitigations=off"/' /etc/default/grub
        run "No se pudo regenerar el menú de GRUB" grub_update && log_success "Mitigaciones deshabilitadas (requiere reinicio)"
    fi

    if confirm "${BLUE}¿Habilitar TRIM automático para SSD?${NC}"; then
        enable_trim
    fi

    echo -e "${GREEN}✓ Ajustes avanzados aplicados${NC}"
}
#@parte comun: datos_swapfile zram_swap_active disk_swap_active swapfile_active swap_summary ram_swappiness_auto apply_ram_tweaks suggest_swap_gb create_swapfile remove_swapfile swappiness_manual ram_status optimize_ram_menu

# --- ZRAM con zram-generator (el método de Arch, Fedora y systemd) ---
ZRAM_CONF="/etc/systemd/zram-generator.conf"

zram_enabled() { [ -f "$ZRAM_CONF" ] && grep -q 'arch-ultimate-tools' "$ZRAM_CONF"; }

enable_zram() {
    echo -e "${YELLOW}📦 Configurando ZRAM...${NC}"
    pkg_install_recorded zram-generator || return 1
    if [ -f "$ZRAM_CONF" ] && ! zram_enabled; then
        sudo cp -p "$ZRAM_CONF" "$ZRAM_CONF.antes-de-arch-ultimate-tools"
    fi
    printf '# Creado por arch-ultimate-tools\n[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd\n' \
        | sudo tee "$ZRAM_CONF" > /dev/null
    run "No se pudo recargar systemd" sudo systemctl daemon-reload
    run "No se pudo iniciar ZRAM" sudo systemctl restart systemd-zram-setup@zram0.service \
        && log_success "ZRAM configurado (50% de RAM como compresión)"
    ram_swappiness_auto
}

disable_zram() {
    if ! zram_enabled; then
        echo -e "  ${GREEN}✓ ZRAM no lo configuró este script${NC}"
        return 0
    fi
    run "No se pudo detener ZRAM" sudo systemctl stop systemd-zram-setup@zram0.service
    sudo rm -f "$ZRAM_CONF"
    [ -f "$ZRAM_CONF.antes-de-arch-ultimate-tools" ] && sudo mv "$ZRAM_CONF.antes-de-arch-ultimate-tools" "$ZRAM_CONF"
    run "No se pudo recargar systemd" sudo systemctl daemon-reload
    log_success "ZRAM desactivado"
    if confirm "${YELLOW}¿Desinstalar también zram-generator?${NC}"; then
        pkg_remove zram-generator && forget_installed zram-generator
    fi
}

# --- TLP: choca con power-profiles-daemon; en Arch hay que quitarlo antes ---
install_tlp() {
    echo -e "${YELLOW}ℹ TLP reemplaza a power-profiles-daemon: el selector de perfiles del escritorio desaparecerá${NC}"
    if [ -n "$(pkg_installed power-profiles-daemon)" ]; then
        run "No se pudo detener power-profiles-daemon" sudo systemctl disable --now power-profiles-daemon
        pkg_remove power-profiles-daemon || return 1
    fi
    pkg_install_recorded tlp tlp-rdw || return 1
    run "No se pudo activar TLP" sudo systemctl enable --now tlp
    # Lo indica la documentación de TLP: si no, systemd pisa su manejo de Wi-Fi/Bluetooth
    run "No se pudo enmascarar systemd-rfkill" sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket
    log_success "TLP activado"
}

remove_tlp() {
    if [ -z "$(pkg_installed tlp)" ]; then
        echo -e "  ${GREEN}✓ TLP no está instalado${NC}"
        return 0
    fi
    run "No se pudo detener TLP" sudo systemctl disable --now tlp
    pkg_remove $(pkg_installed tlp tlp-rdw) || return 1
    forget_installed tlp tlp-rdw
    run "No se pudo desenmascarar systemd-rfkill" sudo systemctl unmask systemd-rfkill.service systemd-rfkill.socket
    pkg_install power-profiles-daemon \
        && run "No se pudo activar power-profiles-daemon" sudo systemctl enable --now power-profiles-daemon \
        && log_success "TLP quitado: vuelve el selector de energía del escritorio"
}

install_gaming_tools() {
    # GameMode: el juego pide máximo rendimiento al sistema. MangoHud: FPS y temperaturas en pantalla.
    # Las versiones lib32 son para los juegos de 32 bits (necesitan multilib).
    local pkgs=(gamemode mangohud)
    multilib_enabled && pkgs+=(lib32-gamemode lib32-mangohud)
    pkg_install_recorded "${pkgs[@]}" || return 1
    getent group gamemode > /dev/null && ! id -nG | grep -qw gamemode \
        && run "No se pudo dar permiso para GameMode" sudo usermod -aG gamemode "$USER"
    # Valor que usan SteamOS y Fedora (y ya trae Arch): evita cierres en juegos modernos
    [ "$(sysctl -n vm.max_map_count 2>/dev/null)" -ge 1048576 ] 2>/dev/null || set_sysctl vm.max_map_count 1048576
    configure_mangohud
    log_success "GameMode y MangoHud instalados (en Steam: gamemoderun mangohud %command%)"
}

# --- Steam: del repositorio multilib (o Flatpak) ---
steam_installed() {
    [ -n "$(pkg_installed steam)" ] || flatpak_app_installed com.valvesoftware.Steam
}

steam_dir() {
    if [ -z "$(pkg_installed steam)" ] && [ -d "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" ]; then
        echo "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    elif [ -d "$HOME/.steam/root" ]; then
        readlink -f "$HOME/.steam/root"
    else
        echo "$HOME/.local/share/Steam"
    fi
}

steam_supported() {
    if ! has_desktop; then
        log_warning "Steam necesita un escritorio (este sistema no tiene)"
        return 1
    fi
    if [ "$(uname -m)" != x86_64 ]; then
        log_warning "Steam solo existe para PC de 64 bits (x86_64)"
        return 1
    fi
}

# Wine: programas y juegos de Windows fuera de Steam (repositorio multilib, como Steam)
install_wine() {
    if command -v wine &> /dev/null; then
        echo -e "  ${GREEN}✓ Wine ya está instalado ($(wine --version 2>/dev/null))${NC}"
        return 0
    fi
    echo -e "${BLUE}🍷 Instalando Wine...${NC}"
    need_multilib "Wine" || { log_error "Wine necesita el repositorio multilib"; return 1; }
    pkg_install_recorded wine winetricks || return 1
    log_success "Wine instalado: abre un programa de Windows con \"wine programa.exe\""
}

install_steam() {
    steam_supported || return 1
    if steam_installed; then
        echo -e "  ${GREEN}✓ Steam ya está instalado${NC}"
        enable_steam_play
        return 0
    fi
    echo -e "${BLUE}🎮 Instalando Steam...${NC}"
    if ! need_multilib "Steam"; then
        echo -e "${YELLOW}ℹ Sin multilib queda la versión de Flathub${NC}"
        confirm "${BLUE}¿Instalar Steam con Flatpak?${NC}" && flathub_install com.valvesoftware.Steam && enable_steam_play
        return
    fi
    # Driver de 32 bits según la GPU (sin él, los juegos no abren o van sin aceleración)
    local libs=() gpus
    ensure_lspci
    gpus=$(lspci 2>/dev/null | grep -Ei 'vga|3d controller')
    grep -qi nvidia <<< "$gpus" && libs+=(lib32-nvidia-utils)
    grep -Eqi 'amd|ati|radeon' <<< "$gpus" && libs+=(lib32-vulkan-radeon)
    grep -qi intel <<< "$gpus" && libs+=(lib32-vulkan-intel)
    pkg_install_recorded steam "${libs[@]}" || return 1
    log_success "Steam instalado (Proton viene incluido)"
    enable_steam_play
}

# --- Java para compilar APK ---
install_jdk() {
    local jdk
    jdk=$(pkg_available jdk21-openjdk jdk17-openjdk | head -n1)
    if [ -z "$jdk" ]; then
        log_error "No hay JDK 17 ni 21 en tus repositorios"
        return 1
    fi
    pkg_install_recorded "$jdk" || return 1
    JAVA_HOME_DIR="/usr/lib/jvm/java-${jdk//[!0-9]/}-openjdk"
    [ -x "$JAVA_HOME_DIR/bin/javac" ] || JAVA_HOME_DIR=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
    [ -x "$JAVA_HOME_DIR/bin/javac" ] || { log_error "No se encontró el JDK instalado"; return 1; }
}

install_flatpak() {
    if ! has_desktop; then
        log_warning "Flatpak es para apps de escritorio (este sistema no tiene)"
        return 1
    fi
    # Discover (KDE) y GNOME Software ya muestran Flatpaks si está instalado
    pkg_install_recorded flatpak || return 1
    run "No se pudo agregar Flathub" sudo flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
    log_success "Flatpak y Flathub listos (cierra sesión y vuelve a entrar para ver las apps en el menú)"
}

# --- Información del sistema: fastfetch e inxi ---
info_fastfetch() {
    if command -v fastfetch &> /dev/null; then
        fastfetch
        return
    fi
    $INFO_QUIET && return 0
    echo -e "${CYAN}ℹ fastfetch no está instalado (está en los repositorios oficiales, ocupa poco).${NC}"
    confirm "${CYAN}¿Instalarlo y mostrarlo?${NC}" || return 0
    pkg_install_recorded fastfetch && fastfetch
}

info_inxi() {
    local flags="$1"
    if command -v inxi &> /dev/null; then
        # shellcheck disable=SC2086  # varias opciones
        inxi $flags
        return
    fi
    $INFO_QUIET && return 0
    echo -e "${CYAN}ℹ inxi no está instalado (está en los repositorios oficiales, ocupa poco).${NC}"
    confirm "${CYAN}¿Instalarlo y mostrarlo?${NC}" || return 0
    # shellcheck disable=SC2086  # varias opciones
    pkg_install_recorded inxi && inxi $flags
}

# --- Deshacer: quitar programas instalados por el script (pacman y Flatpak) ---
remove_installed_programs() {
    local logged=() known=() flatpaks=() entries=() p desc
    # shellcheck disable=SC2046  # lista de paquetes: se separa a propósito
    [ -f "$INSTALLED_LIST" ] && mapfile -t logged < <(pkg_installed $(cat "$INSTALLED_LIST"))
    mapfile -t known < <(pkg_installed "${SCRIPT_PROGRAMS[@]}")
    [ -f "$FLATPAK_APPS_LIST" ] && mapfile -t flatpaks < <(while read -r p; do flatpak_app_installed "$p" && echo "$p"; done < "$FLATPAK_APPS_LIST")

    for p in "${logged[@]}"; do
        desc=$(pkg_description "$p")
        entries+=("$p|${desc:-instalado por el script}")
    done
    for p in "${known[@]}"; do
        printf '%s\n' "${logged[@]}" | grep -qx -- "$p" && continue
        entries+=("$p|(sin registro: puede que ya lo tuvieras) $(pkg_description "$p")")
    done
    for p in "${flatpaks[@]}"; do entries+=("$p|App Flatpak"); done
    # SeaMonkey no es un paquete: se instaló en /opt
    seamonkey_installed && entries+=("opt:seamonkey|SeaMonkey (descarga oficial en $SEAMONKEY_DIR)")

    if [ ${#entries[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ No hay programas instalados por el script${NC}"
        return 0
    fi
    if ! checklist_select "Quitar programas" "Marca los programas que quieres DESINSTALAR" "${entries[@]}" \
        || [ ${#CHOSEN[@]} -eq 0 ]; then
        clear
        echo -e "${YELLOW}ℹ No seleccionaste ningún programa${NC}"
        return 0
    fi
    clear
    local pkgs=() apps=() extra=()
    for p in "${CHOSEN[@]}"; do
        if [ "$p" = opt:seamonkey ]; then remove_seamonkey
        elif printf '%s\n' "${flatpaks[@]}" | grep -qx -- "$p"; then apps+=("$p"); else pkgs+=("$p"); fi
    done

    if [ ${#pkgs[@]} -gt 0 ]; then
        # pacman no quita algo que otro programa necesita: se avisa en lugar de forzar
        if ! extra=($(pkg_removal_set "${pkgs[@]}")); then
            log_error "Algún programa elegido lo necesita otro paquete instalado:"
            LC_ALL=C pacman -Rsp "${pkgs[@]}" 2>&1 | grep -i 'breaks dependency\|required by' | sed 's/^/   /' | head -5
            return 1
        fi
        mapfile -t extra < <(printf '%s\n' "${extra[@]}" | grep -vxF -f <(printf '%s\n' "${pkgs[@]}"))
    fi
    echo -e "${RED}📋 Se desinstalarán:${NC}"
    printf "  ${RED}•${NC} %s\n" "${CHOSEN[@]}"
    if [ ${#extra[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}⚠ También se quitarán sus dependencias que ya nadie usa:${NC}"
        printf "  ${YELLOW}•${NC} %s\n" "${extra[@]}"
    fi
    echo ""
    if ! confirm "${RED}¿Desinstalar?${NC}"; then
        echo -e "${YELLOW}ℹ Cancelado: no se desinstaló nada${NC}"
        return 0
    fi
    if [ ${#pkgs[@]} -gt 0 ]; then
        pkg_remove "${pkgs[@]}" || return 1
        forget_installed "${pkgs[@]}" "${extra[@]}"
    fi
    for p in "${apps[@]}"; do
        run "No se pudo quitar $p" sudo flatpak uninstall -y --noninteractive "$p" \
            && sed -i "/^${p//./\\.}\$/d" "$FLATPAK_APPS_LIST"
    done
    log_success "Desinstalado: ${CHOSEN[*]}"
    # Sin TLP, el selector de energía del escritorio necesita power-profiles-daemon
    if printf '%s\n' "${pkgs[@]}" | grep -qx tlp; then
        run "No se pudo desenmascarar systemd-rfkill" sudo systemctl unmask systemd-rfkill.service systemd-rfkill.socket
        pkg_install power-profiles-daemon \
            && run "No se pudo activar power-profiles-daemon" sudo systemctl enable --now power-profiles-daemon \
            && log_success "Vuelve el selector de energía del escritorio"
    fi
}


# ============================================================
# OPCIÓN 1: ACTUALIZACIÓN DEL SISTEMA (COLOR: VERDE)
# ============================================================

do_system_update() {
    echo -e "${GREEN}[1/4] Actualizando todo el sistema (pacman -Syu)...${NC}"
    pacman_full_upgrade || return 1

    echo -e "${GREEN}[2/4] Paquetes huérfanos...${NC}"
    remove_orphans

    echo -e "${GREEN}[3/4] Limpiando caché de paquetes (se guardan las 2 últimas versiones)...${NC}"
    if command -v paccache &> /dev/null; then
        run "No se pudo limpiar la caché" sudo paccache -rk2
    else
        echo -e "  ${YELLOW}ℹ Sin pacman-contrib: se omite (actívalo en la opción 12)${NC}"
    fi

    echo -e "${GREEN}[4/4] Apps Flatpak...${NC}"
    if command -v flatpak &> /dev/null; then
        run_visible "No se pudieron actualizar las apps Flatpak" flatpak update -y --noninteractive
    else
        echo -e "  ${GREEN}✓ Flatpak no está instalado${NC}"
    fi
    log_success "Sistema actualizado"
    # Si se actualizó el kernel en uso, sus módulos ya no están: conviene reiniciar
    [ -d "/usr/lib/modules/$(uname -r)" ] || echo -e "${YELLOW}⚠ Se actualizó el kernel: reinicia antes de instalar drivers o conectar USB${NC}"
    return 0
}

system_update() {
    clear
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔄 ACTUALIZAR SISTEMA                         ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "\n${GREEN}📋 Se ejecutará:${NC}"
    echo -e "  • sudo pacman -Syu (si fallan las firmas, se actualiza el llavero y se reintenta)"
    echo -e "  • Quitar paquetes huérfanos"
    echo -e "  • paccache -rk2 (limpia la caché, si está pacman-contrib)"
    echo -e "  • Actualizar las apps Flatpak, si está instalado"
    if is_manjaro; then
        echo -e "\n${YELLOW}ℹ Manjaro: antes de actualizar conviene leer el anuncio de la versión en forum.manjaro.org${NC}"
    else
        echo -e "\n${YELLOW}ℹ Arch: si una actualización necesita un paso manual, se anuncia en archlinux.org/news${NC}"
    fi
    echo ""
    confirm "${GREEN}¿Actualizar el sistema?${NC}" || return 0
    do_system_update
    echo ""
    pause
}
#@parte comun: tokyo_color_group write_tokyo_night_colors write_tokyo_night_konsole

THEME_BACKUP="$STATE_DIR/tema-anterior.txt"
#@parte comun: save_theme_value theme_value kde_color_scheme install_tokyo_night_theme gnome_dark_mode

install_custom_software() {
    if ! has_desktop; then
        log_warning "Alacritty y los temas necesitan un escritorio (este sistema no tiene)"
        pause
        return 0
    fi
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    💻 ALACRITTY Y TEMA TOKYO NIGHT               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "\n${CYAN}✨ Alacritty es una terminal moderna que usa la GPU para renderizar${NC}\n"

    if confirm "${CYAN}¿Instalar Alacritty (terminal con aceleración GPU)?${NC}"; then
        echo -e "${CYAN}📦 Instalando Alacritty...${NC}"
        pkg_refresh
        if ! pkg_install_recorded alacritty; then
            pause
            return 1
        fi

        mkdir -p ~/.config/alacritty
        cat > ~/.config/alacritty/alacritty.toml << 'EOF'
[window]
opacity = 0.95
padding = { x = 10, y = 10 }

[font]
size = 12

[font.normal]
family = "Monospace"
style = "Regular"

[colors]
primary = { background = "#1a1b26", foreground = "#c0caf5" }
normal = { black = "#15161e", red = "#f7768e", green = "#9ece6a", yellow = "#e0af68", blue = "#7aa2f7", magenta = "#bb9af7", cyan = "#7dcfff", white = "#a9b1d6" }
EOF
        echo -e "${GREEN}✓ Alacritty instalado (usando GPU para renderizado)${NC}"
    fi

    case $DESKTOP in
        kde)
            if confirm "${CYAN}¿Aplicar tema Tokyo Night a Plasma y Konsole?${NC}"; then
                install_tokyo_night_theme
            fi ;;
        gnome)
            if confirm "${CYAN}¿Activar el modo oscuro de GNOME?${NC}"; then
                gnome_dark_mode
            fi ;;
        *)
            echo -e "${CYAN}ℹ El tema del escritorio solo se aplica en KDE Plasma (Tokyo Night) y GNOME (modo oscuro).${NC}"
            echo -e "${CYAN}  Alacritty ya usa los colores Tokyo Night.${NC}" ;;
    esac

    pause
}

# ------------------------------------------------------------
# Desarrollo: compilar APK (SDK de Android), Android Studio y Flatpak
# ------------------------------------------------------------

ANDROID_SDK="$HOME/Android/Sdk"            # La misma carpeta que usa Android Studio
ANDROID_ENV="$HOME/.config/arch-ultimate-tools/android-sdk.sh"
ANDROID_ENV_MARK="# Arch Ultimate Tools: Android SDK"
ANDROID_STUDIO_DIR="/opt/android-studio"
ANDROID_STUDIO_STATE="$STATE_DIR/android-studio.txt"   # "google" o "snap"
ANDROID_STUDIO_DESKTOP="$HOME/.local/share/applications/android-studio.desktop"
FLATPAK_SDK_LIST="$STATE_DIR/flatpak-sdk.txt"
#@parte comun: android_tools_installed
android_studio_installed() {
    [ -x "$ANDROID_STUDIO_DIR/bin/studio" ] || [ -x "$ANDROID_STUDIO_DIR/bin/studio.sh" ] \
        || [ -n "$(pkg_installed android-studio)" ]
}
#@parte comun: enough_space check_sum

# Variables para la terminal: ANDROID_HOME, JAVA_HOME y las herramientas en el PATH
write_android_env() {
    mkdir -p "$(dirname "$ANDROID_ENV")"
    cat > "$ANDROID_ENV" << ENV
# Creado por Arch Ultimate Tools: herramientas para compilar APK
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
    pkg_refresh
    command -v wget &> /dev/null || pkg_install wget || return 1
    install_jdk || return 1
    # Reglas para que Linux reconozca el celular por USB (adb sin sudo) y unzip para el SDK
    pkg_install_recorded android-udev unzip || return 1
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

# Android Studio oficial de Google: la página de descargas tiene el enlace y su SHA-256
install_android_studio_google() {
    local html url file sum tmp old=""
    enough_space "$HOME" 2 && enough_space /opt 4 || return 1
    command -v wget &> /dev/null || { pkg_refresh; pkg_install wget; }
    echo -e "${BLUE}⬇ Buscando la última versión estable en developer.android.com...${NC}"
    html=$(wget -qO- https://developer.android.com/studio 2>> "$LOG_FILE" | tr -d '\n')
    url=$(grep -oE 'https://redirector\.gvt1\.com/edgedl/android/studio/ide-zips/[0-9.]+/android-studio-[0-9.]+-linux\.tar\.gz' <<< "$html" | head -n1)
    if [ -z "$url" ]; then
        log_error "No se encontró la descarga de Android Studio (¿sin internet o cambió la página de Google?)"
        return 1
    fi
    file=${url##*/}
    sum=$(grep -oE "${file//./\\.}.{0,800}" <<< "$html" | grep -oE '\b[0-9a-f]{64}\b' | head -n1)
    tmp=$(mktemp -d -p "${XDG_CACHE_HOME:-$HOME/.cache}" 2>/dev/null || mktemp -d)
    echo -e "${BLUE}⬇ Descargando $file (más de 1 GB)...${NC}"
    if ! wget -q --show-progress -O "$tmp/$file" "$url"; then
        log_error "No se pudo descargar Android Studio"
        rm -rf "$tmp"
        return 1
    fi
    if [ -n "$sum" ]; then
        if ! check_sum "$tmp/$file" "$sum"; then
            log_error "La descarga de Android Studio llegó dañada (la suma de comprobación no coincide)"
            rm -rf "$tmp"
            return 1
        fi
        log_success "Descarga verificada (SHA-256)"
    else
        log_warning "Google no publicó la suma de comprobación en su página: no se pudo verificar la descarga"
        confirm "${YELLOW}¿Instalarla igual? (viene de la descarga oficial de Google por HTTPS)${NC}" \
            || { rm -rf "$tmp"; return 1; }
    fi
    # Si había una versión anterior, se aparta hasta que la nueva quede instalada
    if [ -d "$ANDROID_STUDIO_DIR" ]; then
        old="$ANDROID_STUDIO_DIR.anterior"
        sudo rm -rf "$old"
        sudo mv "$ANDROID_STUDIO_DIR" "$old"
    fi
    if ! sudo tar -xzf "$tmp/$file" -C /opt >> "$LOG_FILE" 2>&1 || [ ! -d "$ANDROID_STUDIO_DIR/bin" ]; then
        log_error "No se pudo descomprimir Android Studio"
        sudo rm -rf "$ANDROID_STUDIO_DIR"
        [ -n "$old" ] && sudo mv "$old" "$ANDROID_STUDIO_DIR"
        rm -rf "$tmp"
        return 1
    fi
    [ -n "$old" ] && sudo rm -rf "$old"
    rm -rf "$tmp"

    local exe=studio icon=studio.svg
    [ -x "$ANDROID_STUDIO_DIR/bin/studio" ] || exe=studio.sh
    [ -f "$ANDROID_STUDIO_DIR/bin/$icon" ] || icon=studio.png
    mkdir -p "$(dirname "$ANDROID_STUDIO_DESKTOP")"
    cat > "$ANDROID_STUDIO_DESKTOP" << DESKTOP
[Desktop Entry]
Type=Application
Name=Android Studio
Comment=Crear apps para Android
Exec="$ANDROID_STUDIO_DIR/bin/$exe" %f
Icon=$ANDROID_STUDIO_DIR/bin/$icon
Categories=Development;IDE;
Terminal=false
StartupWMClass=jetbrains-studio
DESKTOP
    mkdir -p "$STATE_DIR"
    echo google > "$ANDROID_STUDIO_STATE"
    file=${file#android-studio-}
    log_success "Android Studio ${file%-linux.tar.gz} instalado en $ANDROID_STUDIO_DIR (está en el menú de aplicaciones)"
}

install_android_studio_snap() {
    # En Arch no hay Snap y el AUR no se usa (seguridad): solo la versión oficial de Google
    log_error "En Arch se instala la versión oficial de Google (opción 1)"
    return 1
}

install_android_studio() {
    if ! has_desktop; then
        log_warning "Android Studio necesita un escritorio (este sistema no tiene)"
        return 1
    fi
    if [ "$(uname -m)" != x86_64 ]; then
        log_warning "Android Studio para Linux solo existe para PC de 64 bits (x86_64)"
        return 1
    fi
    echo -e "\n${BLUE}🤖 ANDROID STUDIO - para programar apps de Android (con emulador)${NC}"
    echo -e "${CYAN}  Ocupa unos 3 GB, más el SDK y los emuladores que bajes (unos 10 GB en total).${NC}"
    echo -e "${CYAN}  La primera vez que lo abras, un asistente baja el SDK a $ANDROID_SDK${NC}"
    echo -e "${CYAN}  (si ya instalaste las herramientas para compilar APK, las usa).${NC}\n"
    echo -e "  ${BLUE}1)${NC} Versión oficial de Google (recomendado): en $ANDROID_STUDIO_DIR, se actualiza"
    echo -e "     desde el propio Android Studio (Ayuda → Buscar actualizaciones)"
    echo -e "  ${BLUE}2)${NC} (Snap/AUR: no se usan en Arch; elige la 1)"
    echo -e "  ${BLUE}0)${NC} 🔙 No instalar"
    local choice
    read -r -p "📌 Opción (0-2): " choice
    case $choice in
        1) install_android_studio_google || return 1 ;;
        2) install_android_studio_snap || return 1 ;;
        *) echo -e "${YELLOW}ℹ No se instaló Android Studio${NC}"; return 0 ;;
    esac
    check_kvm
}

# Quita Android Studio y/o el SDK (las claves de firma de ~/.android nunca se tocan)
remove_android() {
    local found=false
    if android_studio_installed; then
        found=true
        if confirm "${RED}¿Quitar Android Studio?${NC}"; then
            if [ -n "$(pkg_installed android-studio)" ]; then
                pkg_remove android-studio && forget_installed android-studio
            fi
            sudo rm -rf "$ANDROID_STUDIO_DIR"
            rm -f "$ANDROID_STUDIO_DESKTOP" "$ANDROID_STUDIO_STATE"
            log_success "Android Studio quitado (su configuración queda en ~/.config/Google por si lo reinstalas)"
        fi
    fi
    if [ -d "$ANDROID_SDK" ]; then
        found=true
        echo -e "${YELLOW}ℹ El SDK de Android ocupa $(du -sh "$ANDROID_SDK" 2>/dev/null | cut -f1) en $ANDROID_SDK (incluye los emuladores)${NC}"
        if confirm "${RED}¿Borrar el SDK de Android? (tus proyectos y tus claves de firma en ~/.android no se tocan)${NC}"; then
            [ "${NUCLEAR_ALL:-false}" = true ] || { [ -d "$HOME/.android" ] && make_backup android-claves "$HOME/.android"; }
            rm -rf "$ANDROID_SDK" "$ANDROID_ENV"
            sed -i "/$ANDROID_ENV_MARK\$/d" "$HOME/.bashrc" "$HOME/.profile" 2>/dev/null
            log_success "SDK de Android borrado"
            echo -e "${CYAN}ℹ El JDK y las reglas USB son paquetes: se quitan en 'Ver y quitar PROGRAMAS' (1)${NC}"
        fi
    fi
    $found || echo -e "${YELLOW}ℹ No hay Android Studio ni SDK de Android instalados${NC}"
}
#@parte comun: flatpak_latest_branch

install_flatpak_builder() {
    command -v flatpak &> /dev/null && flatpak remotes 2>/dev/null | grep -qw flathub || install_flatpak || return 1
    pkg_install_recorded flatpak-builder || return 1
    log_success "flatpak-builder instalado"

    if $AUTO_MODE; then return 0; fi
    echo -e "\n${BLUE}📦 ¿Para qué tipo de app vas a compilar? Cada SDK pesa entre 1 y 3 GB.${NC}"
    echo -e "${CYAN}  Usa el que diga el manifiesto de tu app (runtime: / sdk:). Puedes elegir varios: 1 2${NC}"
    echo -e "  ${BLUE}1)${NC} KDE / Qt         (org.kde.Sdk)"
    echo -e "  ${BLUE}2)${NC} GNOME / GTK      (org.gnome.Sdk)"
    echo -e "  ${BLUE}3)${NC} Básico           (org.freedesktop.Sdk: apps en C, C++, Rust, Python, juegos...)"
    echo -e "  ${BLUE}0)${NC} Ninguno por ahora"
    local choice c app branch refs=()
    read -r -p "📌 Opción: " choice
    for c in $choice; do
        case $c in
            1) app=org.kde ;;
            2) app=org.gnome ;;
            3) app=org.freedesktop ;;
            *) continue ;;
        esac
        branch=$(flatpak_latest_branch "$app.Sdk")
        if [ -z "$branch" ]; then
            log_error "No se pudo consultar la versión de $app.Sdk en Flathub"
            continue
        fi
        refs+=("$app.Sdk//$branch" "$app.Platform//$branch")
    done
    if [ ${#refs[@]} -gt 0 ]; then
        echo -e "${BLUE}⬇ Instalando ${refs[*]}...${NC}"
        if run_visible "No se pudieron instalar los SDK de Flatpak" \
            sudo flatpak install -y --noninteractive --system flathub "${refs[@]}"; then
            mkdir -p "$STATE_DIR"
            printf '%s\n' "${refs[@]}" >> "$FLATPAK_SDK_LIST"
            sort -u -o "$FLATPAK_SDK_LIST" "$FLATPAK_SDK_LIST"
            log_success "SDK instalados: ${refs[*]}"
        fi
    fi
    cat << 'GUIA'

  📖 CÓMO COMPILAR UN FLATPAK (en la carpeta donde está el manifiesto .yml)
     Probarlo en tu PC:
       flatpak-builder --user --install --force-clean compilacion com.ejemplo.App.yml
       flatpak run com.ejemplo.App
     Crear un archivo .flatpak para compartir (se instala con doble clic):
       flatpak-builder --repo=repo --force-clean compilacion com.ejemplo.App.yml
       flatpak build-bundle repo mi-app.flatpak com.ejemplo.App
GUIA
}
#@parte comun: remove_flatpak_sdks

# ------------------------------------------------------------
# Respaldos: antes de borrar algo que no se puede recuperar
# ------------------------------------------------------------

BACKUP_DIR="$HOME/respaldos-arch-ultimate-tools"
#@parte comun: make_backup

# ------------------------------------------------------------
# Docker: compilar con el Dockerfile de un proyecto (SDK, NDK... ya listos adentro)
# ------------------------------------------------------------

DOCKER_PKGS=(docker docker-compose docker-buildx)
#@parte comun: docker_installed

install_docker() {
    echo -e "${BLUE}🐳 DOCKER - compilar con el Dockerfile de un proyecto${NC}"
    echo -e "${CYAN}  Un Dockerfile es una receta: Docker arma un \"contenedor\" con todo lo que el proyecto${NC}"
    echo -e "${CYAN}  necesita (SDK, NDK, versiones exactas...) sin instalarlo en tu sistema.${NC}"
    echo -e "${CYAN}  Sirve también en un VPS sin escritorio.${NC}\n"

    # Otras instalaciones de Docker chocan con la de Arch
    if [ -n "$(pkg_installed docker-ce)" ]; then
        log_info "Ya tienes Docker de docker.com (docker-ce): no se instala el de Arch"
    elif snap list docker &> /dev/null; then
        log_error "Tienes Docker en snap: chocaría con el de Arch. Quítalo antes con: sudo snap remove docker"
        return 1
    else
        # Si había configuración de un Docker anterior, se respalda antes de tocar nada
        sudo test -d /etc/docker && make_backup docker-config /etc/docker
        pkg_refresh
        local pkgs=()
        mapfile -t pkgs < <(pkg_available "${DOCKER_PKGS[@]}")
        if ! printf '%s\n' "${pkgs[@]}" | grep -qx docker; then
            log_error "Tus repositorios no tienen el paquete docker"
            return 1
        fi
        pkg_install_recorded "${pkgs[@]}" || return 1
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

docker_remove_programs() {
    local pkgs=()
    mapfile -t pkgs < <(pkg_installed "${DOCKER_PKGS[@]}" docker-ce docker-ce-cli containerd.io)
    [ ${#pkgs[@]} -gt 0 ] || { echo -e "${YELLOW}ℹ No hay paquetes de Docker instalados${NC}"; return 0; }
    confirm "${RED}¿Quitar ${pkgs[*]}? (los datos en /var/lib/docker se conservan)${NC}" || return 0
    sudo systemctl stop docker.service docker.socket >> "$LOG_FILE" 2>&1
    run "No se pudo quitar Docker" sudo pacman -R --noconfirm "${pkgs[@]}" || return 1
    forget_installed "${pkgs[@]}"
    log_success "Docker quitado (tus imágenes y volúmenes siguen en /var/lib/docker)"
}

docker_nuclear() {
    echo -e "\n${RED}${BOLD}⚠️  ELIMINACIÓN NUCLEAR DE DOCKER${NC}"
    echo -e "${RED}  Se borran para siempre: todos los contenedores, imágenes, volúmenes y redes,${NC}"
    echo -e "${RED}  /var/lib/docker, /var/lib/containerd, /etc/docker, ~/.docker y el grupo 'docker'.${NC}\n"
    if [ "${NUCLEAR_ALL:-false}" != true ]; then
        confirm "${RED}¿Seguro que quieres borrar Docker y TODOS sus datos?${NC}" || return 0
        confirm "${RED}ÚLTIMA ADVERTENCIA: ¿confirmar la eliminación total?${NC}" || return 0
    fi

    # Respaldos: la configuración siempre (es chica); los volúmenes (tus datos), si quieres
    make_backup docker-config /etc/docker "$HOME/.docker"
    if sudo test -d /var/lib/docker/volumes && [ -n "$(sudo ls -A /var/lib/docker/volumes 2>/dev/null | grep -vx metadata.db)" ]; then
        echo -e "${YELLOW}ℹ Tus volúmenes (datos de los contenedores) ocupan $(sudo du -sh /var/lib/docker/volumes | cut -f1)${NC}"
        if confirm "${BLUE}¿Guardar un respaldo de los volúmenes antes de borrarlos?${NC}"; then
            enough_space "$HOME" "$(( $(sudo du -s --block-size=1G /var/lib/docker/volumes | cut -f1) + 1 ))" \
                && make_backup docker-volumes /var/lib/docker/volumes
        fi
    fi

    echo -e "${RED}[1/4] Deteniendo y borrando contenedores...${NC}"
    if docker_installed; then
        sudo docker ps -aq 2>/dev/null | xargs -r sudo docker rm -f >> "$LOG_FILE" 2>&1
    fi
    sudo systemctl stop docker.service docker.socket containerd.service >> "$LOG_FILE" 2>&1

    echo -e "${RED}[2/4] Quitando los programas...${NC}"
    local pkgs=()
    mapfile -t pkgs < <(pkg_installed "${DOCKER_PKGS[@]}" docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin containerd runc)
    if [ ${#pkgs[@]} -gt 0 ]; then
        pkg_remove "${pkgs[@]}"
        forget_installed "${pkgs[@]}"
        remove_orphans
    fi

    echo -e "${RED}[3/4] Borrando datos y configuración...${NC}"
    sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /run/docker.sock "$HOME/.docker"

    echo -e "${RED}[4/4] Quitando el grupo docker...${NC}"
    getent group docker > /dev/null && sudo groupdel docker >> "$LOG_FILE" 2>&1

    log_success "Docker eliminado por completo"
    [ -d "$BACKUP_DIR" ] && echo -e "${CYAN}💾 Respaldos en: $BACKUP_DIR${NC}"
}

# Todo lo de desarrollo que instala el script, de una vez
dev_nuclear() {
    echo -e "${RED}${BOLD}☢️  ELIMINACIÓN NUCLEAR DE LAS HERRAMIENTAS DE DESARROLLO${NC}\n"
    echo -e "${RED}📋 Se borra:${NC}"
    android_studio_installed && echo -e "  • Android Studio"
    [ -d "$ANDROID_SDK" ] && echo -e "  • SDK de Android ($(du -sh "$ANDROID_SDK" 2>/dev/null | cut -f1), con emuladores y NDK)"
    [ -s "$FLATPAK_SDK_LIST" ] && echo -e "  • SDK de Flatpak: $(paste -sd' ' "$FLATPAK_SDK_LIST")"
    { docker_installed || sudo test -d /var/lib/docker; } && echo -e "  • Docker con TODAS sus imágenes, contenedores y volúmenes"
    echo -e "  • Java (JDK), reglas USB de Android y flatpak-builder"
    echo -e "\n${GREEN}✓ No se tocan: tus proyectos, tus claves de firma (~/.android) ni tus apps Flatpak.${NC}"
    echo -e "${GREEN}  Antes se guardan respaldos en $BACKUP_DIR${NC}\n"
    confirm "${RED}¿Borrar todo lo anterior?${NC}" || return 0
    confirm "${RED}ÚLTIMA ADVERTENCIA: ¿confirmar la eliminación total?${NC}" || return 0

    # Las claves de firma no se borran, pero un respaldo extra nunca sobra
    [ -d "$HOME/.android" ] && make_backup android-claves "$HOME/.android"

    local was_force=${FORCE_YES:-false}
    if android_studio_installed || [ -d "$ANDROID_SDK" ]; then
        FORCE_YES=true NUCLEAR_ALL=true remove_android
    fi
    [ -s "$FLATPAK_SDK_LIST" ] && FORCE_YES=true remove_flatpak_sdks
    if docker_installed || sudo test -d /var/lib/docker; then
        NUCLEAR_ALL=true docker_nuclear
    fi
    FORCE_YES=$was_force

    local pkgs=()
    mapfile -t pkgs < <(pkg_installed openjdk-21-jdk-headless openjdk-17-jdk-headless \
        android-sdk-platform-tools-common flatpak-builder)
    if [ ${#pkgs[@]} -gt 0 ]; then
        pkg_remove "${pkgs[@]}" && forget_installed "${pkgs[@]}"
        remove_orphans
    fi
    echo ""
    log_success "Herramientas de desarrollo eliminadas"
    [ -d "$BACKUP_DIR" ] && echo -e "${CYAN}💾 Respaldos en: $BACKUP_DIR${NC}"
}

# ------------------------------------------------------------
# Navegadores: Firefox (repositorios oficiales) y Brave (Flathub), desde Software opcional
# ------------------------------------------------------------


# ============================================================
# OPCIÓN 7: SOFTWARE OPCIONAL (COLOR: AZUL)
# ============================================================

# Programa|descripción|paquetes oficiales (separados por coma)|(sin uso)|app de Flathub
# Solo repositorios oficiales y Flathub: el AUR no se usa por seguridad
# "@nombre" = se instala con su propia función (Steam, Docker, Android...)
# ------------------------------------------------------------
# SeaMonkey: descarga oficial en /opt (no está en los repositorios de Arch, y el AUR no se usa)
# ------------------------------------------------------------
# SeaMonkey (navegador, correo, editor HTML y chat de la comunidad de Mozilla): no está en los
# repositorios de ninguna distribución, se baja la versión oficial a /opt/seamonkey
SEAMONKEY_DIR="/opt/seamonkey"
SEAMONKEY_PAGE="https://www.seamonkey-project.org/releases/"
#@parte comun: seamonkey_installed install_seamonkey remove_seamonkey

ARCH_SOFTWARE=(
    "firefox|🦊 Firefox (de los repositorios oficiales, sin Snap)|firefox||org.mozilla.firefox"
    "google-chrome|🌐 Google Chrome (Flathub)|||com.google.Chrome"
    "chromium|🌐 Chromium (Chrome libre, en los repositorios oficiales)|chromium||"
    "brave|🦁 Brave, con bloqueo de anuncios (Flathub)|||com.brave.Browser"
    "microsoft-edge|🌐 Microsoft Edge (Flathub)|||com.microsoft.Edge"
    "torbrowser-launcher|🧅 Tor Browser (navegación anónima; el lanzador verifica la firma)|torbrowser-launcher||org.torproject.torbrowser-launcher"
    "seamonkey|🐒 SeaMonkey (navegador, correo y editor HTML; descarga oficial)|@seamonkey||"
    "telegram-desktop|📱 Telegram|telegram-desktop||org.telegram.desktop"
    "discord|🎮 Discord|discord||com.discordapp.Discord"
    "filezilla|📁 Cliente FTP/SFTP|filezilla||org.filezillaproject.Filezilla"
    "telnet|📞 Telnet (cliente: conectarse a otros equipos o probar puertos)|inetutils||"
    "code|📝 Visual Studio Code (versión libre Code - OSS)|code||com.visualstudio.code"
    "vscode-microsoft|📝 Visual Studio Code de Microsoft (Flathub)|||com.visualstudio.code"
    "virtualbox|🖥️ VirtualBox (máquinas virtuales)|@virtualbox||"
    "python|🐍 Python 3 + PIP|python,python-pip||"
    "git|📚 Git|git||"
    "curl|🌐 CURL|curl||"
    "wget|⬇️ Wget|wget||"
    "htop|📊 HTOP|htop||"
    "fastfetch|🖥️ Fastfetch|fastfetch||"
    "timeshift|⏰ Timeshift|timeshift||"
    "gparted|💾 GParted|gparted||"
    "vim|⌨️ Vim|vim||"
    "steam|🎮 Steam (con Proton para juegos de Windows)|@steam||"
    "wine|🍷 Wine + winetricks (programas y juegos de Windows fuera de Steam)|@wine||"
    "proton-ge|🍷 Proton-GE (Proton de la comunidad, más compatible)|@proton-ge||"
    "spotify|🎵 Spotify (Flathub)|||com.spotify.Client"
    "obs-studio|🎥 OBS Studio|obs-studio||com.obsproject.Studio"
    "android-tools|🤖 Compilar APK: Java + SDK Android + adb (~3 GB)|@android-tools||"
    "android-studio|🤖 Android Studio con emulador (de Google, ~10 GB)|@android-studio||"
    "flatpak|📦 Flatpak + Flathub: instalar apps Flatpak|@flatpak||"
    "flatpak-builder|🛠️ Compilar Flatpaks: flatpak-builder + el SDK que elijas|@flatpak-builder||"
    "docker|🐳 Docker + Compose (compilar con el Dockerfile)|@docker||"
)

arch_software_field() {
    local key="$1" field="$2" e
    for e in "${ARCH_SOFTWARE[@]}"; do
        [ "${e%%|*}" = "$key" ] && { cut -d'|' -f"$field" <<< "$e"; return 0; }
    done
}

flatpak_app_installed() { command -v flatpak &> /dev/null && flatpak list --app --columns=application 2>/dev/null | grep -qx -- "$1"; }

# ¿Ya está instalado? (por paquete oficial o de Flathub)
arch_software_installed() {
    local key="$1" repo fp
    case $key in
        steam) steam_installed; return ;;
        wine) command -v wine &> /dev/null; return ;;
        proton-ge) [ -n "$(ls -d "$(steam_dir)"/compatibilitytools.d/GE-Proton* 2>/dev/null)" ]; return ;;
        android-tools) android_tools_installed; return ;;
        android-studio) android_studio_installed; return ;;
        docker) docker_installed; return ;;
        virtualbox) [ -n "$(pkg_installed virtualbox)" ]; return ;;
        flatpak) command -v flatpak &> /dev/null; return ;;
        flatpak-builder) command -v flatpak-builder &> /dev/null; return ;;
        seamonkey) seamonkey_installed; return ;;
    esac
    repo=$(arch_software_field "$key" 3); fp=$(arch_software_field "$key" 5)
    [ -n "$repo" ] && [ -n "$(pkg_installed "${repo%%,*}")" ] && return 0
    [ -n "$fp" ] && flatpak_app_installed "$fp" && return 0
    return 1
}

select_optional_software() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    📦 SOFTWARE OPCIONAL                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    local entries=() e key
    for e in "${ARCH_SOFTWARE[@]}"; do
        key=${e%%|*}
        if arch_software_installed "$key"; then
            entries+=("$key|$(cut -d'|' -f2 <<< "$e") (ya instalado)")
        else
            entries+=("$key|$(cut -d'|' -f2 <<< "$e")")
        fi
    done

    SELECTED_OPTIONAL=()
    if checklist_select "Software opcional" "Marca los programas que quieres INSTALAR" "${entries[@]}"; then
        SELECTED_OPTIONAL=("${CHOSEN[@]}")
    fi
    clear
    if [ ${#SELECTED_OPTIONAL[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ No seleccionaste ningún programa${NC}"
        pause
        return 0
    fi
    echo -e "${BLUE}📋 Se instalarán:${NC}"
    printf "  ${BLUE}•${NC} %s\n" "${SELECTED_OPTIONAL[@]}"
    echo -e "\n${CYAN}ℹ Primero desde los repositorios oficiales de Arch; si un programa no está, desde Flathub${NC}"
    echo -e "${CYAN}  (se pregunta antes). El AUR no se usa: ya tuvo paquetes con malware.${NC}\n"
    if confirm "${BLUE}¿Instalar los ${#SELECTED_OPTIONAL[@]} programas seleccionados?${NC}"; then
        install_optional_with_progress "${SELECTED_OPTIONAL[@]}"
    fi
    pause
}

# Instala lo elegido: todo lo de los repositorios oficiales en una sola operación de pacman;
# después lo de Flathub y los que tienen pasos propios.
install_optional_with_progress() {
    local key repo fp batch=() later=() failed=() p
    for key in "$@"; do
        repo=$(arch_software_field "$key" 3)
        if [[ "$repo" == @* ]]; then
            later+=("$key")
            continue
        fi
        if [ -n "$repo" ]; then
            local pkgs=() ok=true
            IFS=',' read -r -a pkgs <<< "$repo"
            for p in "${pkgs[@]}"; do [ -n "$(pkg_available "$p")" ] || ok=false; done
            if $ok; then batch+=("${pkgs[@]}"); continue; fi
        fi
        later+=("$key")
    done

    if [ ${#batch[@]} -gt 0 ]; then
        echo -e "${BLUE}📦 Instalando ${#batch[@]} paquetes de los repositorios oficiales...${NC}"
        if ! pkg_install_recorded "${batch[@]}"; then
            log_warning "Reintentando uno por uno..."
            for p in "${batch[@]}"; do pkg_install_recorded "$p" > /dev/null || failed+=("$p"); done
        fi
    fi

    for key in "${later[@]}"; do
        echo ""
        repo=$(arch_software_field "$key" 3); fp=$(arch_software_field "$key" 5)
        case $repo in
            @steam) install_steam || failed+=(steam); continue ;;
            @wine) install_wine || failed+=(wine); continue ;;
            @proton-ge) install_proton_ge || failed+=(proton-ge); continue ;;
            @android-tools) install_android_tools || failed+=(android-tools); continue ;;
            @android-studio) install_android_studio || failed+=(android-studio); continue ;;
            @flatpak) install_flatpak || failed+=(flatpak); continue ;;
            @flatpak-builder) install_flatpak_builder || failed+=(flatpak-builder); continue ;;
            @docker) install_docker || failed+=(docker); continue ;;
            @virtualbox) install_virtualbox || failed+=(virtualbox); continue ;;
            @seamonkey) install_seamonkey || failed+=(seamonkey); continue ;;
        esac
        # No está en los repositorios oficiales: Flathub, si la app está ahí
        if [ -n "$fp" ]; then
            echo -e "${CYAN}ℹ $key se instala desde Flathub ($fp)${NC}"
            if confirm "${BLUE}¿Instalarlo con Flatpak?${NC}" && flathub_install "$fp"; then
                continue
            fi
        else
            log_error "$key no está en los repositorios oficiales de tu sistema ni en Flathub"
        fi
        failed+=("$key")
    done

    if [ ${#failed[@]} -gt 0 ]; then
        log_error "No se pudieron instalar: ${failed[*]}"
        return 1
    fi
    log_success "Programas instalados"
}

# VirtualBox: sus módulos del kernel se compilan para cada kernel instalado (DKMS)
install_virtualbox() {
    local kernels=() headers=() k
    mapfile -t kernels < <(arch_kernel_pkgs)
    for k in "${kernels[@]}"; do headers+=("$k-headers"); done
    pkg_install_recorded virtualbox virtualbox-host-dkms "${headers[@]}" || return 1
    getent group vboxusers > /dev/null && ! id -nG | grep -qw vboxusers \
        && run "No se pudo dar permiso para VirtualBox" sudo usermod -aG vboxusers "$USER"
    run "No se pudo cargar el módulo de VirtualBox" sudo modprobe vboxdrv
    log_success "VirtualBox instalado (cierra sesión y vuelve a entrar para usar USB en las máquinas virtuales)"
}

# ============================================================
# FUNCIONES DE EJECUCIÓN
# ============================================================

remove_apps_with_progress() {
    local installed=() safe=() app core extra=()

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    mapfile -t installed < <(pkg_installed "$@")
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

    # pacman no quita una app que otro paquete necesita: esas se informan y se dejan
    safe=()
    for app in "${installed[@]}"; do
        if pkg_removal_set "$app" > /dev/null; then
            safe+=("$app")
        else
            echo -e "  ${RED}🛡 No se quita $app: otro paquete instalado la necesita${NC}"
        fi
    done
    installed=("${safe[@]}")
    # Lo que pacman quitaría además (dependencias que quedan sin uso)
    if [ ${#installed[@]} -gt 0 ]; then
        mapfile -t extra < <(pkg_removal_set "${installed[@]}" | grep -vxF -f <(printf '%s\n' "${installed[@]}"))
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

# ============================================================
# OPCIÓN 11: REVERTIR CAMBIOS (COLOR: ROJO)
# ============================================================

# Instala los paquetes que falten; si el lote falla, los intenta uno a uno
install_missing_pkgs() {
    local available=() missing=() failed=() p
    # shellcheck disable=SC2046  # listas de paquetes: se separan a propósito
    mapfile -t available < <(pkg_available $(printf '%s\n' "$@" | sort -u) | sort -u)
    [ ${#available[@]} -gt 0 ] && mapfile -t missing < <(comm -23 \
        <(printf '%s\n' "${available[@]}") <(pkg_installed "${available[@]}" | sort -u))

    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ Todos los paquetes de ${FLAVOR_NAME} ya están instalados${NC}"
        return 0
    fi
    echo -e "  ${RED}📦 Instalando ${#missing[@]} paquetes: ${missing[*]}${NC}"
    if pkg_install "${missing[@]}"; then
        log_success "Paquetes reinstalados"
        return 0
    fi

    log_warning "Reintentando los paquetes uno a uno..."
    for p in "${missing[@]}"; do
        pkg_install "$p" > /dev/null || failed+=("$p")
    done
    if [ ${#failed[@]} -gt 0 ]; then
        log_error "No se pudieron reinstalar: ${failed[*]}"
        return 1
    fi
    log_success "Paquetes reinstalados"
}
#@parte comun: restore_theme

revert_changes() {
    clear
    echo -e "${RED}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                ⏪ REVERTIR A LA INSTALACIÓN ORIGINAL             ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}🐧 Detectado: ${FLAVOR_NAME} (${DESKTOP_NAME})${NC}"

    local removed_count=0
    [ -f "$REMOVED_LIST" ] && removed_count=$(wc -l < "$REMOVED_LIST")

    echo -e "\n${RED}📋 Esto hará:${NC}"
    [ -n "$FLAVOR_META" ] && echo -e "  • Reinstalar ${FLAVOR_META} y todas las apps de tu escritorio"
    [ "$removed_count" -gt 0 ] && echo -e "  • Reinstalar los $removed_count paquetes eliminados con este script"
    if has_desktop; then
        echo -e "  • Restaurar los accesos directos del escritorio y del panel"
        echo -e "  • Restaurar el tema del escritorio (si el script lo cambió)"
    fi
    echo -e "  • Volver a los valores de fábrica los ajustes del script (RAM, DNS, ZRAM, energía...)"
    echo -e "\n${YELLOW}ℹ No cambia el kernel (opción 14), los repositorios (opción 12) ni el arranque (opción 19).${NC}"
    echo -e "${YELLOW}  Los programas que instaló el script se quitan desde la opción 10.${NC}\n"

    if ! confirm "${RED}⚠ ¿Revertir a la instalación original?${NC}"; then
        return 0
    fi

    echo -e "${RED}[1/3] Reinstalando paquetes...${NC}"
    pkg_refresh
    local pkgs=()
    if [ -n "$FLAVOR_META" ]; then
        mapfile -t pkgs < <(flavor_meta_pkgs)
        pkgs+=("$FLAVOR_META")
    fi
    [ -f "$REMOVED_LIST" ] && mapfile -t -O "${#pkgs[@]}" pkgs < "$REMOVED_LIST"
    if [ ${#pkgs[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No hay paquetes que reinstalar${NC}"
    elif install_missing_pkgs "${pkgs[@]}"; then
        rm -f "$REMOVED_LIST"
    fi

    echo -e "${RED}[2/3] Restaurando escritorio...${NC}"
    if has_desktop; then
        restore_desktop_shortcuts
        restore_panel_launchers
        restore_theme
    else
        echo -e "  ${GREEN}✓ Sin escritorio: no hay accesos ni tema que restaurar${NC}"
    fi

    echo -e "${RED}[3/3] Restaurando ajustes y limpiando configuraciones...${NC}"
    restore_all_tweaks
    rm -rf ~/.config/alacritty
    rm -f "$HOME/.config/environment.d/90-mangohud.conf"

    echo ""
    echo -e "${GREEN}✓ ${FLAVOR_NAME} revertido a su estado original${NC}"
    echo -e "${YELLOW}⚠ Reinicia para completar${NC}"
    pause
}
#@parte arranque: datos_boot_root boot_os_value boot_has_cmd on_target boot_detect boot_find_esp boot_find_efi_id grub_available grub_required grub_uses_bls grub_update grub_set_default grub_editenv_list grub_probe grub_packages boot_pkg_supported

boot_pkg_installed() {
    case $BOOT_FAMILY in
        debian) pkg_installed "$@" ;;
        arch) pacman -Qq "$@" 2>/dev/null ;;
        fedora|suse) rpm -q --qf '%{NAME}\n' "$@" 2>/dev/null | grep -v 'not installed' ;;
    esac
}

boot_pkg_install() {
    boot_pkg_supported || return 1
    case $BOOT_FAMILY in
        debian)
            [ -z "$BOOT_ROOT" ] && pkg_refresh
            on_target env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        arch) on_target pacman -S --needed --noconfirm "$@" ;;
        fedora) on_target dnf install -y "$@" ;;
        suse) on_target zypper --non-interactive install "$@" ;;
    esac
}

# Reinstala paquetes reponiendo los archivos que falten
boot_pkg_reinstall() {
    boot_pkg_supported || return 1
    case $BOOT_FAMILY in
        debian)
            [ -z "$BOOT_ROOT" ] && pkg_refresh
            on_target env DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y \
                -o Dpkg::Options::=--force-confmiss "$@" ;;
        arch) on_target pacman -S --noconfirm "$@" ;;
        fedora) on_target dnf reinstall -y "$@" ;;
        suse) on_target zypper --non-interactive install --force "$@" ;;
    esac
}
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

GRUB_OTHERS_FIRST="/etc/grub.d/09_arch_ultimate_tools_otros_primero"
#@parte arranque: others_visible grub_os_prober_toggle uefi_boot_order_menu esp_check_repair esp_fsck

# ------------------------------------------------------------
# Personalizar el menú de GRUB (sin programas externos)
# ------------------------------------------------------------

GRUB_LOOK_FILE="/etc/grub.d/42_arch_ultimate_tools_apariencia"
#@parte arranque: regen_grub grub_scripts grub_scripts_hidden grub_scripts_chmod

# --- Ocultar entradas sueltas -------------------------------------------------
# Cada script de GRUB con entradas ocultas se desactiva (sin permiso de ejecución) y
# en su lugar corre "<script>_arch_ultimate_tools", que lo ejecuta y filtra su salida con
# grub-filtro.awk según la lista de títulos ocultos.
UUT_ETC="/etc/arch-ultimate-tools"
GRUB_HIDDEN_LIST="$UUT_ETC/grub-ocultas"
GRUB_FILTER_AWK="$UUT_ETC/grub-filtro.awk"

write_grub_filter() {
    sudo install -d -m 0755 "$UUT_ETC"
    sudo tee "$GRUB_FILTER_AWK" > /dev/null << 'EOF'
# Arch Ultimate Tools: quita del menú de GRUB las entradas cuyo título está en la lista
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
    sudo tee "${orig}_arch_ultimate_tools" > /dev/null << EOF
#!/bin/sh
# Arch Ultimate Tools: genera las entradas de ${orig##*/} sin las ocultas (ver $GRUB_HIDDEN_LIST)
ORIG='$orig'
[ -f "\$ORIG" ] || exit 0
# Si una actualización volvió a activar el original, este filtro se aparta (sin duplicados)
[ -x "\$ORIG" ] && exit 0
sh "\$ORIG" | awk -v list='$GRUB_HIDDEN_LIST' -f '$GRUB_FILTER_AWK'
EOF
    sudo chmod +x "${orig}_arch_ultimate_tools"
    sudo chmod -x "$orig"
}

remove_grub_filter_wrapper() {
    local orig="$1"
    sudo rm -f "${orig}_arch_ultimate_tools"
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
        [[ "$src" == *arch_ultimate_tools_otros_primero* || "$src" == *_arch_ultimate_tools ]] && src=${src%_arch_ultimate_tools}
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
    for wrapper in /etc/grub.d/*_arch_ultimate_tools; do
        [ -f "$wrapper" ] || continue
        orig=${wrapper%_arch_ultimate_tools}
        printf '%s\n' "${scripts[@]}" | grep -qxF "$orig" || remove_grub_filter_wrapper "$orig"
    done
    for script in "${scripts[@]}"; do
        [[ "$script" == *arch_ultimate_tools_otros_primero ]] && continue
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
# Arch Ultimate Tools: muestra los otros sistemas (Windows, otras distros) antes que Ubuntu.
# El script de os-prober puede estar en su sitio o movido por Grub Customizer; si no
# está, no hace nada (nunca debe hacer fallar update-grub).
GRUB_DISABLE_OS_PROBER=false
export GRUB_DISABLE_OS_PROBER
for script in /etc/grub.d/30_os-prober /etc/grub.d/proxifiedScripts/os-prober; do
    if [ -f "$script" ]; then
        if [ -f /etc/arch-ultimate-tools/grub-filtro.awk ]; then
            sh "$script" | awk -v list=/etc/arch-ultimate-tools/grub-ocultas -f /etc/arch-ultimate-tools/grub-filtro.awk
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
# Arch Ultimate Tools: colores del menú de GRUB
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
            sudo rm -f "$GRUB_DIR"/arch-ultimate-tools-fondo.*
            sudo cp "$file" "$GRUB_DIR/arch-ultimate-tools-fondo.$ext"
            set_grub_var GRUB_BACKGROUND "\"$GRUB_DIR/arch-ultimate-tools-fondo.$ext\""
            ;;
        6)
            backup_grub_config
            sudo sed -i '/^GRUB_BACKGROUND=/d' /etc/default/grub
            sudo rm -f "$GRUB_DIR"/arch-ultimate-tools-fondo.*
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
        [[ "${entry##*/}" == *arch_ultimate_tools* || "${entry##*/}" == README ]] && keep=true
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
    sudo rm -f "$GRUB_LOOK_FILE" "$GRUB_OTHERS_FIRST" $GRUB_DIR/arch-ultimate-tools-fondo.*
    local wrapper
    for wrapper in /etc/grub.d/*_arch_ultimate_tools; do
        [ -f "$wrapper" ] && remove_grub_filter_wrapper "${wrapper%_arch_ultimate_tools}"
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
    echo " Generada el $(date '+%d/%m/%Y') con Arch Ultimate Tools"
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
    echo "    bash /media/\$USER/<pendrive>/arch-ultimate-tools.sh"
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
    if cp "$RESCUE_CARD" "$dir/" 2>> "$LOG_FILE" && cp "$SCRIPT_PATH" "$dir/arch-ultimate-tools.sh" 2>> "$LOG_FILE"; then
        sync
        log_success "Copiados en $dir: el script y la tarjeta de rescate"
        echo -e "${CYAN}ℹ Desde el Live USB: bash /media/\$USER/$(basename "$dir")/arch-ultimate-tools.sh → 18 → 10${NC}"
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
UEFI_FALLBACK_HOOK="/etc/apt/apt.conf.d/99arch-ultimate-tools-arranque-respaldo"
UEFI_FALLBACK_HOOK_PACMAN="/etc/pacman.d/hooks/99-arch-ultimate-tools-arranque-respaldo.hook"
UEFI_FALLBACK_TOOL="/usr/local/sbin/arch-ultimate-tools-arranque-respaldo"
UEFI_FALLBACK_BACKUP="$UUT_ETC/efi-boot-anterior"

# El programa que copia los archivos: lo usa el script y lo llama el gestor de paquetes
# (apt o pacman) después de cada actualización, para que la copia nunca quede vieja.
write_uefi_fallback_tool() {
    sudo install -d -m 755 "$UUT_ETC" /usr/local/sbin
    sed -e "s|__ESP__|$ESP_DIR|" -e "s|__ID__|$EFI_ID|" << 'TOOL' | sudo tee "$UEFI_FALLBACK_TOOL" > /dev/null
#!/bin/sh
# Arch Ultimate Tools: mantiene el arranque de respaldo UEFI (\EFI\BOOT) igual al de
# la distribución (\EFI\__ID__). Solo toca \EFI\BOOT si lo puso el script.
MARK=/etc/arch-ultimate-tools/arranque-respaldo
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
# Arch Ultimate Tools: actualiza el arranque de respaldo UEFI cuando cambia GRUB
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

RESOLVED_DNS_CONF="/etc/systemd/resolved.conf.d/99-arch-ultimate-tools-dns.conf"
NM_WIFI_CONF="/etc/NetworkManager/conf.d/99-arch-ultimate-tools-wifi.conf"

# nombre|servidores (IPv4 e IPv6, con el nombre para DNS cifrado)|descripción
DNS_PROVIDERS=(
    "cloudflare|1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com|Cloudflare: el más rápido en casi todo el mundo, privado"
    "cloudflare-seguro|1.1.1.2#security.cloudflare-dns.com 1.0.0.2#security.cloudflare-dns.com 2606:4700:4700::1112#security.cloudflare-dns.com 2606:4700:4700::1002#security.cloudflare-dns.com|Cloudflare + bloqueo de malware"
    "google|8.8.8.8#dns.google 8.8.4.4#dns.google 2001:4860:4860::8888#dns.google 2001:4860:4860::8844#dns.google|Google Public DNS: muy estable"
    "quad9|9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net|Quad9: bloquea dominios maliciosos, sin registros"
    "adguard|94.140.14.14#dns.adguard-dns.com 94.140.15.15#dns.adguard-dns.com 2a10:50c0::ad1:ff#dns.adguard-dns.com 2a10:50c0::ad2:ff#dns.adguard-dns.com|AdGuard: bloquea anuncios y rastreadores"
)
#@parte comun: dns_provider_field

NM_DNS_CONF="/etc/NetworkManager/conf.d/99-arch-ultimate-tools-dns.conf"

current_dns() {
    if [ -f "$RESOLVED_DNS_CONF" ]; then
        sed -n 's/^# Proveedor: //p' "$RESOLVED_DNS_CONF"
    elif [ -f "$NM_DNS_CONF" ]; then
        sed -n 's/^# Proveedor: //p' "$NM_DNS_CONF"
    else
        echo "automático (el del router)"
    fi
}

# Aplica el DNS para todo el sistema. Con systemd-resolved, además cifrado (DNS over TLS)
# cuando el servidor lo permite. Si no está (lo normal en Debian y Arch), se usa
# NetworkManager. Si después no se resuelven nombres, se deshace solo.
set_dns() {
    local name="$1" servers plain
    servers=$(dns_provider_field "$name" 2) || { log_error "Proveedor DNS desconocido: $name"; return 1; }
    if systemctl is-active --quiet systemd-resolved; then
        sudo rm -f "$NM_DNS_CONF"
        sudo install -d -m 0755 /etc/systemd/resolved.conf.d
        # Domains=~. hace que se use este DNS para todo, en lugar del que da el router
        printf '# Proveedor: %s\n[Resolve]\nDNS=%s\nDomains=~.\nDNSOverTLS=opportunistic\n' "$name" "$servers" \
            | sudo tee "$RESOLVED_DNS_CONF" > /dev/null
        run "No se pudo reiniciar systemd-resolved" sudo systemctl restart systemd-resolved || return 1
    elif systemctl is-active --quiet NetworkManager; then
        # Sin resolved: DNS global de NetworkManager (sin cifrado: eso lo da resolved)
        plain=$(tr ' ' '\n' <<< "$servers" | cut -d'#' -f1 | paste -sd, -)
        sudo install -d -m 0755 /etc/NetworkManager/conf.d
        printf '# Proveedor: %s\n[global-dns-domain-*]\nservers=%s\n' "$name" "$plain" | sudo tee "$NM_DNS_CONF" > /dev/null
        run "No se pudo recargar NetworkManager" sudo systemctl reload NetworkManager || return 1
        log_info "Sin systemd-resolved el DNS no va cifrado (sí más rápido y con el filtro del proveedor)"
    else
        log_error "No hay systemd-resolved ni NetworkManager: el DNS se cambia en la configuración de tu red"
        return 1
    fi

    sleep 2
    if getent hosts debian.org > /dev/null || getent hosts archlinux.org > /dev/null; then
        log_success "DNS cambiado a $name"
    else
        log_error "Con $name no se resuelven nombres: se vuelve al DNS automático"
        reset_dns
        return 1
    fi
}

reset_dns() {
    if [ -f "$RESOLVED_DNS_CONF" ]; then
        sudo rm -f "$RESOLVED_DNS_CONF"
        run "No se pudo reiniciar systemd-resolved" sudo systemctl restart systemd-resolved
    fi
    if [ -f "$NM_DNS_CONF" ]; then
        sudo rm -f "$NM_DNS_CONF"
        run "No se pudo recargar NetworkManager" sudo systemctl reload NetworkManager
    fi
    log_success "DNS automático restaurado"
}
#@parte comun: measure_dns set_fastest_dns bbr_algorithm enable_bbr disable_bbr disable_wifi_powersave enable_wifi_powersave

# Firmware de BIOS/UEFI, SSD, docks, etc. desde LVFS
update_firmware() {
    pkg_refresh
    command -v fwupdmgr &> /dev/null || pkg_install fwupd || return 1
    run "No se pudo consultar el servicio de firmware" fwupdmgr refresh --force
    echo -e "${BLUE}📋 Actualizaciones de firmware disponibles:${NC}"
    if ! fwupdmgr get-updates 2>&1 | tee -a "$LOG_FILE"; then
        echo -e "${GREEN}✓ No hay actualizaciones de firmware${NC}"
        return 0
    fi
    if confirm "${BLUE}¿Instalar las actualizaciones de firmware? (no apagues el equipo durante el proceso)${NC}"; then
        run_visible "Falló la actualización de firmware" sudo fwupdmgr update -y --no-reboot-check \
            && log_success "Firmware actualizado (puede requerir reinicio)"
    fi
}
#@parte comun: network_menu is_laptop current_power_profile power_profiles_available set_gaming_power

set_power_profile() {
    local profile="$1"
    if ! command -v powerprofilesctl &> /dev/null; then
        if pkg_installed tlp | grep -qx tlp; then
            log_error "Usas TLP: los perfiles de energía los maneja TLP (quítalo en la opción 10 para usar estos)"
            return 1
        fi
        # Xubuntu, Lubuntu y otros no lo traen: es el servicio estándar de perfiles de energía
        echo -e "${YELLOW}📦 Instalando power-profiles-daemon (perfiles de energía)...${NC}"
        pkg_refresh
        pkg_install_recorded power-profiles-daemon || return 1
        run "No se pudo iniciar power-profiles-daemon" sudo systemctl enable --now power-profiles-daemon || return 1
    fi
    if ! powerprofilesctl list 2>/dev/null | grep -q "$profile:"; then
        log_error "Tu equipo no admite el perfil '$profile' (disponibles: $(power_profiles_available))"
        return 1
    fi
    run "No se pudo cambiar el perfil de energía" powerprofilesctl set "$profile" \
        && log_success "Perfil de energía: $profile"
}
#@parte comun: enable_power_saving baloo_cmd disable_baloo gnome_indexer_unit indexer_disabled disable_indexer enable_indexer enable_baloo

MANGOHUD_CONF="$HOME/.config/MangoHud/MangoHud.conf"
MANGOHUD_ENV="$HOME/.config/environment.d/90-mangohud.conf"

# Deja MangoHud mostrando y grabando los FPS (SysMonitorPro lee esos registros).
# Sin configuración, MangoHud no graba nada y solo actúa en juegos lanzados con 'mangohud'.
configure_mangohud() {
    mkdir -p "$(dirname "$MANGOHUD_CONF")" "$HOME/mangohud-logs"
    if [ ! -f "$MANGOHUD_CONF" ]; then
        cat > "$MANGOHUD_CONF" << EOF
# Creado por Arch Ultimate Tools
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
    elif [[ "$ACTIVE_PROFILE" == gaming* ]] || confirm "${YELLOW}¿Activar MangoHud en todos los juegos Vulkan/Proton (sin configurar cada juego)?${NC}"; then
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
PROTON_GE_LIST="$STATE_DIR/proton-ge.txt"
#@parte comun: enable_steam_play steam_play_vdf

# Proton-GE: versión de la comunidad con arreglos para juegos y vídeos que el oficial aún no tiene
install_proton_ge() {
    steam_supported || return 1
    command -v wget &> /dev/null || { pkg_refresh; pkg_install wget; }
    local tag dir tmp
    tag=$(wget -qO- https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest 2>> "$LOG_FILE" \
        | grep -m1 '"tag_name"' | cut -d'"' -f4)
    if [[ ! "$tag" =~ ^GE-Proton[0-9A-Za-z.-]+$ ]]; then
        log_error "No se pudo consultar la última versión de Proton-GE (¿sin internet?)"
        return 1
    fi
    dir="$(steam_dir)/compatibilitytools.d"
    if [ -d "$dir/$tag" ]; then
        echo -e "  ${GREEN}✓ $tag ya está instalado (es la última versión)${NC}"
        return 0
    fi

    echo -e "${BLUE}⬇ Descargando $tag (unos 500 MB)...${NC}"
    mkdir -p "$dir" "${XDG_CACHE_HOME:-$HOME/.cache}"
    tmp=$(mktemp -d -p "${XDG_CACHE_HOME:-$HOME/.cache}")
    local base="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$tag/$tag"
    if ! wget -q --show-progress -O "$tmp/$tag.tar.gz" "$base.tar.gz" \
        || ! wget -qO "$tmp/$tag.sha512sum" "$base.sha512sum"; then
        log_error "No se pudo descargar $tag"
        rm -rf "$tmp"
        return 1
    fi
    # Se comprueba que el archivo llegó entero y es el publicado
    if ! (cd "$tmp" && sha512sum -c --status "$tag.sha512sum"); then
        log_error "La descarga de $tag está dañada (la suma de comprobación no coincide)"
        rm -rf "$tmp"
        return 1
    fi
    if ! tar -xzf "$tmp/$tag.tar.gz" -C "$dir" >> "$LOG_FILE" 2>&1 || [ ! -d "$dir/$tag" ]; then
        log_error "No se pudo descomprimir $tag"
        rm -rf "$tmp" "${dir:?}/$tag"
        return 1
    fi
    rm -rf "$tmp"
    mkdir -p "$STATE_DIR"
    echo "$dir/$tag" >> "$PROTON_GE_LIST"
    log_success "$tag instalado"
    log_info "Para usarlo en un juego: Propiedades → Compatibilidad → $tag (reinicia Steam si estaba abierto)"
}
#@parte comun: remove_proton_ge power_menu

# ============================================================
# OPCIÓN 10: DESHACER OPTIMIZACIONES (COLOR: ROJO)
# ============================================================

# Programas que el script puede instalar. Sirve para ofrecer también los que se
# instalaron antes de que existiera el registro. No incluye paquetes del sistema
# que Ubuntu ya trae (python3, curl, wget): quitarlos podría romper otras cosas.
SCRIPT_PROGRAMS=(torbrowser-launcher inetutils filezilla code virtualbox virtualbox-host-dkms chromium telegram-desktop python-pip git htop
    fastfetch inxi timeshift gparted vim discord obs-studio alacritty gamemode lib32-gamemode mangohud lib32-mangohud
    steam corectrl tlp tlp-rdw zram-generator reflector pacman-contrib smartmontools jdk21-openjdk jdk17-openjdk
    android-tools android-udev flatpak flatpak-builder docker docker-compose docker-buildx cuda)
#@parte comun: sysctl_default restore_sysctl_defaults

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
    if [ -f "$RESOLVED_DNS_CONF" ] || [ -f "$NM_DNS_CONF" ]; then changed_line "DNS: $(current_dns)"; else factory_line "DNS: automático (el del router)"; fi
    if [ -f "$NM_WIFI_CONF" ]; then changed_line "Wi-Fi: ahorro de energía desactivado"; else factory_line "Wi-Fi: de fábrica"; fi
    if zram_enabled; then changed_line "ZRAM: activo"; else factory_line "ZRAM: no configurado por el script"; fi
    if pkg_installed tlp | grep -qx tlp; then
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
    echo ""
    [ "$changed" -gt 0 ]
}

# Todo lo que el script cambia en la configuración, sin desinstalar programas
restore_all_tweaks() {
    echo -e "${YELLOW}🔧 Ajustes del sistema (RAM, inotify, BBR...)${NC}"
    restore_sysctl_defaults
    echo -e "${YELLOW}🌐 DNS y Wi-Fi${NC}"
    if [ -f "$RESOLVED_DNS_CONF" ] || [ -f "$NM_DNS_CONF" ]; then reset_dns; else echo -e "  ${GREEN}✓ El DNS ya es el automático${NC}"; fi
    if [ -f "$NM_WIFI_CONF" ]; then enable_wifi_powersave; else echo -e "  ${GREEN}✓ El ahorro del Wi-Fi ya está como de fábrica${NC}"; fi
    echo -e "${YELLOW}💾 ZRAM${NC}"
    disable_zram
    echo -e "${YELLOW}🔋 Energía${NC}"
    if pkg_installed tlp | grep -qx tlp; then
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
        echo -e "  ${RED}11)${NC} 📝 Quitar el registro de auditoría (auditd)"
        echo -e "\n  ${RED} 0)${NC} 🔙 Volver"
        echo -e "\n${YELLOW}ℹ Otros cambios se deshacen en su menú: kernel (14), distribución original (11),${NC}"
        echo -e "${YELLOW}  accesos directos (6), DNS/BBR/Wi-Fi (16), energía e indexador (17)${NC}\n"
        read -r -p "📌 Opción (0-11): " undo_option

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
            11) disable_audit ;;
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
#@parte comun: datos_info_quiet info_title cpu_temperature info_summary info_cpu_ram info_gpu

info_disks() {
    local disk
    info_title "DISCOS Y PARTICIONES"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL 2>/dev/null | grep -v -E 'loop|zram' | sed 's/^/  /'
    info_title "ESPACIO"
    df -h -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | sed 's/^/  /'
    info_title "SALUD DE LOS DISCOS (SMART)"
    if ! command -v smartctl &> /dev/null; then
        if $INFO_QUIET; then
            echo "  (smartmontools no está instalado)"
            return 0
        fi
        echo -e "${CYAN}ℹ Para leer la salud de los discos hace falta smartmontools (se puede quitar en la opción 10)${NC}"
        confirm "${CYAN}¿Instalarlo?${NC}" || return 0
        pkg_refresh
        pkg_install_recorded smartmontools || return 1
    fi
    for disk in $(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" && $1 !~ /zram/ {print $1}'); do
        echo "  $disk"
        LC_ALL=C sudo smartctl -H -A "$disk" 2>/dev/null | grep -E \
            'overall-health|Percentage Used|Power On Hours|Power_On_Hours|^Temperature:|Temperature_Celsius|Media and Data Integrity|Reallocated_Sector|Wear_Leveling|Percent_Lifetime|Unsafe Shutdowns|Available Spare:' \
            | sed -e 's/SMART overall-health self-assessment test result:/Estado general:/' -e 's/  */ /g; s/^/    /'
    done
}
#@parte comun: info_temps info_network info_battery info_usb info_diagnostics

info_script_changes() {
    local custom count
    info_title "CAMBIOS HECHOS POR ESTE SCRIPT"
    echo "  Kernel en uso: $(uname -r)"
    custom=$(pkg_installed 'linux-image-[0-9]*' | grep -E 'liquorix|xanmod' | sed 's/^linux-image-//' | tr '\n' ' ')
    [ -n "$custom" ] && echo "  Kernels de terceros instalados: $custom"
    [ -n "$FLAVOR_META" ] && ! pkg_installed "$FLAVOR_META" | grep -qx -- "$FLAVOR_META" \
        && echo "  Meta-paquete $FLAVOR_META: quitado"
    [ -f /etc/default/grub ] && echo "  GRUB: $(grep -E '^GRUB_(DEFAULT|TIMEOUT)=' /etc/default/grub | tr '\n' ' ')"
    if [ -s "$GRUB_HIDDEN_LIST" ]; then
        echo "  Entradas ocultas en GRUB: $(wc -l < "$GRUB_HIDDEN_LIST")"
    fi
    [ -f "$GRUB_OTHERS_FIRST" ] && echo "  GRUB: otros sistemas antes que ${FLAVOR_NAME}"
    [ -f "$GRUB_LOOK_FILE" ] && echo "  GRUB: colores personalizados"
    if [ -f "$REMOVED_LIST" ]; then
        count=$(wc -l < "$REMOVED_LIST")
        echo "  Paquetes eliminados: $count"
    fi
    if [ -f "$INSTALLED_LIST" ]; then
        echo "  Programas instalados: $(tr '\n' ' ' < "$INSTALLED_LIST")"
    fi
    show_tweaks_status | sed 's/\x1b\[[0-9;]*m//g' | grep -v '^$' | grep -v 'Estado actual' | sed 's/^ */  /'
    return 0
}

# Informe completo en texto, sin preguntas ni descargas
info_full_report() {
    local was=$INFO_QUIET
    INFO_QUIET=true
    echo "Informe de Arch Ultimate Tools · $(date '+%Y-%m-%d %H:%M')"
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
    if command -v wget &> /dev/null && wget -qO /dev/null "https://speed.cloudflare.com/__down?bytes=$bytes" 2>> "$LOG_FILE"; then
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
#   En Arch se instala desde los repositorios oficiales (se quita en 10 → 1).
# - auditd (Linux Audit, GPL-2.0): registra cambios en usuarios, sudo, SSH, hora, módulos...
#   Las reglas son propias de este script, sin "-e 2" (no se bloquean) y se quitan cuando quieras.
# Idea inspirada en Linux-Security-Policy de Jeff Starke (Starke427): no se usa su código
# porque su repositorio no tiene licencia.
# ------------------------------------------------------------
AUDIT_RULES_FILE="/etc/audit/rules.d/60-ultimate-tools.rules"
SECURITY_DIR="$HOME/auditoria-seguridad"
#@parte auditoria: lynis_summary

security_audit_lynis() {
    clear
    echo -e "${CYAN}${BOLD}🛡️ AUDITORÍA DE SEGURIDAD CON LYNIS${NC}\n"
    echo -e "Lynis (de CISOfy, licencia GPL-3.0) revisa cientos de puntos de seguridad: usuarios,"
    echo -e "contraseñas, SSH, cortafuegos, servicios, permisos, kernel... y da un puntaje con consejos."
    echo -e "${GREEN}Solo mira: no cambia nada. Tarda unos minutos.${NC}\n"

    local stamp out lynis_cmd=() tmp="" choice
    stamp=$(date +%Y%m%d-%H%M)
    out="$SECURITY_DIR/$stamp"

    if command -v lynis &> /dev/null; then
        lynis_cmd=(lynis)
    else
        echo -e "${CYAN}ℹ Lynis no está instalado. Se instala desde los repositorios oficiales de Arch${NC}"
        echo -e "${CYAN}  (~1 MB, se quita en 10 → 1).${NC}"
        confirm "${CYAN}¿Instalar Lynis?${NC}" || return 0
        pkg_install_recorded lynis || return 1
        lynis_cmd=(lynis)
    fi

    mkdir -p "$out"
    chmod 700 "$SECURITY_DIR" "$out"
    echo -e "\n${BLUE}🔍 Revisando el sistema (puede tardar unos minutos)...${NC}\n"
    sudo "${lynis_cmd[@]}" audit system --quick --logfile "$out/lynis.log" --report-file "$out/lynis-informe.dat"
    [ -n "$tmp" ] && sudo rm -rf "$tmp"
    if [ ! -s "$out/lynis-informe.dat" ]; then
        log_error "Lynis no generó el informe (detalles en $out)"
        return 1
    fi
    sudo chown -R "$(id -u):$(id -g)" "$out"
    lynis_summary "$out/lynis-informe.dat" | tee "$out/resumen.txt"
    echo -e "\n${GREEN}📁 Informe completo en $out${NC}"
    echo -e "${YELLOW}  Contiene datos de tu sistema: no lo compartas en público.${NC}"
    [ -n "$tmp" ] && echo -e "${GREEN}✓ Lynis se borró: no quedó nada instalado${NC}"
}
#@parte auditoria: audit_rules_active

# Reglas del script: solo vigila rutas que existen y llamadas que existen en este procesador
build_audit_rules() {
    local p arch
    echo "## Arch Ultimate Tools: registro de auditoría (se quita desde el menú 2 → 5)"
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

enable_audit() {
    echo -e "${CYAN}📝 Registro de auditoría (auditd, Linux Audit, GPL-2.0)${NC}"
    echo -e "   Anota quién y cuándo cambia usuarios, contraseñas, sudo, SSH, la hora, la red,"
    echo -e "   tareas programadas, servicios, repositorios y módulos del kernel."
    echo -e "   ${GREEN}No protege por sí solo: sirve para saber qué pasó si algo cambia.${NC}"
    echo -e "   Los registros van a /var/log/audit (auditd los rota solo, ~40 MB como máximo).\n"
    if ! command -v auditctl &> /dev/null; then
        confirm "${CYAN}¿Instalar auditd (paquete audit, ~1 MB, se quita desde aquí mismo)?${NC}" || return 0
        pkg_install_recorded audit || return 1
    fi
    local tmp
    tmp=$(mktemp)
    build_audit_rules > "$tmp"
    sudo install -D -m 0640 "$tmp" "$AUDIT_RULES_FILE"
    rm -f "$tmp"
    run "No se pudo activar auditd" sudo systemctl enable --now auditd
    if sudo auditctl -s 2>/dev/null | grep -q '^enabled 2'; then
        log_warning "Las reglas de auditoría están bloqueadas hasta reiniciar (las puso otro programa): se aplican al reiniciar"
        return 0
    fi
    if sudo augenrules --load >> "$LOG_FILE" 2>&1 && sudo auditctl -l 2>/dev/null | grep -q -- '-k identidad'; then
        log_success "Registro de auditoría activo ($(sudo auditctl -l | grep -c -- ' -k ') reglas)"
        echo -e "${CYAN}ℹ Para verlo: opción 2 → 4 (Ver qué se registró)${NC}"
    else
        sudo rm -f "$AUDIT_RULES_FILE"
        sudo augenrules --load >> "$LOG_FILE" 2>&1
        log_error "auditd no aceptó las reglas en este sistema (¿contenedor o WSL?): se quitaron, todo queda como estaba"
        return 1
    fi
}
#@parte auditoria: show_audit_events

disable_audit() {
    if ! audit_rules_active && ! grep -qx audit "$INSTALLED_LIST" 2>/dev/null; then
        echo -e "${YELLOW}ℹ El script no activó el registro de auditoría${NC}"
        return 0
    fi
    confirm "${RED}¿Quitar el registro de auditoría del script?${NC}" || return 0
    if audit_rules_active; then
        sudo rm -f "$AUDIT_RULES_FILE"
        command -v augenrules &> /dev/null && sudo augenrules --load >> "$LOG_FILE" 2>&1
        log_success "Reglas de auditoría del script quitadas"
    fi
    if grep -qx audit "$INSTALLED_LIST" 2>/dev/null \
        && confirm "${RED}¿Desinstalar también auditd (paquete audit, lo instaló el script)?${NC}"; then
        pkg_remove audit && forget_installed audit && log_success "auditd desinstalado"
        if [ -d /var/log/audit ] && confirm "${RED}¿Borrar también los registros guardados en /var/log/audit?${NC}"; then
            sudo rm -rf /var/log/audit && log_success "Registros borrados"
        fi
    fi
}
#@parte auditoria: datos_linaudit_git linaudit_cleanup
LINAUDIT_BIN="/usr/local/bin/linaudit"
LINAUDIT_STATE="$STATE_DIR/linaudit.txt"
LINAUDIT_MIN_RUST="1.85"
#@parte auditoria: version_ge linaudit_need_cc linaudit_get_cargo linaudit_build linaudit_run security_audit_linaudit remove_linaudit security_menu
#@parte comun: info_htop

sysinfo_menu() {
    $INFO_QUIET || ensure_lspci > /dev/null 2>&1
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

# ============================================================
# MENÚ PRINCIPAL (COLOR: CIAN)
# ============================================================

# Arch y sus derivadas (Manjaro, EndeavourOS, CachyOS, Garuda...). En cualquier otra
# distribución solo está el menú de arranque, que sirve en todas.
arch_based() {
    local ids=" $(os_release_value ID) $(os_release_value ID_LIKE) "
    [[ "$ids" == *" arch "* || "$ids" == *" archlinux "* || "$ids" == *" manjaro "* ]] && command -v pacman &> /dev/null
}

ubuntu_based() {
    [[ " $(os_release_value ID) $(os_release_value ID_LIKE) " == *" ubuntu "* ]]
}

BOOT_ONLY=false

boot_only_menu() {
    while true; do
        print_header
        if ubuntu_based; then
            echo -e "${CYAN}ℹ ${BOOT_DISTRO} está basado en Ubuntu: usa ubuntu-ultimate-tools.sh, que tiene todo.${NC}"
            echo -e "${CYAN}  Aquí está disponible el menú de arranque (GRUB y EFI), que sirve en cualquier Linux.${NC}\n"
        else
            echo -e "${CYAN}ℹ En ${BOOT_DISTRO} está disponible el menú de arranque (GRUB y EFI), que sirve en${NC}"
            echo -e "${CYAN}  Ubuntu, Debian, Arch, Manjaro, Fedora y openSUSE. El resto del script es para Arch.${NC}\n"
        fi
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
            0) echo -e "\n${GREEN}✅ ¡Hasta luego!${NC}"; exit 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}
#@parte usb: datos_usb_distros usb_download_dir usb_norm_sums usb_pick_from_sums usb_first_hash usb_hash_of usb_hash_name usb_check_signature usb_index_names usb_sorted usb_resolve_download usb_choose_distro usb_download_iso usb_write_sum_file usb_pick_local_iso usb_entry_pattern usb_official_sum_for usb_sum_lookup usb_known_sum usb_verify_local_iso usb_check_iso usb_candidates usb_pick_device usb_unmount_dev create_usb_menu datos_ventoy_dir ventoy_get_tool ventoy_has ventoy_need_partitioner ventoy_part_label ventoy_find_part ventoy_run ventoy_candidates ventoy_pick_and_mount ventoy_list_images ventoy_write_json ventoy_conf_set ventoy_alias_for ventoy_install ventoy_add ventoy_guess_name ventoy_manage ventoy_persistence_kind ventoy_persistence ventoy_update ventoy_menu

main_menu() {
    $BOOT_ONLY && boot_only_menu
    while true; do
        print_header
        echo -e "${CYAN}📌 ¿Qué deseas hacer?${NC}\n"
        echo -e "  ${CYAN} 1)${NC} 🔄 ACTUALIZAR SISTEMA (pacman -Syu y Flatpak)"
        echo -e "  ${CYAN} 2)${NC} 🛡️ AUDITORÍA DE SEGURIDAD (Lynis, linaudit y registro)"
        echo -e "  ${CYAN} 3)${NC} 📊 Información del sistema y hardware"
        echo ""
        echo -e "  ${CYAN} 4)${NC} 🚮 Eliminar aplicaciones preinstaladas"
        echo -e "  ${CYAN} 6)${NC} 🧹 Quitar accesos directos (escritorio y panel)"
        echo ""
        echo -e "  ${CYAN} 7)${NC} 📦 Instalar software opcional"
        echo -e "  ${CYAN} 8)${NC} 💻 Instalar Alacritty (terminal GPU) y temas"
        echo -e "  ${CYAN}10)${NC} 🩹 Deshacer optimizaciones / quitar programas"
        echo -e "  ${CYAN}11)${NC} ⏪ Revertir a la instalación original"
        echo ""
        echo -e "  ${CYAN}12)${NC} 🔩 Configurar sistema (multilib, servidores, descargas en paralelo)"
        echo -e "  ${CYAN}13)${NC} 🎮 GPU y drivers (NVIDIA/AMD/Intel)"
        echo -e "  ${CYAN}14)${NC} 🐧 Kernel (linux, LTS, Zen; en Manjaro con mhwd-kernel)"
        echo -e "  ${CYAN}15)${NC} 💾 Optimizar Memoria RAM (automático)"
        echo -e "  ${CYAN}16)${NC} 🌐 Red, DNS y firmware"
        echo -e "  ${CYAN}17)${NC} 🔋 Energía y rendimiento"
        echo -e "  ${CYAN}19)${NC} 🔧 ARRANQUE: reparar y personalizar GRUB/EFI"
        echo ""
        echo -e "  ${CYAN}20)${NC} 💿 DESCARGAR SISTEMAS (ISO) Y CREAR USB DE INSTALACIÓN"
        echo ""
        echo -e "  ${CYAN}21)${NC} 🔌 Apagar / Reiniciar sistema"
        echo -e "\n  ${CYAN} 0)${NC} ❌ Salir"
        echo -e "\n${YELLOW}ℹ Versión beta: los números son los mismos que en Ubuntu. Snap (5 y 9) no aplica en${NC}"
        echo -e "${YELLOW}  Arch y los perfiles automáticos (18) llegan en una próxima versión.${NC}"
        echo ""
        read -r -p "🔢 Opción (0-21): " option

        case $option in
            1) ( MENU_SUBSHELL=1; system_update ) ;;
            2) ( MENU_SUBSHELL=1; security_menu ) ;;
            3) ( MENU_SUBSHELL=1; sysinfo_menu ) ;;
            4) ( MENU_SUBSHELL=1; select_apps_to_remove ) ;;
            6) ( MENU_SUBSHELL=1; remove_shortcuts_menu ) ;;
            7) ( MENU_SUBSHELL=1; select_optional_software ) ;;
            8) ( MENU_SUBSHELL=1; install_custom_software ) ;;
            10) ( MENU_SUBSHELL=1; undo_menu ) ;;
            11) ( MENU_SUBSHELL=1; revert_changes ) ;;
            12) ( MENU_SUBSHELL=1; configure_system ) ;;
            13) ( MENU_SUBSHELL=1; optimize_gpu_menu ) ;;
            14) ( MENU_SUBSHELL=1; optimize_kernel_menu ) ;;
            15) ( MENU_SUBSHELL=1; optimize_ram_menu ) ;;
            16) ( MENU_SUBSHELL=1; network_menu ) ;;
            17) ( MENU_SUBSHELL=1; power_menu ) ;;
            19) ( MENU_SUBSHELL=1; grub_repair_menu ) ;;
            20) ( MENU_SUBSHELL=1; create_usb_menu; pause ) ;;
            21) ( MENU_SUBSHELL=1; shutdown_menu ) ;;
            4|8) echo -e "${YELLOW}ℹ Snap no se usa en Arch${NC}"; sleep 2 ;;
            18) echo -e "${YELLOW}ℹ Los perfiles automáticos llegan en una próxima versión${NC}"; sleep 2 ;;
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
    echo -e "${BOLD}Arch Ultimate Tools (beta)${NC} es software libre bajo la licencia ${BOLD}GNU AGPL-3.0${NC} (archivo LICENSE)."
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

SCRIPT_FAMILY=arch
#@parte comun: right_script_family offer_right_script

# ============================================================
# INICIO
# ============================================================

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}❌ No ejecutes este script como root (no uses sudo)${NC}"
    exit 1
fi
NOTICE_OK=false
case ${1:-} in
    -h|--ayuda) echo "Uso: $0 [--entiendo]   (menú interactivo; versión beta para Arch y derivadas)"
                echo "  --entiendo   No mostrar el aviso del primer uso (si ya lo leíste)"; exit 0 ;;
    --entiendo) NOTICE_OK=true ;;
    "") ;;
    *) echo -e "${RED}❌ Opción desconocida: $1${NC} (en la beta no hay perfiles automáticos)"; exit 1 ;;
esac

set_terminal_title "Arch Ultimate Tools (beta) · $(os_release_value PRETTY_NAME)"

# Antes de pedir la contraseña o tocar nada
first_run_notice
offer_right_script
if ! command -v sudo &> /dev/null; then
    echo -e "${RED}❌ Falta sudo. Instálalo como root: su -c 'pacman -S sudo'${NC}"
    echo -e "${RED}   y permite el grupo wheel: su -c 'EDITOR=nano visudo' (descomenta %wheel ALL=(ALL:ALL) ALL)${NC}"
    exit 1
fi

echo "=== Arch Ultimate Tools (beta) - $(date) ===" > "$LOG_FILE"

# Pide la contraseña una sola vez y la mantiene activa mientras corre el script
echo -e "${YELLOW}🔑 Se necesitan permisos de administrador${NC}"
if ! sudo -v; then
    echo -e "${RED}❌ No se pudo obtener sudo. Tu usuario tiene que estar en el grupo wheel:${NC}"
    echo -e "${RED}   su -c 'usermod -aG wheel $USER' y vuelve a entrar (y %wheel habilitado en visudo).${NC}"
    exit 1
fi
while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 60; done 2>/dev/null &

boot_detect
if arch_based; then
    detect_flavor
    boot_detect   # otra vez, ahora con el nombre detectado
    if ! command -v systemctl &> /dev/null; then
        echo -e "${YELLOW}⚠ Este sistema no usa systemd (¿Artix?): ZRAM, energía, DNS y TRIM no van a funcionar${NC}"
        sleep 3
    fi
    case $(os_release_value ID) in
        arch|manjaro|endeavouros) ;;
        *) echo -e "${YELLOW}⚠ Este script está probado en Arch, Manjaro y EndeavourOS; en $(os_release_value NAME)${NC}"
           echo -e "${YELLOW}  algunas opciones pueden variar${NC}"; sleep 2 ;;
    esac
else
    BOOT_ONLY=true
    FLAVOR_NAME="$BOOT_DISTRO" DESKTOP_NAME="modo arranque"
fi

main_menu
