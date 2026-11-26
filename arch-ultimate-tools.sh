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

# ============================================================
# FUNCIONES DE LOG Y PROGRESO
# ============================================================

log() {
    local msg="$1"
    echo -e "$msg"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOG_FILE"
}

log_info() { log "${BLUE}ℹ $1${NC}"; }
log_success() { log "${GREEN}✓ $1${NC}"; }
log_error() { log "${RED}✗ $1${NC}"; }
log_warning() { log "${YELLOW}⚠ $1${NC}"; }
log_title() { log "\n${PURPLE}${BOLD}► $1${NC}\n"; }

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

clear() {
    $AUTO_MODE || command clear
}

pause() {
    $AUTO_MODE && return 0
    echo -e "\n${YELLOW}─────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}📌 Presiona Enter para continuar...${NC}"
    read -r
}

confirm() {
    local prompt="$1"
    local response
    if [ "${FORCE_YES:-false}" = true ]; then
        echo -e "$prompt ${YELLOW}→ sí (ya confirmado)${NC}"
        return 0
    fi
    if $AUTO_MODE; then
        echo -e "$prompt ${YELLOW}→ no (modo automático)${NC}"
        return 1
    fi
    # Dentro de una opción del menú principal, 0 vuelve al menú en cualquier pregunta s/n
    if [ -n "${MENU_SUBSHELL:-}" ]; then
        echo -e -n "$prompt (s/n, 0 = volver al menú): "
    else
        echo -e -n "$prompt (s/n): "
    fi
    read -r response
    if [ "$response" = 0 ] && [ -n "${MENU_SUBSHELL:-}" ]; then
        echo -e "${YELLOW}↩ Volviendo al menú principal (lo que ya se hizo queda hecho)${NC}"
        sleep 1
        exit 0
    fi
    [[ "$response" =~ ^([sSyY]|[sS][iI]|[sS]í|[sS]Í)$ ]]
}

# ============================================================
# FUNCIONES DE EJECUCIÓN SEGURA
# ============================================================

# Ejecuta un comando guardando su salida en el log.
# Si falla, muestra el error en pantalla en lugar de ocultarlo.
run() {
    local desc="$1"
    shift
    echo "[$(date '+%H:%M:%S')] \$ $*" >> "$LOG_FILE"
    # Instalar, quitar o actualizar paquetes puede tardar minutos: con terminal se muestra el avance
    if [ -t 1 ] && progress_wanted "$@"; then
        run_with_progress "$desc" "$@"
        return
    fi
    "$@" >> "$LOG_FILE" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
        log_error "$desc (código $rc). Detalles en: $LOG_FILE"
    fi
    return $rc
}

# ¿El comando es apt-get o pacman cambiando paquetes? (no las consultas rápidas)
progress_wanted() {
    local a
    for a in "$@"; do
        case $a in
            apt-get|pacman) return 0 ;;
        esac
    done
    return 1
}

# Barra de avance: [#######-------]  45%  01:23  Quitando libreoffice-core
progress_draw() {
    local pct="$1" text="$2" secs="$3" elapsed cols width filled bar line
    cols=$(tput cols 2>/dev/null || echo 80)
    printf -v elapsed '%02d:%02d' $((secs / 60)) $((secs % 60))
    if [ -n "$pct" ]; then
        width=20
        filled=$((pct * width / 100))
        printf -v bar '%*s' "$filled" ''
        bar=${bar// /#}
        printf -v bar '%-*s' "$width" "$bar"
        bar=${bar// /-}
        line="  [$bar] $(printf '%3d' "$pct")%  $elapsed  $text"
    else
        local spin='|/-\'
        line="  ${spin:$((secs % 4)):1} Trabajando...  $elapsed  $text"
    fi
    printf '\r\033[K%s' "${line:0:$((cols - 1))}"
}

run_with_progress() {
    local desc="$1"
    shift
    local status="" verb="Procesando" a cmd=() is_apt=false pid rc start line pct pkg n m
    for a in "$@"; do
        case $a in
            apt-get) is_apt=true ;;
            install|-S|-Syu|-Su) verb="Instalando" ;;
            purge|remove|-R|-Rns|-Rs) verb="Quitando" ;;
            autoremove) verb="Limpiando" ;;
            full-upgrade|upgrade|dist-upgrade) verb="Actualizando" ;;
        esac
    done
    if $is_apt && [ "$1" = sudo ]; then
        # apt informa su avance real por un descriptor aparte (APT::Status-Fd)
        status=$(mktemp)
        shift
        cmd=(sudo bash -c 'exec 3>>"$1"; shift; exec "$@"' _ "$status")
        for a in "$@"; do
            cmd+=("$a")
            [ "$a" = apt-get ] && cmd+=(-o APT::Status-Fd=3)
        done
    else
        cmd=("$@")
    fi
    "${cmd[@]}" >> "$LOG_FILE" 2>&1 &
    pid=$!
    start=$SECONDS
    # sudo corre como root: se mira /proc en vez de kill -0
    while [ -d "/proc/$pid" ]; do
        pct="" line=""
        if [ -n "$status" ]; then
            line=$(grep -a -E '^(pm|dl)status:' "$status" 2>/dev/null | tail -1)
            if [ -n "$line" ]; then
                IFS=: read -r _ pkg pct _ <<< "$line"
                pct=${pct%%.*}
                if [[ "$line" == dlstatus:* ]]; then
                    line="Descargando"
                elif [ "$pkg" = dpkg-exec ]; then
                    line="Preparando..."
                else
                    line="$verb $pkg"
                fi
            fi
        else
            # pacman escribe "( 3/12) eliminando paquete": el avance sale de ahí
            line=$(tail -n 5 "$LOG_FILE" 2>/dev/null | grep -a -E '^\( *[0-9]+/[0-9]+\)' | tail -1)
            if [[ "$line" =~ ^\(\ *([0-9]+)/([0-9]+)\)\ *(.*)$ ]]; then
                n=${BASH_REMATCH[1]} m=${BASH_REMATCH[2]}
                pct=$((n * 100 / m))
                line=${BASH_REMATCH[3]}
            else
                line=$(tail -n 1 "$LOG_FILE" 2>/dev/null | tr -d '\r')
            fi
        fi
        [[ "$pct" =~ ^[0-9]+$ ]] || pct=""
        progress_draw "$pct" "$line" $((SECONDS - start))
        sleep 0.5
    done
    wait "$pid"
    rc=$?
    printf '\r\033[K'
    [ -n "$status" ] && rm -f "$status"
    if [ $rc -ne 0 ]; then
        log_error "$desc (código $rc). Detalles en: $LOG_FILE"
    elif [ $((SECONDS - start)) -ge 3 ]; then
        echo -e "  ${GREEN}✓ Listo en $(printf '%02d:%02d' $(((SECONDS - start) / 60)) $(((SECONDS - start) % 60)))${NC}"
    fi
    return $rc
}

# Nombre del script en la pestaña y la ventana de la terminal (Konsole muestra la carpeta si no)
set_terminal_title() {
    [ -t 1 ] || return 0
    printf '\033]0;%s\007\033]30;%s\007' "$1" "$1"
    trap 'printf "\033]30;\007"' EXIT
}

# Como 'run', pero mostrando la salida en pantalla (para operaciones largas)
run_visible() {
    local desc="$1"
    shift
    echo "[$(date '+%H:%M:%S')] \$ $*" >> "$LOG_FILE"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then
        log_error "$desc (código $rc). Detalles en: $LOG_FILE"
    fi
    return "$rc"
}

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

# Aplica un parámetro sysctl y lo deja persistente sin duplicar líneas
set_sysctl() {
    local key="$1" value="$2"
    run "No se pudo aplicar $key=$value" sudo sysctl -w "$key=$value"
    # Versiones anteriores añadían líneas repetidas en /etc/sysctl.conf
    sudo sed -i "/^${key//./\\.}=/d" /etc/sysctl.conf 2>/dev/null
    sudo touch "$SYSCTL_FILE"
    if grep -q "^${key//./\\.} *=" "$SYSCTL_FILE"; then
        sudo sed -i "s|^${key//./\\.} *=.*|$key = $value|" "$SYSCTL_FILE"
    else
        echo "$key = $value" | sudo tee -a "$SYSCTL_FILE" > /dev/null
    fi
}

# Colores de alto contraste para whiptail: los de fábrica (azul y gris claro) se leen
# mal con muchos temas de Konsole. Se respeta NEWT_COLORS si el usuario ya lo definió.
WHIPTAIL_COLORS='
root=white,black
border=cyan,black
window=white,black
shadow=black,black
title=brightcyan,black
textbox=white,black
listbox=white,black
actlistbox=black,cyan
sellistbox=white,black
actsellistbox=black,cyan
checkbox=white,black
actcheckbox=black,cyan
button=white,blue
actbutton=black,cyan
compactbutton=white,black
helpline=white,black
roottext=white,black
'

# Colores de dialog iguales a los del script: fondo oscuro y la línea del cursor resaltada en celeste.
# Lo resaltado va SIN negrita: muchas terminales (Konsole) muestran el negro en negrita como gris
# claro, y sobre celeste no se lee.
DIALOG_RC='use_shadow = OFF
use_colors = ON
screen_color = (WHITE,BLACK,OFF)
dialog_color = (WHITE,BLACK,OFF)
title_color = (CYAN,BLACK,ON)
border_color = (CYAN,BLACK,OFF)
border2_color = (CYAN,BLACK,OFF)
button_active_color = (BLACK,CYAN,OFF)
button_inactive_color = (WHITE,BLACK,OFF)
button_key_active_color = (BLACK,CYAN,OFF)
button_key_inactive_color = (WHITE,BLACK,ON)
button_label_active_color = (BLACK,CYAN,OFF)
button_label_inactive_color = (WHITE,BLACK,ON)
menubox_color = (WHITE,BLACK,OFF)
menubox_border_color = (CYAN,BLACK,OFF)
menubox_border2_color = (CYAN,BLACK,OFF)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (BLACK,CYAN,OFF)
tag_color = (CYAN,BLACK,OFF)
tag_selected_color = (BLACK,CYAN,OFF)
tag_key_color = (CYAN,BLACK,OFF)
tag_key_selected_color = (BLACK,CYAN,OFF)
check_color = (WHITE,BLACK,OFF)
check_selected_color = (BLACK,CYAN,OFF)
uarrow_color = (CYAN,BLACK,ON)
darrow_color = (CYAN,BLACK,ON)
position_indicator_color = (CYAN,BLACK,ON)'

# whiptail (viene en todas las distros) solo marca la casilla del cursor, no la línea; dialog sí
# resalta la línea entera. Si no está dialog, se ofrece instalarlo una vez (~300 KB).
checklist_tool() {
    if command -v dialog &> /dev/null; then
        echo dialog
        return
    fi
    if ! $AUTO_MODE && [ ! -f "$STATE_DIR/dialog-preguntado" ]; then
        mkdir -p "$STATE_DIR"
        touch "$STATE_DIR/dialog-preguntado"
        echo -e "${CYAN}ℹ Las listas con casillas se ven mejor con 'dialog': resalta la línea donde está el cursor${NC}" >&2
        echo -e "${CYAN}  (~300 KB, de los repositorios oficiales; se quita en 10 → 1).${NC}" >&2
        if confirm "${CYAN}¿Instalar dialog?${NC}" >&2; then
            if declare -F apt_install_recorded > /dev/null; then
                { apt_update; apt_install_recorded dialog; } >&2
            else
                pkg_install_recorded dialog >&2
            fi
            command -v dialog &> /dev/null && { echo dialog; return; }
        fi
    fi
    command -v whiptail &> /dev/null && echo whiptail
}

# Lista con casillas: barra espaciadora para marcar, Enter para aceptar.
# Entradas "paquete|descripción" o "paquete|descripción|ON" (casilla ya marcada);
# deja lo elegido en CHOSEN. Devuelve 1 si se cancela.
# Con CHECKLIST_NOTAGS=true no se muestra la columna de nombres internos.
# Si no hay dialog ni whiptail (o no es una terminal interactiva) se elige escribiendo números.
checklist_select() {
    local title="$1" text="$2"
    shift 2
    local entries=("$@") args=() entry name desc status i=0 input num tool="" has_sys=false
    CHOSEN=()

    [ -t 0 ] && [ -t 1 ] && tool=$(checklist_tool)
    if [ -n "$tool" ]; then
        local cols lines w h lh tagw=0 max_desc out
        cols=$(tput cols 2>/dev/null || echo 80)
        lines=$(tput lines 2>/dev/null || echo 24)
        # Ancho según la terminal (entre 60 y 120 columnas) y alto justo para la lista
        w=$((cols - 4))
        [ "$w" -gt 120 ] && w=120
        [ "$w" -lt 60 ] && w=60
        if [ -z "$CHECKLIST_NOTAGS" ]; then
            for entry in "${entries[@]}"; do
                name=${entry%%|*}
                [ ${#name} -gt "$tagw" ] && tagw=${#name}
            done
            [ "$tagw" -gt 28 ] && tagw=28
        fi
        # Lo que queda para la descripción: así ningún renglón se sale del recuadro
        max_desc=$((w - tagw - 14))
        for entry in "${entries[@]}"; do
            status=off
            [[ "$entry" == *"|ON" ]] && { status=on; entry=${entry%|ON}; }
            name=${entry%%|*}
            desc=${entry#*|}
            local sysmark=false
            [[ "$desc" == SYS::* ]] && { sysmark=true; desc=${desc#SYS::}; has_sys=true; }
            # Sin el emoji inicial: se calcula mal su ancho y descuadra la lista
            [[ "$desc" == *" "* ]] && [[ "${desc%% *}" != *[A-Za-z0-9]* ]] && desc=${desc#* }
            if $sysmark; then
                if [ "$tool" = dialog ]; then desc="\\Z1⚠ SISTEMA\\Zn $desc"; else desc="⚠ SISTEMA: $desc"; fi
            fi
            # whiptail no se adapta: se recorta al ancho de ahora. dialog se ajusta solo (también al
            # agrandar o achicar la ventana), así que solo se limita a algo razonable
            if [ "$tool" = whiptail ]; then
                [ ${#desc} -gt "$max_desc" ] && desc="${desc:0:$((max_desc - 1))}…"
            else
                [ ${#desc} -gt 100 ] && desc="${desc:0:99}…"
            fi
            args+=("$name" "$desc" "$status")
        done
        lh=${#entries[@]}
        [ "$lh" -gt $((lines - 12)) ] && lh=$((lines - 12))
        [ "$lh" -lt 3 ] && lh=3
        h=$((lh + 10))
        if [ "$tool" = dialog ]; then
            # Tamaño 0 0 0 = automático: dialog lo calcula y lo recalcula si cambias el tamaño de la ventana
            local rc_file
            rc_file=$(mktemp)
            printf '%s\n' "$DIALOG_RC" > "$rc_file"
            $has_sys && text="$text\n\Z1⚠ SISTEMA\Zn = herramienta del sistema o de tu distribución: quítala solo si sabes que no la usas"
            out=$(DIALOGRC="${DIALOGRC:-$rc_file}" NCURSES_NO_UTF8_ACS=1 dialog --colors --title " $title " --ok-label "Aceptar" --cancel-label "Cancelar" \
                --separate-output ${CHECKLIST_NOTAGS:+--no-tags} \
                --checklist "$text\n\nEspacio: marcar/desmarcar · Flechas: moverse · Enter: aceptar" \
                0 0 0 "${args[@]}" 3>&1 1>&2 2>&3)
            local rc=$?
            rm -f "$rc_file"
            [ $rc -eq 0 ] || return 1
        else
            $has_sys && text="$text\n⚠ SISTEMA = herramienta del sistema o de tu distribución: quítala solo si sabes que no la usas"
            out=$(NEWT_COLORS="${NEWT_COLORS:-$WHIPTAIL_COLORS}" \
                whiptail --title "$title" --ok-button "Aceptar" --cancel-button "Cancelar" \
                --separate-output ${CHECKLIST_NOTAGS:+--notags} \
                --checklist "$text\n\nEspacio: marcar/desmarcar · Flechas: moverse · Enter: aceptar" \
                "$h" "$w" "$lh" "${args[@]}" 3>&1 1>&2 2>&3) || return 1
        fi
        [ -n "$out" ] && mapfile -t CHOSEN <<< "$out"
        return 0
    fi

    echo -e "${CYAN}$text${NC}\n"
    for entry in "${entries[@]}"; do
        i=$((i + 1))
        status=" "
        [[ "$entry" == *"|ON" ]] && { status="x"; entry=${entry%|ON}; }
        [[ "${entry#*|}" == SYS::* ]] && entry="${entry%%|*}|⚠ SISTEMA: ${entry#*|SYS::}"
        if [ -n "$CHECKLIST_NOTAGS" ]; then
            printf "  ${CYAN}[%2s]${NC} [%s] %s\n" "$i" "$status" "${entry#*|}"
        else
            printf "  ${CYAN}[%2s]${NC} [%s] %-22s - %s\n" "$i" "$status" "${entry%%|*}" "${entry#*|}"
        fi
    done
    echo -e "\n${CYAN}([x] = marcado ahora; escribe todos los que quieras dejar marcados; 0 o Enter = volver)${NC}"
    read -r -p "🔢 Números separados por espacio: " input
    # Sin respuesta (o 0) no se cambia nada (no significa "desmarcar todo")
    [ -n "${input// /}" ] && [ "${input// /}" != 0 ] || return 1
    for num in $input; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#entries[@]} ]; then
            CHOSEN+=("${entries[$((num - 1))]%%|*}")
        fi
    done
}

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

has_desktop() { [ "$FLAVOR" != server ]; }

# Aviso para las opciones que dependen de un escritorio concreto
desktop_only() {
    local needed="$1" what="$2"
    [[ " $needed " == *" $DESKTOP "* ]] && return 0
    log_warning "$what no está disponible en $FLAVOR_NAME ($DESKTOP_NAME)"
    return 1
}

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
print_pkgs_described() {
    local p d
    for p in "$@"; do
        d=$(pkg_summary "$p")
        if [ -n "$d" ]; then
            [ ${#d} -gt 70 ] && d="${d:0:69}…"
            echo -e "  ${YELLOW}•${NC} $p ${CYAN}— $d${NC}"
        else
            echo -e "  ${YELLOW}•${NC} $p"
        fi
    done
}

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

# ============================================================
# OPCIÓN 4: ELIMINAR APLICACIONES (COLOR: CIAN)
# ============================================================

# Apps con ícono en el menú que no están en la lista conocida: se detectan solas en cualquier
# distro (cada .desktop de /usr/share/applications se busca en el gestor de paquetes)
desktop_file_owners() {
    local files=() f owned
    shopt -s nullglob
    files=(/usr/share/applications/*.desktop /usr/local/share/applications/*.desktop)
    shopt -u nullglob
    [ ${#files[@]} -gt 0 ] || return 0
    if command -v dpkg-query &> /dev/null; then
        # "paquete: ruta" (o "paquete:amd64: ruta")
        owned=$(dpkg-query -S "${files[@]}" 2>/dev/null \
            | awk -F': ' '{split($1, p, ", "); sub(/:.*/, "", p[1]); print p[1], $2}')
    elif command -v pacman &> /dev/null; then
        # "ruta is owned by paquete versión"
        owned=$(LC_ALL=C pacman -Qo "${files[@]}" 2>/dev/null | awk '{print $(NF-1), $1}')
    fi
    [ -n "$owned" ] && echo "$owned"
    # Los que no son de ningún paquete (instalados a mano): "- ruta"
    for f in "${files[@]}"; do
        grep -qF " $f" <<< "$owned" || echo "- $f"
    done
}

# Nunca se ofrecen: piezas del escritorio, la terminal (la que estás usando) ni paneles de configuración
DETECT_SKIP_PKGS=(konsole gnome-terminal gnome-console kgx xfce4-terminal qterminal mate-terminal lxterminal
    terminator tilix xterm kitty sudo policykit-1 polkitd)

detected_app_entries() {
    local -A seen=() important=()
    local k pkg path name desc stem known=" $* "
    for k in "$@" "${CORE_PKGS[@]}" "${DETECT_SKIP_PKGS[@]}"; do
        seen[$k]=1
    done
    # Paquetes que la distribución marca como imprescindibles (Debian/Ubuntu: prioridad required o important)
    if command -v dpkg-query &> /dev/null; then
        while read -r k; do important[$k]=1; done < <(dpkg-query -W -f='${Package} ${Priority}\n' 2>/dev/null \
            | awk '$2 == "required" || $2 == "important" {print $1}')
    fi
    while read -r pkg path; do
        [ -n "$pkg" ] && [ -f "$path" ] || continue
        if [ "$pkg" = - ]; then
            name=$(awk '/^\[/ {main = ($0 == "[Desktop Entry]")} main && /^Name=/ {sub(/^[^=]*=/, ""); print; exit}' "$path")
            grep -qiE '^(NoDisplay|Hidden)=true' "$path" || echo "-|${name:-$(basename "$path" .desktop)}"
            continue
        fi
        [ -n "${seen[$pkg]:-}" ] || [ -n "${important[$pkg]:-}" ] && continue
        # libreoffice-common, foo-data...: es la misma app que una de la lista conocida
        stem=${pkg%-common}
        stem=${stem%-data}
        [ "$stem" != "$pkg" ] && [[ "$known" == *" $stem-"* ]] && continue
        grep -qiE '^(NoDisplay|Hidden)=true' "$path" && continue
        grep -q '^Type=Application' "$path" || continue
        # Nombre en castellano si lo tiene, solo de la sección principal (no de sus acciones)
        name=$(awk '/^\[/ {main = ($0 == "[Desktop Entry]")} main && /^Name\[es\]=/ {sub(/^[^=]*=/, ""); print; exit}' "$path")
        [ -n "$name" ] || name=$(awk '/^\[/ {main = ($0 == "[Desktop Entry]")} main && /^Name=/ {sub(/^[^=]*=/, ""); print; exit}' "$path")
        # Qué es: nombre genérico ("Navegador web") o, si no tiene, el comentario del .desktop
        desc=""
        for k in 'GenericName[es]' GenericName 'Comment[es]' Comment; do
            desc=$(awk -v key="$k=" '/^\[/ {main = ($0 == "[Desktop Entry]")} main && index($0, key) == 1 {print substr($0, length(key) + 1); exit}' "$path")
            [ -n "$desc" ] && [ "$desc" != "$name" ] && break
            desc=""
        done
        [ ${#desc} -gt 55 ] && desc="${desc:0:54}…"
        seen[$pkg]=1
        echo "$pkg|🔎 ${name:-$pkg}${desc:+ — $desc} (detectada)"
    done < <(desktop_file_owners)
}

# Apps de Flatpak instaladas: "flatpak:ID|📦 Nombre (Flatpak)"
flatpak_app_entries() {
    command -v flatpak &> /dev/null || return 0
    local id name
    flatpak list --app --columns=application,name 2>/dev/null | while IFS=$'\t' read -r id name; do
        [ -n "$id" ] && echo "flatpak:$id|📦 ${name:-$id} (Flatpak)"
    done
}

# Quita apps de Flatpak, del sistema o del usuario según dónde estén instaladas
remove_flatpak_apps() {
    local id where
    for id in "$@"; do
        where=$(flatpak list --app --columns=application,installation 2>/dev/null | awk -v a="$id" '$1 == a {print $2; exit}')
        if [ "$where" = user ]; then
            run "No se pudo quitar $id" flatpak uninstall -y --noninteractive --user "$id"
        else
            run "No se pudo quitar $id" sudo flatpak uninstall -y --noninteractive --system "$id"
        fi && echo -e "  ${GREEN}✓ Eliminado: $id (Flatpak)${NC}"
    done
    # Runtimes que ya no usa ninguna app
    sudo flatpak uninstall -y --noninteractive --unused >> "$LOG_FILE" 2>&1
}

# Paquetes de herramientas del sistema o de la propia distro (categorías System, Settings, Security,
# HardwareSettings o PackageManager en su .desktop, o nombre que empieza con el de la distro):
# en "Eliminar aplicaciones" llevan la marca ⚠ SISTEMA
system_app_pkgs() {
    local id pkg path cats
    id=$(os_release_value ID)
    while read -r pkg path; do
        [ "$pkg" != - ] && [ -f "$path" ] || continue
        cats=$(awk '/^\[/ {main = ($0 == "[Desktop Entry]")} main && /^Categories=/ {sub(/^[^=]*=/, ""); print; exit}' "$path")
        if [[ ";$cats;" =~ \;(System|Settings|Security|HardwareSettings|PackageManager)\; ]] \
            || { [ -n "$id" ] && [[ "$pkg" == "$id"-* ]]; }; then
            echo "$pkg"
        fi
    done < <(desktop_file_owners) | sort -u
}

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

# ============================================================
# OPCIÓN 13: OPTIMIZACIÓN DE GPU (COLOR: MAGENTA)
# ============================================================

optimize_gpu_menu() {
    while true; do
        clear
        echo -e "${PURPLE}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    🎮 OPTIMIZACIÓN DE GPU                        ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "\n${PURPLE}🎮 Selecciona tu tarjeta gráfica:${NC}\n"
        echo -e "  ${PURPLE}1)${NC} NVIDIA - Optimización completa"
        echo -e "  ${PURPLE}2)${NC} AMD   - Optimización completa"
        echo -e "  ${PURPLE}3)${NC} Intel - Optimización completa"
        echo -e "  ${PURPLE}4)${NC} Detectar automáticamente y optimizar"
        echo -e "\n  ${PURPLE}0)${NC} 🔙 Volver"
        echo ""
        read -r -p "📌 Opción (0-4): " gpu_option

        case $gpu_option in
            1) optimize_nvidia ;;
            2) optimize_amd ;;
            3) optimize_intel ;;
            4) auto_detect_gpu ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
        return 0
    done
}

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

secure_boot_enabled() {
    if command -v mokutil &> /dev/null; then
        mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"
        return
    fi
    # Sin mokutil (Arch, Manjaro...): se lee la variable del firmware (el último byte es 1 si está activo)
    local var
    var=$(ls /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d0-aa0d-00e098032b8c 2>/dev/null) || return 1
    [ "$(od -An -t u1 "$var" 2>/dev/null | awk '{print $NF}')" = 1 ]
}

# Cambia GRUB_DEFAULT en /etc/default/grub
GRUB_DEFAULT_BACKUP="/etc/default/grub.arch-ultimate-tools.orig"

# Antes del primer cambio guarda /etc/default/grub para poder volver al original
backup_grub_config() {
    [ -f "$GRUB_DEFAULT_BACKUP" ] || sudo cp -p /etc/default/grub "$GRUB_DEFAULT_BACKUP"
}

set_grub_default() {
    local value="$1"
    backup_grub_config
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sudo sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"$value\"|" /etc/default/grub
    else
        echo "GRUB_DEFAULT=\"$value\"" | sudo tee -a /etc/default/grub > /dev/null
    fi
}

# Elige el kernel que GRUB arranca por defecto: "0" (el más reciente) o una versión.
# Con GRUB_DEFAULT=saved basta 'grub-set-default': no hace falta regenerar grub.cfg
# (update-grub tarda bastante, sobre todo con os-prober). La instalación y
# eliminación de kernels ya regenera grub.cfg por su cuenta.
# Identificador (o, si no lo tiene, el título) de una línea menuentry/submenu de grub.cfg
grub_line_id() {
    local id
    id=$(grep -oP "\\\$menuentry_id_option '\K[^']+" <<< "$1")
    [ -z "$id" ] && id=$(grep -oP "^\s*(menuentry|submenu) ['\"]\K[^'\"]+" <<< "$1")
    echo "$id"
}

# Ruta para grub-set-default de la entrada del kernel indicado: "submenú>entrada" o
# solo "entrada" si no está en un submenú (GRUB_DISABLE_SUBMENU, grub-customizer...)
grub_entry_path() {
    local target="$1" cfg="$2" found=() sub_id entry_id
    mapfile -t found < <(sudo awk -v t="$target" '
        /^submenu / { s = $0; next }
        /^}/ { s = ""; next }
        /menuentry / && index($0, t) && tolower($0) !~ /recovery|recuperaci/ { print s; print $0; exit }
    ' "$cfg")
    [ ${#found[@]} -eq 2 ] || return 1
    entry_id=$(grub_line_id "${found[1]}")
    [ -n "$entry_id" ] || return 1
    if [ -n "${found[0]}" ]; then
        sub_id=$(grub_line_id "${found[0]}")
        [ -n "$sub_id" ] || return 1
        echo "${sub_id}>${entry_id}"
    else
        echo "$entry_id"
    fi
}

# Pasa GRUB a GRUB_DEFAULT=saved (una sola vez). Devuelve 2 si tuvo que regenerar grub.cfg.
ensure_grub_saved() {
    grep -Eq '^GRUB_DEFAULT="?saved"?$' /etc/default/grub && return 0
    set_grub_default saved
    run "No se pudo regenerar el menú" grub_update || return 1
    return 2
}

# ------------------------------------------------------------
# Instalación de kernels
# ------------------------------------------------------------

os_release_value() {
    # shellcheck disable=SC1091
    (. /etc/os-release && eval "echo \"\$$1\"")
}

enable_trim() {
    run "No se pudo habilitar fstrim.timer" sudo systemctl enable --now fstrim.timer \
        && log_success "TRIM automático semanal habilitado"
}

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

# ============================================================
# OPCIÓN 15: OPTIMIZACIÓN DE MEMORIA RAM (COLOR: AMARILLO)
# ============================================================

# ------------------------------------------------------------
# Swap y swappiness. El archivo swap está basado en create-swap, del mismo autor
# (https://github.com/george0884/create-swap, GPL-3.0), con más seguridad: solo toca
# /swapfile (nunca otras particiones swap ni la ZRAM), funciona en btrfs y comprueba el espacio.
# ------------------------------------------------------------
SWAPFILE="/swapfile"
FSTAB_BACKUP="/etc/fstab.antes-de-ultimate-tools"

zram_swap_active() { swapon --noheadings --show=NAME 2>/dev/null | grep -q '^/dev/zram'; }
disk_swap_active() { swapon --noheadings --show=NAME 2>/dev/null | grep -qv '^/dev/zram'; }
swapfile_active() { swapon --noheadings --show=NAME 2>/dev/null | grep -qx "$SWAPFILE"; }

# "8G (archivo /swapfile) + 15,6G (ZRAM)" o "ninguno"
swap_summary() {
    local out
    out=$(swapon --noheadings --show=NAME,TYPE,SIZE 2>/dev/null | awk '{
        kind = ($1 ~ /^\/dev\/zram/) ? "ZRAM" : ($2 == "file" ? "archivo " $1 : "partición " $1)
        printf "%s%s (%s)", sep, $3, kind; sep = " + " }')
    echo "${out:-ninguno}"
}

# swappiness solo tiene efecto si hay swap: con ZRAM conviene usarla antes que el disco (100);
# con swap en disco, solo cuando hace falta (10); sin swap no se toca
ram_swappiness_auto() {
    if zram_swap_active; then
        set_sysctl vm.swappiness 100
        echo -e "  ${GREEN}✓ swappiness=100: con ZRAM conviene usar la memoria comprimida antes que el disco${NC}"
    elif disk_swap_active; then
        set_sysctl vm.swappiness 10
        echo -e "  ${GREEN}✓ swappiness=10: el swap en disco se usa solo cuando la RAM se llena${NC}"
    else
        echo -e "  ${CYAN}ℹ No hay swap: swappiness no se cambia (sin swap no tiene efecto).${NC}"
        echo -e "  ${CYAN}  Puedes crear un archivo swap o activar ZRAM en Optimizar RAM (opción 15).${NC}"
    fi
}

apply_ram_tweaks() {
    echo -e "${YELLOW}🔧 Ajustando el uso de la memoria...${NC}"
    set_sysctl vm.vfs_cache_pressure 50
    echo -e "  ${GREEN}✓ Caché de archivos optimizada (vfs_cache_pressure=50)${NC}"
    ram_swappiness_auto
}

# Tamaño sugerido en GB: el doble de la RAM si es poca, igual a la RAM hasta 8 GB, luego 4-8 GB
suggest_swap_gb() {
    local ram
    ram=$(awk '/MemTotal/ {print int(($2 + 1048575) / 1048576)}' /proc/meminfo)
    if [ "$ram" -le 2 ]; then echo $((ram * 2))
    elif [ "$ram" -le 8 ]; then echo "$ram"
    elif [ "$ram" -le 32 ]; then echo 4
    else echo 8
    fi
}

create_swapfile() {
    local fs gb suggested free_gb current_gb=0
    echo -e "${YELLOW}💽 ARCHIVO SWAP${NC}\n"
    echo -e "   El swap es espacio del disco que se usa como RAM extra cuando la memoria se llena."
    echo -e "   Sin swap, si se llena la RAM el sistema cierra programas de golpe. Para hibernar hace falta"
    echo -e "   al menos tanto swap como RAM.\n"
    fs=$(findmnt -no FSTYPE / 2>/dev/null)
    case $fs in
        zfs) log_error "ZFS no admite archivo swap: usa ZRAM (opción 4 de este menú)"; return 1 ;;
    esac
    if [ -f "$SWAPFILE" ]; then
        current_gb=$(( $(stat -c %s "$SWAPFILE") / 1073741824 ))
        echo -e "   Ya hay un archivo swap de ${BOLD}${current_gb} GB${NC} en $SWAPFILE: se puede cambiar su tamaño.\n"
    fi
    suggested=$(suggest_swap_gb)
    read -r -p "📏 Tamaño en GB [Enter = $suggested, 0 = volver]: " gb
    gb=${gb:-$suggested}
    [ "$gb" = 0 ] && return 0
    if ! [[ "$gb" =~ ^[0-9]+$ ]] || [ "$gb" -lt 1 ] || [ "$gb" -gt 512 ]; then
        log_error "Tamaño no válido: escribe un número de GB entre 1 y 512"
        return 1
    fi
    free_gb=$(( $(df -P --block-size=1G / | awk 'NR == 2 {print $4}') + current_gb ))
    if [ "$free_gb" -lt $((gb + 2)) ]; then
        log_error "No hay espacio: hacen falta $((gb + 2)) GB libres en / (hay $free_gb GB)"
        return 1
    fi
    confirm "${YELLOW}¿Crear un archivo swap de $gb GB en $SWAPFILE?${NC}" || return 0

    # Solo se apaga y se borra este archivo, nunca otras particiones swap ni la ZRAM
    if [ -f "$SWAPFILE" ]; then
        swapfile_active && { run "No se pudo desactivar el swap actual (¿poca RAM libre?)" sudo swapoff "$SWAPFILE" || return 1; }
        sudo rm -f -- "$SWAPFILE"
    fi
    echo -e "${BLUE}⏳ Creando $SWAPFILE ($gb GB)...${NC}"
    if [ "$fs" = btrfs ]; then
        # En btrfs el archivo no puede tener copia en escritura (sin esto no funciona como swap)
        if sudo btrfs filesystem mkswapfile --help &> /dev/null; then
            run "No se pudo crear el archivo swap" sudo btrfs filesystem mkswapfile --size "${gb}g" "$SWAPFILE" || return 1
        else
            sudo truncate -s 0 "$SWAPFILE" && sudo chattr +C "$SWAPFILE" \
                && run "No se pudo crear el archivo swap" sudo fallocate -l "${gb}G" "$SWAPFILE" || return 1
        fi
    elif ! sudo fallocate -l "${gb}G" "$SWAPFILE" 2>> "$LOG_FILE"; then
        # Algunos sistemas de archivos no admiten fallocate: se escribe con dd
        run_visible "No se pudo crear el archivo swap" sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((gb * 1024)) status=progress || return 1
    fi
    sudo chmod 600 "$SWAPFILE"
    run "No se pudo preparar el swap" sudo mkswap "$SWAPFILE" || return 1
    run "No se pudo activar el swap" sudo swapon "$SWAPFILE" || return 1
    # fstab: copia una sola vez y solo se agrega la línea de /swapfile si no está
    [ -f "$FSTAB_BACKUP" ] || sudo cp -p /etc/fstab "$FSTAB_BACKUP"
    if ! grep -qE "^[[:space:]]*$SWAPFILE[[:space:]]" /etc/fstab; then
        echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
    fi
    mkdir -p "$STATE_DIR"
    echo "$(date '+%Y-%m-%d %H:%M')|${gb}G" > "$STATE_DIR/swapfile.txt"
    log_success "Archivo swap de $gb GB activo (se mantiene al reiniciar)"
    ram_swappiness_auto
}

remove_swapfile() {
    if [ ! -f "$SWAPFILE" ]; then
        echo -e "${YELLOW}ℹ No hay archivo swap en $SWAPFILE${NC}"
        return 0
    fi
    if [ ! -f "$STATE_DIR/swapfile.txt" ]; then
        echo -e "${YELLOW}⚠ $SWAPFILE no lo creó este script (puede ser el de tu distribución)${NC}"
    fi
    local used avail
    used=$(swapon --noheadings --bytes --show=NAME,USED 2>/dev/null | awk -v f="$SWAPFILE" '$1 == f {print $2}')
    avail=$(awk '/MemAvailable/ {print $2 * 1024}' /proc/meminfo)
    if [ -n "$used" ] && [ "$used" -gt "$avail" ]; then
        log_error "El swap tiene más datos ($(numfmt --to=iec "$used")) que la RAM libre: cierra programas antes"
        return 1
    fi
    confirm "${RED}¿Quitar el archivo swap $SWAPFILE?${NC}" || return 0
    swapfile_active && { run "No se pudo desactivar el swap" sudo swapoff "$SWAPFILE" || return 1; }
    [ -f "$FSTAB_BACKUP" ] || sudo cp -p /etc/fstab "$FSTAB_BACKUP"
    # Solo la línea de /swapfile: las particiones swap quedan como estaban
    sudo sed -i "\\#^[[:space:]]*$SWAPFILE[[:space:]]#d" /etc/fstab
    sudo rm -f -- "$SWAPFILE"
    rm -f "$STATE_DIR/swapfile.txt"
    log_success "Archivo swap quitado"
    ram_swappiness_auto
}

swappiness_manual() {
    local value
    echo -e "${YELLOW}🎚 swappiness: cuánto prefiere el sistema usar el swap${NC}"
    echo -e "   Ahora: ${BOLD}$(cat /proc/sys/vm/swappiness)${NC} · Swap: $(swap_summary)"
    echo -e "   10 = solo cuando la RAM se llena · 60 = lo normal · 100 o más = con ZRAM\n"
    read -r -p "🔢 Nuevo valor (0 a 200; Enter = volver): " value
    [ -n "$value" ] || return 0
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -gt 200 ]; then
        log_error "Valor no válido"
        return 1
    fi
    set_sysctl vm.swappiness "$value" && log_success "swappiness=$value (se mantiene al reiniciar)"
}

ram_status() {
    echo -e "${YELLOW}📊 Memoria${NC}"
    free -h | sed 's/^/   /'
    echo -e "\n${YELLOW}💽 Swap${NC}"
    swapon --show 2>/dev/null | sed 's/^/   /' | grep . || echo "   (ninguno)"
    echo -e "\n   swappiness=$(cat /proc/sys/vm/swappiness) · vfs_cache_pressure=$(cat /proc/sys/vm/vfs_cache_pressure)"
}

optimize_ram_menu() {
    local option ram
    while true; do
        clear
        echo -e "${YELLOW}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    💾 MEMORIA RAM Y SWAP                         ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        ram=$(free -m | awk '/^Mem:/ {printf "%.1f", $2 / 1024}')
        echo -e "${YELLOW}📊 RAM: ${ram} GB · Swap: $(swap_summary) · swappiness=$(cat /proc/sys/vm/swappiness)${NC}\n"
        echo -e "  ${YELLOW}1)${NC} Optimizar automáticamente (caché, y swappiness según el swap que tengas)"
        echo -e "  ${YELLOW}2)${NC} Crear archivo swap o cambiar su tamaño ($SWAPFILE)"
        echo -e "  ${YELLOW}3)${NC} Quitar el archivo swap"
        echo -e "  ${YELLOW}4)${NC} Activar ZRAM (swap comprimida en la RAM: rápida, ideal con poca memoria)"
        echo -e "  ${YELLOW}5)${NC} Desactivar ZRAM"
        echo -e "  ${YELLOW}6)${NC} Ajustar swappiness a mano"
        echo -e "  ${YELLOW}7)${NC} Ver el estado de la RAM y el swap"
        echo -e "\n  ${YELLOW}0)${NC} 🔙 Volver\n"
        read -r -p "📌 Opción (0-7): " option
        case $option in
            1) apply_ram_tweaks ;;
            2) create_swapfile ;;
            3) remove_swapfile ;;
            4) enable_zram ;;
            5) disable_zram && ram_swappiness_auto ;;
            6) swappiness_manual ;;
            7) ram_status ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
    done
}

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

# ============================================================
# OPCIÓN 8: INSTALAR ALACRITTY Y TEMAS (COLOR: CIAN)
# ============================================================

# ------------------------------------------------------------
# Tema Tokyo Night (incluido en el script: no depende de descargas)
# Colores del tema Tokyo Night de enkia (https://github.com/enkia/tokyo-night-vscode-theme), licencia MIT
# ------------------------------------------------------------

# Un grupo de colores de KDE: $1 nombre, $2 fondo, $3 fondo alterno, $4 texto
tokyo_color_group() {
    cat << EOF
[Colors:$1]
BackgroundAlternate=$3
BackgroundNormal=$2
DecorationFocus=122,162,247
DecorationHover=125,207,255
ForegroundActive=255,158,100
ForegroundInactive=86,95,137
ForegroundLink=122,162,247
ForegroundNegative=247,118,142
ForegroundNeutral=224,175,104
ForegroundNormal=$4
ForegroundPositive=158,206,106
ForegroundVisited=187,154,247

EOF
}

write_tokyo_night_colors() {
    local file="$HOME/.local/share/color-schemes/TokyoNight.colors"
    mkdir -p "$(dirname "$file")"
    {
        tokyo_color_group View "26,27,38" "31,35,53" "192,202,245"
        tokyo_color_group Window "22,22,30" "26,27,38" "192,202,245"
        tokyo_color_group Button "41,46,66" "31,35,53" "192,202,245"
        tokyo_color_group Selection "61,89,161" "41,46,66" "192,202,245"
        tokyo_color_group Tooltip "22,22,30" "26,27,38" "192,202,245"
        tokyo_color_group Complementary "22,22,30" "26,27,38" "192,202,245"
        tokyo_color_group Header "22,22,30" "26,27,38" "192,202,245"
        cat << 'EOF'
[General]
ColorScheme=TokyoNight
Name=Tokyo Night
shadeSortColumn=true

[KDE]
contrast=4

[WM]
activeBackground=22,22,30
activeBlend=192,202,245
activeForeground=192,202,245
inactiveBackground=22,22,30
inactiveBlend=86,95,137
inactiveForeground=86,95,137
EOF
    } > "$file"
}

write_tokyo_night_konsole() {
    local dir="$HOME/.local/share/konsole"
    mkdir -p "$dir"
    # Colores 0-7 normales y su versión intensa (negro, rojo, verde, amarillo, azul, magenta, cian, blanco)
    local normal=("21,22,30" "247,118,142" "158,206,106" "224,175,104" "122,162,247" "187,154,247" "125,207,255" "169,177,214")
    local bright=("65,72,104" "247,118,142" "158,206,106" "224,175,104" "122,162,247" "187,154,247" "125,207,255" "192,202,245")
    local i
    {
        printf '[Background]\nColor=26,27,38\n\n[BackgroundIntense]\nColor=26,27,38\n\n'
        printf '[Foreground]\nColor=192,202,245\n\n[ForegroundIntense]\nColor=192,202,245\n\n'
        for i in 0 1 2 3 4 5 6 7; do
            printf '[Color%s]\nColor=%s\n\n[Color%sIntense]\nColor=%s\n\n' "$i" "${normal[$i]}" "$i" "${bright[$i]}"
        done
        printf '[General]\nDescription=Tokyo Night\nOpacity=1\n'
    } > "$dir/TokyoNight.colorscheme"

    printf '[Appearance]\nColorScheme=TokyoNight\n\n[General]\nName=Tokyo Night\nParent=FALLBACK/\n' \
        > "$dir/TokyoNight.profile"
}

THEME_BACKUP="$STATE_DIR/tema-anterior.txt"

# Anota un ajuste del tema tal como estaba antes del primer cambio (para "Revertir")
save_theme_value() {
    local key="$1" value="$2"
    mkdir -p "$STATE_DIR"
    grep -qs "^$key=" "$THEME_BACKUP" || echo "$key=$value" >> "$THEME_BACKUP"
}

theme_value() { sed -n "s/^$1=//p" "$THEME_BACKUP" 2>/dev/null | head -n1; }

kde_color_scheme() { sed -n '/^\[General\]/,/^\[/ s/^ColorScheme=//p' "$HOME/.config/kdeglobals" 2>/dev/null | head -n1; }

install_tokyo_night_theme() {
    echo -e "${CYAN}🎨 Aplicando tema Tokyo Night...${NC}"
    local before
    before=$(kde_color_scheme)
    [ "$before" != TokyoNight ] && save_theme_value kde-colores "${before:-BreezeLight}"
    save_theme_value konsole-perfil "$(sed -n 's/^DefaultProfile=//p' "$HOME/.config/konsolerc" 2>/dev/null)"
    write_tokyo_night_colors
    write_tokyo_night_konsole

    if command -v plasma-apply-colorscheme &> /dev/null; then
        run "No se pudo aplicar el esquema de colores (¿estás en una sesión de Plasma?)" \
            plasma-apply-colorscheme TokyoNight \
            && log_success "Colores Tokyo Night aplicados a Plasma"
    else
        log_warning "Aplica los colores a mano: Preferencias del sistema → Colores → Tokyo Night"
    fi

    # Konsole: perfil Tokyo Night como predeterminado (si ya usas otro, se pregunta)
    local kwrite current
    kwrite=$(command -v kwriteconfig6 || command -v kwriteconfig5)
    current=$(sed -n 's/^DefaultProfile=//p' "$HOME/.config/konsolerc" 2>/dev/null)
    if [ -n "$kwrite" ] && { [ -z "$current" ] || [ "$current" = "TokyoNight.profile" ] \
        || confirm "${CYAN}Konsole usa el perfil '$current'. ¿Cambiarlo por Tokyo Night?${NC}"; }; then
        "$kwrite" --file konsolerc --group "Desktop Entry" --key DefaultProfile TokyoNight.profile \
            && log_success "Konsole usará Tokyo Night en las ventanas nuevas"
    else
        echo -e "${CYAN}ℹ En Konsole: Configuración → Gestionar perfiles → Tokyo Night${NC}"
    fi
    echo -e "${CYAN}ℹ Para volver a los colores originales: opción 11 (Revertir) o Preferencias del sistema → Colores${NC}"
}

# Modo oscuro de GNOME: estilo oscuro y, con el tema Yaru de Ubuntu, su variante oscura
gnome_dark_mode() {
    local theme
    save_theme_value gnome-estilo "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
    save_theme_value gnome-tema "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)"
    run "No se pudo activar el modo oscuro" gsettings set org.gnome.desktop.interface color-scheme prefer-dark || return 1
    theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    if [[ "$theme" == Yaru* && "$theme" != *-dark ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme "${theme}-dark"
    fi
    log_success "Modo oscuro de GNOME activado"
}

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

android_tools_installed() { [ -x "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" ]; }
android_studio_installed() {
    [ -x "$ANDROID_STUDIO_DIR/bin/studio" ] || [ -x "$ANDROID_STUDIO_DIR/bin/studio.sh" ] \
        || [ -n "$(pkg_installed android-studio)" ]
}

# Avisa si no hay espacio suficiente (en GB) en la carpeta dada
enough_space() {
    local dir="$1" need="$2" free
    free=$(df -BG --output=avail "$dir" 2>/dev/null | tail -1 | tr -dc '0-9')
    [ -z "$free" ] || [ "$free" -ge "$need" ] && return 0
    log_error "Hace falta unos $need GB libres en $dir y hay $free GB"
    return 1
}

# Comprueba el SHA de un archivo (sha1 o sha256 según el largo)
check_sum() {
    local file="$1" sum="$2" got
    case ${#sum} in
        40) got=$(sha1sum < "$file" | cut -d' ' -f1) ;;
        64) got=$(sha256sum < "$file" | cut -d' ' -f1) ;;
        *) return 1 ;;
    esac
    [ "$got" = "$sum" ]
}

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

# Paquetes de Google para la última versión estable de Android
android_sdk_packages() {
    local list platform build
    list=$("$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK" --list 2>/dev/null)
    platform=$(grep -oE '^ *platforms;android-[0-9]+ ' <<< "$list" | tr -d ' ' | sort -t- -k2 -n | tail -n1)
    build=$(grep -oE '^ *build-tools;[0-9.]+ ' <<< "$list" | tr -d ' ' | sort -V | tail -n1)
    echo platform-tools $platform $build
}

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

# El emulador de Android necesita la virtualización del procesador (KVM)
check_kvm() {
    echo -e "${BLUE}🖥️ Emulador de Android: comprobando la virtualización (KVM)...${NC}"
    if ! grep -Eqw 'vmx|svm' /proc/cpuinfo; then
        log_warning "Tu procesador no tiene virtualización: el emulador no funcionará. Prueba en tu celular por USB."
        return 0
    fi
    if [ ! -e /dev/kvm ]; then
        log_warning "La virtualización está APAGADA en la BIOS: el emulador será muy lento o no abrirá"
        echo -e "${YELLOW}  Actívala al encender (Supr, F2 o F10): busca 'Intel VT-x', 'Virtualization Technology'${NC}"
        echo -e "${YELLOW}  o en AMD 'SVM Mode', ponla en Enabled, guarda y reinicia.${NC}"
        return 0
    fi
    if getent group kvm > /dev/null && ! id -nG | grep -qw kvm; then
        run "No se pudo dar permiso para KVM" sudo usermod -aG kvm "$USER" \
            && log_success "Permiso para el emulador listo (cierra sesión y vuelve a entrar)"
    else
        log_success "La virtualización está activa: el emulador irá rápido"
    fi
}

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

# Última versión de un SDK de Flathub (las versiones con letras o "-" se ignoran)
flatpak_latest_branch() {
    flatpak remote-ls --system flathub --runtime --columns=application,branch 2>/dev/null \
        | awk -v app="$1" '$1 == app {print $2}' | grep -E '^[0-9]+(\.[0-9]+)?$' | sort -V | tail -n1
}

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

remove_flatpak_sdks() {
    local refs=()
    [ -f "$FLATPAK_SDK_LIST" ] && mapfile -t refs < "$FLATPAK_SDK_LIST"
    if [ ${#refs[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ No hay SDK de Flatpak instalados por el script${NC}"
        return 0
    fi
    printf "  ${RED}•${NC} %s\n" "${refs[@]}"
    confirm "${RED}¿Quitar estos SDK de Flatpak?${NC}" || return 0
    run "No se pudieron quitar los SDK" sudo flatpak uninstall -y --noninteractive --system "${refs[@]}"
    sudo flatpak uninstall -y --noninteractive --system --unused >> "$LOG_FILE" 2>&1
    rm -f "$FLATPAK_SDK_LIST"
    log_success "SDK de Flatpak quitados (Flatpak y flatpak-builder se quitan en 'Ver y quitar PROGRAMAS')"
}

# ------------------------------------------------------------
# Respaldos: antes de borrar algo que no se puede recuperar
# ------------------------------------------------------------

BACKUP_DIR="$HOME/respaldos-arch-ultimate-tools"

# Guarda carpetas en un .tar.gz con fecha (también las de root). Uso: make_backup nombre ruta...
make_backup() {
    local name="$1" file paths=() p
    shift
    for p in "$@"; do sudo test -e "$p" && paths+=("${p#/}"); done
    [ ${#paths[@]} -gt 0 ] || return 0
    mkdir -p "$BACKUP_DIR"
    file="$BACKUP_DIR/$name-$(date +%Y%m%d-%H%M%S)"
    # Nunca se pisa un respaldo anterior
    [ -e "$file.tar.gz" ] && file="$file-$$-$RANDOM"
    file="$file.tar.gz"
    echo -e "${BLUE}💾 Guardando respaldo de: $*${NC}"
    if sudo tar -czf "$file" -C / "${paths[@]}" 2>> "$LOG_FILE"; then
        sudo chown "$(id -u):$(id -g)" "$file"
        log_success "Respaldo guardado: $file ($(du -h "$file" | cut -f1))"
        LAST_BACKUP="$file"
        return 0
    fi
    sudo rm -f "$file"
    log_error "No se pudo guardar el respaldo de $name"
    return 1
}

# ------------------------------------------------------------
# Docker: compilar con el Dockerfile de un proyecto (SDK, NDK... ya listos adentro)
# ------------------------------------------------------------

DOCKER_PKGS=(docker docker-compose docker-buildx)

docker_installed() { command -v docker &> /dev/null; }

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

# Tamaño ocupado por Docker (imágenes, contenedores, volúmenes)
docker_usage() {
    sudo docker system df 2>/dev/null | sed 's/^/   /'
    sudo du -sh /var/lib/docker 2>/dev/null | awk '{print "   Total en disco: " $1}'
}

# Quitar Docker. Normal: los programas (imágenes y volúmenes se conservan).
# Nuclear: además todos los datos, la configuración y el grupo, con respaldo antes.
remove_docker() {
    if ! docker_installed && ! sudo test -d /var/lib/docker; then
        echo -e "${YELLOW}ℹ Docker no está instalado${NC}"
        return 0
    fi
    echo -e "${RED}🐳 Quitar Docker${NC}\n"
    docker_usage
    echo ""
    echo -e "  ${RED}1)${NC} 📦 Quitar los programas y CONSERVAR imágenes, contenedores y volúmenes"
    echo -e "        (si lo reinstalas, todo vuelve a estar)"
    echo -e "  ${RED}2)${NC} 💥 ELIMINACIÓN NUCLEAR: programas + TODOS los datos + configuración + grupo"
    echo -e "        (antes se guarda un respaldo de la configuración y, si quieres, de tus volúmenes)"
    echo -e "  ${RED}0)${NC} 🔙 Volver sin cambiar nada"
    local choice
    read -r -p "📌 Opción (0-2): " choice
    case $choice in
        1) docker_remove_programs ;;
        2) docker_nuclear ;;
        *) echo -e "${YELLOW}ℹ No se cambió nada${NC}" ;;
    esac
}

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
seamonkey_installed() { [ -x "$SEAMONKEY_DIR/seamonkey" ]; }

install_seamonkey() {
    echo -e "${BLUE}🐒 SeaMonkey (navegador, correo, editor HTML y chat, de la comunidad de Mozilla)${NC}"
    if seamonkey_installed; then
        echo -e "  ${GREEN}✓ Ya está instalado en $SEAMONKEY_DIR${NC}"
        return 0
    fi
    [ "$(uname -m)" = x86_64 ] || { log_error "SeaMonkey publica versiones solo para PC de 64 bits (x86_64)"; return 1; }
    echo -e "${CYAN}ℹ No está en los repositorios de ninguna distribución: se baja la versión oficial de${NC}"
    echo -e "${CYAN}  seamonkey-project.org a $SEAMONKEY_DIR (se quita en 10 → 1)${NC}"
    local page url root rel tmp sums expected got algo
    page=$(curl -fsSL -m 30 "$SEAMONKEY_PAGE") || { log_error "No se pudo leer $SEAMONKEY_PAGE"; return 1; }
    # Preferir la versión en castellano; si no, la en inglés
    url=$(grep -oE 'https?://[^"'"'"' ]+linux-x86_64/es-ES/[^"'"'"' ]+\.tar\.(bz2|xz)' <<< "$page" | head -1)
    [ -n "$url" ] || url=$(grep -oE 'https?://[^"'"'"' ]+linux-x86_64/en-US/[^"'"'"' ]+\.tar\.(bz2|xz)' <<< "$page" | head -1)
    if [ -z "$url" ]; then
        log_error "No se encontró la descarga para Linux en $SEAMONKEY_PAGE (puede haber cambiado la página)"
        return 1
    fi
    echo -e "   ${GREEN}$(basename "$url")${NC}"
    tmp=$(mktemp -d)
    if ! curl -fL --progress-bar -o "$tmp/seamonkey.tar" "$url"; then
        log_error "No se pudo descargar SeaMonkey"
        rm -rf -- "$tmp"
        return 1
    fi
    # Comprobación con la lista de sumas de la versión, si la publica
    root=${url%%/linux-x86_64/*}
    rel=${url#"$root/"}
    for algo in 512 256; do
        sums=$(curl -fsSL -m 30 "$root/SHA${algo}SUMS" 2>/dev/null) || continue
        expected=$(awk -v f="$rel" '{n = $2; sub(/^\*/, "", n)} n == f {print $1; exit}' <<< "$sums")
        [ -n "$expected" ] && break
    done
    if [ -n "$expected" ]; then
        got=$(sha${algo}sum "$tmp/seamonkey.tar" | awk '{print $1}')
        if [ "$got" != "$expected" ]; then
            log_error "La descarga no coincide con la suma oficial (SHA-$algo): no se instala"
            rm -rf -- "$tmp"
            return 1
        fi
        echo -e "   ${GREEN}✓ Verificada con la suma oficial (SHA-$algo)${NC}"
    else
        log_warning "SeaMonkey no publica una suma de verificación para esta versión: se bajó por HTTPS de su sitio"
        confirm "${YELLOW}¿Instalarla igualmente?${NC}" || { rm -rf -- "$tmp"; return 1; }
    fi
    sudo mkdir -p "$SEAMONKEY_DIR" \
        && sudo tar -xf "$tmp/seamonkey.tar" -C "$SEAMONKEY_DIR" --strip-components=1 --no-same-owner \
        || { log_error "No se pudo descomprimir SeaMonkey"; rm -rf -- "$tmp"; return 1; }
    rm -rf -- "$tmp"
    sudo ln -sf "$SEAMONKEY_DIR/seamonkey" /usr/local/bin/seamonkey
    sudo mkdir -p /usr/local/share/applications
    local icon=seamonkey
    for f in "$SEAMONKEY_DIR"/chrome/icons/default/default128.png "$SEAMONKEY_DIR"/chrome/icons/default/default48.png; do
        [ -f "$f" ] && { icon=$f; break; }
    done
    printf '[Desktop Entry]\nType=Application\nName=SeaMonkey\nGenericName=Navegador web\nComment=Navegador, correo, editor HTML y chat\nExec=%s %%u\nIcon=%s\nCategories=Network;WebBrowser;Email;\nMimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;\n' \
        "$SEAMONKEY_DIR/seamonkey" "$icon" | sudo tee /usr/local/share/applications/seamonkey.desktop > /dev/null
    mkdir -p "$STATE_DIR"
    echo "$(date '+%Y-%m-%d %H:%M')|$(basename "$url")" > "$STATE_DIR/seamonkey.txt"
    log_success "SeaMonkey instalado (menú del escritorio o 'seamonkey' en la terminal)"
    echo -e "${CYAN}ℹ Se actualiza solo desde su menú Ayuda → Acerca de SeaMonkey${NC}"
}

remove_seamonkey() {
    seamonkey_installed || return 0
    [ "$SEAMONKEY_DIR" = /opt/seamonkey ] && sudo rm -rf -- /opt/seamonkey
    sudo rm -f /usr/local/bin/seamonkey /usr/local/share/applications/seamonkey.desktop
    rm -f "$STATE_DIR/seamonkey.txt"
    log_success "SeaMonkey quitado (tu perfil en ~/.mozilla/seamonkey no se toca)"
}

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

# Vuelve el tema del escritorio al de antes de la opción 8 (Tokyo Night o modo oscuro)
restore_theme() {
    local kwrite value
    kwrite=$(command -v kwriteconfig6 || command -v kwriteconfig5)
    case $DESKTOP in
        kde)
            if [ "$(kde_color_scheme)" = TokyoNight ]; then
                value=$(theme_value kde-colores)
                run "No se pudieron restaurar los colores de Plasma" plasma-apply-colorscheme "${value:-BreezeLight}" \
                    && log_success "Colores de Plasma restaurados (${value:-BreezeLight})"
            else
                echo -e "  ${GREEN}✓ Plasma no usa Tokyo Night${NC}"
            fi
            if [ -n "$kwrite" ] && grep -qs '^DefaultProfile=TokyoNight.profile' "$HOME/.config/konsolerc"; then
                value=$(theme_value konsole-perfil)
                if [ -n "$value" ]; then
                    "$kwrite" --file konsolerc --group "Desktop Entry" --key DefaultProfile "$value"
                else
                    "$kwrite" --file konsolerc --group "Desktop Entry" --key DefaultProfile --delete
                fi
                log_success "Konsole vuelve a su perfil anterior"
            fi
            rm -f "$HOME/.local/share/color-schemes/TokyoNight.colors" \
                "$HOME/.local/share/konsole/TokyoNight.colorscheme" "$HOME/.local/share/konsole/TokyoNight.profile"
            ;;
        gnome)
            if grep -qs '^gnome-' "$THEME_BACKUP"; then
                for value in color-scheme:gnome-estilo gtk-theme:gnome-tema; do
                    if [ -n "$(theme_value "${value#*:}")" ]; then
                        gsettings set org.gnome.desktop.interface "${value%%:*}" "$(theme_value "${value#*:}")"
                    fi
                done
                log_success "Tema de GNOME restaurado"
            else
                echo -e "  ${GREEN}✓ El script no cambió el tema de GNOME${NC}"
            fi
            ;;
        *) echo -e "  ${GREEN}✓ El script no cambia el tema de ${DESKTOP_NAME}${NC}" ;;
    esac
    rm -f "$THEME_BACKUP"
}

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

# ============================================================
# OPCIÓN 19: REPARAR GRUB (COLOR: MAGENTA)
# ============================================================

# ------------------------------------------------------------
# Arranque en cualquier distribución: Ubuntu/Debian, Arch/Manjaro, Fedora y openSUSE.
# Todo lo de GRUB pasa por estas funciones, así el menú 19 sirve en todas.
# BOOT_ROOT vacío = el sistema que está corriendo; con una ruta = el sistema montado
# desde un Live USB (los comandos se ejecutan dentro de él con chroot).
# ------------------------------------------------------------

BOOT_ROOT=""
BOOT_FAMILY=""      # debian | arch | fedora | suse | otra
BOOT_DISTRO=""      # Nombre para mostrar (Ubuntu, Debian GNU/Linux, Arch Linux, Manjaro...)
BOOT_ID=""          # ID de os-release (ubuntu, debian, arch, manjaro, fedora...)
GRUB_PREFIX="grub"  # Fedora y openSUSE usan grub2-mkconfig, grub2-install...
GRUB_DIR="/boot/grub"
GRUB_CFG="/boot/grub/grub.cfg"
GRUB_REGEN=()       # Cómo se regenera el menú (update-grub o grub-mkconfig -o ...)
ESP_DIR="/boot/efi"  # Dónde está montada la partición EFI (/boot/efi, /efi o /boot)
EFI_ID="ubuntu"     # Carpeta de la distro dentro de EFI/ (ubuntu, debian, GRUB, manjaro, fedora...)

# Valor de /etc/os-release del sistema de arranque (el actual o el montado)
boot_os_value() {
    (. "$BOOT_ROOT/etc/os-release" 2>/dev/null && eval "echo \"\${$1:-}\"")
}

boot_has_cmd() {
    local d
    for d in /usr/sbin /usr/bin /sbin /bin; do
        [ -x "$BOOT_ROOT$d/$1" ] && return 0
    done
    return 1
}

# Ejecuta un comando como administrador en el sistema de arranque
on_target() {
    if [ -n "$BOOT_ROOT" ]; then
        sudo chroot "$BOOT_ROOT" "$@"
    else
        sudo "$@"
    fi
}

# Detecta la familia, los comandos de GRUB y la partición EFI. Uso: boot_detect [raíz]
boot_detect() {
    BOOT_ROOT="${1:-}"
    local like
    BOOT_ID=$(boot_os_value ID)
    like=" $BOOT_ID $(boot_os_value ID_LIKE) "
    BOOT_DISTRO=$(boot_os_value NAME)
    [ -n "$BOOT_DISTRO" ] || BOOT_DISTRO="Linux"
    # En Ubuntu, el sabor detectado es más preciso (Kubuntu también se llama "Ubuntu" en os-release)
    [ -z "$BOOT_ROOT" ] && [ -n "$FLAVOR_NAME" ] && [ "${BOOT_ONLY:-false}" = false ] && BOOT_DISTRO="$FLAVOR_NAME"
    case $like in
        *" ubuntu "*|*" debian "*) BOOT_FAMILY=debian ;;
        *" arch "*|*" archlinux "*|*" manjaro "*) BOOT_FAMILY=arch ;;
        *" fedora "*|*" rhel "*|*" centos "*) BOOT_FAMILY=fedora ;;
        *" suse "*|*" opensuse "*|*" sles "*) BOOT_FAMILY=suse ;;
        *) BOOT_FAMILY=otra ;;
    esac

    GRUB_PREFIX=grub
    if ! boot_has_cmd grub-mkconfig && boot_has_cmd grub2-mkconfig; then
        GRUB_PREFIX=grub2
    fi
    GRUB_DIR=/boot/grub
    [ "$GRUB_PREFIX" = grub2 ] && [ -d "$BOOT_ROOT/boot/grub2" ] && GRUB_DIR=/boot/grub2
    GRUB_CFG="$GRUB_DIR/grub.cfg"
    if boot_has_cmd update-grub; then
        GRUB_REGEN=(update-grub)
    else
        GRUB_REGEN=("$GRUB_PREFIX-mkconfig")
        # Fedora 38+: sin esta opción, los parámetros del kernel no llegan a las entradas BLS
        if [ "$BOOT_FAMILY" = fedora ] && on_target "$GRUB_PREFIX-mkconfig" --help 2>/dev/null | grep -q update-bls-cmdline; then
            GRUB_REGEN+=(--update-bls-cmdline)
        fi
        GRUB_REGEN+=(-o "$GRUB_CFG")
    fi

    ESP_DIR=$(boot_find_esp)
    EFI_ID=$(boot_find_efi_id)
}

# Punto de montaje de la partición EFI (FAT): primero el que dice fstab
boot_find_esp() {
    local mp
    for mp in /boot/efi /efi /boot; do
        if [ -n "$BOOT_ROOT" ]; then
            awk -v m="$mp" '$1 !~ /^#/ && $2 == m && $3 ~ /vfat|fat/ {f = 1} END {exit !f}' "$BOOT_ROOT/etc/fstab" 2>/dev/null \
                && { echo "$mp"; return; }
        elif [ "$(findmnt -no FSTYPE "$mp" 2>/dev/null)" = vfat ]; then
            echo "$mp"
            return
        fi
    done
    echo /boot/efi
}

# Carpeta de la distro dentro de EFI/: la que ya tiene GRUB, o la que usaría grub-install
boot_find_efi_id() {
    local id dir
    for id in "$BOOT_ID" $(boot_os_value ID_LIKE) ubuntu debian GRUB grub arch manjaro endeavouros fedora opensuse; do
        [ -n "$id" ] || continue
        dir=$(sudo find "$BOOT_ROOT$ESP_DIR/EFI" -maxdepth 1 -iname "$id" 2>/dev/null | head -n1)
        if [ -n "$dir" ] && sudo find "$dir" -maxdepth 1 \( -iname 'grubx64.efi' -o -iname 'shimx64.efi' \) 2>/dev/null | grep -q .; then
            basename "$dir"
            return
        fi
    done
    case $BOOT_FAMILY in
        debian) [ "$BOOT_ID" = debian ] && echo debian || echo ubuntu ;;
        arch) case $BOOT_ID in manjaro|endeavouros) echo "$BOOT_ID" ;; *) echo GRUB ;; esac ;;
        fedora) echo fedora ;;
        suse) echo opensuse ;;
        *) echo "${BOOT_ID:-GRUB}" ;;
    esac
}

# ¿Hay GRUB en este sistema? (Arch y EndeavourOS a veces usan systemd-boot)
grub_available() {
    boot_has_cmd "$GRUB_PREFIX-mkconfig" || boot_has_cmd update-grub
}

grub_required() {
    grub_available && return 0
    if on_target bootctl is-installed &> /dev/null; then
        log_warning "$BOOT_DISTRO arranca con systemd-boot, no con GRUB: esta opción no aplica"
    else
        log_error "GRUB no está instalado en $BOOT_DISTRO"
    fi
    return 1
}

# Menú de GRUB con entradas BLS (Fedora): los kernels no están en grub.cfg
grub_uses_bls() {
    sudo grep -q '^[[:space:]]*blscfg' "$BOOT_ROOT$GRUB_CFG" 2>/dev/null
}

grub_update() { on_target "${GRUB_REGEN[@]}"; }
grub_set_default() { on_target "$GRUB_PREFIX-set-default" "$@"; }
grub_editenv_list() { on_target "$GRUB_PREFIX-editenv" "$GRUB_DIR/grubenv" list 2>/dev/null; }
grub_probe() { on_target "$GRUB_PREFIX-probe" "$@"; }

# Paquetes de GRUB de cada familia: uefi | bios
grub_packages() {
    case $BOOT_FAMILY:$1 in
        debian:uefi) echo grub-efi-amd64 grub-efi-amd64-signed shim-signed ;;
        debian:bios) echo grub-pc ;;
        arch:uefi) echo grub efibootmgr ;;
        arch:bios) echo grub ;;
        fedora:uefi) echo grub2-efi-x64 shim-x64 grub2-tools ;;
        fedora:bios) echo grub2-pc grub2-tools ;;
        suse:uefi) echo grub2-x86_64-efi shim ;;
        suse:bios) echo grub2-i386-pc ;;
    esac
}

boot_pkg_supported() {
    [ "$BOOT_FAMILY" != otra ] && return 0
    log_error "No sé instalar paquetes en $BOOT_DISTRO: hazlo con su gestor de paquetes"
    return 1
}

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

boot_pkg_remove() {
    boot_pkg_supported || return 1
    case $BOOT_FAMILY in
        debian) on_target env DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@" ;;
        arch) on_target pacman -Rns --noconfirm "$@" ;;
        fedora) on_target dnf remove -y "$@" ;;
        suse) on_target zypper --non-interactive remove "$@" ;;
    esac
}

# Archivos de /etc/grub.d que instalan los paquetes: "paquete ruta" (aunque falten)
boot_grubd_owned() {
    case $BOOT_FAMILY in
        debian) dpkg-query -S '/etc/grub.d/*' 2>/dev/null | grep -v '^diversion' \
            | awk -F': ' '{n = split($1, p, ", "); for (i = 1; i <= n; i++) print p[i], $2}' ;;
        arch) pacman -Ql 2>/dev/null ;;
        fedora|suse) rpm -qa --filesbypkg 2>/dev/null ;;
    esac | awk '$2 ~ "^/etc/grub.d/[^/]+$" {print $1, $2}' | sort -u
}

# Instala GRUB en la partición EFI o en el disco (BIOS), según la distro
grub_install_uefi() {
    case $BOOT_FAMILY in
        # Fedora no usa grub2-install en UEFI: los archivos firmados vienen en los paquetes
        fedora) boot_pkg_reinstall shim-x64 grub2-efi-x64 ;;
        suse)
            if boot_has_cmd shim-install; then
                on_target shim-install --config-file="$GRUB_CFG"
            else
                on_target grub2-install --target=x86_64-efi --efi-directory="$ESP_DIR" --bootloader-id="$EFI_ID"
            fi ;;
        *)
            if [ "$BOOT_FAMILY" = arch ] && secure_boot_enabled 2>/dev/null; then
                log_warning "Secure Boot está activo: el GRUB de $BOOT_DISTRO no viene firmado y puede no arrancar"
                echo -e "${YELLOW}  Desactiva Secure Boot en la BIOS, o firma GRUB (por ejemplo con sbctl).${NC}"
            fi
            on_target "$GRUB_PREFIX-install" --target=x86_64-efi --efi-directory="$ESP_DIR" \
                --bootloader-id="$EFI_ID" --recheck ;;
    esac
}

grub_install_bios() {
    on_target "$GRUB_PREFIX-install" --target=i386-pc --recheck "$1"
}

# Nombre de la sesión Live: Ubuntu (casper), Debian (live), Arch, Manjaro y Fedora
is_live_session() {
    local cmdline
    cmdline=$(cat /proc/cmdline 2>/dev/null)
    [[ "$cmdline" == *boot=casper* || "$cmdline" == *boot=live* || "$cmdline" == *archisobasedir* \
        || "$cmdline" == *misobasedir* || "$cmdline" == *rd.live.image* ]] && return 0
    [ -d /cdrom/casper ] || [ -d /run/archiso ] || [ "$(findmnt -no FSTYPE / 2>/dev/null)" = overlay ]
}


# ¿La opción N del menú de arranque sirve en este equipo? (usa BOOT_LIVE, BOOT_UEFI y BOOT_GRUB)
# Los números no cambian aunque se oculten opciones: la tarjeta de rescate y las guías los usan.
boot_option_ok() {
    case $1 in
        1|10|11|12|13) return 0 ;;
        5) $BOOT_UEFI && ! $BOOT_LIVE ;;
        8) $BOOT_UEFI ;;
        4) $BOOT_GRUB && ! $BOOT_LIVE && ! $BOOT_UEFI ;;
        15) $BOOT_GRUB && ! $BOOT_LIVE && $BOOT_UEFI ;;
        2|3|6|7|9|14|16) $BOOT_GRUB && ! $BOOT_LIVE ;;
        *) return 1 ;;
    esac
}

# Por qué una opción no aparece (para quien escribe su número igual)
boot_option_reason() {
    if $BOOT_LIVE; then
        echo "en un Live USB se repara con la opción 10 (las demás son para el sistema ya arrancado)"
    elif [ "$1" = 4 ]; then
        echo "este equipo arranca en modo UEFI: GRUB va en la partición EFI (usa la 2 o la 3)"
    elif [ "$1" = 5 ] || [ "$1" = 8 ] || [ "$1" = 15 ] && ! $BOOT_UEFI; then
        echo "este equipo arranca en modo BIOS (Legacy): no tiene partición EFI ni entradas UEFI"
    else
        echo "$BOOT_DISTRO no usa GRUB (¿systemd-boot?)"
    fi
}

# Imprime una opción solo si sirve en este equipo
boot_option() {
    boot_option_ok "$1" || return 0
    printf "  ${PURPLE}%2s)${NC} %s\n" "$1" "$2"
    [ -n "${3:-}" ] && echo -e "         $3"
    return 0
}

# Imprime el título de una sección solo si alguna de sus opciones se muestra
boot_section() {
    local title="$1" n
    shift
    for n in "$@"; do
        if boot_option_ok "$n"; then
            echo -e "\n${PURPLE}$title${NC}"
            return 0
        fi
    done
}

grub_repair_menu() {
    boot_detect
    while true; do
        BOOT_LIVE=false BOOT_UEFI=false BOOT_GRUB=false
        is_live_session && BOOT_LIVE=true
        [ -d /sys/firmware/efi ] && BOOT_UEFI=true
        grub_available && BOOT_GRUB=true

        clear
        echo -e "${PURPLE}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    🔧 ARRANQUE: GRUB Y EFI                       ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        # Qué se detectó: así se entiende por qué hay opciones que no aparecen
        if $BOOT_LIVE; then
            echo -e "${GREEN}💿 Live USB · modo $($BOOT_UEFI && echo UEFI || echo "BIOS (Legacy)")${NC}"
            echo -e "${GREEN}   Para reparar el sistema instalado en el disco, usa la opción 10.${NC}"
        else
            echo -e "${CYAN}🐧 $BOOT_DISTRO · modo $($BOOT_UEFI && echo "UEFI (EFI en $ESP_DIR)" || echo "BIOS (Legacy)")${NC}"
            if $BOOT_GRUB; then
                echo -e "${CYAN}   GRUB: menú en $GRUB_CFG · se regenera con ${GRUB_REGEN[0]}${NC}"
            else
                echo -e "${YELLOW}⚠ GRUB no está instalado (¿usas systemd-boot?): solo se muestra lo que sirve igual${NC}"
            fi
        fi
        echo -e "${CYAN}ℹ Solo aparecen las opciones que sirven en este equipo${NC}"

        boot_section "🔍 Diagnóstico:" 1
        boot_option 1 "📊 DIAGNÓSTICO - Estado del arranque (y guardar un informe)"
        boot_section "🔧 Reparar (con el sistema arrancado):" 2 3 4 5
        boot_option 2 "🔧 REPARACIÓN RÁPIDA - Reinstalar GRUB y regenerar el menú"
        if $BOOT_UEFI; then
            boot_option 3 "🧰 REPARACIÓN COMPLETA - EFI + paquetes de GRUB + reinstalación + orden UEFI"
        else
            boot_option 3 "🧰 REPARACIÓN COMPLETA - Paquetes de GRUB + reinstalación en el disco + menú"
        fi
        boot_option 4 "💿 INSTALAR GRUB EN OTRO DISCO - Elegir en qué disco va el arranque"
        boot_option 5 "🩺 PARTICIÓN EFI - Verificar, reparar y ver espacio libre"
        boot_section "🎨 Configurar el menú de arranque:" 6 7 8 9 16
        boot_option 6 "📂 SISTEMA POR DEFECTO - Qué arranca solo y cuánto espera el menú"
        boot_option 7 "🪟 OTROS SISTEMAS - Detectar Windows y otras distros"
        boot_option 8 "🔢 ORDEN DE ARRANQUE UEFI - Qué arranca primero / solo la próxima vez"
        boot_option 9 "🎨 PERSONALIZAR MENÚ - Ocultar entradas, orden, colores, fondo, parámetros"
        if boot_verbose_active; then
            boot_option 16 "🐞 ARRANQUE DETALLADO (verbose) - Activado: elige para restaurar la pantalla de carga"
        else
            boot_option 16 "🐞 ARRANQUE DETALLADO (verbose) - Quitar la pantalla de carga (splash) para ver errores"
        fi
        boot_section "🚑 Cuando el sistema NO arranca:" 10 11 12 13
        if $BOOT_LIVE; then
            boot_option 10 "🚑 REPARAR EL SISTEMA DEL DISCO - Automático (chroot)"
        else
            boot_option 10 "🚑 REPARAR DESDE LIVE USB - Automático (chroot): se usa desde el USB"
        fi
        boot_option 11 "📖 GUÍA 'grub>' - Arrancar a mano desde el prompt de GRUB"
        boot_option 12 "📖 GUÍA 'grub rescue>' - Recuperar el menú de GRUB"
        boot_option 13 "📖 GUÍA LIVE USB - Reparación manual con comandos"
        boot_section "🛟 Prepárate ANTES de que falle (con el sistema funcionando):" 14 15
        boot_option 14 "🪪 TARJETA DE RESCATE - Los comandos exactos de TU PC para 'grub>' y" \
            "'grub rescue>', para fotografiar y copiar al pendrive junto con el script"
        boot_option 15 "🛟 ARRANQUE DE RESPALDO UEFI - Que la PC arranque aunque la BIOS" \
            "pierda la entrada de tu sistema (actualización de BIOS, reseteo...)"
        echo -e "\n  ${PURPLE} 0)${NC} 🔙 Volver al menú principal"
        echo ""
        read -r -p "📌 Opción: " grub_option

        if [[ "$grub_option" =~ ^[0-9]+$ ]] && [ "$grub_option" -ge 1 ] && [ "$grub_option" -le 16 ] \
            && ! boot_option_ok "$grub_option"; then
            echo -e "${YELLOW}ℹ La opción $grub_option no aplica: $(boot_option_reason "$grub_option")${NC}"
            sleep 3
            continue
        fi
        case $grub_option in
            1) grub_diagnostic ;;
            2) grub_normal_repair ;;
            3) grub_full_repair; pause ;;
            4) grub_reinstall_to_disk ;;
            5) esp_check_repair; pause ;;
            6) grub_default_entry_menu; pause ;;
            7) grub_os_prober_toggle; pause ;;
            8) uefi_boot_order_menu; pause ;;
            9) grub_customize_menu ;;
            10) grub_live_repair ;;
            11) grub_prompt_guide ;;
            12) grub_rescue_guide ;;
            13) grub_live_guide ;;
            14) rescue_card_menu ;;
            15) uefi_fallback_menu ;;
            16) boot_verbose_menu; pause ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

# Informe del arranque en texto plano (se muestra y se guarda para compartirlo)
boot_report() {
    echo "== Fecha: $(date '+%Y-%m-%d %H:%M')"
    echo "== Sistema: $(os_release_value PRETTY_NAME) · kernel en uso $(uname -r)"
    echo "   Familia: $BOOT_FAMILY · GRUB: $GRUB_PREFIX-* · menú: $GRUB_CFG · regenerar: ${GRUB_REGEN[*]}"
    echo ""
    echo "== MODO DE ARRANQUE"
    if [ -d /sys/firmware/efi ]; then
        echo "  UEFI · Secure Boot: $(secure_boot_enabled && echo activado || echo desactivado)"
    else
        echo "  BIOS (Legacy)"
    fi
    echo ""
    echo "== DISCOS Y PARTICIONES"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS 2>/dev/null | grep -v loop | sed 's/^/  /'
    echo ""
    echo "== ESPACIO EN /boot"
    df -h /boot 2>/dev/null | sed 's/^/  /'
    echo ""
    echo "== KERNELS INSTALADOS"
    ls /boot/vmlinuz-* 2>/dev/null | sed 's|^/boot/vmlinuz-|  |' | sort -V
    echo ""
    echo "== GRUB"
    if command -v "$GRUB_PREFIX-install" &> /dev/null; then
        echo "  $("$GRUB_PREFIX-install" --version 2>/dev/null | head -1)"
        grub_uses_bls && echo "  Entradas de kernels en formato BLS (/boot/loader/entries)"
    elif bootctl is-installed &> /dev/null; then
        echo "  ✗ GRUB no está instalado: el sistema usa systemd-boot"
    else
        echo "  ✗ GRUB NO está instalado"
    fi
    grep -E '^GRUB_(DEFAULT|TIMEOUT|TIMEOUT_STYLE|SAVEDEFAULT|DISABLE_OS_PROBER|DISABLE_RECOVERY|CMDLINE_LINUX_DEFAULT|GFXMODE|BACKGROUND)=' \
        /etc/default/grub 2>/dev/null | sed 's/^/  /'
    echo "  Entrada guardada: $(grub_editenv_list | sed -n 's/^saved_entry=//p')"
    [ -d /etc/grub.d/proxifiedScripts ] && echo "  ⚠ Configuración modificada por Grub Customizer"
    echo ""
    echo "== MENÚ DE ARRANQUE"
    grub_menu_entries | cut -d'|' -f2 | sed 's/^/  • /'
    if [ -d /sys/firmware/efi ]; then
        echo ""
        echo "== ENTRADAS UEFI"
        LC_ALL=C efibootmgr 2>/dev/null | sed 's/\t.*//; s/^/  /'
        echo ""
        echo "== PARTICIÓN EFI"
        if findmnt "$ESP_DIR" > /dev/null 2>&1; then
            df -h "$ESP_DIR" | sed 's/^/  /'
            echo "  Carpetas: $(sudo ls "$ESP_DIR/EFI" 2>/dev/null | tr '\n' ' ')(la de esta distro: $EFI_ID)"
        else
            echo "  ✗ No hay partición EFI montada (en /boot/efi, /efi ni /boot)"
        fi
    fi
}

grub_diagnostic() {
    grub_guide_header "📊 DIAGNÓSTICO DEL ARRANQUE"
    local report="$HOME/diagnostico-arranque.txt"
    boot_report | tee "$report"
    echo -e "\n${GREEN}💾 Informe guardado en: $report${NC}"
    echo -e "${YELLOW}   (sirve para pedir ayuda: compártelo si algo no arranca)${NC}"
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}

grub_normal_repair() {
    grub_guide_header "🔧 REPARACIÓN RÁPIDA DE GRUB"
    echo -e "${PURPLE}Reinstala GRUB y regenera el menú. Si no alcanza, usa la REPARACIÓN COMPLETA (3).${NC}\n"
    if ! confirm "${PURPLE}¿Reparar GRUB ahora?${NC}"; then
        return 0
    fi

    local ok=true
    if [ -d /sys/firmware/efi ]; then
        echo -e "${PURPLE}🔄 Reparando GRUB en modo UEFI (partición EFI en $ESP_DIR, carpeta $EFI_ID)...${NC}"
        if ! findmnt "$ESP_DIR" > /dev/null 2>&1; then
            log_error "La partición EFI no está montada (revisa la opción 5)"
            ok=false
        else
            run_visible "Falló la instalación de GRUB" grub_install_uefi || ok=false
        fi
    else
        local root_dev boot_disk
        root_dev=$(findmnt -no SOURCE /)
        # Sube por la jerarquía (LVM/LUKS/partición) hasta el disco físico
        boot_disk=$(lsblk -rnso NAME,TYPE "$root_dev" 2>/dev/null | awk '$2 == "disk" {print $1; exit}')
        if [ -z "$boot_disk" ]; then
            log_error "No se pudo detectar el disco del sistema; usa la opción 4"
            ok=false
        else
            echo -e "${PURPLE}🔄 Reparando GRUB en modo BIOS (disco: /dev/$boot_disk)...${NC}"
            run_visible "Falló la instalación de GRUB" grub_install_bios "/dev/$boot_disk" || ok=false
        fi
    fi

    echo -e "${PURPLE}🔄 Regenerando configuración (${GRUB_REGEN[*]})...${NC}"
    run_visible "No se pudo regenerar el menú" grub_update || ok=false

    if $ok; then
        log_success "GRUB reparado correctamente"
    else
        log_error "La reparación tuvo errores: prueba la REPARACIÓN COMPLETA (opción 3)"
    fi
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}

grub_reinstall_to_disk() {
    grub_guide_header "💿 INSTALAR GRUB EN OTRO DISCO"
    if [ -d /sys/firmware/efi ]; then
        echo -e "${YELLOW}ℹ Este equipo arranca en modo UEFI: GRUB no se instala en un disco sino en la${NC}"
        echo -e "${YELLOW}  partición EFI. Usa la REPARACIÓN RÁPIDA (2) o la COMPLETA (3).${NC}"
        echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
        read -r
        return 0
    fi

    echo -e "${PURPLE}[*] Discos disponibles:${NC}"
    lsblk -dpno NAME,SIZE,MODEL 2>/dev/null | grep -v "loop" | sed 's/^/  /'
    echo ""
    echo -e "  ${PURPLE}0)${NC} 🔙 Volver (o Enter)"
    read -r -p "📌 Disco (ej: /dev/sda; el DISCO, no una partición como /dev/sda1): " target_disk
    if [ -z "$target_disk" ] || [ "$target_disk" = 0 ]; then
        echo -e "${YELLOW}ℹ No se cambió nada${NC}"
        return 0
    fi

    if [ ! -b "$target_disk" ] || [ "$(lsblk -dno TYPE "$target_disk" 2>/dev/null)" != "disk" ]; then
        log_error "$target_disk no es un disco"
        echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
        read -r
        return 1
    fi

    echo -e "\n${RED}⚠ Esto instalará GRUB en $target_disk${NC}"
    if ! confirm "${PURPLE}¿Confirmar?${NC}"; then
        return 0
    fi

    if run_visible "Falló la instalación de GRUB" grub_install_bios "$target_disk" \
        && run_visible "No se pudo regenerar el menú" grub_update; then
        log_success "GRUB instalado en $target_disk"
    fi
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}

grub_guide_header() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    # Relleno según el ancho en pantalla: cada título empieza con un emoji, que ocupa 2 columnas
    local LC_ALL=C.UTF-8   # para contar letras y no bytes, sea cual sea el idioma del sistema
    local pad=$(( 46 - ${#1} - 1 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "║                    %s%*s║\n" "$1" "$pad" ""
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Comandos calculados para esta PC (si el script corre en el sistema instalado)
guide_my_commands() {
    is_live_session && return 1
    rescue_card_collect 2>/dev/null && $rc_ok && ! $rc_crypt || return 1
    echo -e "${GREEN}${BOLD}⭐ TUS COMANDOS (calculados para esta PC)${NC}"
    case $1 in
        prompt)
            echo -e "${GREEN}  Escribe estas líneas en 'grub>' y aparece el menú de siempre:${NC}"
            $rc_lvm && echo -e "${CYAN}    insmod lvm${NC}"
            echo -e "${CYAN}    search --no-floppy --fs-uuid --set=root $rc_uuid"
            echo -e "    configfile $rc_grubpath/grub.cfg${NC}"
            echo -e "${GREEN}  O, para arrancar directo sin menú:${NC}"
            echo -e "${CYAN}    search --no-floppy --fs-uuid --set=root $rc_uuid"
            echo -e "    linux $rc_kernel $rc_root ro"
            echo -e "    initrd $rc_initrd"
            echo -e "    boot${NC}"
            ;;
        rescue)
            echo -e "${GREEN}  Escribe estas 4 líneas en 'grub rescue>':${NC}"
            echo -e "${CYAN}    set prefix=($rc_drive)$rc_grubpath"
            echo -e "    set root=($rc_drive)"
            echo -e "    insmod normal"
            echo -e "    normal${NC}"
            $rc_approx && echo -e "${YELLOW}  (el número de disco es calculado: si falla, prueba hd0, hd1, hd2...)${NC}"
            ;;
    esac
    echo -e "${YELLOW}  📷 Sácales una foto, o guarda la tarjeta completa con la opción 14 (también al pendrive).${NC}"
    echo -e "${YELLOW}  Si ya estás frente a 'grub>' en otra PC o no tienes la foto, sigue la guía de abajo.${NC}\n"
}

grub_prompt_guide() {
    grub_guide_header "📖 ARRANQUE MANUAL DESDE 'grub>'"
    echo -e "Si al encender aparece ${BOLD}grub>${NC}, GRUB funciona pero no encuentra su menú."
    echo -e "Desde ahí se puede arrancar escribiendo unos comandos. ${BOLD}TAB${NC} autocompleta.\n"
    guide_my_commands prompt
    cat << 'EOF'
CAMINO RÁPIDO: QUE GRUB BUSQUE SOLO DÓNDE ESTÁ TU SISTEMA
  Escribe estas 2 líneas. La primera busca la partición que tiene el menú:
    search --no-floppy --file --set=root /boot/grub/grub.cfg
    configfile /boot/grub/grub.cfg
  • Si aparece el menú de siempre: elige tu sistema y ve al PASO FINAL.
  • Si dice "no such device": puede que /boot esté en su propia partición
    que uses btrfs o una distro con "grub2". Prueba cambiando /boot/grub/grub.cfg
    (en las 2 líneas) por:
        /grub/grub.cfg              (/boot en partición aparte)
        /@/boot/grub/grub.cfg       (btrfs, como Ubuntu o Fedora)
        /boot/grub2/grub.cfg        (Fedora, openSUSE)
  • Si tienes DOS Linux instalados, puede encontrar el otro primero:
    usa el CAMINO MANUAL.

CAMINO MANUAL: BUSCAR LA PARTICIÓN A MANO
  1. Lista los discos y particiones:
        ls
     Verás algo como: (hd0) (hd0,gpt1) (hd0,gpt2) ...  (o msdos1, msdos2)
  2. Mira cada una hasta encontrar la de tu sistema (muestra boot/, etc/, home/...):
        ls (hd0,gpt2)/
     Con "ls (hd0,gpt2)" (sin la barra) GRUB dice el tipo (ext*) y el tamaño.
  3. Arranca con ella (cambia hd0,gpt2 por la tuya):
        set root=(hd0,gpt2)
        linux /boot/vmlinuz root=/dev/sda2 ro
        initrd /boot/initrd.img
        boot
     • Los nombres del kernel cambian según la distro (TAB los autocompleta):
         Ubuntu y Debian:  /boot/vmlinuz           /boot/initrd.img
         Arch y Manjaro:   /boot/vmlinuz-linux     /boot/initramfs-linux.img
                           (en Manjaro: vmlinuz-6.x-x86_64 e initramfs-6.x-x86_64.img)
         Fedora:           /boot/vmlinuz-<versión> /boot/initramfs-<versión>.img
     • root= usa el nombre de LINUX, no el de GRUB: (hd0,gpt2) suele ser
       /dev/sda2 (SATA) o /dev/nvme0n1p2 (NVMe). Si te equivocas, verás
       "(initramfs)": reinicia y prueba con el otro nombre.
     • Con /boot en partición aparte: usa esa partición y quita "/boot":
       linux /vmlinuz ...  e  initrd /initrd.img

PASO FINAL: YA DENTRO DEL SISTEMA (repararlo de forma permanente)
  Ejecuta este script → opción 19 → 2 (REPARACIÓN RÁPIDA) o → 3 (COMPLETA).
EOF
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}

grub_rescue_guide() {
    grub_guide_header "🆘 GUÍA PARA 'grub rescue>'"
    echo -e "${BOLD}grub rescue>${NC} significa que GRUB arrancó pero no encuentra ni sus propios"
    echo -e "archivos. Es un modo muy limitado: solo existen ${BOLD}ls${NC}, ${BOLD}set${NC} e ${BOLD}insmod${NC}"
    echo -e "(no puede buscar solo). Hay que decirle dónde está su carpeta.\n"
    guide_my_commands rescue
    cat << 'EOF'
PASO 1: VER LAS PARTICIONES
    ls
  Verás algo como: (hd0) (hd0,gpt1) (hd0,gpt2) (hd0,gpt3)

PASO 2: ENCONTRAR LA QUE TIENE GRUB
  Prueba cada una hasta que una muestre archivos (grub.cfg, fonts, x86_64-efi...):
    ls (hd0,gpt2)/boot/grub
  • "unknown filesystem": esa no es (suele ser la EFI o la de Windows), sigue.
  • /boot en partición aparte:  ls (hd0,gpt3)/grub
  • btrfs:                       ls (hd0,gpt2)/@/boot/grub
  • Fedora, openSUSE:            ls (hd0,gpt2)/boot/grub2

PASO 3: CARGAR GRUB (cambia hd0,gpt2 y la ruta por las que encontraste)
    set prefix=(hd0,gpt2)/boot/grub
    set root=(hd0,gpt2)
    insmod normal
    normal
  Aparece el menú de siempre (o "grub>": entonces sigue la guía 11).

PASO 4: YA DENTRO DEL SISTEMA
  Ejecuta este script → opción 19 → 2 (REPARACIÓN RÁPIDA) o → 3 (COMPLETA).

SI "insmod normal" FALLA
  Los archivos de GRUB están dañados: arranca desde un USB de tu distribución
  y usa la opción 10 (reparación automática desde Live USB).
EOF
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}

grub_live_guide() {
    grub_guide_header "📖 REPARACIÓN MANUAL DESDE LIVE USB"
    cat << 'EOF'
Arranca desde un USB de instalación de tu distribución ("Probar Ubuntu", el Live
de Debian, el USB de Arch o de Manjaro, el Live de Fedora...) y abre una terminal.
La opción 10 de este menú hace todo esto automáticamente.

1. IDENTIFICAR LA PARTICIÓN DEL SISTEMA (y la EFI, si el equipo es UEFI)
    sudo fdisk -l            (o: lsblk -f)
  • Sistema: la partición ext4/btrfs/xfs grande (ej: /dev/sda2)
  • EFI: la partición FAT32 de ~100-1000 MB "EFI System" (ej: /dev/sda1)
  • ¿UEFI o BIOS? Si existe /sys/firmware/efi, es UEFI.

2. MONTAR EL SISTEMA
    sudo mount /dev/sda2 /mnt
    sudo mount /dev/sda1 /mnt/boot/efi            (solo UEFI)
  • La partición EFI va donde la monta tu sistema: mira /mnt/etc/fstab
    (Ubuntu, Debian y Fedora: /boot/efi · Arch y Manjaro: a veces /boot o /efi)
  • btrfs: sudo mount -o subvol=@ /dev/sda2 /mnt   (Fedora: subvol=root)
  • Cifrado (LUKS): sudo cryptsetup open /dev/sda3 cripta
                    sudo vgchange -ay   y monta el volumen que aparezca
  • /boot separado: sudo mount /dev/sdaX /mnt/boot (antes que la EFI)

3. PREPARAR EL ENTORNO PARA EL CHROOT
    for d in dev dev/pts proc sys run; do sudo mount --bind /$d /mnt/$d; done
    sudo mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars   (solo UEFI)
  (En el USB de Arch o Manjaro, arch-chroot / manjaro-chroot hace este paso solo.)

4. ENTRAR AL SISTEMA DAÑADO
    sudo chroot /mnt

5. REINSTALAR GRUB Y REGENERAR EL MENÚ (dentro del chroot)
  Ubuntu y Debian:
    grub-install --target=x86_64-efi --efi-directory=/boot/efi     (UEFI)
    grub-install --target=i386-pc /dev/sda                          (BIOS: el DISCO)
    update-grub
  Arch y Manjaro (cambia /boot/efi por donde esté la EFI):
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
  Fedora (en UEFI no se usa grub2-install):
    dnf reinstall shim-x64 grub2-efi-x64                            (UEFI)
    grub2-install /dev/sda                                          (BIOS)
    grub2-mkconfig -o /boot/grub2/grub.cfg
  openSUSE:
    shim-install --config-file=/boot/grub2/grub.cfg                 (UEFI)
    grub2-mkconfig -o /boot/grub2/grub.cfg

  Si grub-install falla por archivos que faltan, reinstala GRUB (necesita internet):
    Ubuntu/Debian:  apt install --reinstall grub-efi-amd64-signed shim-signed  (BIOS: grub-pc)
    Arch/Manjaro:   pacman -S grub efibootmgr
    Fedora:         dnf reinstall grub2-efi-x64 shim-x64 grub2-tools         (BIOS: grub2-pc)

6. SALIR, DESMONTAR Y REINICIAR
    exit
    sudo umount -R /mnt      (desmonta todo lo de /mnt de una vez)
    reboot
EOF
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}

# ------------------------------------------------------------
# Reparación automática desde Live USB
# ------------------------------------------------------------

RESCUE_MNT="/mnt/rescate-arranque"

# Particiones con sistema de archivos de Linux: "dispositivo|tamaño|tipo|etiqueta"
linux_partitions() {
    local dev fs
    while read -r dev; do
        fs=$(lsblk -dno FSTYPE "$dev" 2>/dev/null)
        case $fs in ext4|ext3|btrfs|xfs) ;; *) continue ;; esac
        echo "$dev|$(lsblk -dno SIZE "$dev" | tr -d ' ')|$fs|$(lsblk -dno LABEL "$dev")"
    done < <(lsblk -lnpo NAME,TYPE | awk '$2 == "part" || $2 == "lvm" || $2 == "crypt" {print $1}')
}

unlock_encrypted_partitions() {
    local dev
    for dev in $(lsblk -lnpo NAME,FSTYPE | awk '$2 == "crypto_LUKS" {print $1}'); do
        lsblk -lnpo TYPE "$dev" | grep -q crypt && continue
        if confirm "${PURPLE}🔐 $dev está cifrada. ¿Desbloquearla?${NC}"; then
            sudo cryptsetup open "$dev" "rescate_$(basename "$dev")" \
                || log_error "No se pudo desbloquear $dev"
        fi
    done
    command -v vgchange &> /dev/null && sudo vgchange -ay >> "$LOG_FILE" 2>&1
}

rescue_umount() {
    # De vuelta al sistema que está corriendo (el USB)
    [ "$BOOT_ROOT" = "$RESCUE_MNT" ] && boot_detect
    findmnt "$RESCUE_MNT" > /dev/null 2>&1 || return 0
    sudo umount -R "$RESCUE_MNT" 2>> "$LOG_FILE" || sudo umount -lR "$RESCUE_MNT" 2>> "$LOG_FILE"
}

rescue_grub_install() {
    local uefi="$1" disk="$2"
    if $uefi; then
        run_visible "Falló la instalación de GRUB" grub_install_uefi
    else
        run_visible "Falló la instalación de GRUB" grub_install_bios "$disk"
    fi
}

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

# ------------------------------------------------------------
# Menú de arranque y EFI
# ------------------------------------------------------------

# Cambia (o agrega) una variable de /etc/default/grub
set_grub_var() {
    local key="$1" value="$2" escaped
    backup_grub_config
    # Escapa los caracteres especiales del reemplazo de sed (\ & |)
    escaped=${value//\\/\\\\}
    escaped=${escaped//&/\\&}
    escaped=${escaped//|/\\|}
    if grep -q "^${key}=" /etc/default/grub; then
        sudo sed -i "s|^${key}=.*|${key}=${escaped}|" /etc/default/grub
    else
        echo "${key}=${value}" | sudo tee -a /etc/default/grub > /dev/null
    fi
}

# Entradas del menú de GRUB: "ruta para grub-set-default|título visible"
grub_menu_entries() {
    local cfg="$BOOT_ROOT$GRUB_CFG" sub_line entry_line sub_title entry_title sub_id entry_id
    # Separador \037: con un tabulador, read se come el campo vacío de las entradas sin submenú
    while IFS=$'\037' read -r sub_line entry_line; do
        entry_id=$(grub_line_id "$entry_line")
        entry_title=$(grep -oP "^\s*menuentry ['\"]\K[^'\"]+" <<< "$entry_line")
        if [ -n "$sub_line" ]; then
            sub_id=$(grub_line_id "$sub_line")
            sub_title=$(grep -oP "^\s*submenu ['\"]\K[^'\"]+" <<< "$sub_line")
            echo "${sub_id}>${entry_id}|${sub_title} › ${entry_title}"
        else
            echo "${entry_id}|${entry_title}"
        fi
    done < <(sudo awk '
        /^submenu / { s = $0; next }
        /^}/ { s = ""; next }
        /menuentry / && tolower($0) !~ /recovery|recuperaci/ { print s "\037" $0 }
    ' "$cfg" 2>/dev/null)
}

grub_default_entry_menu() {
    grub_guide_header "📂 SISTEMA POR DEFECTO Y TIEMPO DEL MENÚ"
    local entries=() entry i=0 choice timeout
    # Fedora (BLS): los kernels no están en grub.cfg; se leen con grubby ("bls:índice|título")
    if grub_uses_bls && command -v grubby &> /dev/null; then
        mapfile -t entries < <(sudo grubby --info=ALL 2>/dev/null | awk -F= '
            /^index=/ {i = $2}
            /^title=/ {t = substr($0, 7); gsub(/^"|"$/, "", t); print "bls:" i "|" t}')
    fi
    mapfile -t -O "${#entries[@]}" entries < <(grub_menu_entries)
    if [ ${#entries[@]} -eq 0 ]; then
        log_error "No se pudo leer el menú de GRUB ($GRUB_CFG)"
        return 1
    fi

    echo -e "${PURPLE}📋 Entradas del menú de arranque:${NC}\n"
    for entry in "${entries[@]}"; do
        i=$((i + 1))
        printf "  ${PURPLE}[%2s]${NC} %s\n" "$i" "${entry#*|}"
    done
    echo ""
    read -r -p "📌 ¿Cuál arranca por defecto? (Enter = no cambiar): " choice
    if [ -n "$choice" ]; then
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#entries[@]} ]; then
            log_error "Opción inválida"
            return 1
        fi
        entry=${entries[$((choice - 1))]}
        if [[ "$entry" == bls:* ]]; then
            entry=${entry#bls:}
            run "No se pudo cambiar el sistema por defecto" sudo grubby --set-default-index="${entry%%|*}" \
                && log_success "Por defecto: ${entry#*|}"
        else
            ensure_grub_saved
            [ $? -eq 1 ] && return 1
            run "No se pudo cambiar el sistema por defecto" grub_set_default "${entry%%|*}" \
                && log_success "Por defecto: ${entry#*|}"
        fi
    fi

    timeout=$(sed -n 's/^GRUB_TIMEOUT=//p' /etc/default/grub | tr -d '"')
    echo ""
    read -r -p "⏱ Segundos que espera el menú (actual: ${timeout:-?}; 0 = no mostrarlo; Enter = no cambiar): " choice
    if [ -n "$choice" ]; then
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            log_error "Escribe un número de segundos"
            return 1
        fi
        set_grub_var GRUB_TIMEOUT "$choice"
        if [ "$choice" -eq 0 ]; then
            set_grub_var GRUB_TIMEOUT_STYLE hidden
        else
            set_grub_var GRUB_TIMEOUT_STYLE menu
        fi
        run_visible "No se pudo regenerar el menú" grub_update \
            && log_success "El menú de GRUB espera $choice segundos"
    fi
}

GRUB_OTHERS_FIRST="/etc/grub.d/09_arch_ultimate_tools_otros_primero"

others_visible() {
    grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub || [ -f "$GRUB_OTHERS_FIRST" ]
}

grub_os_prober_toggle() {
    grub_guide_header "🪟 DETECTAR OTROS SISTEMAS"
    if others_visible; then
        echo -e "${GREEN}✓ La detección de otros sistemas ya está activada${NC}\n"
        if confirm "${PURPLE}¿Desactivarla? (los otros sistemas desaparecerán del menú)${NC}"; then
            sudo rm -f "$GRUB_OTHERS_FIRST"
            set_grub_var GRUB_DISABLE_OS_PROBER true
            run_visible "No se pudo regenerar el menú" grub_update && log_success "Detección de otros sistemas desactivada"
        fi
        return 0
    fi

    echo -e "${PURPLE}Desde GRUB 2.06, muchas distros (Ubuntu, Debian, Arch...) no buscan otros sistemas por seguridad.${NC}"
    echo -e "${PURPLE}Al activarlo, aparecerán en el menú de arranque.${NC}\n"
    confirm "${PURPLE}¿Activar la detección de otros sistemas?${NC}" || return 0
    command -v os-prober &> /dev/null || boot_pkg_install os-prober || return 1
    set_grub_var GRUB_DISABLE_OS_PROBER false
    echo -e "${PURPLE}🔍 Buscando otros sistemas...${NC}"
    local found
    found=$(sudo os-prober 2>> "$LOG_FILE")
    if [ -n "$found" ]; then
        echo -e "${GREEN}Encontrados:${NC}"
        cut -d: -f2 <<< "$found" | sed 's/^/  • /'
    else
        log_warning "No se encontró otro sistema (si está en otro disco, conéctalo y vuelve a intentarlo)"
    fi
    run_visible "No se pudo regenerar el menú" grub_update && log_success "Detección activada"
    echo -e "${YELLOW}ℹ Si el menú no aparece al encender, usa la opción 6 para darle unos segundos${NC}"
}

uefi_boot_order_menu() {
    grub_guide_header "🔢 ORDEN DE ARRANQUE UEFI"
    if [ ! -d /sys/firmware/efi ]; then
        log_warning "Este equipo arranca en modo BIOS (Legacy): el orden se cambia en la BIOS"
        return 0
    fi
    command -v efibootmgr &> /dev/null || boot_pkg_install efibootmgr || return 1

    local out entries=() order current entry i=0 choice action num
    out=$(LC_ALL=C efibootmgr 2>> "$LOG_FILE")
    order=$(sed -n 's/^BootOrder: //p' <<< "$out")
    current=$(sed -n 's/^BootCurrent: //p' <<< "$out")
    mapfile -t entries < <(sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} \{1,\}\([^\t]*\).*/\1|\2/p' <<< "$out")
    if [ ${#entries[@]} -eq 0 ]; then
        log_error "No se pudieron leer las entradas UEFI"
        return 1
    fi

    echo -e "${PURPLE}📋 Entradas de arranque (orden actual: $order):${NC}\n"
    for entry in "${entries[@]}"; do
        i=$((i + 1))
        num=${entry%%|*}
        printf "  ${PURPLE}[%2s]${NC} %s %s" "$i" "$num" "${entry#*|}"
        [ "$num" = "$current" ] && printf " ${GREEN}(arrancado ahora)${NC}"
        [ "$num" = "${order%%,*}" ] && printf " ${CYAN}(primero)${NC}"
        echo ""
    done
    echo -e "\n  ${PURPLE}[ 0]${NC} 🔙 Volver sin cambiar nada"
    echo ""
    read -r -p "📌 Entrada: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#entries[@]} ]; then
        echo -e "${YELLOW}ℹ No se cambió nada${NC}"
        return 0
    fi
    entry=${entries[$((choice - 1))]}
    num=${entry%%|*}

    echo -e "\n  ${PURPLE}1)${NC} Ponerla primera (siempre)"
    echo -e "  ${PURPLE}2)${NC} Arrancarla solo la próxima vez (p. ej. entrar a Windows una vez)"
    echo -e "  ${PURPLE}0)${NC} 🔙 Volver sin cambiar nada"
    read -r -p "📌 Opción: " action
    case $action in
        1)
            local new_order
            new_order=$(tr ',' '\n' <<< "$order" | grep -vix "$num" | paste -sd, -)
            new_order="$num${new_order:+,$new_order}"
            run "No se pudo cambiar el orden" sudo efibootmgr -o "$new_order" \
                && log_success "Primero: ${entry#*|} (orden: $new_order)"
            ;;
        2)
            run "No se pudo programar el próximo arranque" sudo efibootmgr -n "$num" \
                && log_success "El próximo arranque será: ${entry#*|}"
            confirm "${PURPLE}¿Reiniciar ahora?${NC}" && sudo reboot
            ;;
        *) echo -e "${YELLOW}ℹ No se cambió nada${NC}" ;;
    esac
}

esp_check_repair() {
    grub_guide_header "🩺 PARTICIÓN EFI"
    local dev
    dev=$(findmnt -no SOURCE "$ESP_DIR" 2>/dev/null)
    if [ -z "$dev" ]; then
        log_warning "No hay partición EFI montada en /boot/efi, /efi ni /boot (¿el equipo arranca en modo BIOS?)"
        return 0
    fi
    echo -e "${PURPLE}💾 Partición EFI: $dev${NC}"
    df -h "$ESP_DIR" | sed 's/^/  /'
    echo -e "\n${PURPLE}📁 Sistemas registrados en ella:${NC}"
    sudo ls "$ESP_DIR/EFI" 2>/dev/null | sed 's/^/  • /'
    echo -e "\n${YELLOW}ℹ Windows con 'inicio rápido' o un apagado brusco pueden dañarla y dejar GRUB sin arrancar${NC}\n"
    confirm "${PURPLE}¿Verificar y reparar la partición EFI? (se desmonta unos segundos)${NC}" || return 0

    esp_fsck "$dev"
}

# Desmonta la partición EFI, la verifica con fsck.vfat y la vuelve a montar
esp_fsck() {
    local dev="$1"
    command -v fsck.vfat &> /dev/null || boot_pkg_install dosfstools || return 1
    run "No se pudo desmontar $ESP_DIR (¿la está usando otro programa?)" sudo umount "$ESP_DIR" || return 1
    sudo fsck.vfat -a "$dev" 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}
    run "No se pudo volver a montar $ESP_DIR" sudo mount "$ESP_DIR" || return 1
    # fsck: 0 = sin errores, 1 = errores corregidos, más = quedaron errores
    case $rc in
        0) log_success "Partición EFI sin errores" ;;
        1) log_success "Partición EFI reparada" ;;
        *) log_error "Quedaron errores en la partición EFI (código $rc)"; return 1 ;;
    esac
}

# ------------------------------------------------------------
# Personalizar el menú de GRUB (sin programas externos)
# ------------------------------------------------------------

GRUB_LOOK_FILE="/etc/grub.d/42_arch_ultimate_tools_apariencia"

# Regenera grub.cfg. Si falla, muestra el error en pantalla: grub-mkconfig solo
# reemplaza el menú cuando termina bien, así que el anterior sigue intacto.
regen_grub() {
    # La primera versión de este script buscaba os-prober solo en su sitio y hacía
    # fallar update-grub si Grub Customizer lo había movido: se reemplaza por la nueva
    if [ -f "$GRUB_OTHERS_FIRST" ] && grep -q '^exec sh /etc/grub.d/30_os-prober$' "$GRUB_OTHERS_FIRST"; then
        write_others_first_script
    fi
    # El filtro de entradas ocultas se reescribe siempre con la versión actual del script
    # (la primera dejaba bloques "if" vacíos y update-grub fallaba)
    [ -f "$GRUB_FILTER_AWK" ] && write_grub_filter
    echo -e "${PURPLE}🔄 Regenerando el menú de GRUB...${NC}"
    local out rc
    out=$(grub_update 2>&1)
    rc=$?
    echo "[$(date '+%H:%M:%S')] \$ ${GRUB_REGEN[*]}" >> "$LOG_FILE"
    echo "$out" >> "$LOG_FILE"
    if [ $rc -eq 0 ]; then
        rescue_card_refresh
        return 0
    fi

    log_error "Falló ${GRUB_REGEN[0]} (código $rc). El menú de arranque anterior sigue intacto."
    echo -e "${YELLOW}Últimas líneas del error:${NC}"
    tail -8 <<< "$out" | sed 's/^/   /'
    if [ -d /etc/grub.d/proxifiedScripts ]; then
        echo -e "${YELLOW}⚠ Grub Customizer cambió los scripts de /etc/grub.d: suele ser la causa de este error.${NC}"
        echo -e "${YELLOW}  Deshazlo en: opción 19 → 9 (Personalizar menú) → 7${NC}"
    fi
    return $rc
}

# Scripts de /etc/grub.d cuyo nombre contiene el texto dado, con cualquier número
# delante: Grub Customizer los renumera (37_uefi-firmware) o los cambia por *_proxy
grub_scripts() {
    local f
    for f in /etc/grub.d/[0-9][0-9]_*"$1"*; do
        [ -f "$f" ] && echo "$f"
    done
}

# Oculto = existe y ninguno de sus scripts es ejecutable
grub_scripts_hidden() {
    local f found=false
    while IFS= read -r f; do
        found=true
        [ -x "$f" ] && return 1
    done < <(grub_scripts "$1")
    $found
}

grub_scripts_chmod() {
    local mode="$1" f
    while IFS= read -r f; do
        sudo chmod "$mode" "$f"
    done < <(grub_scripts "$2")
}

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

# Entradas del grub.cfg actual: "script|ruta visible|título"
grub_cfg_entries() {
    sudo awk -v q="'" '
        /^### BEGIN / { src = $3; next }
        /^submenu / { s = $0; sub("^submenu[ \t]+[" q "\"]", "", s); sub("[" q "\"].*", "", s); next }
        /^}/ { s = ""; next }
        /^[ \t]*menuentry / {
            t = $0; sub("^[ \t]*menuentry[ \t]+[" q "\"]", "", t); sub("[" q "\"].*", "", t)
            print src "|" (s != "" ? s " › " t : t) "|" t
        }
    ' "$GRUB_CFG" 2>/dev/null
}

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

# Otros sistemas antes que Ubuntu: un script que corre antes que 10_linux llama a
# 30_os-prober, y el original queda desactivado con GRUB_DISABLE_OS_PROBER=true.
grub_others_first_toggle() {
    if [ -f "$GRUB_OTHERS_FIRST" ]; then
        confirm "${PURPLE}Los otros sistemas ya aparecen primero. ¿Volver a mostrar ${BOOT_DISTRO} primero?${NC}" || return 0
        sudo rm -f "$GRUB_OTHERS_FIRST"
        set_grub_var GRUB_DISABLE_OS_PROBER false
        regen_grub && log_success "${BOOT_DISTRO} vuelve a estar primero en el menú"
        return
    fi
    confirm "${PURPLE}¿Mostrar Windows y los otros sistemas ANTES que ${BOOT_DISTRO} en el menú?${NC}" || return 0
    command -v os-prober &> /dev/null || boot_pkg_install os-prober || return 1
    write_others_first_script
    set_grub_var GRUB_DISABLE_OS_PROBER true
    # Que el orden no cambie lo que arranca solo: Ubuntu sigue siendo el predeterminado
    ensure_grub_saved
    [ $? -eq 1 ] && return 1
    regen_grub || return 1
    local saved kubuntu
    saved=$(grub_editenv_list | sed -n 's/^saved_entry=//p')
    if [ -z "$saved" ] || [ "$saved" = "0" ]; then
        kubuntu=$(grub_menu_entries | grep -m1 '^gnulinux-simple-' | cut -d'|' -f1)
        [ -n "$kubuntu" ] && grub_set_default "$kubuntu"
    fi
    log_success "Los otros sistemas aparecen primero (${BOOT_DISTRO} sigue arrancando por defecto; cámbialo con la opción 6)"
}

grub_remember_last_toggle() {
    if grep -q '^GRUB_SAVEDEFAULT=true' /etc/default/grub; then
        confirm "${PURPLE}GRUB recuerda el último sistema elegido. ¿Desactivarlo?${NC}" || return 0
        set_grub_var GRUB_SAVEDEFAULT false
        regen_grub && log_success "GRUB arrancará siempre la entrada por defecto (opción 6)"
        return
    fi
    confirm "${PURPLE}¿Que GRUB arranque solo el último sistema que elegiste en el menú?${NC}" || return 0
    ensure_grub_saved
    [ $? -eq 1 ] && return 1
    set_grub_var GRUB_SAVEDEFAULT true
    regen_grub && log_success "GRUB recordará el último sistema elegido"
}

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

# Parámetros con los que arranca el kernel (GRUB_CMDLINE_LINUX_DEFAULT)
# ------------------------------------------------------------
# Arranque detallado (verbose): quita la pantalla de carga (splash, Plymouth) y el arranque silencioso
# (quiet) para ver los errores que el inicio decorado tapa.
# Sirve en todas las distros del menú de arranque (Ubuntu, Debian, Arch, Manjaro, Fedora, openSUSE)
# y recuerda cómo estaba, para volver exactamente a eso.
# ------------------------------------------------------------
BOOT_VERBOSE_STATE="$STATE_DIR/arranque-con-mensajes.txt"
BOOT_VERBOSE_DROPIN="/etc/default/grub.d/99-ultimate-tools-ver-arranque.cfg"
# Palabras que esconden los mensajes: logo (splash, rhgb en Fedora, splash=silent en openSUSE),
# modo silencioso (quiet), y niveles de registro bajos (loglevel=3 en Arch, udev, systemd)
BOOT_QUIET_RE='^(quiet|splash|splash=.*|rhgb|loglevel=[0-3]|rd\.udev\.log_level=.*|udev\.log_level=.*|udev\.log_priority=.*|rd\.systemd\.show_status=.*|systemd\.show_status=.*|vt\.global_cursor_default=0)$'

boot_strip_quiet() {
    local w words=() out=()
    read -r -a words <<< "$1"
    for w in "${words[@]}"; do
        [[ "$w" =~ $BOOT_QUIET_RE ]] || out+=("$w")
    done
    echo "${out[*]}"
}

# Valor real de una variable de GRUB. En Ubuntu y Debian los archivos de /etc/default/grub.d
# se leen después y pueden pisarlo (pasa en imágenes de la nube); el archivo de este script no cuenta.
grub_effective_var() {
    (
        # shellcheck disable=SC1091
        . /etc/default/grub 2> /dev/null
        if [ "$BOOT_FAMILY" = debian ]; then
            for f in /etc/default/grub.d/*.cfg; do
                # shellcheck disable=SC1090
                [ -e "$f" ] && [ "$f" != "$BOOT_VERBOSE_DROPIN" ] && . "$f"
            done
        fi
        eval "printf '%s' \"\${$1}\""
    )
}

boot_verbose_active() { [ -f "$BOOT_VERBOSE_STATE" ]; }

# Valor entre comillas dobles, escapado para /etc/default/grub (parámetros como acpi_osi="Windows 2020")
grub_quote() {
    local v="$1"
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    v=${v//\$/\\\$}
    v=${v//\`/\\\`}
    printf '"%s"' "$v"
}

boot_verbose_on() {
    local cur_def cur_lin new_def new_lin w removed=""
    cur_def=$(grub_effective_var GRUB_CMDLINE_LINUX_DEFAULT)
    cur_lin=$(grub_effective_var GRUB_CMDLINE_LINUX)
    new_def=$(boot_strip_quiet "$cur_def")
    new_lin=$(boot_strip_quiet "$cur_lin")
    local words=()
    read -r -a words <<< "$cur_def $cur_lin"
    for w in "${words[@]}"; do
        [[ "$w" =~ $BOOT_QUIET_RE ]] && [[ " $removed " != *" $w "* ]] && removed+="$w "
    done
    removed=${removed% }
    if [ -z "$removed" ] && ! boot_verbose_active; then
        echo -e "${GREEN}✓ El arranque ya es detallado (no hay pantalla de carga ni quiet)${NC}"
        return 0
    fi
    echo -e "${PURPLE}Se quita:${NC} ${removed:-nada nuevo}"
    mkdir -p "$STATE_DIR"
    if [ "$BOOT_FAMILY" = debian ] && [ -d /etc/default/grub.d ]; then
        # Un archivo propio que se lee al final: /etc/default/grub no se toca y se deshace borrándolo
        {
            echo "# Ubuntu Ultimate Tools: arranque detallado (se deshace en el menú de arranque → 16)"
            [ "$new_def" != "$cur_def" ] && echo "GRUB_CMDLINE_LINUX_DEFAULT=$(grub_quote "$new_def")"
            [ "$new_lin" != "$cur_lin" ] && echo "GRUB_CMDLINE_LINUX=$(grub_quote "$new_lin")"
        } | sudo tee "$BOOT_VERBOSE_DROPIN" > /dev/null
        boot_verbose_active || echo "modo=archivo" > "$BOOT_VERBOSE_STATE"
    else
        # Se anotan los valores originales una sola vez, para volver exactamente a ellos
        if ! boot_verbose_active; then
            {
                echo "modo=default"
                [ "$new_def" != "$cur_def" ] && echo "orig_default=$cur_def"
                [ "$new_lin" != "$cur_lin" ] && echo "orig_linux=$cur_lin"
            } > "$BOOT_VERBOSE_STATE"
        fi
        [ "$new_def" != "$cur_def" ] && set_grub_var GRUB_CMDLINE_LINUX_DEFAULT "$(grub_quote "$new_def")"
        [ "$new_lin" != "$cur_lin" ] && set_grub_var GRUB_CMDLINE_LINUX "$(grub_quote "$new_lin")"
    fi
    # Fedora y openSUSE con BLS: cada kernel guarda sus parámetros, se cambian con grubby
    if [ -n "$removed" ] && grub_uses_bls && command -v grubby &> /dev/null; then
        run "No se pudieron cambiar los parámetros de los kernels" sudo grubby --update-kernel=ALL --remove-args="$removed" \
            && echo "bls_quitados=$removed" >> "$BOOT_VERBOSE_STATE"
    fi
    regen_grub || return 1
    log_success "Arranque detallado activado: al reiniciar vas a ver cada paso y los errores, sin pantalla de carga"
    echo -e "${CYAN}ℹ Si el arranque se queda trabado, la última línea es la pista de qué falla (sácale una foto).${NC}"
    echo -e "${CYAN}  Para restaurar la pantalla de carga: esta misma opción.${NC}"
}

boot_verbose_off() {
    local mode orig_def orig_lin bls
    mode=$(sed -n 's/^modo=//p' "$BOOT_VERBOSE_STATE")
    orig_def=$(sed -n 's/^orig_default=//p' "$BOOT_VERBOSE_STATE")
    orig_lin=$(sed -n 's/^orig_linux=//p' "$BOOT_VERBOSE_STATE")
    bls=$(sed -n 's/^bls_quitados=//p' "$BOOT_VERBOSE_STATE" | head -1)
    if [ "$mode" = archivo ]; then
        sudo rm -f "$BOOT_VERBOSE_DROPIN"
    else
        grep -q '^orig_default=' "$BOOT_VERBOSE_STATE" && set_grub_var GRUB_CMDLINE_LINUX_DEFAULT "$(grub_quote "$orig_def")"
        grep -q '^orig_linux=' "$BOOT_VERBOSE_STATE" && set_grub_var GRUB_CMDLINE_LINUX "$(grub_quote "$orig_lin")"
    fi
    if [ -n "$bls" ] && command -v grubby &> /dev/null; then
        run "No se pudieron restaurar los parámetros de los kernels" sudo grubby --update-kernel=ALL --args="$bls"
    fi
    rm -f "$BOOT_VERBOSE_STATE"
    regen_grub && log_success "Pantalla de carga restaurada: el arranque vuelve a como estaba"
}

boot_verbose_menu() {
    echo -e "${PURPLE}🐞 ARRANQUE DETALLADO (verbose)${NC}\n"
    echo -e "   Muchas distros arrancan con una pantalla de carga decorada (splash, la dibuja Plymouth) y en"
    echo -e "   modo silencioso (quiet): eso tapa los errores. En arranque detallado ves cada paso y cada fallo."
    echo -e "   La pantalla de carga se puede restaurar cuando quieras desde esta misma opción.\n"
    echo -e "   Parámetros ahora: ${CYAN}$(grub_effective_var GRUB_CMDLINE_LINUX) $(grub_effective_var GRUB_CMDLINE_LINUX_DEFAULT)${NC}"
    echo -e "   ${CYAN}💡 Solo para un arranque: en el menú de GRUB pulsa 'e', borra 'quiet splash' y pulsa Ctrl+X;${NC}"
    echo -e "   ${CYAN}   en Ubuntu también puedes pulsar Esc mientras se ve el logo.${NC}\n"
    if boot_verbose_active; then
        echo -e "   Estado: ${GREEN}arranque detallado activado${NC} (lo cambió el script)\n"
        confirm "${PURPLE}¿Restaurar la pantalla de carga (splash) y el arranque silencioso?${NC}" && boot_verbose_off
    else
        echo -e "   Estado: ${YELLOW}arranque con pantalla de carga (como viene de fábrica)${NC}\n"
        confirm "${PURPLE}¿Activar el arranque detallado (quitar la pantalla de carga)?${NC}" && boot_verbose_on
    fi
}

grub_kernel_params_menu() {
    local current option params word
    current=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT=//p' /etc/default/grub | tr -d '"')
    echo -e "${PURPLE}⚙ Parámetros actuales:${NC} ${current:-(ninguno)}\n"
    echo -e "  ${PURPLE}1)${NC} Arranque detallado (verbose): quitar la pantalla de carga para ver errores"
    echo -e "  ${PURPLE}2)${NC} Restaurar la pantalla de carga y el arranque silencioso (como estaba, o 'quiet splash')"
    echo -e "  ${PURPLE}3)${NC} Escribirlos a mano"
    echo -e "\n  ${PURPLE}0)${NC} 🔙 Volver"
    echo ""
    read -r -p "📌 Opción: " option
    case $option in
        1) boot_verbose_on; return ;;
        2) if boot_verbose_active; then boot_verbose_off; return; fi ;;&
        2)
            params=""
            for word in $current; do
                [[ "$word" == "quiet" || "$word" == "splash" ]] || params+="$word "
            done
            [ "$option" = 2 ] && params="quiet splash $params"
            ;;
        3)
            read -r -e -i "$current" -p "✏ Parámetros: " params
            ;;
        *) echo -e "${YELLOW}ℹ No se cambió nada${NC}"; return 0 ;;
    esac
    params=$(xargs <<< "$params")
    set_grub_var GRUB_CMDLINE_LINUX_DEFAULT "\"$params\""
    regen_grub && log_success "Parámetros del kernel: ${params:-(ninguno)} (se aplican al reiniciar)"
}

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

grub_customize_menu() {
    local entry
    while true; do
        grub_guide_header "🎨 PERSONALIZAR MENÚ DE GRUB"
        echo -e "${PURPLE}📋 Así se ve ahora el menú:${NC}"
        while IFS= read -r entry; do
            echo "   • ${entry#*|}"
        done < <(grub_menu_entries)
        if [ -d /etc/grub.d/proxifiedScripts ]; then
            echo -e "\n${YELLOW}⚠ Grub Customizer modificó este menú: usa la opción 7 para deshacerlo.${NC}"
        fi
        echo ""
        echo -e "  ${PURPLE}1)${NC} Ocultar o mostrar entradas: marca cada una (kernels, Windows, memtest...)"
        echo -e "  ${PURPLE}2)${NC} Orden: otros sistemas (Windows...) antes o después de ${BOOT_DISTRO}"
        echo -e "  ${PURPLE}3)${NC} Recordar el último sistema elegido"
        echo -e "  ${PURPLE}4)${NC} Apariencia: colores, imagen de fondo y resolución"
        echo -e "  ${PURPLE}5)${NC} Parámetros de arranque del kernel"
        echo -e "  ${PURPLE}6)${NC} Restaurar el menú original (deshace los cambios de este script)"
        echo -e "  ${PURPLE}7)${NC} Deshacer los cambios de Grub Customizer"
        echo -e "\n  ${PURPLE}0)${NC} 🔙 Volver"
        echo -e "\n${YELLOW}ℹ Qué arranca por defecto y cuánto espera el menú: opción 6 del menú de GRUB${NC}\n"
        read -r -p "📌 Opción (0-7): " custom_option
        case $custom_option in
            1) grub_hide_entries ;;
            2) grub_others_first_toggle ;;
            3) grub_remember_last_toggle ;;
            4) grub_appearance_menu ;;
            5) grub_kernel_params_menu ;;
            6) grub_restore_original ;;
            7) undo_grub_customizer ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
    done
}

# ------------------------------------------------------------
# Reparación completa (sin programas externos)
# ------------------------------------------------------------

# Quita rEFInd (versiones anteriores del script podían instalarlo) y vuelve a GRUB
remove_refind() {
    run "No se pudo desinstalar rEFInd" boot_pkg_remove refind && forget_installed refind
    # Su entrada UEFI y sus archivos en la partición EFI no se borran con el paquete
    local num
    for num in $(LC_ALL=C efibootmgr 2>/dev/null | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} \{1,\}rEFInd.*/\1/p'); do
        run "No se pudo quitar la entrada UEFI de rEFInd" sudo efibootmgr -b "$num" -B
    done
    sudo rm -rf "$ESP_DIR/EFI/refind"
    log_success "rEFInd quitado"
}

# Pone primera la entrada UEFI de esta distro (su etiqueta es la carpeta EFI: ubuntu, debian, GRUB...)
uefi_distro_first() {
    local out order num new_order
    out=$(LC_ALL=C efibootmgr 2>/dev/null)
    order=$(sed -n 's/^BootOrder: //p' <<< "$out")
    num=$(awk -v id="$EFI_ID" -v name="$BOOT_DISTRO" '
        match($0, /^Boot[0-9A-Fa-f]{4}\*? +/) {
            label = substr($0, RLENGTH + 1); sub(/\t.*/, "", label)
            if (tolower(label) == tolower(id) || tolower(label) == tolower(name)) { print substr($0, 5, 4); exit }
        }' <<< "$out")
    [ -n "$num" ] || return 0
    [ "${order%%,*}" = "$num" ] && return 0
    new_order=$(tr ',' '\n' <<< "$order" | grep -vix "$num" | paste -sd, -)
    run "No se pudo cambiar el orden de arranque" sudo efibootmgr -o "$num${new_order:+,$new_order}"
}

grub_full_repair() {
    grub_guide_header "🧰 REPARACIÓN COMPLETA DEL ARRANQUE"
    local uefi=false disk step=0 total=4 failed=()
    [ -d /sys/firmware/efi ] && { uefi=true; total=7; }

    echo -e "${PURPLE}📋 Se hará, en orden:${NC}"
    $uefi && echo -e "  • Verificar y reparar la partición EFI"
    echo -e "  • Reinstalar los paquetes de GRUB: $(grub_packages "$($uefi && echo uefi || echo bios)")"
    echo -e "  • Reinstalar GRUB en $($uefi && echo "la partición EFI" || echo "el disco del sistema")"
    echo -e "  • Regenerar el menú de arranque"
    $uefi && echo -e "  • Poner ${BOOT_DISTRO} primero en el orden de arranque UEFI"
    $uefi && echo -e "  • Arranque de respaldo UEFI (se pregunta; si ya está, se actualiza)"
    echo -e "  • Comprobar el resultado y actualizar la tarjeta de rescate"
    echo -e "\n${YELLOW}ℹ Para un sistema que NO arranca, usa la opción 10 desde un Live USB${NC}\n"
    confirm "${PURPLE}¿Empezar la reparación completa?${NC}" || return 0

    if boot_pkg_installed refind | grep -qx refind \
        && confirm "${PURPLE}rEFInd está instalado y puede tapar a GRUB. ¿Quitarlo?${NC}"; then
        remove_refind
    fi

    if $uefi; then
        step=$((step + 1)); echo -e "\n${PURPLE}[$step/$total] Partición EFI...${NC}"
        if findmnt "$ESP_DIR" > /dev/null 2>&1; then
            esp_fsck "$(findmnt -no SOURCE "$ESP_DIR")" || failed+=("partición EFI")
        else
            log_error "No hay partición EFI montada (en /boot/efi, /efi ni /boot)"
            failed+=("partición EFI")
        fi
    fi

    step=$((step + 1)); echo -e "\n${PURPLE}[$step/$total] Reinstalando los paquetes de GRUB...${NC}"
    local pkgs=()
    read -r -a pkgs <<< "$(grub_packages "$($uefi && echo uefi || echo bios)")"
    if [ ${#pkgs[@]} -gt 0 ]; then
        run_visible "No se pudieron reinstalar los paquetes de GRUB" boot_pkg_reinstall "${pkgs[@]}" \
            || failed+=("paquetes de GRUB")
    else
        log_warning "No sé qué paquetes de GRUB usa ${BOOT_DISTRO}: se reinstala solo GRUB"
    fi

    step=$((step + 1)); echo -e "\n${PURPLE}[$step/$total] Reinstalando GRUB...${NC}"
    if $uefi; then
        run_visible "Falló la instalación de GRUB" grub_install_uefi || failed+=("instalar GRUB")
    else
        disk=$(lsblk -rnso NAME,TYPE "$(findmnt -no SOURCE /)" 2>/dev/null | awk '$2 == "disk" {print $1; exit}')
        if [ -n "$disk" ]; then
            run_visible "Falló la instalación de GRUB" grub_install_bios "/dev/$disk" || failed+=("instalar GRUB")
        else
            log_error "No se pudo detectar el disco del sistema (usa la opción 4)"
            failed+=("instalar GRUB")
        fi
    fi

    step=$((step + 1)); echo -e "\n${PURPLE}[$step/$total] Regenerando el menú...${NC}"
    run_visible "No se pudo regenerar el menú" grub_update || failed+=("regenerar el menú")

    if $uefi; then
        step=$((step + 1)); echo -e "\n${PURPLE}[$step/$total] Orden de arranque UEFI...${NC}"
        uefi_distro_first || failed+=("orden UEFI")
        step=$((step + 1)); echo -e "\n${PURPLE}[$step/$total] Arranque de respaldo UEFI...${NC}"
        if [ "$(uefi_fallback_state)" = nuestro ]; then
            install_uefi_fallback || failed+=("arranque de respaldo")
        elif [ "$(uefi_fallback_state)" = vacio ]; then
            echo -e "${CYAN}ℹ Si la BIOS pierde la entrada de ${BOOT_DISTRO} (al actualizarla o resetearla), la PC no arranca.${NC}"
            echo -e "${CYAN}  El arranque de respaldo lo evita: arranca igual por la ruta de emergencia.${NC}"
            if confirm "${PURPLE}¿Instalar el arranque de respaldo? (recomendado)${NC}"; then
                install_uefi_fallback || failed+=("arranque de respaldo")
            fi
        else
            echo -e "${CYAN}ℹ La ruta de respaldo la usa otro sistema: no se toca (opción 15 para más detalles)${NC}"
        fi
    fi

    step=$((step + 1)); echo -e "\n${PURPLE}[$step/$total] Comprobando...${NC}"
    local entry_count
    entry_count=$(grub_menu_entries | wc -l)
    if [ -s "$GRUB_CFG" ] && [ "$entry_count" -gt 0 ]; then
        log_success "El menú de GRUB tiene $entry_count entradas"
    else
        log_error "El menú de GRUB quedó vacío"
        failed+=("comprobación")
    fi
    if $uefi && ! LC_ALL=C efibootmgr 2>/dev/null | grep -qiE "^Boot[0-9A-F]{4}\*? +($EFI_ID|$BOOT_DISTRO)"; then
        log_error "No hay entrada UEFI de ${BOOT_DISTRO} (carpeta $EFI_ID)"
        failed+=("entrada UEFI")
    fi
    if [ -f "$RESCUE_CARD" ]; then
        rescue_card_refresh && log_success "Tarjeta de rescate actualizada ($RESCUE_CARD)"
    else
        echo -e "${CYAN}💡 Consejo: genera tu tarjeta de rescate (opción 14) para estar preparado si falla otra vez${NC}"
    fi

    echo ""
    if [ ${#failed[@]} -eq 0 ]; then
        log_success "Reparación completa terminada sin errores"
    else
        log_error "Pasos con problemas: ${failed[*]}. Detalles en: $LOG_FILE"
    fi
}

# ------------------------------------------------------------
# Prepararse antes de que falle: tarjeta de rescate y arranque de respaldo
# ------------------------------------------------------------

RESCUE_CARD="$HOME/tarjeta-rescate-arranque.txt"
RESCUE_CARD_ESP="/boot/efi/tarjeta-rescate-arranque.txt"   # se ajusta a la partición EFI de cada distro

# Datos del arranque de ESTA PC, como los ve GRUB. Deja variables rc_* listas para la tarjeta.
rescue_card_collect() {
    local grubdir="$GRUB_DIR" mnt fsroot rel dev part disk pnum pttype idx name
    rc_ok=false rc_approx=false rc_crypt=false rc_lvm=false
    [ -d "$grubdir" ] || return 1
    dev=$(findmnt -no SOURCE -T "$grubdir" 2>/dev/null | sed 's/\[.*//')
    [ -b "$dev" ] || return 1
    mnt=$(findmnt -no TARGET -T "$grubdir")
    fsroot=$(findmnt -no FSROOT -T "$grubdir")
    rel=${grubdir#"${mnt%/}"}
    # Ruta de /boot/grub DENTRO de su partición (con /boot aparte es /grub; con btrfs @ es /@/boot/grub)
    rc_grubpath="${fsroot%/}$rel"
    rc_bootpath="${rc_grubpath%/*}"   # /boot/grub → /boot · /grub2 (boot aparte) → vacío
    rc_uuid=$(lsblk -no UUID "$dev" 2>/dev/null | head -n1)
    rc_fstype=$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -n1)
    rc_size=$(lsblk -no SIZE "$dev" 2>/dev/null | head -n1 | tr -d ' ')
    rc_dev=$dev

    local abstraction
    abstraction=$(grub_probe --target=abstraction "$grubdir" 2>/dev/null)
    [[ "$abstraction" == *crypt* || "$abstraction" == *luks* ]] && rc_crypt=true
    [[ "$abstraction" == *lvm* ]] && rc_lvm=true
    if lsblk -no TYPE "$dev" 2>/dev/null | grep -qx crypt; then rc_crypt=true; fi

    # Nombre de la partición para GRUB, p. ej. (hd0,gpt2)
    name=$(grub_probe --target=drive "$grubdir" 2>/dev/null)
    if [[ "$name" =~ ^\((hd[0-9]+,(gpt|msdos)[0-9]+|lvm/[^\)]+)\)$ ]]; then
        rc_drive=${name:1:-1}
    else
        # grub-probe no lo sabe: se calcula (el número de disco puede variar)
        part=$(basename "$(readlink -f "$dev")")
        disk=$(lsblk -no PKNAME "/dev/$part" 2>/dev/null | head -n1)
        pnum=$(cat "/sys/class/block/$part/partition" 2>/dev/null)
        pttype=$(lsblk -dno PTTYPE "/dev/$disk" 2>/dev/null)
        [ "$pttype" = dos ] && pttype=msdos
        [ -n "$disk" ] && [ -n "$pnum" ] && [ -n "$pttype" ] || return 1
        idx=$(lsblk -dno NAME,TYPE,RM 2>/dev/null | awk '$2 == "disk" && $3 == 0 {print $1}' | grep -nx "$disk" | cut -d: -f1)
        rc_drive="hd$(( ${idx:-1} - 1 )),$pttype$pnum"
        rc_approx=true
    fi

    # Parámetros del kernel con los que arrancó este sistema (root= y, si hay, rootflags=)
    rc_root=$(tr ' ' '\n' < /proc/cmdline | grep -E '^(root|rootflags)=' | paste -sd' ')
    # Nombres del kernel e initramfs. Ubuntu y openSUSE tienen enlaces fijos (siempre el más
    # nuevo); Arch usa vmlinuz-linux; Fedora y Debian, la versión. Se toma el que arrancó.
    local img k ver f
    img=$(tr ' ' '\n' < /proc/cmdline | sed -n 's/^BOOT_IMAGE=//p' | sed 's/^([^)]*)//')
    k=${img##*/}
    [ -n "$k" ] || k="vmlinuz-$(uname -r)"
    [ -e /boot/vmlinuz ] && k=vmlinuz
    ver=${k#vmlinuz}; ver=${ver#-}
    rc_initrd=""
    for f in initrd.img initrd "initramfs-$ver.img" "initrd.img-$ver" "initrd-$ver"; do
        [ "$k" != vmlinuz ] && { [ "$f" = initrd.img ] || [ "$f" = initrd ]; } && continue
        [ -e "/boot/$f" ] && { rc_initrd="$rc_bootpath/$f"; break; }
    done
    rc_kernel="$rc_bootpath/$k"
    [ -n "$rc_initrd" ] || rc_initrd="$rc_bootpath/initrd.img"
    [ -n "$rc_uuid" ] && [ -n "$rc_root" ] && rc_ok=true
}

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

# Guarda la tarjeta en la carpeta personal y en la partición EFI (sin preguntas)
rescue_card_write() {
    RESCUE_CARD_ESP="$ESP_DIR/tarjeta-rescate-arranque.txt"
    rescue_card_collect && $rc_ok || return 1
    rescue_card_text > "$RESCUE_CARD" || return 1
    # En la partición EFI se puede leer desde un Live USB o desde Windows
    if [ "$(findmnt -no FSTYPE "$ESP_DIR" 2>/dev/null)" = vfat ]; then
        sudo cp "$RESCUE_CARD" "$RESCUE_CARD_ESP" 2>> "$LOG_FILE"
    fi
    return 0
}

# Pendrives montados: "carpeta|tamaño libre"
mounted_usb_drives() {
    findmnt -rno TARGET,SOURCE 2>/dev/null | awk '$1 ~ "^(/media/|/run/media/)" {print $1}' | while read -r dir; do
        dir=$(printf '%b' "$dir")   # findmnt escapa los espacios como \x20
        echo "$dir|$(df -h --output=avail "$dir" 2>/dev/null | tail -1 | tr -d ' ') libres"
    done
}

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

rescue_card_menu() {
    grub_guide_header "🪪 TARJETA DE RESCATE DE ESTA PC"
    if is_live_session; then
        log_warning "Esto es un Live USB: la tarjeta se genera desde tu sistema instalado, cuando arranca bien"
        echo -e "${YELLOW}  Si tu sistema no arranca, usa la opción 10.${NC}"
        echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"; read -r
        return 0
    fi
    cat << 'EXPL'
Cuando GRUB se rompe, en lugar del menú aparece "grub>" o "grub rescue>" y hay
que escribir comandos con el nombre exacto de TU disco. Ahí no se puede abrir
este script ni buscar en internet desde la PC.

Esta tarjeta trae esos comandos ya calculados para esta PC. Guárdala ahora,
mientras todo funciona:
  📷 sácale una FOTO con el celular (es lo más seguro: la tienes siempre),
  💾 y cópiala al pendrive junto con este script (opción de abajo).
Se guarda también en tu carpeta personal y en la partición EFI, y se actualiza
sola cada vez que el script cambia GRUB.
EXPL
    echo ""
    if ! rescue_card_write; then
        log_error "No se pudieron leer los datos del arranque (¿falta $GRUB_DIR?). Usa el diagnóstico (opción 1)"
        echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"; read -r
        return 1
    fi
    echo -e "${YELLOW}📌 Presiona Enter para ver la tarjeta...${NC}"; read -r
    clear
    # Los comandos para escribir, resaltados (líneas con sangría)
    sed -E "s/^(    .*)$/$(printf '\033[1;36m')\1$(printf '\033[0m')/" "$RESCUE_CARD"
    echo ""
    echo -e "${GREEN}💾 Guardada en: $RESCUE_CARD${NC}"
    [ "$(findmnt -no FSTYPE "$ESP_DIR" 2>/dev/null)" = vfat ] && echo -e "${GREEN}💾 Copia en la partición EFI: $RESCUE_CARD_ESP${NC}"
    echo ""
    if confirm "${PURPLE}¿Copiar la tarjeta y este script a un pendrive?${NC}"; then
        rescue_copy_to_usb
    fi
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}

# Actualiza la tarjeta si ya existe (después de cambiar GRUB o el kernel)
rescue_card_refresh() {
    [ -f "$RESCUE_CARD" ] || return 0
    is_live_session && return 0
    rescue_card_write 2>/dev/null || true
}

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

# Estado de \EFI\BOOT\BOOTX64.EFI: vacio | nuestro | sistema | windows | otro
# "sistema": lo puso la propia distro (Fedora y openSUSE lo instalan y mantienen con shim)
uefi_fallback_state() {
    local cur own
    cur=$(sudo find "$ESP_DIR/EFI" -maxdepth 2 -ipath '*/boot/bootx64.efi' 2>/dev/null | head -n1)
    own=$(sudo find "$ESP_DIR/EFI" -maxdepth 2 -ipath "*/$EFI_ID/shimx64.efi" 2>/dev/null | head -n1)
    if [ -z "$cur" ]; then
        echo vacio
    elif [ -f "$UEFI_FALLBACK_MARK" ] && [ "$(sudo sha256sum < "$cur" | cut -d' ' -f1)" = "$(cat "$UEFI_FALLBACK_MARK")" ]; then
        echo nuestro
    elif [ -n "$own" ] && sudo cmp -s "$cur" "$own"; then
        echo sistema
    elif sudo grep -qa 'Microsoft Corporation' "$cur" && ! sudo grep -qa -i 'shim' "$cur"; then
        echo windows
    else
        echo otro
    fi
}

install_uefi_fallback() {
    local state
    state=$(uefi_fallback_state)
    # Fedora y openSUSE: el paquete shim pone y actualiza la ruta de respaldo por su cuenta
    if [ "$BOOT_FAMILY" = fedora ] || [ "$BOOT_FAMILY" = suse ]; then
        if [ "$state" = sistema ]; then
            log_success "${BOOT_DISTRO} ya instala y mantiene su arranque de respaldo: no hace falta nada"
            return 0
        fi
        if [ "$state" = vacio ]; then
            local shim=shim-x64
            [ "$BOOT_FAMILY" = suse ] && shim=shim
            run_visible "No se pudo reinstalar $shim" boot_pkg_reinstall "$shim" || return 1
            [ "$(uefi_fallback_state)" = sistema ] && log_success "Arranque de respaldo repuesto por ${BOOT_DISTRO}" \
                || log_warning "El paquete $shim no puso la ruta de respaldo: revisa la partición EFI (opción 5)"
            return 0
        fi
    fi
    case $state in
        nuestro)
            write_uefi_fallback_tool
            sudo "$UEFI_FALLBACK_TOOL" --forzar
            log_success "El arranque de respaldo ya estaba puesto: se actualizó"
            return 0 ;;
        sistema)
            log_success "${BOOT_DISTRO} ya puso su arranque de respaldo: no hace falta nada"
            return 0 ;;
        windows)
            log_warning "La ruta de respaldo la usa Windows: no se toca (Windows dejaría de arrancar por esa vía)"
            echo -e "${YELLOW}  Si algún día la PC va directo a Windows sin mostrar GRUB: entra al menú de arranque${NC}"
            echo -e "${YELLOW}  del BIOS (F12, F11, F8 o Esc al encender, según la marca), elige $EFI_ID y luego${NC}"
            echo -e "${YELLOW}  usa este script → 18 → 8 para ponerlo primero.${NC}"
            return 0 ;;
        otro)
            echo -e "${YELLOW}⚠ La ruta de respaldo ya tiene el arranque de otro sistema (otra distro o un programa).${NC}"
            confirm "${PURPLE}¿Reemplazarlo por el de ${BOOT_DISTRO}? (se guarda una copia para volver atrás)${NC}" || return 0
            sudo rm -rf "$UEFI_FALLBACK_BACKUP"
            sudo cp -r "$(sudo find "$ESP_DIR/EFI" -maxdepth 1 -iname boot | head -n1)" "$UEFI_FALLBACK_BACKUP" \
                || { log_error "No se pudo guardar la copia: no se cambió nada"; return 1; } ;;
    esac
    write_uefi_fallback_tool
    echo "nuevo" | sudo tee "$UEFI_FALLBACK_MARK" > /dev/null
    sudo "$UEFI_FALLBACK_TOOL" --forzar
    if [ "$(uefi_fallback_state)" = nuestro ]; then
        log_success "Arranque de respaldo instalado en la ruta de respaldo EFI/BOOT (se actualiza solo con cada actualización de GRUB)"
        [ "$BOOT_FAMILY" = debian ] || [ "$BOOT_FAMILY" = arch ] \
            || log_info "En ${BOOT_DISTRO} no se actualiza solo: vuelve a usar esta opción después de actualizar GRUB"
    else
        log_error "No se pudo instalar el arranque de respaldo (¿falta la carpeta EFI/$EFI_ID? Prueba la reparación completa)"
        sudo rm -f "$UEFI_FALLBACK_MARK" "$UEFI_FALLBACK_HOOK" "$UEFI_FALLBACK_HOOK_PACMAN"
        return 1
    fi
}

remove_uefi_fallback() {
    local dir state
    state=$(uefi_fallback_state)
    if [ "$state" != nuestro ]; then
        echo -e "${GREEN}✓ El arranque de respaldo no lo puso este script: no se toca${NC}"
        sudo rm -f "$UEFI_FALLBACK_MARK" "$UEFI_FALLBACK_HOOK" "$UEFI_FALLBACK_HOOK_PACMAN" "$UEFI_FALLBACK_TOOL"
        return 0
    fi
    confirm "${PURPLE}¿Quitar el arranque de respaldo?${NC}" || return 0
    dir=$(sudo find "$ESP_DIR/EFI" -maxdepth 1 -iname boot | head -n1)
    # Solo los archivos que copia el script; si había otros, se quedan
    sudo find "$dir" -maxdepth 1 -type f \( -iname bootx64.efi -o -iname grubx64.efi -o -iname mmx64.efi \
        -o -iname fbx64.efi -o -iname grub.cfg \) -delete
    if [ -d "$UEFI_FALLBACK_BACKUP" ]; then
        sudo cp -r "$UEFI_FALLBACK_BACKUP/." "$dir/" && sudo rm -rf "$UEFI_FALLBACK_BACKUP" \
            && log_success "Se restauró el arranque de respaldo que había antes"
    fi
    sudo rmdir "$dir" 2>/dev/null
    sudo rm -f "$UEFI_FALLBACK_MARK" "$UEFI_FALLBACK_HOOK" "$UEFI_FALLBACK_HOOK_PACMAN" "$UEFI_FALLBACK_TOOL"
    log_success "Arranque de respaldo quitado"
}

uefi_fallback_menu() {
    grub_guide_header "🛟 ARRANQUE DE RESPALDO UEFI"
    if [ ! -d /sys/firmware/efi ]; then
        log_warning "Este equipo arranca en modo BIOS (Legacy): esto es solo para UEFI"
        echo -e "${YELLOW}  En BIOS, GRUB vive en el propio disco y no depende de entradas del firmware.${NC}"
        echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"; read -r
        return 0
    fi
    if [ "$(findmnt -no FSTYPE "$ESP_DIR" 2>/dev/null)" != vfat ]; then
        log_error "La partición EFI no está montada (revisa la opción 5)"
        echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"; read -r
        return 1
    fi
    cat << 'EXPL'
El firmware (la BIOS UEFI) guarda una lista de sistemas para arrancar. A veces
esa lista se borra: al actualizar la BIOS, al quitar la pila, al cambiar el disco
de PC o por un reseteo. Entonces la PC dice "no hay sistema" o va directo a
Windows, aunque tu sistema y GRUB estén perfectos.

El arranque de respaldo es una copia del arranque de tu sistema en la "ruta de
emergencia" (\EFI\BOOT\BOOTX64.EFI), la que el firmware prueba cuando no
encuentra nada en su lista. Si la entrada se borra, la PC arranca igual por esa
ruta (y en Ubuntu, Debian y Fedora la entrada se vuelve a crear sola).

  • Con Secure Boot usa los mismos archivos firmados de tu distribución.
    (En Arch y Manjaro GRUB no viene firmado: con Secure Boot no arranca.)
  • Se actualiza solo con cada actualización de GRUB (apt o pacman).
  • Fedora y openSUSE ya lo traen: el script solo lo comprueba.
  • Si esa ruta la usa Windows, no se toca.
EXPL
    local state
    state=$(uefi_fallback_state)
    echo ""
    case $state in
        nuestro) echo -e "${GREEN}✓ Estado: INSTALADO (lo puso este script)${NC}" ;;
        sistema) echo -e "${GREEN}✓ Estado: INSTALADO por ${BOOT_DISTRO}${NC}" ;;
        vacio) echo -e "${YELLOW}○ Estado: no hay arranque de respaldo${NC}" ;;
        windows) echo -e "${CYAN}ℹ Estado: la ruta de respaldo es de Windows${NC}" ;;
        *) echo -e "${YELLOW}ℹ Estado: la ruta de respaldo tiene el arranque de otro sistema${NC}" ;;
    esac
    echo -e "${CYAN}  Partición EFI: $ESP_DIR · carpeta de ${BOOT_DISTRO}: EFI/$EFI_ID${NC}"
    echo ""
    echo -e "  ${PURPLE}1)${NC} $([ "$state" = nuestro ] && echo "Actualizarlo ahora" || echo "Instalarlo")"
    echo -e "  ${PURPLE}2)${NC} Quitarlo (vuelve a como estaba)"
    echo -e "  ${PURPLE}0)${NC} 🔙 Volver"
    local choice
    read -r -p "📌 Opción (0-2): " choice
    case $choice in
        1) install_uefi_fallback ;;
        2) remove_uefi_fallback ;;
        *) return 0 ;;
    esac
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}

# ============================================================
# OPCIÓN 20: APAGAR O REINICIAR (COLOR: AMARILLO)
# ============================================================

shutdown_menu() {
    clear
    echo -e "${YELLOW}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🔌 APAGAR / REINICIAR SISTEMA                 ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "\n${YELLOW}📋 Opciones:${NC}\n"
    echo -e "  ${YELLOW}1)${NC} Apagar sistema ahora"
    echo -e "  ${YELLOW}2)${NC} Reiniciar sistema ahora"
    echo -e "\n  ${YELLOW}0)${NC} 🔙 Volver"
    echo ""
    read -r -p "📌 Opción (0-2): " power_option

    case $power_option in
        1)
            echo -e "\n${RED}🔴 Apagando el sistema...${NC}"
            sudo shutdown -h now
            ;;
        2)
            echo -e "\n${GREEN}🟢 Reiniciando el sistema...${NC}"
            sudo reboot
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}❌ Opción inválida${NC}"
            sleep 1
            ;;
    esac
}

# ============================================================
# OPCIÓN 6: QUITAR ACCESOS DIRECTOS (COLOR: CIAN)
# ============================================================

PLASMA_APPLETSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

# Carpeta del escritorio (en español suele ser ~/Escritorio, no ~/Desktop)
desktop_dir() {
    local dir
    dir=$(xdg-user-dir DESKTOP 2>/dev/null)
    if [ -z "$dir" ] || [ "$dir" = "$HOME" ] || [ ! -d "$dir" ]; then
        for dir in "$HOME/Escritorio" "$HOME/Desktop" ""; do
            [ -d "$dir" ] && break
        done
    fi
    echo "$dir"
}

# Plasma guarda su configuración al cerrarse: hay que pararlo antes de editarla
stop_plasmashell() {
    pgrep -x plasmashell > /dev/null || return 0
    kquitapp6 plasmashell >> "$LOG_FILE" 2>&1 || kquitapp5 plasmashell >> "$LOG_FILE" 2>&1
    local i
    for i in $(seq 20); do
        pgrep -x plasmashell > /dev/null || return 0
        sleep 0.5
    done
    pkill -x plasmashell
    sleep 1
}

start_plasmashell() {
    pgrep -x plasmashell > /dev/null && return 0
    if command -v kstart &> /dev/null; then
        kstart plasmashell >> "$LOG_FILE" 2>&1
    elif command -v kstart5 &> /dev/null; then
        kstart5 plasmashell >> "$LOG_FILE" 2>&1
    else
        setsid plasmashell >> "$LOG_FILE" 2>&1 < /dev/null &
    fi
}

# IDs "contenedor applet" de los gestores de tareas del panel
taskmanager_applets() {
    [ -f "$PLASMA_APPLETSRC" ] || return 0
    awk '
        /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { g = $0; next }
        /^\[/ { g = "" }
        g != "" && /^plugin=org\.kde\.plasma\.(icontasks|taskmanager)$/ { gsub(/[^0-9]+/, " ", g); print g }
    ' "$PLASMA_APPLETSRC"
}

remove_desktop_shortcuts() {
    local dir items=() item i=0 input selected=() kind
    dir=$(desktop_dir)
    if [ -z "$dir" ]; then
        log_warning "No se encontró la carpeta del escritorio"
        return 1
    fi

    mapfile -t items < <(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.*' -printf '%f\n' | sort)
    if [ ${#items[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ No hay accesos en $dir${NC}"
        echo -e "${YELLOW}  Si aún ves íconos, son widgets: clic derecho sobre ellos → Eliminar${NC}"
        return 0
    fi

    echo -e "${CYAN}📁 Contenido de $dir:${NC}\n"
    for item in "${items[@]}"; do
        i=$((i + 1))
        kind="archivo"
        [[ "$item" == *.desktop ]] && kind="acceso directo"
        [ -L "$dir/$item" ] && kind="enlace"
        [ -d "$dir/$item" ] && kind="carpeta"
        printf "  ${CYAN}[%2s]${NC} %-40s ${YELLOW}(%s)${NC}\n" "$i" "$item" "$kind"
    done
    echo -e "\n${CYAN}📝 Números separados por espacio, 't' = todos los accesos directos (.desktop y enlaces), 0 o Enter = volver${NC}"
    read -r -p "🔢 Quitar: " input
    if [ -z "${input// /}" ] || [ "${input// /}" = 0 ]; then
        echo -e "${YELLOW}ℹ No se quitó nada${NC}"
        return 0
    fi

    if [ "$input" = "t" ] || [ "$input" = "T" ]; then
        for item in "${items[@]}"; do
            [[ "$item" == *.desktop ]] || [ -L "$dir/$item" ] && selected+=("$item")
        done
    else
        for i in $input; do
            [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le ${#items[@]} ] && selected+=("${items[$((i - 1))]}")
        done
    fi
    if [ ${#selected[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ No seleccionaste nada${NC}"
        return 0
    fi

    # Se mueven a una copia de seguridad en lugar de borrarlos, para poder restaurarlos
    mkdir -p "$SHORTCUTS_BACKUP/escritorio"
    for item in "${selected[@]}"; do
        if run "No se pudo quitar $item" mv --backup=numbered "$dir/$item" "$SHORTCUTS_BACKUP/escritorio/"; then
            echo -e "  ${GREEN}✓ Quitado: $item${NC}"
        fi
    done
    echo -e "${CYAN}ℹ Guardados en $SHORTCUTS_BACKUP/escritorio (se restauran con 'Revertir')${NC}"
}

GNOME_FAVORITES_BACKUP="$SHORTCUTS_BACKUP/gnome-favoritas"

# Apps fijadas en el dock de GNOME (Ubuntu): se guardan antes de vaciarlo
remove_gnome_favorites() {
    local current
    current=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)
    if [ -z "$current" ] || [ "$current" = "@as []" ] || [ "$current" = "[]" ]; then
        echo -e "${YELLOW}ℹ No hay apps fijadas en el dock${NC}"
        return 0
    fi
    echo -e "${CYAN}📌 Apps fijadas en el dock:${NC}"
    tr -d "[]'" <<< "$current" | tr ',' '\n' | sed 's/^ *//; s/\.desktop$//; s/^/  • /'
    echo ""
    confirm "${CYAN}¿Quitar todas las apps fijadas del dock?${NC}" || return 0
    mkdir -p "$SHORTCUTS_BACKUP"
    [ -f "$GNOME_FAVORITES_BACKUP" ] || echo "$current" > "$GNOME_FAVORITES_BACKUP"
    run "No se pudo cambiar el dock" gsettings set org.gnome.shell favorite-apps "[]" \
        && log_success "Apps fijadas quitadas del dock"
}

restore_gnome_favorites() {
    if [ ! -f "$GNOME_FAVORITES_BACKUP" ]; then
        echo -e "  ${YELLOW}ℹ No hay copia del dock guardada${NC}"
        return 0
    fi
    run "No se pudo restaurar el dock" gsettings set org.gnome.shell favorite-apps "$(cat "$GNOME_FAVORITES_BACKUP")" \
        && rm -f "$GNOME_FAVORITES_BACKUP" && log_success "Dock restaurado"
}

remove_panel_launchers() {
    case $DESKTOP in
        gnome) remove_gnome_favorites; return ;;
        kde) ;;
        *) log_warning "Quitar las apps fijadas del panel solo está disponible en KDE Plasma y GNOME"; return 0 ;;
    esac
    local applets launchers kwrite
    mapfile -t applets < <(taskmanager_applets)
    if [ ${#applets[@]} -eq 0 ]; then
        log_warning "No se encontró la barra de tareas de Plasma en $PLASMA_APPLETSRC"
        return 1
    fi
    kwrite=$(command -v kwriteconfig6 || command -v kwriteconfig5)
    if [ -z "$kwrite" ]; then
        log_error "No se encontró kwriteconfig6/kwriteconfig5"
        return 1
    fi

    launchers=$(grep '^launchers=' "$PLASMA_APPLETSRC" | cut -d= -f2- | tr ',' '\n' | sed '/^$/d')
    echo -e "${CYAN}📌 Aplicaciones fijadas en el panel:${NC}"
    if [ -n "$launchers" ]; then
        sed 's/^/  • /' <<< "$launchers"
    else
        echo -e "  • (las predeterminadas de Plasma: Discover, Dolphin, navegador...)"
    fi
    echo ""
    confirm "${CYAN}¿Quitar todas las aplicaciones fijadas del panel?${NC}" || return 0

    mkdir -p "$SHORTCUTS_BACKUP"
    [ -f "$SHORTCUTS_BACKUP/panel-appletsrc" ] || cp "$PLASMA_APPLETSRC" "$SHORTCUTS_BACKUP/panel-appletsrc"

    echo -e "${CYAN}🔄 Reiniciando el escritorio (la pantalla parpadeará)...${NC}"
    stop_plasmashell
    local entry ids
    for entry in "${applets[@]}"; do
        read -r -a ids <<< "$entry"
        # Si la clave no existe, Plasma usa sus lanzadores por defecto: se escribe vacía
        "$kwrite" --file "$PLASMA_APPLETSRC" --group Containments --group "${ids[0]}" --group Applets \
            --group "${ids[1]}" --group Configuration --group General --key launchers ""
    done
    start_plasmashell
    log_success "Aplicaciones fijadas quitadas del panel"
}

restore_desktop_shortcuts() {
    local dir src="$SHORTCUTS_BACKUP/escritorio"
    dir=$(desktop_dir)
    [ -n "$dir" ] || dir="$HOME/Desktop"
    if [ -d "$src" ] && [ -n "$(ls -A "$src")" ]; then
        mkdir -p "$dir"
        run "No se pudieron restaurar los íconos del escritorio" mv -n "$src"/* "$dir/" \
            && log_success "Íconos del escritorio restaurados"
        rmdir "$src" 2>/dev/null
    else
        echo -e "  ${YELLOW}ℹ No hay íconos del escritorio guardados${NC}"
    fi
}

restore_panel_launchers() {
    [ -f "$GNOME_FAVORITES_BACKUP" ] && restore_gnome_favorites
    local backup="$SHORTCUTS_BACKUP/panel-appletsrc"
    if [ ! -f "$backup" ]; then
        echo -e "  ${YELLOW}ℹ No hay copia del panel guardada${NC}"
        return 0
    fi
    stop_plasmashell
    if cp "$backup" "$PLASMA_APPLETSRC"; then
        rm -f "$backup"
        log_success "Panel restaurado"
    fi
    start_plasmashell
}

remove_shortcuts_menu() {
    if ! has_desktop; then
        log_warning "Los accesos directos necesitan un escritorio (este sistema no tiene)"
        pause
        return 0
    fi
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    🧹 QUITAR ACCESOS DIRECTOS                    ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "\n${CYAN}📋 Opciones:${NC}\n"
        echo -e "  ${CYAN}1)${NC} Íconos del escritorio"
        echo -e "  ${CYAN}2)${NC} Aplicaciones fijadas en el panel o el dock"
        echo -e "  ${CYAN}3)${NC} Restaurar los accesos quitados"
        echo -e "\n  ${CYAN}0)${NC} 🔙 Volver"
        echo ""
        read -r -p "📌 Opción (0-3): " shortcut_option

        case $shortcut_option in
            1) remove_desktop_shortcuts ;;
            2) remove_panel_launchers ;;
            3) restore_desktop_shortcuts; restore_panel_launchers ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
    done
}

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

dns_provider_field() {
    local name="$1" field="$2" entry
    for entry in "${DNS_PROVIDERS[@]}"; do
        if [ "${entry%%|*}" = "$name" ]; then
            cut -d'|' -f"$field" <<< "$entry"
            return 0
        fi
    done
    return 1
}

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

# Mide la latencia a cada proveedor (ping al primer servidor IPv4) y deja el
# nombre del más rápido en FASTEST_DNS
measure_dns() {
    local entry name ip avg best=999999
    FASTEST_DNS=""
    echo -e "${BLUE}⏱ Midiendo latencia de cada DNS...${NC}"
    for entry in "${DNS_PROVIDERS[@]}"; do
        name=${entry%%|*}
        ip=$(cut -d'|' -f2 <<< "$entry" | cut -d' ' -f1 | cut -d'#' -f1)
        avg=$(LC_ALL=C ping -c 3 -W 1 -q "$ip" 2>/dev/null | awk -F'/' '/^rtt|^round-trip/ {print $5}')
        if [ -n "$avg" ]; then
            printf "  %-18s %8s ms\n" "$name" "$avg"
            if awk -v a="$avg" -v b="$best" 'BEGIN {exit !(a < b)}'; then
                best=$avg
                FASTEST_DNS=$name
            fi
        else
            printf "  %-18s %8s\n" "$name" "sin respuesta"
        fi
    done
    [ -n "$FASTEST_DNS" ]
}

set_fastest_dns() {
    if ! measure_dns; then
        log_error "Ningún DNS respondió (¿hay conexión a internet?)"
        return 1
    fi
    echo -e "${GREEN}🏆 Más rápido: $FASTEST_DNS${NC}"
    set_dns "$FASTEST_DNS"
}

# BBR: algoritmo de congestión TCP de Google. Mejora la velocidad y la latencia
# sobre todo en Wi-Fi y conexiones con pérdidas.
# Versión de BBR que ofrece el kernel: bbr (Ubuntu, XanMod), bbr3 (Liquorix) o bbr2
bbr_algorithm() {
    local algo
    for algo in bbr bbr3 bbr2; do
        if grep -qw "$algo" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            echo "$algo"
            return 0
        fi
    done
    return 1
}

enable_bbr() {
    local kernel algo
    kernel=$(uname -r)
    # Algunos kernels (XanMod, Liquorix...) traen BBR incluido: no hay módulo que cargar
    if ! algo=$(bbr_algorithm); then
        if ! sudo modprobe tcp_bbr >> "$LOG_FILE" 2>&1 || ! algo=$(bbr_algorithm); then
            if [ ! -d "/lib/modules/$kernel/kernel" ]; then
                log_error "Faltan los módulos del kernel en uso ($kernel): reinicia y vuelve a intentarlo"
            else
                log_error "El kernel $kernel no incluye BBR (disponibles: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null))"
            fi
            return 1
        fi
    fi
    # Si BBR es un módulo, se carga en cada arranque
    if [ "$algo" = "bbr" ] && modinfo tcp_bbr &> /dev/null; then
        echo tcp_bbr | sudo tee "$BBR_MODULES_FILE" > /dev/null
    fi
    set_sysctl net.core.default_qdisc fq
    set_sysctl net.ipv4.tcp_congestion_control "$algo"
    log_success "TCP BBR activado ($algo)"
}

disable_bbr() {
    sudo rm -f "$BBR_MODULES_FILE"
    sudo sed -i '/^net\.core\.default_qdisc/d; /^net\.ipv4\.tcp_congestion_control/d' "$SYSCTL_FILE" 2>/dev/null
    # Valores por defecto de Ubuntu
    run "No se pudo restaurar TCP" sudo sysctl -w net.ipv4.tcp_congestion_control=cubic net.core.default_qdisc=fq_codel \
        && log_success "TCP vuelve a la configuración por defecto (cubic)"
}

# El ahorro de energía del Wi-Fi causa picos de latencia y microcortes
disable_wifi_powersave() {
    printf '[connection]\nwifi.powersave = 2\n' | sudo tee "$NM_WIFI_CONF" > /dev/null
    run "No se pudo recargar NetworkManager" sudo systemctl reload NetworkManager \
        && log_success "Ahorro de energía del Wi-Fi desactivado (se aplica al reconectar)"
}

enable_wifi_powersave() {
    sudo rm -f "$NM_WIFI_CONF"
    run "No se pudo recargar NetworkManager" sudo systemctl reload NetworkManager \
        && log_success "Ahorro de energía del Wi-Fi restaurado"
}

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

network_menu() {
    while true; do
        clear
        echo -e "${BLUE}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    🌐 RED, DNS Y DRIVERS                         ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "${BLUE}🌐 DNS actual: ${BOLD}$(current_dns)${NC}"
        echo -e "${BLUE}📶 TCP: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)${NC}"
        echo -e "${YELLOW}ℹ Un DNS rápido acelera el inicio de cada página; no aumenta los Mbps contratados${NC}\n"
        echo -e "  ${BLUE}1)${NC} Elegir DNS (Cloudflare, Google, Quad9, AdGuard)"
        echo -e "  ${BLUE}2)${NC} Medir qué DNS es más rápido desde tu conexión y usarlo"
        echo -e "  ${BLUE}3)${NC} Restaurar DNS automático (el del router)"
        echo -e "  ${BLUE}4)${NC} Activar/desactivar TCP BBR (mejor velocidad en Wi-Fi y conexiones inestables)"
        echo -e "  ${BLUE}5)${NC} Activar/desactivar ahorro de energía del Wi-Fi (menos latencia y cortes)"
        echo -e "  ${BLUE}6)${NC} Drivers: detectar e instalar los recomendados (GPU, Wi-Fi...)"
        echo -e "  ${BLUE}7)${NC} Actualizar firmware (BIOS, SSD...)"
        echo -e "\n  ${BLUE}0)${NC} 🔙 Volver"
        echo ""
        read -r -p "📌 Opción (0-7): " net_option

        case $net_option in
            1)
                local i=0 entry choice
                echo ""
                for entry in "${DNS_PROVIDERS[@]}"; do
                    i=$((i + 1))
                    echo -e "  ${BLUE}${i})${NC} $(cut -d'|' -f3 <<< "$entry")"
                done
                echo -e "  ${BLUE}0)${NC} 🔙 Volver"
                echo -e "\n${YELLOW}⚠ Si usas una VPN de trabajo con nombres internos, puede que necesites el DNS automático${NC}"
                read -r -p "📌 Proveedor: " choice
                if [ -z "$choice" ] || [ "$choice" = 0 ]; then
                    continue
                elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#DNS_PROVIDERS[@]} ]; then
                    entry=${DNS_PROVIDERS[$((choice - 1))]}
                    set_dns "${entry%%|*}"
                else
                    log_error "Opción inválida"
                fi
                ;;
            2) set_fastest_dns ;;
            3) reset_dns ;;
            4)
                if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == bbr* ]]; then
                    confirm "${BLUE}BBR ya está activo. ¿Desactivarlo?${NC}" && disable_bbr
                else
                    enable_bbr
                fi
                ;;
            5)
                if [ -f "$NM_WIFI_CONF" ]; then
                    confirm "${BLUE}El ahorro del Wi-Fi ya está desactivado. ¿Restaurarlo?${NC}" && enable_wifi_powersave
                else
                    disable_wifi_powersave
                fi
                ;;
            6) install_recommended_drivers ;;
            7) update_firmware ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
    done
}

# ============================================================
# OPCIÓN 17: ENERGÍA Y RENDIMIENTO (COLOR: AMARILLO)
# ============================================================

is_laptop() {
    ls /sys/class/power_supply/BAT* &> /dev/null
}

current_power_profile() {
    if command -v tlp &> /dev/null && systemctl is-enabled --quiet tlp 2>/dev/null; then
        echo "TLP"
    elif command -v powerprofilesctl &> /dev/null; then
        powerprofilesctl get 2>/dev/null
    else
        echo "desconocido"
    fi
}

# Perfiles de power-profiles-daemon: performance | balanced | power-saver
power_profiles_available() {
    powerprofilesctl list 2>/dev/null | grep -oE '^[ *]*[a-z-]+:' | tr -d ' *:' | tr '\n' ' '
}

# Perfil de rendimiento para juegos. Si el equipo no lo ofrece (depende de la CPU y la
# BIOS) no es un error: GameMode ya pone la CPU al máximo mientras hay un juego abierto.
set_gaming_power() {
    if command -v powerprofilesctl &> /dev/null && powerprofilesctl list 2>/dev/null | grep -q 'performance:'; then
        set_power_profile performance
        return
    fi
    log_warning "Tu equipo no ofrece el perfil de energía 'rendimiento' (depende de la CPU y la BIOS)"
    echo -e "  ${YELLOW}ℹ No hace falta: GameMode pone la CPU al máximo automáticamente mientras juegas${NC}"
}

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

# Portátil: TLP. Escritorio: perfil de ahorro de power-profiles-daemon
enable_power_saving() {
    if is_laptop; then
        install_tlp
    else
        set_power_profile power-saver
    fi
}

baloo_cmd() {
    command -v balooctl6 || command -v balooctl
}

# Baloo indexa todos los archivos para la búsqueda: consume CPU, disco y batería
disable_baloo() {
    local cmd
    cmd=$(baloo_cmd) || { echo -e "  ${YELLOW}ℹ Baloo no está instalado${NC}"; return 0; }
    run "No se pudo desactivar Baloo" "$cmd" disable && log_success "Indexador de archivos Baloo desactivado"
}

# Servicio del indexador de GNOME (LocalSearch en versiones nuevas, Tracker en las anteriores)
gnome_indexer_unit() {
    local unit
    for unit in localsearch-3.service tracker-miner-fs-3.service; do
        if systemctl --user cat "$unit" &> /dev/null; then
            echo "$unit"
            return 0
        fi
    done
    return 1
}

indexer_disabled() {
    local cmd unit
    if cmd=$(baloo_cmd); then
        "$cmd" status 2>/dev/null | grep -qi 'disabled\|desactivad'
    elif unit=$(gnome_indexer_unit); then
        [ "$(systemctl --user is-enabled "$unit" 2>/dev/null)" = masked ]
    else
        return 1
    fi
}

# El indexador recorre todos los archivos para la búsqueda: consume CPU, disco y batería
disable_indexer() {
    local unit
    if baloo_cmd > /dev/null; then
        disable_baloo
    elif unit=$(gnome_indexer_unit); then
        run "No se pudo desactivar el indexador" systemctl --user mask --now "$unit" \
            && log_success "Indexador de archivos desactivado (${unit%%-*})"
    else
        echo -e "  ${YELLOW}ℹ No hay indexador de archivos activo en ${DESKTOP_NAME}${NC}"
    fi
}

enable_indexer() {
    local unit
    if baloo_cmd > /dev/null; then
        enable_baloo
    elif unit=$(gnome_indexer_unit); then
        run "No se pudo activar el indexador" systemctl --user unmask "$unit" \
            && systemctl --user start "$unit" 2>> "$LOG_FILE"
        log_success "Indexador de archivos activado (${unit%%-*})"
    else
        echo -e "  ${YELLOW}ℹ No hay indexador de archivos en ${DESKTOP_NAME}${NC}"
    fi
}

enable_baloo() {
    local cmd
    cmd=$(baloo_cmd) || { log_error "Baloo no está instalado"; return 1; }
    run "No se pudo activar Baloo" "$cmd" enable && log_success "Indexador de archivos Baloo activado"
}

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
PROTON_GE_LIST="$STATE_DIR/proton-ge.txt"

# Activa Proton para todos los juegos (Steam → Configuración → Compatibilidad).
# El ajuste vive en config.vdf, que Steam crea la primera vez que se abre.
enable_steam_play() {
    local cfg tmp
    cfg="$(steam_dir)/config/config.vdf"
    if [ ! -f "$cfg" ]; then
        log_info "Abre Steam una vez e inicia sesión. Proton ya está activo para los juegos verificados;"
        log_info "para todos: Steam → Configuración → Compatibilidad → 'Activar Steam Play para todos los demás títulos'"
        log_info "(o, con Steam cerrado, usa la opción 17 → 6 y se activa solo)"
        return 0
    fi
    if pgrep -x steam &> /dev/null; then
        log_warning "Steam está abierto: ciérralo y usa la opción 17 → 6 para activar Proton en todos los juegos"
        return 0
    fi
    tmp=$(mktemp)
    if steam_play_vdf < "$cfg" > "$tmp"; then
        cp "$cfg" "$cfg.bak"
        mv "$tmp" "$cfg"
        log_success "Proton activado para todos los juegos (Proton Experimental; copia en config.vdf.bak)"
    else
        rm -f "$tmp"
        log_info "Steam ya tiene elegida una versión de Proton para todos los juegos: no se cambia"
    fi
}

# Agrega a config.vdf la versión de Proton para "todos los demás títulos" (la entrada "0").
# Falla (sin salida útil) si ya hay una elegida o si el archivo no tiene la forma esperada.
steam_play_vdf() {
    awk '
        function path(   s, i) { s = ""; for (i = 1; i <= d; i++) s = s "/" tolower(st[i]); return s }
        function tabs(n,   s) { s = ""; while (n-- > 0) s = s "\t"; return s }
        function entry(t) {
            print t "\"0\""; print t "{"
            print t "\t\"name\"\t\t\"proton_experimental\""
            print t "\t\"config\"\t\t\"\""
            print t "\t\"priority\"\t\t\"75\""
            print t "}"
        }
        { lines[NR] = $0 }
        END {
            base = "/installconfigstore/software/valve/steam"
            # Primera pasada: ¿ya existe la entrada "0"? ¿existe CompatToolMapping?
            d = 0
            for (n = 1; n <= NR; n++) {
                l = lines[n]
                if (l ~ /^[ \t]*"[^"]*"[ \t]*$/) { k = l; gsub(/^[ \t]*"|"[ \t]*$/, "", k); pend = k }
                else if (l ~ /^[ \t]*\{[ \t]*$/) { st[++d] = pend; p = path()
                    if (p == base "/compattoolmapping") mapping = 1
                    if (p == base "/compattoolmapping/0") exit 1 }
                else if (l ~ /^[ \t]*\}[ \t]*$/) d--
            }
            if (d != 0) exit 1
            # Segunda pasada: copia el archivo e inserta lo que falta
            for (n = 1; n <= NR; n++) {
                l = lines[n]; print l
                if (l ~ /^[ \t]*"[^"]*"[ \t]*$/) { k = l; gsub(/^[ \t]*"|"[ \t]*$/, "", k); pend = k }
                else if (l ~ /^[ \t]*\{[ \t]*$/) { st[++d] = pend; p = path(); t = tabs(d)
                    if (!done && mapping && p == base "/compattoolmapping") { entry(t); done = 1 }
                    if (!done && !mapping && p == base) {
                        print t "\"CompatToolMapping\""; print t "{"; entry(t "\t"); print t "}"; done = 1 } }
                else if (l ~ /^[ \t]*\}[ \t]*$/) d--
            }
            exit !done
        }'
}

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

# Quita las versiones de Proton-GE que instaló el script
remove_proton_ge() {
    local dirs=() d
    [ -f "$PROTON_GE_LIST" ] && mapfile -t dirs < <(sort -u "$PROTON_GE_LIST")
    mapfile -t dirs < <(for d in "${dirs[@]}"; do [ -d "$d" ] && [[ "$(basename "$d")" == GE-Proton* ]] && echo "$d"; done)
    if [ ${#dirs[@]} -eq 0 ]; then
        echo -e "${YELLOW}ℹ No hay versiones de Proton-GE instaladas por el script${NC}"
        rm -f "$PROTON_GE_LIST"
        return 0
    fi
    printf "  ${RED}•${NC} %s\n" "${dirs[@]##*/}"
    confirm "${RED}¿Quitar estas versiones de Proton-GE? Los juegos que las usen vuelven al Proton oficial${NC}" || return 0
    rm -rf "${dirs[@]}"
    rm -f "$PROTON_GE_LIST"
    log_success "Proton-GE quitado"
}

power_menu() {
    while true; do
        clear
        echo -e "${YELLOW}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    🔋 ENERGÍA Y RENDIMIENTO                      ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "${YELLOW}⚡ Perfil actual: ${BOLD}$(current_power_profile)${NC}"
        is_laptop && echo -e "${YELLOW}💻 Portátil detectado${NC}"
        echo ""
        echo -e "  ${YELLOW}1)${NC} Rendimiento máximo"
        echo -e "  ${YELLOW}2)${NC} Equilibrado"
        echo -e "  ${YELLOW}3)${NC} Ahorro de energía"
        echo -e "  ${YELLOW}4)${NC} TLP: ahorro avanzado de batería para portátiles"
        echo -e "  ${YELLOW}5)${NC} Activar/desactivar el indexador de archivos (Baloo / Tracker)"
        echo -e "  ${YELLOW}6)${NC} Herramientas de juego (GameMode, MangoHud, Steam y Proton)"
        echo -e "\n  ${YELLOW}0)${NC} 🔙 Volver"
        echo ""
        read -r -p "📌 Opción (0-6): " power_option

        case $power_option in
            1) set_power_profile performance ;;
            2) set_power_profile balanced ;;
            3) set_power_profile power-saver ;;
            4) confirm "${YELLOW}¿Instalar TLP?${NC}" && install_tlp ;;
            5)
                local cmd
                if indexer_disabled; then
                    enable_indexer
                else
                    disable_indexer
                fi
                ;;
            6)
                install_gaming_tools
                if steam_installed; then
                    enable_steam_play
                elif has_desktop && confirm "${YELLOW}¿Instalar Steam (incluye Proton para juegos de Windows)?${NC}"; then
                    install_steam
                fi
                if has_desktop && confirm "${YELLOW}¿Instalar Proton-GE (versión de la comunidad, más compatible)?${NC}"; then
                    install_proton_ge
                fi
                ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
    done
}

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

# Valor de fábrica de los ajustes que cambia el script (los demás vuelven al reiniciar)
sysctl_default() {
    case $1 in
        vm.swappiness) echo 60 ;;
        vm.vfs_cache_pressure) echo 100 ;;
        net.ipv4.tcp_congestion_control) echo cubic ;;
        net.core.default_qdisc) echo fq_codel ;;
        *) return 1 ;;
    esac
}

restore_sysctl_defaults() {
    if [ ! -s "$SYSCTL_FILE" ]; then
        echo -e "  ${GREEN}✓ No hay ajustes del sistema cambiados por el script${NC}"
        return 0
    fi
    local key value def
    echo -e "${YELLOW}📋 Ajustes que vuelven a su valor original:${NC}"
    while read -r key _ value; do
        [ -n "$key" ] || continue
        if def=$(sysctl_default "$key"); then
            sudo sysctl -w "$key=$def" >> "$LOG_FILE" 2>&1
            echo -e "  • $key: $value → $def"
        else
            echo -e "  • $key: $value → valor de fábrica (al reiniciar)"
        fi
    done < "$SYSCTL_FILE"
    sudo rm -f "$SYSCTL_FILE" "$BBR_MODULES_FILE"
    # Vuelve a aplicar los valores que definen Ubuntu y los demás paquetes
    run "No se pudieron recargar los ajustes del sistema" sudo sysctl --system \
        && log_success "Ajustes del sistema restaurados"
}

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

# ============================================================
# OPCIÓN 3: INFORMACIÓN DEL SISTEMA Y HARDWARE (COLOR: CIAN)
# ============================================================

# Cada sección imprime texto sin colores: así sirve para la pantalla, para buscar
# y para guardar el informe. Con INFO_QUIET=true no pregunta ni descarga nada.
INFO_QUIET=false

info_title() {
    echo ""
    echo "▶ $1"
}

# Temperatura de la CPU desde el kernel (no necesita programas extra)
cpu_temperature() {
    local dir name temp
    for dir in /sys/class/hwmon/hwmon*; do
        name=$(cat "$dir/name" 2>/dev/null)
        case $name in
            k10temp|coretemp|zenpower|cpu_thermal|acpitz)
                temp=$(cat "$dir/temp1_input" 2>/dev/null) || continue
                echo "$((temp / 1000))°C"
                return 0 ;;
        esac
    done
    return 1
}

info_summary() {
    local temp
    info_title "RESUMEN"
    echo "  Sistema:    $(os_release_value PRETTY_NAME) · ${FLAVOR_NAME} (${DESKTOP_NAME}, sesión ${XDG_SESSION_TYPE:-sin escritorio})"
    echo "  Kernel:     $(uname -r)"
    echo "  Encendido:  $(LC_ALL=C uptime -p | sed -e 's/^up //' -e 's/weeks/semanas/; s/week/semana/' \
        -e 's/days/días/; s/day/día/; s/hours/horas/; s/hour/hora/; s/minutes/minutos/; s/minute/minuto/')"
    echo "  CPU:        $(LC_ALL=C lscpu | sed -n 's/^Model name: *//p' | head -1) ($(nproc) hilos)"
    LC_ALL=C lspci 2>/dev/null | grep -Ei 'vga|3d controller|display controller' | sed 's/^[^ ]* [^:]*: /  GPU:        /'
    free -h | awk '/^Mem:/ {print "  RAM:        " $3 " en uso de " $2} /^Swap:/ {print "  Swap/ZRAM:  " $3 " en uso de " $2}'
    df -h / | awk 'NR == 2 {print "  Disco (/):  " $3 " en uso de " $2 " (" $5 ")"}'
    temp=$(cpu_temperature) && echo "  Temp. CPU:  $temp"
}

info_cpu_ram() {
    info_title "CPU"
    LC_ALL=C lscpu | grep -E '^(Model name|CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|CPU max MHz|CPU min MHz|L3 cache|Virtualization):' \
        | sed -e 's/^Model name:/Modelo:/' -e 's/^CPU(s):/Hilos:/' -e 's/^Thread(s) per core:/Hilos por núcleo:/' \
              -e 's/^Core(s) per socket:/Núcleos:/' -e 's/^CPU max MHz:/Frecuencia máxima (MHz):/' \
              -e 's/^CPU min MHz:/Frecuencia mínima (MHz):/' -e 's/^L3 cache:/Caché L3:/' -e 's/^Virtualization:/Virtualización:/' \
              -e 's/  */ /g; s/^/  /'
    info_title "MEMORIA RAM"
    free -h | awk '/^Mem:/ {print "  Total " $2 " · en uso " $3 " · disponible " $7}'
    if command -v dmidecode &> /dev/null; then
        # Un bloque "Memory Device" por ranura de la placa
        LC_ALL=C sudo dmidecode -t memory 2>/dev/null | awk -F': ' '
            /^Memory Device/ { if (slot != "") out(); size = type = speed = maker = slot = ""; next }
            /^\tSize:/ { size = $2 }
            /^\tType:/ { type = $2 }
            /^\tConfigured Memory Speed:/ { speed = $2 }
            /^\tSpeed:/ { if (speed == "" || speed == "Unknown") speed = $2 }
            /^\tManufacturer:/ { maker = $2 }
            /^\tLocator:/ { slot = $2 }
            function out() {
                if (size ~ /No Module|^$/) printf "  Ranura %-12s vacía\n", slot
                else printf "  Ranura %-12s %s %s a %s (%s)\n", slot, size, type, speed, maker
            }
            END { if (slot != "") out() }'
    fi
}

info_gpu() {
    info_title "TARJETA GRÁFICA"
    LC_ALL=C lspci -k 2>/dev/null | awk '
        /^[^\t]/ { show = ($0 ~ /VGA|3D controller|Display controller/) }
        show && /^[^\t]/ { sub(/^[^ ]+ [^:]+: /, ""); print "  " $0 }
        show && /Kernel driver in use/ { sub(/.*: /, ""); print "    Driver en uso: " $0 }'
    if LC_ALL=C lspci -k 2>/dev/null | grep -A3 -i nvidia | grep -q 'driver in use: nouveau'; then
        echo "  ⚠ La NVIDIA usa el driver libre 'nouveau': para juegos instala el de NVIDIA (opción 16 → 6)"
    fi
}

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

info_temps() {
    local dir name file label value found=false
    info_title "TEMPERATURAS Y VENTILADORES"
    for dir in /sys/class/hwmon/hwmon*; do
        name=$(cat "$dir/name" 2>/dev/null) || continue
        for file in "$dir"/temp*_input "$dir"/fan*_input; do
            [ -f "$file" ] || continue
            value=$(cat "$file" 2>/dev/null) || continue
            label=$(cat "${file%_input}_label" 2>/dev/null || basename "${file%_input}")
            if [[ "$file" == *temp* ]]; then
                printf "  %-14s %-12s %3s°C\n" "$name" "$label" "$((value / 1000))"
            else
                printf "  %-14s %-12s %s RPM\n" "$name" "$label" "$value"
            fi
            found=true
        done
    done
    $found || echo "  No hay sensores disponibles"
}

info_network() {
    local iface speed
    info_title "RED"
    ip -br addr 2>/dev/null | grep -v '^lo ' | sed 's/^/  /'
    echo "  Salida a internet por: $(ip route show default 2>/dev/null | awk '{print $5; exit}')"
    for iface in /sys/class/net/*; do
        speed=$(cat "$iface/speed" 2>/dev/null) || continue
        [ "${speed:-0}" -gt 0 ] 2>/dev/null && echo "  Velocidad del enlace de ${iface##*/}: $speed Mb/s"
    done
    if command -v nmcli &> /dev/null; then
        LC_ALL=C nmcli -t -f ACTIVE,SSID,SIGNAL,RATE,SECURITY dev wifi 2>/dev/null | awk -F: '$1 == "yes" {
            print "  Wi-Fi conectado: " $2 " · señal " $3 "% · " $4 " · " $5 }'
    fi
    echo "  DNS: $(current_dns) · TCP: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
}

info_battery() {
    local bat full design health found=false
    info_title "BATERÍA"
    for bat in /sys/class/power_supply/BAT*; do
        [ -d "$bat" ] || continue
        found=true
        full=$(cat "$bat/energy_full" 2>/dev/null || cat "$bat/charge_full" 2>/dev/null)
        design=$(cat "$bat/energy_full_design" 2>/dev/null || cat "$bat/charge_full_design" 2>/dev/null)
        echo "  ${bat##*/}: $(cat "$bat/manufacturer" 2>/dev/null) $(cat "$bat/model_name" 2>/dev/null)"
        echo "    Carga: $(cat "$bat/capacity" 2>/dev/null)% · estado: $(cat "$bat/status" 2>/dev/null)"
        if [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ]; then
            health=$((full * 100 / design))
            echo "    Salud: ${health}% de la capacidad original"
        fi
        [ -f "$bat/cycle_count" ] && echo "    Ciclos de carga: $(cat "$bat/cycle_count")"
    done
    $found || echo "  No hay batería (equipo de escritorio)"
}

info_usb() {
    info_title "USB Y PERIFÉRICOS"
    if command -v lsusb &> /dev/null; then
        lsusb | sed 's/^Bus [0-9]* Device [0-9]*: ID [0-9a-f:]* /  /' | grep -vi 'root hub'
    else
        echo "  (usbutils no está instalado)"
    fi
}

info_diagnostics() {
    info_title "SERVICIOS QUE FALLARON"
    { LC_ALL=C systemctl --failed --no-legend --plain 2>/dev/null; LC_ALL=C systemctl --user --failed --no-legend --plain 2>/dev/null; } \
        | sed 's/^/  /' | grep . || echo "  Ninguno"
    info_title "ERRORES DEL ÚLTIMO ARRANQUE (los 15 más recientes)"
    LC_ALL=C sudo journalctl -b -p err --no-pager -q 2>/dev/null | tail -15 | cut -c1-160 | sed 's/^/  /' | grep . || echo "  Ninguno"
    info_title "TIEMPO DE ARRANQUE"
    LC_ALL=C systemd-analyze 2>/dev/null | head -1 | sed 's/^/  /'
    echo "  Lo que más tarda:"
    LC_ALL=C systemd-analyze blame 2>/dev/null | head -8 | sed 's/^ */    /'
    info_title "PROCESOS QUE MÁS CONSUMEN"
    echo "  Por CPU:"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -6 | sed 's/^/    /'
    echo "  Por memoria:"
    ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -6 | sed 's/^/    /'
}

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

# Quita datos personales antes de compartir: números de serie, MAC, IP, UUID,
# nombre de usuario, nombre del equipo y red Wi-Fi
privacy_filter() {
    local host
    host=$(hostname)
    sed -E \
        -e 's/(Serial( Number)?|serial)( *[:=] *).*/\1\3(oculto)/' \
        -e 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/XX:XX:XX:XX:XX:XX/g' \
        -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]+)?\b/x.x.x.x/g' \
        -e 's/\b([0-9a-fA-F]{0,4}:){3,7}[0-9a-fA-F]{1,4}(\/[0-9]+)?\b/x:x:x:x/g' \
        -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/uuid-oculto/g' \
        -e 's/(Wi-Fi conectado: )[^·]*/\1(oculta) /' \
        -e "s/\\b${USER}\\b/usuario/g" \
        -e "s/\\b${host}\\b/equipo/g"
}

info_search() {
    local report term
    report=$(mktemp)
    echo -e "${CYAN}⏳ Reuniendo toda la información...${NC}"
    info_full_report > "$report" 2>/dev/null
    while true; do
        echo ""
        read -r -p "🔎 Palabra a buscar (por ejemplo nvidia, temp, wifi, error; Enter = volver): " term
        [ -n "$term" ] || break
        local matches
        # Solo en el contenido, no en los títulos de las secciones
        matches=$(awk -v t="$term" 'BEGIN {t = tolower(t)}
            /^▶ / {sec = substr($0, 5); next}
            index(tolower($0), t) {print "[" sec "]\t" $0}' "$report")
        if [ -z "$matches" ]; then
            echo -e "${YELLOW}  No aparece \"$term\"${NC}"
            continue
        fi
        echo -e "${GREEN}  $(wc -l <<< "$matches") resultados:${NC}"
        local sec line
        while IFS=$'\t' read -r sec line; do
            printf "  ${CYAN}%s${NC} %s\n" "$sec" "$(GREP_COLORS='mt=01;33' grep --color=always -i -F -- "$term" <<< "${line# }")"
        done <<< "$matches"
    done
    rm -f "$report"
}

info_save_report() {
    local file
    file="$HOME/informe-sistema-$(date +%Y%m%d-%H%M).txt"
    echo -e "${CYAN}⏳ Reuniendo toda la información...${NC}"
    info_full_report 2>/dev/null | privacy_filter > "$file"
    log_success "Informe guardado en: $file"
    echo -e "${CYAN}ℹ Se ocultaron números de serie, MAC, IP, UUID, usuario, nombre del equipo y red Wi-Fi.${NC}"
    echo -e "${CYAN}  Revísalo antes de compartirlo.${NC}"
}

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

# Resumen en castellano del informe de Lynis
lynis_summary() {
    local report="$1" index warnings suggestions
    index=$(sed -n 's/^hardening_index=//p' "$report")
    warnings=$(grep -c '^warning\[\]=' "$report")
    suggestions=$(grep -c '^suggestion\[\]=' "$report")
    echo -e "\n${CYAN}══════════════════ 🛡️ RESUMEN DE LA AUDITORÍA ══════════════════${NC}"
    if [ -n "$index" ]; then
        if [ "$index" -ge 75 ]; then
            echo -e "  Puntaje de seguridad: ${GREEN}${BOLD}$index/100${NC} (bueno)"
        elif [ "$index" -ge 60 ]; then
            echo -e "  Puntaje de seguridad: ${YELLOW}${BOLD}$index/100${NC} (aceptable)"
        else
            echo -e "  Puntaje de seguridad: ${RED}${BOLD}$index/100${NC} (mejorable)"
        fi
    fi
    echo -e "  ${RED}⚠ Advertencias: $warnings${NC}   ${YELLOW}💡 Sugerencias: $suggestions${NC}"
    if [ "$warnings" -gt 0 ]; then
        echo -e "\n${RED}Advertencias (lo más importante):${NC}"
        grep '^warning\[\]=' "$report" | cut -d'|' -f1,2 | sed 's/^warning\[\]=/  • [/; s/|/] /'
    fi
    if [ "$suggestions" -gt 0 ]; then
        echo -e "\n${YELLOW}Primeras sugerencias (en inglés, como las da Lynis):${NC}"
        grep '^suggestion\[\]=' "$report" | grep -v '^suggestion\[\]=LYNIS|' | head -12 \
            | cut -d'|' -f1,2 | sed 's/^suggestion\[\]=/  • [/; s/|/] /' | cut -c1-96
    fi
    echo -e "\n${CYAN}ℹ Cada código (por ejemplo SSH-7408) se explica en https://cisofy.com/lynis/controls/${NC}"
    echo -e "${CYAN}  Lynis solo revisa: no cambia nada del sistema.${NC}"
}

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

# ------------------------------------------------------------
# auditd con reglas propias
# ------------------------------------------------------------
audit_rules_active() { [ -f "$AUDIT_RULES_FILE" ]; }

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

show_audit_events() {
    if ! command -v aureport &> /dev/null; then
        echo -e "${YELLOW}ℹ El registro de auditoría no está activo${NC}"
        return 0
    fi
    echo -e "${CYAN}📝 Cambios registrados por categoría (desde que se activó):${NC}\n"
    sudo aureport -k --summary -i 2>/dev/null | sed 's/^/  /'
    echo -e "\n${CYAN}Últimos cambios en usuarios, sudo y SSH:${NC}"
    local k
    for k in identidad sudo ssh; do sudo ausearch -k "$k" -i 2>/dev/null; done \
        | awk '/^type=SYSCALL/ {
            t = $0; sub(/.*msg=audit\(/, "", t); sub(/\).*/, "", t); c = ""; a = ""; key = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^comm=/) c = substr($i, 6)
                if ($i ~ /^auid=/) a = substr($i, 6)
                if ($i ~ /^key=/) key = substr($i, 5)
            }
            print "  " t "  " key "  " c " (usuario " a ")" }' | tail -10
    echo -e "\n${CYAN}ℹ Detalle completo: sudo ausearch -k identidad -i   (categorías: identidad, sudo, ssh,${NC}"
    echo -e "${CYAN}  hora, red, tareas, servicios, repositorios, modulos, montajes, sesiones)${NC}"
}

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

# ------------------------------------------------------------
# linaudit (Alexia Michelle, AGPL-3.0-or-later, https://lexiworks.dev/linaudit):
# auditoría de solo lectura, en castellano, con puntaje de 1 a 10.
# Todavía no publica binarios ni está en los repositorios, así que se compila desde su código
# oficial en una carpeta temporal (con Rust temporal si el del sistema es viejo) y se borra todo
# al terminar. Opcionalmente queda instalado en /usr/local/bin, con su opción para quitarlo.
# Si algún día está en los repositorios de la distro, se usa ese paquete.
# ------------------------------------------------------------
LINAUDIT_GIT="https://github.com/alexiarstein/linaudit"
LINAUDIT_SRC_URL="https://codeload.github.com/alexiarstein/linaudit/tar.gz/refs/heads/main"
LINAUDIT_COMMIT=""

# Borra la carpeta temporal de compilación (solo si es una de las creadas en /var/tmp/linaudit.*)
linaudit_cleanup() {
    case "$1" in
        /var/tmp/linaudit.?*) [ -d "$1" ] && rm -rf -- "$1" ;;
    esac
}
LINAUDIT_BIN="/usr/local/bin/linaudit"
LINAUDIT_STATE="$STATE_DIR/linaudit.txt"
LINAUDIT_MIN_RUST="1.85"

# ¿La versión $1 es igual o más nueva que $2?
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# Compilador de C (Rust lo necesita para enlazar): se instala y queda registrado si falta
linaudit_need_cc() {
    command -v cc &> /dev/null && return 0
    echo -e "${YELLOW}ℹ Para compilar hace falta un compilador de C (gcc, ~40 MB; se quita en 10 → 1)${NC}"
    confirm "${CYAN}¿Instalar gcc?${NC}" || return 1
    if declare -F apt_install_recorded > /dev/null; then
        apt_update
        apt_install_recorded gcc libc6-dev
    else
        pkg_install_recorded gcc
    fi
}

# Deja en LINAUDIT_CARGO un cargo >= 1.85: el del sistema o uno temporal dentro de $1
linaudit_get_cargo() {
    local tmp="$1" v triple url
    if command -v cargo &> /dev/null; then
        v=$(cargo --version 2>/dev/null | awk '{print $2}')
        if version_ge "${v%%-*}" "$LINAUDIT_MIN_RUST"; then
            LINAUDIT_CARGO=(cargo)
            return 0
        fi
    fi
    triple="$(uname -m)-unknown-linux-gnu"
    url="https://static.rust-lang.org/rustup/dist/$triple/rustup-init"
    echo -e "${BLUE}⬇ Bajando Rust temporal (rustup oficial, se borra al terminar)...${NC}"
    if ! curl -sSfL -o "$tmp/rustup-init" "$url" || ! curl -sSfL -o "$tmp/rustup-init.sha256" "$url.sha256"; then
        log_error "No se pudo descargar Rust (static.rust-lang.org)"
        return 1
    fi
    if [ "$(sha256sum "$tmp/rustup-init" | awk '{print $1}')" != "$(awk '{print $1}' "$tmp/rustup-init.sha256")" ]; then
        log_error "La descarga de Rust no coincide con su suma de comprobación: no se usa"
        return 1
    fi
    chmod +x "$tmp/rustup-init"
    export RUSTUP_HOME="$tmp/rustup" CARGO_HOME="$tmp/cargo"
    run_visible "No se pudo preparar Rust" "$tmp/rustup-init" -y --quiet --profile minimal \
        --default-toolchain stable --no-modify-path || return 1
    LINAUDIT_CARGO=("$tmp/cargo/bin/cargo")
}

# Compila linaudit en $1; deja el programa en $1/src/target/release/linaudit
linaudit_build() {
    local tmp="$1" free_mb
    free_mb=$(df -Pm "$tmp" | awk 'NR == 2 {print $4}')
    if [ "$free_mb" -lt 3000 ]; then
        log_error "Hacen falta ~3 GB libres en $(dirname "$tmp") para compilar (hay ${free_mb} MB)"
        return 1
    fi
    command -v curl &> /dev/null || { log_error "Falta curl"; return 1; }
    linaudit_need_cc || return 1
    linaudit_get_cargo "$tmp" || return 1
    echo -e "${BLUE}⬇ Bajando el código de linaudit (github.com/alexiarstein/linaudit)...${NC}"
    LINAUDIT_COMMIT=""
    if command -v git &> /dev/null && git clone -q --depth 1 "$LINAUDIT_GIT" "$tmp/src" >> "$LOG_FILE" 2>&1; then
        LINAUDIT_COMMIT=$(git -C "$tmp/src" rev-parse --short HEAD)
    else
        [ -d "$tmp/src/.git" ] && rm -rf -- "$tmp/src"
        mkdir -p "$tmp/src"
        if ! curl -sSfL "$LINAUDIT_SRC_URL" | tar -xz -C "$tmp/src" --strip-components=1; then
            log_error "No se pudo descargar el código de linaudit"
            return 1
        fi
    fi
    echo -e "${BLUE}🔨 Compilando (varios minutos la primera vez)...${NC}"
    export CARGO_HOME="${CARGO_HOME:-$tmp/cargo}" CARGO_TARGET_DIR="$tmp/src/target"
    (cd "$tmp/src" && run_visible "No se pudo compilar linaudit" "${LINAUDIT_CARGO[@]}" build --release --locked -p linaudit) \
        || return 1
    [ -x "$tmp/src/target/release/linaudit" ]
}

linaudit_run() {
    local bin="$1"
    echo -e "\n${CYAN}ℹ linaudit solo mira: no cambia nada. Pregunta qué tipo de equipo es (servidor, escritorio${NC}"
    echo -e "${CYAN}  o contenedor). En la pantalla final: ? muestra los atajos, y copia el arreglo, q sale.${NC}"
    pause
    sudo "$bin" --lang es
}

security_audit_linaudit() {
    clear
    echo -e "${CYAN}${BOLD}🔎 AUDITORÍA CON LINAUDIT${NC}\n"
    echo -e "linaudit, de ${BOLD}Alexia Michelle${NC} (licencia AGPL-3.0, https://lexiworks.dev/linaudit), revisa más de"
    echo -e "100 puntos en castellano: cuentas y sudo, SSH, permisos, contraseñas guardadas en texto, red y"
    echo -e "cortafuegos, actualizaciones, indicios de intrusión y apps de servidor. Da un puntaje de 1 a 10"
    echo -e "y explica cómo arreglar cada cosa. ${GREEN}Solo mira: no cambia nada.${NC}\n"

    if command -v linaudit &> /dev/null; then
        linaudit_run "$(command -v linaudit)"
        return
    fi
    # Cuando esté en los repositorios de la distro, se usa el paquete oficial
    if declare -F available_pkgs > /dev/null && [ -n "$(available_pkgs linaudit)" ]; then
        confirm "${CYAN}linaudit está en los repositorios oficiales. ¿Instalarlo? (se quita en 10 → 1)${NC}" || return 0
        apt_install_recorded linaudit || return 1
        record_installed linaudit "repositorios oficiales de la distro"
        linaudit_run "$(command -v linaudit)"
        return
    fi

    echo -e "${YELLOW}ℹ linaudit todavía no publica programas listos ni está en los repositorios: hay que compilarlo.${NC}"
    echo -e "   • Se baja su código oficial y se compila en una carpeta temporal (5 a 15 minutos, ~3 GB)."
    echo -e "   • Si tu Rust es viejo o no lo tienes, se usa uno temporal. Todo se borra al terminar."
    echo -e "   • Al final puedes dejarlo instalado para la próxima vez (se quita en 2 → 6).\n"
    confirm "${CYAN}¿Compilar y ejecutar linaudit?${NC}" || return 0

    local tmp
    tmp=$(mktemp -d /var/tmp/linaudit.XXXXXX) || return 1
    if ! linaudit_build "$tmp"; then
        linaudit_cleanup "$tmp"
        unset RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR
        return 1
    fi
    unset RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR
    log_success "linaudit compilado"
    linaudit_run "$tmp/src/target/release/linaudit"

    echo ""
    if confirm "${CYAN}¿Dejar linaudit instalado para usarlo cuando quieras (sudo linaudit)? (se quita en 2 → 6)${NC}"; then
        sudo install -m 0755 "$tmp/src/target/release/linaudit" "$LINAUDIT_BIN" \
            && sudo install -D -m 0644 "$tmp/src/doc/linaudit.1" /usr/local/share/man/man1/linaudit.1 \
            && sudo install -D -m 0644 "$tmp/src/doc/linaudit.es.1" /usr/local/share/man/es/man1/linaudit.1 \
            && { mkdir -p "$STATE_DIR"; echo "$(date '+%Y-%m-%d %H:%M')|compilado de github.com/alexiarstein/linaudit (rama main${LINAUDIT_COMMIT:+, commit $LINAUDIT_COMMIT})" > "$LINAUDIT_STATE"; } \
            && log_success "linaudit instalado en $LINAUDIT_BIN"
    fi
    linaudit_cleanup "$tmp"
    echo -e "${GREEN}✓ Carpeta temporal de compilación borrada (código, Rust temporal y archivos intermedios)${NC}"
}

remove_linaudit() {
    if [ ! -f "$LINAUDIT_STATE" ] && [ ! -x "$LINAUDIT_BIN" ]; then
        if grep -qx linaudit "$INSTALLED_LIST" 2>/dev/null; then
            echo -e "${YELLOW}ℹ linaudit vino de los repositorios: se quita en 10 → 1${NC}"
        else
            echo -e "${YELLOW}ℹ El script no instaló linaudit${NC}"
        fi
        return 0
    fi
    echo -e "linaudit instalado: $(cut -d'|' -f1 "$LINAUDIT_STATE" 2>/dev/null) ($(cut -d'|' -f2 "$LINAUDIT_STATE" 2>/dev/null))"
    confirm "${RED}¿Quitar linaudit?${NC}" || return 0
    sudo rm -f "$LINAUDIT_BIN" /usr/local/share/man/man1/linaudit.1 /usr/local/share/man/es/man1/linaudit.1
    rm -f "$LINAUDIT_STATE"
    log_success "linaudit quitado (tu elección de idioma en ~/.config/linaudit no se toca)"
}

security_menu() {
    local option
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                    🔒 AUDITORÍA DE SEGURIDAD                     ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo -e "${CYAN}🔍 Revisar:${NC}"
        echo -e "  ${CYAN}1)${NC} Revisar la seguridad con Lynis (puntaje y consejos; solo mira, no cambia nada)"
        echo -e "  ${CYAN}2)${NC} Revisar con linaudit, de Alexia Michelle (en castellano, puntaje de 1 a 10)"
        echo -e "\n${CYAN}📝 Registro de auditoría (auditd): quién y cuándo cambió usuarios, sudo, SSH...${NC}"
        if audit_rules_active; then
            echo -e "     Estado: ${GREEN}activo${NC} (reglas del script en $AUDIT_RULES_FILE)"
        else
            echo -e "     Estado: ${YELLOW}no activado${NC}"
        fi
        echo -e "  ${CYAN}3)${NC} Activar (o actualizar las reglas)"
        echo -e "  ${CYAN}4)${NC} Ver qué se registró"
        echo -e "  ${CYAN}5)${NC} Quitar (reglas y, si lo instaló el script, auditd)"
        echo -e "\n${CYAN}🧹 Herramientas:${NC}"
        echo -e "  ${CYAN}6)${NC} Quitar linaudit (si lo dejaste instalado)"
        echo -e "\n  ${CYAN}0)${NC} 🔙 Volver\n"
        read -r -p "📌 Opción (0-6): " option
        case $option in
            1) security_audit_lynis ;;
            2) security_audit_linaudit ;;
            3) enable_audit ;;
            4) show_audit_events ;;
            5) disable_audit ;;
            6) remove_linaudit ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        pause
    done
}

# Procesos en vivo: htop si está (o se ofrece instalar, ~400 KB); si no, top, que viene siempre
info_htop() {
    if ! command -v htop &> /dev/null && ! $INFO_QUIET; then
        echo -e "${CYAN}ℹ htop muestra los procesos en vivo con colores, la CPU por núcleo y la memoria (~400 KB).${NC}"
        if confirm "${CYAN}¿Instalar htop? (se quita en 10 → 1)${NC}"; then
            if declare -F apt_install_recorded > /dev/null; then
                apt_update
                apt_install_recorded htop
            else
                pkg_install_recorded htop
            fi
        fi
    fi
    $INFO_QUIET && return 0
    echo -e "${CYAN}ℹ Para salir pulsa q (F9 cierra un proceso, F6 cambia el orden)${NC}"
    sleep 2
    if command -v htop &> /dev/null; then
        htop
    else
        top
    fi
}

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

# ============================================================
# CREAR USB DE INSTALACIÓN (con dd), fácil y a prueba de errores
# - La ISO: una que ya tengas (la busca sola) o la descarga oficial, siempre verificada con
#   la suma (SHA-256 o SHA-512) que publica la propia distribución: sin suma, no se descarga
# - El pendrive: solo discos USB (o tarjetas SD), nunca el disco del sistema; si no hay,
#   espera a que lo conectes y lo detecta solo
# - Muestra qué tiene el pendrive y pide escribir BORRAR antes de grabar
# - Graba con dd, comprueba que se copió bien y lo expulsa
# ============================================================

# Distribuciones que se pueden descargar: clave|nombre|tipo|datos del tipo
# (las líneas que empiezan con "#" son los grupos del menú: "#título|ejemplos")
#   ubuntu:  carpeta|patrón (la última LTS se detecta sola)
#   lista:   url de la carpeta|archivo de sumas|patrón
#   fijo:    url de la carpeta|nombre de la ISO|archivo con su suma
#   carpeta: url|patrón de la subcarpeta de la versión (- = ninguna)|patrón|archivo de sumas,
#            o ".extensión" si cada ISO tiene su propio archivo de suma al lado
#   sf:      proyecto de SourceForge|carpeta|patrón|extensión del archivo de suma de cada ISO
#   pop:     variante (intel o nvidia)|patrón (API oficial de System76)
#   fedora:  subvariante|patrón (releases.json oficial de Fedora)
#   zorin:   edición|patrón (sumas de la página oficial de ayuda de Zorin)
#   gentoo:  carpeta de autobuilds|patrón (latest-iso.txt dice cuál es la última)
#   slackware: espejo oficial|patrón (suma MD5 y firma GPG oficial de Slackware)
#   nixos:   variante|patrón (la última versión estable, de channels.nixos.org)
#   enlace:  página de descarga|patrón (pide iniciar sesión: se explica cómo bajarla a mano)
# La subcarpeta de "carpeta" puede seguir con una ruta fija: "[0-9]+/isos/x86_64"
USB_DISTROS=(
    "#Ubuntu y sus derivadas|Ubuntu y sus sabores, KDE neon, Linux Mint, Zorin OS, Pop!_OS"
    "ubuntu|Ubuntu (GNOME), última LTS|ubuntu|releases|ubuntu-[0-9.]+-desktop-amd64\\.iso"
    "kubuntu|Kubuntu (KDE Plasma), última LTS|ubuntu|kubuntu|kubuntu-[0-9.]+-desktop-amd64\\.iso"
    "xubuntu|Xubuntu (Xfce, liviano), última LTS|ubuntu|xubuntu|xubuntu-[0-9.]+-desktop-amd64\\.iso"
    "lubuntu|Lubuntu (LXQt, el más liviano), última LTS|ubuntu|lubuntu|lubuntu-[0-9.]+-desktop-amd64\\.iso"
    "ubuntu-mate|Ubuntu MATE (escritorio clásico), última LTS|ubuntu|ubuntu-mate|ubuntu-mate-[0-9.]+-desktop-amd64\\.iso"
    "ubuntu-budgie|Ubuntu Budgie (moderno y sencillo), última LTS|ubuntu|ubuntu-budgie|ubuntu-budgie-[0-9.]+-desktop-amd64\\.iso"
    "server|Ubuntu Server, última LTS|ubuntu|releases|ubuntu-[0-9.]+-live-server-amd64\\.iso"
    "kdeneon|KDE neon User (el KDE Plasma más nuevo y estable, sobre Ubuntu LTS)|fijo|https://files.kde.org/neon/images/user/current|neon-user-current.iso|neon-user-current.iso.sha256sum"
    "kdeneon-testing|KDE neon Testing (Plasma en prueba, antes de salir: para probar)|fijo|https://files.kde.org/neon/images/testing/current|neon-testing-current.iso|neon-testing-current.iso.sha256sum"
    "kdeneon-unstable|KDE neon Unstable (lo último en desarrollo: puede fallar)|fijo|https://files.kde.org/neon/images/unstable/current|neon-unstable-current.iso|neon-unstable-current.iso.sha256sum"
    "mint|Linux Mint Cinnamon (la más fácil si vienes de Windows)|carpeta|https://mirrors.kernel.org/linuxmint/stable|[0-9.]+|linuxmint-[0-9.]+-cinnamon-64bit\\.iso|sha256sum.txt"
    "mint-xfce|Linux Mint Xfce (liviano)|carpeta|https://mirrors.kernel.org/linuxmint/stable|[0-9.]+|linuxmint-[0-9.]+-xfce-64bit\\.iso|sha256sum.txt"
    "mint-mate|Linux Mint MATE (clásico)|carpeta|https://mirrors.kernel.org/linuxmint/stable|[0-9.]+|linuxmint-[0-9.]+-mate-64bit\\.iso|sha256sum.txt"
    "zorin|Zorin OS Core (se parece a Windows o macOS)|zorin|Core|Zorin-OS-[0-9.]+-Core-64-bit(-r[0-9]+)?\\.iso"
    "pop|Pop!_OS (de System76, escritorio COSMIC)|pop|intel|pop-os_[0-9.]+_amd64_intel_[0-9]+\\.iso"
    "pop-nvidia|Pop!_OS para placas NVIDIA (trae el driver)|pop|nvidia|pop-os_[0-9.]+_amd64_nvidia_[0-9]+\\.iso"
    "#Debian y sus derivadas|Debian estable y testing, LMDE, MX Linux, Kali"
    "debian-kde|Debian estable con KDE Plasma (live)|lista|https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid|SHA256SUMS|debian-live-[0-9.]+-amd64-kde\\.iso"
    "debian-gnome|Debian estable con GNOME (live)|lista|https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid|SHA256SUMS|debian-live-[0-9.]+-amd64-gnome\\.iso"
    "debian-net|Debian estable netinst (instalador mínimo, baja el resto de internet)|lista|https://cdimage.debian.org/debian-cd/current/amd64/iso-cd|SHA256SUMS|debian-[0-9.]+-amd64-netinst\\.iso"
    "debian-testing-kde|Debian testing con KDE Plasma (live: la próxima versión, se arma cada semana)|lista|https://cdimage.debian.org/cdimage/weekly-live-builds/amd64/iso-hybrid|SHA256SUMS|debian-live-testing-amd64-kde\\.iso"
    "debian-testing-net|Debian testing netinst (la próxima versión, se arma cada semana)|lista|https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd|SHA256SUMS|debian-testing-amd64-netinst\\.iso"
    "lmde|LMDE: Linux Mint sobre Debian (Cinnamon)|lista|https://mirrors.kernel.org/linuxmint/debian|sha256sum.txt|lmde-[0-9.]+-cinnamon-64bit\\.iso"
    "mx|MX Linux Xfce (liviano y muy estable)|sf|mx-linux|Final/Xfce|MX-[0-9.]+_Xfce_x64\\.iso|sha256"
    "mx-kde|MX Linux KDE Plasma|sf|mx-linux|Final/KDE|MX-[0-9.]+_KDE_x64\\.iso|sha256"
    "kali|Kali Linux (seguridad y pruebas de intrusión, instalador)|lista|https://cdimage.kali.org/current|SHA256SUMS|kali-linux-[0-9.]+[a-z]?-installer-amd64\\.iso"
    "#Arch y sus derivadas|Arch, Manjaro, CachyOS, EndeavourOS"
    "arch|Arch Linux (instalación por terminal)|lista|https://geo.mirror.pkgbuild.com/iso/latest|sha256sums.txt|archlinux-[0-9.]+-x86_64\\.iso"
    "manjaro-kde|Manjaro KDE Plasma (Arch fácil, con instalador gráfico)|sf|manjarolinux|kde|manjaro-kde-[0-9.]+-[0-9]+-linux[0-9]+\\.iso|sha256"
    "manjaro-gnome|Manjaro GNOME|sf|manjarolinux|gnome|manjaro-gnome-[0-9.]+-[0-9]+-linux[0-9]+\\.iso|sha256"
    "manjaro-xfce|Manjaro Xfce (liviano)|sf|manjarolinux|xfce|manjaro-xfce-[0-9.]+-[0-9]+-linux[0-9]+\\.iso|sha256"
    "cachyos|CachyOS (Arch optimizado para velocidad, instalador gráfico)|sf|cachyos-arch|gui-installer/desktop|cachyos-desktop-linux-[0-9]+\\.iso|sha256"
    "endeavouros|EndeavourOS (Arch casi puro, con instalador gráfico)|carpeta|https://mirror.alpix.eu/endeavouros/iso|-|EndeavourOS_[A-Za-z_-]+-[0-9.]+\\.iso|.sha512sum"
    "#Fedora y la familia Red Hat|Fedora, CentOS Stream, AlmaLinux, Rocky Linux, Red Hat"
    "fedora|Fedora Workstation (GNOME)|fedora|Workstation|Fedora-Workstation-Live-.+\\.iso"
    "fedora-kde|Fedora KDE Plasma|fedora|KDE|Fedora-KDE-.+\\.iso"
    "centos|CentOS Stream (lo que será la próxima Red Hat, instalador completo ~10 GB)|carpeta|https://mirror.stream.centos.org|[0-9]+-stream/BaseOS/x86_64/iso|CentOS-Stream-[0-9]+-[0-9.]+-x86_64-dvd1\\.iso|.SHA256SUM"
    "alma|AlmaLinux (compatible con Red Hat, gratis; instalador completo ~10 GB)|carpeta|https://repo.almalinux.org/almalinux|[0-9]+/isos/x86_64|AlmaLinux-[0-9]+\\.[0-9]+-x86_64-dvd\\.iso|CHECKSUM"
    "rocky|Rocky Linux (compatible con Red Hat, gratis; instalador completo ~10 GB)|carpeta|https://download.rockylinux.org/pub/rocky|[0-9]+/isos/x86_64|Rocky-[0-9]+\\.[0-9]+-x86_64-dvd1?\\.iso|CHECKSUM"
    "rhel|Red Hat Enterprise Linux (pide iniciar sesión: te explico cómo)|enlace|https://developers.redhat.com/products/rhel/download|rhel-[0-9.]+-x86_64-(dvd|boot)\\.iso"
    "#openSUSE|Tumbleweed y Leap"
    "opensuse|openSUSE Tumbleweed (siempre al día)|fijo|https://download.opensuse.org/tumbleweed/iso|openSUSE-Tumbleweed-DVD-x86_64-Current.iso|openSUSE-Tumbleweed-DVD-x86_64-Current.iso.sha256"
    "leap|openSUSE Leap (estable, versión fija)|carpeta|https://download.opensuse.org/distribution/openSUSE-stable/offline|-|Leap-[0-9.]+-offline-installer-x86_64\\.install\\.iso|.sha256"
    "#Independientes e históricas|Slackware, Gentoo, Void Linux, NixOS"
    "slackware|Slackware (la más antigua que sigue viva, desde 1993)|slackware|https://mirrors.slackware.com/slackware|slackware64-[0-9.]+-install-dvd\\.iso"
    "gentoo|Gentoo LiveGUI (KDE Plasma; todo se compila a tu medida)|gentoo|https://distfiles.gentoo.org/releases/amd64/autobuilds|livegui-amd64-[0-9TZ]+\\.iso"
    "gentoo-min|Gentoo mínima (instalación por terminal)|gentoo|https://distfiles.gentoo.org/releases/amd64/autobuilds|install-amd64-minimal-[0-9TZ]+\\.iso"
    "void|Void Linux Xfce (independiente, sin systemd)|lista|https://repo-default.voidlinux.org/live/current|sha256sum.txt|void-live-x86_64-[0-9]+-xfce\\.iso"
    "nixos|NixOS (todo el sistema en un archivo de configuración)|nixos|graphical|nixos-graphical-.+-x86_64-linux\\.iso"
)

usb_download_dir() {
    local d
    d=$(xdg-user-dir DOWNLOAD 2>/dev/null)
    [ -n "$d" ] && [ "$d" != "$HOME" ] || d="$HOME/Descargas"
    [ -d "$d" ] || d="$HOME/Downloads"
    [ -d "$d" ] || { d="$HOME/Descargas"; mkdir -p "$d"; }
    echo "$d"
}

# Las listas en formato BSD ("SHA256 (archivo) = hash", Fedora, Rocky, Void...) pasan a "hash  archivo"
usb_norm_sums() {
    sed -E 's/^(SHA|MD)[0-9]* \(([^)]+)\) = ([0-9a-fA-F]+)[[:space:]]*$/\3  \2/'
}

# "hash archivo" de la versión más nueva que coincide con el patrón, dentro de una lista de sumas
usb_pick_from_sums() {
    local sums
    sums=$(usb_norm_sums <<< "$1")
    local pattern="$2"
    awk -v re="^${pattern}\$" '{f = $2; sub(/^\*/, "", f); if (f ~ re) print $1, f}' <<< "$sums" \
        | sort -k2,2V | tail -1
}

# Primera suma SHA-256 o SHA-512 de un archivo de suma (lo lee por la entrada)
usb_first_hash() {
    usb_norm_sums | grep -oiE '^[0-9a-f]+' | awk 'length($0) == 64 || length($0) == 128 {print; exit}'
}

# Suma de un archivo según el largo de la oficial: 128 = SHA-512, 32 = MD5 (Slackware), si no SHA-256
usb_hash_of() {
    case ${2:-64} in
        128) sha512sum "$1" ;;
        32) md5sum "$1" ;;
        *) sha256sum "$1" ;;
    esac | awk '{print $1}'
}

usb_hash_name() {
    case $1 in 128) echo SHA-512 ;; 32) echo MD5 ;; *) echo SHA-256 ;; esac
}

# Firma GPG de la ISO (Slackware): se comprueba con la llave oficial y su huella conocida
usb_check_signature() {
    [ -n "$USB_ISO_SIG" ] || return 0
    if ! command -v gpg &> /dev/null; then
        log_warning "No está gpg: solo se comprobó la suma $(usb_hash_name ${#USB_ISO_SHA})"
        return 0
    fi
    local g status=""
    g=$(mktemp -d)
    echo -e "${BLUE}🔏 Comprobando la firma oficial (GPG)...${NC}"
    if curl -sSfL -m 30 -o "$g/firma.asc" "$USB_ISO_SIG" && curl -sSfL -m 30 -o "$g/llave" "$USB_ISO_KEY" \
        && gpg --homedir "$g" --batch --quiet --import "$g/llave" 2>/dev/null; then
        status=$(gpg --homedir "$g" --batch --status-fd 1 --verify "$g/firma.asc" "$USB_ISO" 2>/dev/null)
    fi
    gpgconf --homedir "$g" --kill all &> /dev/null
    rm -rf -- "$g"
    if grep -q "^\[GNUPG:\] VALIDSIG .*$USB_ISO_KEYID" <<< "$status"; then
        log_success "Firma oficial correcta"
        return 0
    fi
    # Firma que no corresponde (ISO alterada o de otra llave): no se usa
    if grep -qE "^\[GNUPG:\] (BADSIG|VALIDSIG)" <<< "$status"; then
        log_error "La firma no es la oficial: la ISO no se usa"
        return 1
    fi
    log_warning "No se pudo comprobar la firma (sin internet o gpg no la acepta): queda comprobada solo con $(usb_hash_name ${#USB_ISO_SHA})"
    return 0
}

# Nombres de los enlaces de una página índice de un servidor (las carpetas sin la "/" final)
usb_index_names() {
    curl -sSfL -m 30 "$1/" 2>/dev/null | grep -oiE 'href="[^"?#]+"' \
        | sed -E 's/^href="//I; s/"$//; s#/$##; s#.*/##'
}

# De los nombres o rutas que llegan por la entrada, los que coinciden con el patrón (en su
# último tramo), ordenados de la versión más vieja a la más nueva según los números del nombre
usb_sorted() {
    local re="^$1\$" n base
    sort -u | while IFS= read -r n; do
        base=${n##*/}
        [[ "$base" =~ $re ]] && printf '%s\t%s\n' "$(sed 's/[^0-9.]//g' <<< "$base")" "$n"
    done | sort -t$'\t' -k1,1V | cut -f2
}

# Deja en USB_ISO_URL, USB_ISO_FILE y USB_ISO_SHA la descarga elegida
usb_resolve_download() {
    local entry="$1" key name type a b c d dist sums base="" picked="" url="" dirs=() iso rel json ver h
    USB_ISO_SIG="" USB_ISO_KEY="" USB_ISO_KEYID=""
    local tokens=() i
    IFS='|' read -r key name type a b c d <<< "$entry"
    case $type in
        ubuntu)
            # Las LTS de la más nueva a la más vieja: si un sabor todavía no sacó (o no saca)
            # la última LTS, se usa la anterior
            mapfile -t dirs < <(curl -sSfL -m 30 https://changelogs.ubuntu.com/meta-release-lts 2>/dev/null \
                | awk '/^Dist:/ {print $2}' | tac | head -2)
            [ ${#dirs[@]} -gt 0 ] || { log_error "No se pudo saber cuál es la última versión LTS de Ubuntu"; return 1; }
            for dist in "${dirs[@]}"; do
                if [ "$a" = releases ]; then
                    base="https://releases.ubuntu.com/$dist"
                else
                    base="https://cdimage.ubuntu.com/$a/releases/$dist/release"
                fi
                sums=$(curl -sSfL -m 30 "$base/SHA256SUMS" 2>/dev/null) || continue
                picked=$(usb_pick_from_sums "$sums" "$b")
                [ -n "$picked" ] && break
            done ;;
        fijo)
            # Una sola ISO con su archivo de suma (que puede nombrarla con la fecha en vez de "current")
            base="$a"
            sums=$(curl -sSfL -m 30 "$base/$c" 2>/dev/null) || sums=$(curl -sSfL -m 30 "$base/SHA256SUMS" 2>/dev/null)
            h=$(usb_first_hash <<< "$sums")
            [ -n "$h" ] && picked="$h $b" ;;
        lista)
            base="$a"
            sums=$(curl -sSfL -m 30 "$base/$b") || { log_error "No se pudo leer la lista de $name"; return 1; }
            picked=$(usb_pick_from_sums "$sums" "$c") ;;
        carpeta)
            # La subcarpeta de la versión más nueva (si recién salió y aún no tiene la lista
            # de sumas, se prueba con la anterior)
            if [ "$b" = - ]; then
                dirs=("$a")
            else
                # "[0-9]+/isos/x86_64": la versión más nueva y, dentro, siempre la misma ruta
                local sub=${b%%/*} rest=""
                [[ "$b" == */* ]] && rest="/${b#*/}"
                mapfile -t dirs < <(usb_index_names "$a" | usb_sorted "$sub" | tail -3 | tac | sed "s#^#$a/#; s#\$#$rest#")
            fi
            for base in "${dirs[@]}"; do
                if [[ "$d" == .* ]]; then
                    iso=$(usb_index_names "$base" | usb_sorted "$c" | tail -1)
                    [ -n "$iso" ] || continue
                    h=$(curl -sSfL -m 30 "$base/$iso$d" 2>/dev/null | usb_first_hash)
                    [ -n "$h" ] && picked="$h $iso"
                else
                    sums=$(curl -sSfL -m 30 "$base/$d" 2>/dev/null) || continue
                    picked=$(usb_pick_from_sums "$sums" "$c")
                fi
                [ -n "$picked" ] && break
            done ;;
        sf)
            # La lista de archivos de SourceForge (RSS) trae también las subcarpetas de versión
            rel=$(curl -sSfL -m 30 "https://sourceforge.net/projects/$a/rss?path=/$b&limit=100" 2>/dev/null \
                | grep -oE "https://sourceforge\\.net/projects/$a/files/[^<\"]+/download" \
                | sed -E "s#^https://sourceforge\\.net/projects/$a/files/##; s#/download\$##" \
                | usb_sorted "$c" | tail -1)
            if [ -n "$rel" ]; then
                base="https://downloads.sourceforge.net/project/$a/${rel%/*}"
                iso=${rel##*/}
                h=$(curl -sSfL -m 30 "$base/$iso.$d" 2>/dev/null | usb_first_hash)
                [ -n "$h" ] && picked="$h $iso"
            fi ;;
        pop)
            # La API de System76 da la ISO y su suma; se prueba de la versión más nueva a la más vieja
            for ver in 26.04 24.04 22.04; do
                json=$(curl -sSfL -m 30 "https://api.pop-os.org/builds/$ver/$a" 2>/dev/null) || continue
                url=$(grep -oE '"url" *: *"[^"]+\.iso"' <<< "$json" | sed -E 's/.*"([^"]+)"$/\1/' | head -1)
                h=$(grep -oE '"sha_sum" *: *"[0-9a-fA-F]+"' <<< "$json" | sed -E 's/.*"([^"]+)"$/\1/' | usb_first_hash)
                if [ -n "$url" ] && [ -n "$h" ]; then
                    picked="$h ${url##*/}"
                    break
                fi
                url=""
            done ;;
        fedora)
            # releases.json (el que usa Fedora Media Writer): la ISO x86_64 de la versión estable más nueva
            json=$(curl -sSfL -m 60 https://fedoraproject.org/releases.json 2>/dev/null)
            picked=$(tr -d '\n' <<< "$json" | sed 's/}[[:space:]]*,[[:space:]]*{/}\n{/g' \
                | grep -E '"arch" *: *"x86_64"' | grep -E "\"subvariant\" *: *\"$a\"" \
                | while IFS= read -r i; do
                    ver=$(grep -oE '"version" *: *"[^"]+"' <<< "$i" | sed -E 's/.*"([^"]+)"$/\1/')
                    url=$(grep -oE '"link" *: *"[^"]+\.iso"' <<< "$i" | sed -E 's/.*"([^"]+)"$/\1/')
                    h=$(grep -oE '"sha256" *: *"[0-9a-fA-F]{64}"' <<< "$i" | sed -E 's/.*"([^"]+)"$/\1/')
                    # Solo versiones estables (las Beta dicen "43 Beta")
                    [[ "$ver" =~ ^[0-9]+$ ]] && [ -n "$url" ] && [ -n "$h" ] && printf '%s %s %s\n' "$ver" "$h" "$url"
                done | sort -k1,1n | tail -1)
            if [ -n "$picked" ]; then
                url=${picked##* }
                picked="$(cut -d' ' -f2 <<< "$picked") ${url##*/}"
            fi ;;
        zorin)
            # Zorin publica las sumas en su página de ayuda, junto al nombre de cada ISO
            mapfile -t tokens < <(curl -sSfL -m 30 https://help.zorin.com/docs/getting-started/check-the-integrity-of-your-copy-of-zorin-os/ 2>/dev/null \
                | sed 's/<[^>]*>/\n/g' | grep -oiE "Zorin-OS-[0-9.]+-$a-64-bit(-r[0-9]+)?\\.iso|\\b[0-9a-f]{64}\\b")
            iso=$(printf '%s\n' "${tokens[@]}" | usb_sorted "$b" | tail -1)
            for i in "${!tokens[@]}"; do
                [ "${tokens[$i]}" = "$iso" ] || continue
                if [[ "${tokens[$((i + 1))]:-}" =~ ^[0-9a-fA-F]{64}$ ]]; then h=${tokens[$((i + 1))]}
                elif [ "$i" -gt 0 ] && [[ "${tokens[$((i - 1))]}" =~ ^[0-9a-fA-F]{64}$ ]]; then h=${tokens[$((i - 1))]}
                fi
                break
            done
            if [ -n "$iso" ] && [ -n "$h" ]; then
                picked="$h $iso"
                # Espejo oficial de kernel.org, carpeta de la versión principal (17, 18...)
                url="https://mirrors.edge.kernel.org/zorinos-isos/$(cut -d. -f1 <<< "${iso#Zorin-OS-}" | cut -d- -f1)/$iso"
            fi ;;
        gentoo)
            # latest-iso.txt: "20261124T170000Z/livegui-amd64-20261124T170000Z.iso tamaño"
            rel=$(curl -sSfL -m 30 "$a/latest-iso.txt" 2>/dev/null | grep -v '^#' | awk '{print $1}' | usb_sorted "$b" | tail -1)
            if [ -n "$rel" ]; then
                base="$a/${rel%/*}"
                iso=${rel##*/}
                h=$(curl -sSfL -m 30 "$base/$iso.sha256" 2>/dev/null | usb_first_hash)
                # Si no hay .sha256, la SHA-512 del archivo DIGESTS (que también trae BLAKE2)
                [ -n "$h" ] || h=$(curl -sSfL -m 30 "$base/$iso.DIGESTS" 2>/dev/null \
                    | awk '/^# SHA512 HASH/ {getline; print $1; exit}' | usb_first_hash)
                [ -n "$h" ] && picked="$h $iso"
            fi ;;
        slackware)
            # La versión estable más nueva; Slackware publica MD5 y firma GPG (se comprueban las dos)
            ver=$(usb_index_names "$a/slackware-iso" | usb_sorted 'slackware64-[0-9.]+-iso' | tail -1)
            ver=${ver#slackware64-}
            ver=${ver%-iso}
            if [ -n "$ver" ]; then
                base="$a/slackware-iso/slackware64-$ver-iso"
                iso="slackware64-$ver-install-dvd.iso"
                h=$(curl -sSfL -m 30 "$base/$iso.md5" 2>/dev/null | grep -oiE '^[0-9a-f]{32}' | head -1)
                if [ -n "$h" ]; then
                    picked="$h $iso"
                    USB_ISO_SIG="$base/$iso.asc"
                    USB_ISO_KEY="$a/slackware64-$ver/GPG-KEY"
                    # Huella de la llave de Slackware Linux Project <security@slackware.com>
                    USB_ISO_KEYID=EC5649DA401E22ABFA6736EF6A4463C040102233
                fi
            fi ;;
        nixos)
            # La estable más nueva ya publicada: salen a fin de mayo (AA.05) y de noviembre (AA.11)
            local y m cand
            y=$(date +%y); m=$(date +%m)
            for cand in "$y.11" "$y.05" "$((10#$y - 1)).11" "$((10#$y - 1)).05"; do
                [ "$(( ${cand%.*} * 100 + 10#${cand#*.} ))" -lt "$(( 10#$y * 100 + 10#$m ))" ] || continue
                url="https://channels.nixos.org/nixos-$cand/latest-nixos-$a-x86_64-linux.iso"
                sums=$(curl -sSfL -m 30 "$url.sha256" 2>/dev/null) || { url=""; continue; }
                h=$(usb_first_hash <<< "$sums")
                iso=$(awk '{print $2; exit}' <<< "$sums")
                if [ -n "$h" ] && [ -n "$iso" ]; then
                    picked="$h $iso"
                    # El enlace "latest" lleva a la versión exacta: se baja esa
                    dist=$(curl -sSI -m 30 "$url" 2>/dev/null | awk 'tolower($1) == "location:" {l = $2} END {print l}' | tr -d '\r')
                    [ -n "$dist" ] && url=$dist
                    break
                fi
                url=""
            done ;;
        enlace)
            echo -e "\n${YELLOW}ℹ ${name%% (*} se baja con una cuenta gratuita de su sitio${NC} (hay que iniciar sesión, por eso"
            echo -e "  no la puedo descargar sola). Pasos:"
            echo -e "  1. Entra a ${BOLD}$a${NC} y crea la cuenta o inicia sesión."
            echo -e "  2. Baja la ISO y copia la suma SHA-256 que muestra la página."
            echo -e "  3. Vuelve aquí: ${BOLD}20 → 3) Grabar en un pendrive una ISO que ya tengo${NC}, y pega esa suma."
            if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v xdg-open &> /dev/null \
                && confirm "${CYAN}¿Abro la página en el navegador?${NC}"; then
                xdg-open "$a" &> /dev/null &
            fi
            return 1 ;;
    esac
    if [ -z "$picked" ]; then
        log_error "No se encontró la ISO de $name con su suma oficial: no se descarga sin poder comprobarla"
        return 1
    fi
    USB_ISO_SHA=${picked%% *}
    USB_ISO_FILE=${picked#* }
    USB_ISO_URL=${url:-$base/$USB_ISO_FILE}
}

# Elige un sistema en dos pasos (familia y sistema); deja la línea de USB_DISTROS en USB_CHOSEN
usb_choose_distro() {
    local groups=() entry group="" i choice shown=() names
    for entry in "${USB_DISTROS[@]}"; do
        [[ "$entry" == "#"* ]] && groups+=("${entry#\#}")
    done
    local g
    while true; do
        echo -e "\n${CYAN}💿 ¿De qué familia es el sistema?${NC} (descarga oficial, se verifica sola)\n"
        i=1
        for g in "${groups[@]}"; do
            printf "  ${CYAN}%d)${NC} ${BOLD}%s${NC}: %s\n" "$i" "${g%%|*}" "${g#*|}"
            i=$((i + 1))
        done
        echo -e "  ${CYAN}0)${NC} Volver"
        read -r -p "🔢 Familia: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#groups[@]} ] || return 1
        group=${groups[$((choice - 1))]}
        shown=()
        echo -e "\n${CYAN}💿 ${group%%|*}${NC}\n"
        local on=false
        for entry in "${USB_DISTROS[@]}"; do
            if [[ "$entry" == "#"* ]]; then
                [ "${entry#\#}" = "$group" ] && on=true || on=false
                continue
            fi
            $on || continue
            shown+=("$entry")
            IFS='|' read -r _ names _ <<< "$entry"
            printf "  ${CYAN}%2d)${NC} %s\n" "${#shown[@]}" "$names"
        done
        echo -e "  ${CYAN} 0)${NC} Volver a las familias"
        read -r -p "🔢 Sistema: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#shown[@]} ]; then
            USB_CHOSEN=${shown[$((choice - 1))]}
            return 0
        fi
    done
}

# Descarga (se puede retomar si se corta) y verifica; deja la ruta en USB_ISO y el nombre del
# sistema en USB_CHOSEN_NAME. Con una carpeta (el pendrive Ventoy) baja ahí y deja al lado un
# archivo con la suma oficial, para poder comprobarla después sin internet
usb_download_iso() {
    local entry dir size_mb free_mb target="${1:-}"
    usb_choose_distro || return 1
    entry=$USB_CHOSEN
    IFS='|' read -r _ USB_CHOSEN_NAME _ <<< "$entry"
    command -v curl &> /dev/null || { log_error "Falta curl para descargar"; return 1; }
    echo -e "${BLUE}🔍 Buscando la última versión y su suma oficial...${NC}"
    usb_resolve_download "$entry" || return 1
    if [ -n "$target" ]; then
        dir=$target
        mkdir -p "$dir" || { log_error "No se pudo escribir en $dir"; return 1; }
    else
        dir=$(usb_download_dir)
    fi
    USB_ISO="$dir/$USB_ISO_FILE"
    echo -e "   ${GREEN}$USB_ISO_FILE${NC}\n   desde $USB_ISO_URL\n   se guarda en $dir"
    # Si ya está bajada y entera, no se vuelve a bajar
    if [ -f "$USB_ISO" ] && [ "$(usb_hash_of "$USB_ISO" ${#USB_ISO_SHA})" = "${USB_ISO_SHA,,}" ]; then
        log_success "Ya la tenías descargada y está entera"
        usb_check_signature || return 1
        [ -n "$target" ] && usb_write_sum_file "$USB_ISO" "$USB_ISO_SHA"
        return 0
    fi
    size_mb=$(( $(curl -sSfLI -m 30 "$USB_ISO_URL" | awk 'tolower($1) == "content-length:" {n = $2} END {print n + 0}') / 1048576 ))
    free_mb=$(df -Pm "$dir" | awk 'NR == 2 {print $4}')
    if [ "$size_mb" -gt 0 ] && [ "$free_mb" -lt $((size_mb + 200)) ]; then
        log_error "No hay espacio en $dir: la ISO ocupa ~${size_mb} MB y hay ${free_mb} MB libres"
        return 1
    fi
    confirm "${CYAN}¿Descargar ($([ "$size_mb" -gt 0 ] && echo "~${size_mb} MB" || echo "tamaño desconocido"))?${NC}" || return 1
    echo -e "${BLUE}⬇ Descargando (si se corta, vuelve a elegirla y sigue donde quedó)...${NC}"
    if ! curl -fL -C - --progress-bar -o "$USB_ISO" "$USB_ISO_URL"; then
        log_error "La descarga se cortó: vuelve a elegirla para continuar"
        return 1
    fi
    echo -e "${BLUE}🔐 Comprobando que llegó entera ($(usb_hash_name ${#USB_ISO_SHA}))...${NC}"
    if [ "$(usb_hash_of "$USB_ISO" ${#USB_ISO_SHA})" != "${USB_ISO_SHA,,}" ]; then
        log_error "La ISO no coincide con la suma oficial: está dañada, no se usa (se borra)"
        rm -f -- "$USB_ISO"
        return 1
    fi
    if ! usb_check_signature; then
        rm -f -- "$USB_ISO"
        return 1
    fi
    [ -n "$target" ] && usb_write_sum_file "$USB_ISO" "$USB_ISO_SHA"
    log_success "ISO descargada y verificada"
}

# Deja "suma  nombre" al lado de la ISO (.sha256, .sha512 o .md5 según el largo de la suma)
usb_write_sum_file() {
    local iso="$1" sum="${2,,}" ext
    [ -n "$sum" ] || return 0
    case ${#sum} in 128) ext=sha512 ;; 32) ext=md5 ;; *) ext=sha256 ;; esac
    printf '%s  %s\n' "$sum" "$(basename "$iso")" > "$iso.$ext" 2>/dev/null || true
}

# Busca ISOs en las carpetas habituales y deja la elegida en USB_ISO
usb_pick_local_iso() {
    local isos=() i choice f path
    mapfile -t isos < <(find "$(usb_download_dir)" "$HOME" "$HOME/Escritorio" "$HOME/Desktop" /media /run/media \
        -maxdepth 3 -type f -iname '*.iso' -size +50M 2>/dev/null | sort -u)
    echo ""
    if [ ${#isos[@]} -gt 0 ]; then
        echo -e "${CYAN}💿 ISOs encontradas:${NC}"
        i=1
        for f in "${isos[@]}"; do
            printf "  ${CYAN}%d)${NC} %s  ${YELLOW}(%s, %s)${NC}\n" "$i" "$(basename "$f")" \
                "$(du -h "$f" | cut -f1)" "$(date -r "$f" '+%d/%m/%Y')"
            i=$((i + 1))
        done
    else
        echo -e "${YELLOW}ℹ No encontré ISOs en Descargas, tu carpeta personal ni en discos conectados${NC}"
    fi
    echo -e "  ${CYAN}r)${NC} Escribir la ruta a mano"
    echo -e "  ${CYAN}0)${NC} Volver"
    read -r -p "🔢 Opción: " choice
    if [ "$choice" = r ]; then
        read -r -e -p "📁 Ruta de la ISO (Enter = volver): " path
        [ -n "$path" ] && [ "$path" != 0 ] || return 1
        path=${path/#\~/$HOME}
        [ -f "$path" ] || { log_error "No existe: $path"; return 1; }
        USB_ISO="$path"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#isos[@]} ]; then
        USB_ISO=${isos[$((choice - 1))]}
    else
        return 1
    fi
    USB_ISO_SHA=""
}

# Patrón del nombre de las ISO de una distribución de la lista
usb_entry_pattern() {
    local key dname type a b c d
    IFS='|' read -r key dname type a b c d <<< "$1"
    case $type in
        lista|carpeta) echo "$c" ;;
        sf) echo "$c" ;;
        # fijo: neon-user-current.iso también reconoce las fechadas (neon-user-20261101-0700.iso)
        fijo) sed -e 's/[.]/\\./g' -e 's/[Cc]urrent/.*/' <<< "$b" ;;
        *) echo "$b" ;;
    esac
}

# Suma oficial de una ISO que ya tienes, si es de una distribución de la lista (vacío si no se encuentra)
usb_official_sum_for() {
    local entry="$1" name="$2" key dname type a b c d ver major sums base url
    IFS='|' read -r key dname type a b c d <<< "$entry"
    case $type in
        ubuntu)
            # ubuntu-24.04.3-desktop-amd64.iso → carpeta de esa versión (o de la serie, o de old-releases)
            ver=$(sed -E 's/^[a-z-]+-([0-9]+\.[0-9]+(\.[0-9]+)*)-.*/\1/' <<< "$name")
            major=$(cut -d. -f1,2 <<< "$ver")
            for base in "$ver" "$major"; do
                if [ "$a" = releases ]; then
                    for url in "https://releases.ubuntu.com/$base" "https://old-releases.ubuntu.com/releases/$base"; do
                        sums=$(curl -sSfL -m 30 "$url/SHA256SUMS" 2>/dev/null) && usb_sum_lookup "$sums" "$name" && return 0
                    done
                else
                    url="https://cdimage.ubuntu.com/$a/releases/$base/release"
                    sums=$(curl -sSfL -m 30 "$url/SHA256SUMS" 2>/dev/null) && usb_sum_lookup "$sums" "$name" && return 0
                fi
            done ;;
        lista)
            sums=$(curl -sSfL -m 30 "$a/$b" 2>/dev/null) && usb_sum_lookup "$sums" "$name" && return 0 ;;
        fijo)
            sums=$(curl -sSfL -m 30 "$a/$c" 2>/dev/null) || return 1
            usb_sum_lookup "$sums" "$name" && return 0
            # Bajada con el nombre "current": su suma está en el archivo con el nombre fechado
            [ "$name" = "$b" ] && usb_first_hash <<< "$sums" | grep . && return 0 ;;
        sf)
            # Cualquier versión que siga publicada: su archivo de suma está al lado
            url=$(curl -sSfL -m 30 "https://sourceforge.net/projects/$a/rss?path=/$b&limit=100" 2>/dev/null \
                | grep -oE "https://sourceforge\\.net/projects/$a/files/[^<\"]+/$name/download" | head -1)
            if [ -n "$url" ]; then
                url=${url#https://sourceforge.net/projects/$a/files/}
                curl -sSfL -m 30 "https://downloads.sourceforge.net/project/$a/${url%/download}.$d" 2>/dev/null \
                    | usb_first_hash | grep . && return 0
            fi ;;
        *)
            # El resto: solo si es la versión que se descargaría hoy
            ( usb_resolve_download "$entry" > /dev/null 2>&1 && [ "$USB_ISO_FILE" = "$name" ] && echo "$USB_ISO_SHA" ) \
                && return 0 ;;
    esac
    return 1
}

# Busca "nombre" en una lista de sumas ("hash  nombre" o "hash *nombre"); imprime el hash
usb_sum_lookup() {
    local sums="$1" name="$2" h
    h=$(usb_norm_sums <<< "$sums" | awk -v n="$name" '{f = $2; sub(/^\*/, "", f)} f == n {print $1; exit}')
    [ -n "$h" ] && { echo "$h"; return 0; }
    return 1
}

# Suma oficial conocida de una ISO, sin preguntar nada: un archivo de sumas al lado (también el
# que deja Ventoy → Agregar sistemas) o la lista oficial de su distribución. Deja USB_KNOWN_SUM y USB_SUM_SRC
usb_known_sum() {
    local iso="$1" dir name f entry pattern key dname
    dir=$(dirname "$iso")
    name=$(basename "$iso")
    USB_KNOWN_SUM="" USB_SUM_SRC=""
    for f in "$dir/$name.sha256" "$dir/$name.sha256sum" "$dir/$name.sha512" "$dir/$name.sha512sum" "$dir/$name.md5" \
             "$dir/$name.SHA256SUM" "$dir/SHA256SUMS" "$dir/sha256sums.txt" "$dir/SHA256SUMS.txt" \
             "$dir/sha256sum.txt" "$dir/CHECKSUM"; do
        [ -f "$f" ] || continue
        USB_KNOWN_SUM=$(usb_sum_lookup "$(cat "$f")" "$name")
        # Los archivos de un solo archivo a veces traen solo el hash
        [ -z "$USB_KNOWN_SUM" ] && [[ "$f" == *"$name".* ]] && USB_KNOWN_SUM=$(usb_norm_sums < "$f" \
            | grep -oiE '^[0-9a-f]+' | awk 'length($0) == 32 || length($0) == 64 || length($0) == 128 {print; exit}')
        [ -n "$USB_KNOWN_SUM" ] && { USB_SUM_SRC="$(basename "$f"), junto a la ISO"; return 0; }
    done
    for entry in "${USB_DISTROS[@]}"; do
        [[ "$entry" == "#"* ]] && continue
        pattern=$(usb_entry_pattern "$entry")
        if [[ "$name" =~ ^${pattern}$ ]]; then
            IFS='|' read -r key dname _ <<< "$entry"
            dname=${dname%%, última LTS}
            dname=${dname%% (*}
            echo -e "   Es una ISO de ${BOLD}$dname${NC}: busco su suma oficial..."
            USB_KNOWN_SUM=$(usb_official_sum_for "$entry" "$name") && { USB_SUM_SRC="lista oficial de $dname"; return 0; }
            USB_KNOWN_SUM=""
            break
        fi
    done
    return 1
}

# ¿Coincide la ISO que ya tienes con su suma oficial? Busca la suma junto a la ISO, en la lista
# oficial de su distribución o te deja pegarla; si no coincide, no se graba.
# Si coincide, deja la suma en USB_VERIFIED_SUM (vacía si se eligió seguir sin comprobar)
usb_verify_local_iso() {
    local iso="$1" got expected="" src="" answer
    USB_VERIFIED_SUM=""
    echo ""
    usb_known_sum "$iso" && { expected=$USB_KNOWN_SUM; src=$USB_SUM_SRC; }
    echo -e "\n${BLUE}🔐 Comprobando que la ISO esté entera (calculando su suma, puede tardar un minuto)...${NC}"
    got=$(usb_hash_of "$iso" ${#expected})
    # 3. La suma que publica el sitio de la distribución, pegada a mano
    if [ -z "$expected" ]; then
        echo -e "${YELLOW}ℹ No encontré la suma oficial de esta ISO. Su SHA-256 es:${NC}"
        echo -e "   ${BOLD}$got${NC}"
        echo -e "   Compárala con la que publica la página de descarga de tu distribución."
        read -r -p "📋 Pega aquí la suma oficial (Enter = grabar sin comprobar, 0 = volver): " answer
        [ "$answer" = 0 ] && return 1
        if [ -z "$answer" ]; then
            log_warning "Se graba sin comprobar la suma"
            return 0
        fi
        expected=$(grep -oiE '[0-9a-f]+' <<< "$answer" | awk 'length($0) == 64 || length($0) == 128 {print; exit}')
        [ -n "$expected" ] || { log_error "Eso no es una suma SHA-256 ni SHA-512 (64 o 128 caracteres hexadecimales)"; return 1; }
        [ ${#expected} -eq 128 ] && got=$(usb_hash_of "$iso" 128)
        src="la que pegaste"
    fi
    if [ "${got,,}" = "${expected,,}" ]; then
        log_success "La ISO está entera: coincide con la suma oficial ($src)"
        USB_VERIFIED_SUM=${expected,,}
        return 0
    fi
    log_error "La ISO NO coincide con la suma oficial ($src): está dañada o es otra versión. Vuelve a descargarla."
    return 1
}

# ¿Se puede grabar con dd? Las ISO de Linux son "híbridas" (arrancan desde un USB);
# las de Windows no (necesitan otra herramienta, por ejemplo WoeUSB)
usb_check_iso() {
    local iso="$1" label sig
    label=$(dd if="$iso" bs=1 skip=32808 count=32 2>/dev/null | tr -d '\0' | sed 's/ *$//')
    sig=$(dd if="$iso" bs=1 skip=510 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
    echo -e "   Nombre del disco: ${CYAN}${label:-(sin nombre)}${NC}, tamaño ${CYAN}$(du -h "$iso" | cut -f1)${NC}"
    if [[ "$label" =~ ^(CCCOMA|CPBA|CCSA|CENA|ESD-ISO|J_CCSA|IR[0-9]) ]] || [[ "$(basename "$iso")" =~ [Ww]in(dows)?[0-9._-] ]]; then
        log_error "Parece una ISO de Windows: con dd no arranca. Usa WoeUSB o Ventoy para Windows."
        return 1
    fi
    if [ "$sig" != 55aa ]; then
        log_warning "Esta ISO no es 'híbrida': grabada con dd puede no arrancar desde USB"
        confirm "${YELLOW}¿Grabarla igualmente?${NC}" || return 1
    fi
}

# Discos USB (y tarjetas SD) que se pueden borrar: "dispositivo|tamaño en bytes|descripción"
usb_candidates() {
    local name tran rm size model vendor busy p mp
    while read -r name rm size tran; do
        [ "$tran" = usb ] || { [[ "$name" == /dev/mmcblk* ]] && [ "$rm" = 1 ]; } || continue
        # Nunca un disco con algo del sistema montado (raíz, /boot, /home, swap, el Live USB...)
        busy=""
        while read -r p mp; do
            case "$mp" in
                /|/boot|/boot/*|/efi|/home|/home/*|/usr|/var|/cdrom|/run/live/*|/run/archiso/*|/run/initramfs/*|\[SWAP\]) busy="$mp" ;;
            esac
        done < <(lsblk -lnpo NAME,MOUNTPOINT "$name" 2>/dev/null)
        [ -n "$busy" ] && continue
        model=$(lsblk -dno MODEL "$name" 2>/dev/null | sed 's/ *$//')
        vendor=$(lsblk -dno VENDOR "$name" 2>/dev/null | sed 's/ *$//')
        echo "$name|$size|$(lsblk -dno SIZE "$name" | tr -d ' ') ${vendor:+$vendor }${model:-USB}"
    done < <(lsblk -dnbpo NAME,RM,SIZE,TRAN 2>/dev/null)
}

# Elige el pendrive; si no hay, espera a que lo conectes. Deja USB_DEV, USB_DEV_SIZE, USB_DEV_DESC
usb_pick_device() {
    local min_bytes="$1" list_fn="${2:-usb_candidates}" devs=() i d choice waited=0
    mapfile -t devs < <("$list_fn")
    if [ ${#devs[@]} -eq 0 ]; then
        echo -e "\n${YELLOW}🔌 Conecta el pendrive ahora... (lo detecto solo; Ctrl+C para cancelar)${NC}"
        while [ ${#devs[@]} -eq 0 ] && [ $waited -lt 120 ]; do
            sleep 2
            waited=$((waited + 2))
            mapfile -t devs < <("$list_fn")
        done
        [ ${#devs[@]} -gt 0 ] || { log_error "No se detectó ningún pendrive en 2 minutos"; return 1; }
        sleep 2   # que el sistema termine de reconocerlo
        mapfile -t devs < <("$list_fn")
    fi
    echo -e "\n${CYAN}🔌 Pendrives conectados:${NC}"
    i=1
    for d in "${devs[@]}"; do
        printf "  ${CYAN}%d)${NC} %s  ${YELLOW}%s${NC}\n" "$i" "${d%%|*}" "${d##*|}"
        i=$((i + 1))
    done
    echo -e "  ${CYAN}0)${NC} Volver"
    if [ ${#devs[@]} -eq 1 ]; then
        read -r -p "🔢 Opción [1]: " choice
        choice=${choice:-1}
    else
        read -r -p "🔢 Opción: " choice
    fi
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#devs[@]} ] || return 1
    IFS='|' read -r USB_DEV USB_DEV_SIZE USB_DEV_DESC <<< "${devs[$((choice - 1))]}"
    if [ "$USB_DEV_SIZE" -lt "$min_bytes" ]; then
        log_error "El pendrive es chico: tiene $(numfmt --to=iec "$USB_DEV_SIZE") y la ISO necesita $(numfmt --to=iec "$min_bytes")"
        return 1
    fi
}

# Desmonta las particiones de un disco (el escritorio las monta solas al conectarlo)
usb_unmount_dev() {
    local part
    sync
    for part in $(lsblk -lnpo NAME "$1" | tail -n +2); do
        if findmnt -rn -S "$part" > /dev/null; then
            sudo umount "$part" 2>/dev/null || udisksctl unmount -b "$part" &> /dev/null \
                || { log_error "No se pudo desmontar $part: cierra lo que lo esté usando"; return 1; }
        fi
    done
}

create_usb_menu() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║       💿 DESCARGAR SISTEMAS Y CREAR USB DE INSTALACIÓN           ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "Descarga la imagen (ISO) oficial de más de 40 sistemas, verificada, y grábala en un pendrive"
    echo -e "para instalarla o probarla en cualquier PC. También sirve para solo descargarla."
    echo -e "${YELLOW}⚠ Al grabar, se borra todo lo que tenga el pendrive.${NC} El disco de tu sistema nunca aparece.\n"
    echo -e "  ${BLUE}1)${NC} 💿 Descargar un sistema y grabarlo en un pendrive"
    echo -e "  ${BLUE}2)${NC} ⬇  Solo descargar la imagen ISO (para grabarla después, Ventoy o una máquina virtual)"
    echo -e "  ${BLUE}3)${NC} 🔥 Grabar en un pendrive una ISO que ya tengo (la busco sola)"
    echo -e "  ${BLUE}4)${NC} 🧰 VENTOY: varios sistemas en un solo pendrive (live, con persistencia)"
    echo -e "  ${BLUE}0)${NC} 🔙 Volver\n"
    local option
    read -r -p "📌 Opción (0-4): " option
    USB_ISO="" USB_ISO_SHA=""
    case $option in
        1) usb_download_iso || return 1 ;;
        2)
            usb_download_iso || return 1
            echo -e "\n${GREEN}✓ Lista: ${BOLD}$USB_ISO${NC}"
            echo -e "${CYAN}💡 Para grabarla en un pendrive más tarde: opción 20 → 3.${NC}"
            return 0 ;;
        3) usb_pick_local_iso || return 1 ;;
        4) ventoy_menu; return 0 ;;
        *) return 0 ;;
    esac

    echo -e "\n${CYAN}💿 ISO:${NC} $USB_ISO"
    usb_check_iso "$USB_ISO" || return 1
    # Las descargadas ya se comprobaron; las que ya tenías, ahora
    if [ "$option" = 3 ]; then
        usb_verify_local_iso "$USB_ISO" || return 1
    fi
    local iso_bytes
    iso_bytes=$(stat -c %s "$USB_ISO")
    usb_pick_device "$iso_bytes" || return 1

    # Qué se va a borrar, para que no haya dudas
    echo -e "\n${RED}${BOLD}⚠ SE VA A BORRAR TODO ESTE PENDRIVE:${NC}"
    echo -e "   ${BOLD}$USB_DEV${NC} — $USB_DEV_DESC"
    lsblk -no NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$USB_DEV" 2>/dev/null | sed 's/^/     /'
    [ "$USB_DEV_SIZE" -gt $((256 * 1024 * 1024 * 1024)) ] \
        && echo -e "${YELLOW}   ⚠ Es muy grande para ser un pendrive: ¿no será un disco externo con tus archivos?${NC}"
    echo -e "\n   Se grabará: ${GREEN}$(basename "$USB_ISO")${NC}"
    if $AUTO_MODE; then
        log_error "Grabar un pendrive siempre se confirma a mano"
        return 1
    fi
    local answer
    read -r -p "✍ Para confirmar escribe BORRAR (cualquier otra cosa cancela): " answer
    [ "$answer" = BORRAR ] || { echo -e "${YELLOW}ℹ Cancelado: no se tocó nada${NC}"; return 0; }

    # Se comprueba otra vez que sea el mismo pendrive (por si se desconectó o cambió de nombre)
    if ! usb_candidates | grep -q "^$USB_DEV|$USB_DEV_SIZE|"; then
        log_error "El pendrive cambió o se desconectó: no se grabó nada"
        return 1
    fi
    usb_unmount_dev "$USB_DEV" || return 1

    echo -e "\n${BLUE}🔥 Grabando (no desconectes el pendrive)...${NC}"
    if ! sudo dd if="$USB_ISO" of="$USB_DEV" bs=4M status=progress oflag=direct conv=fsync; then
        log_error "Falló la grabación: prueba con otro puerto USB u otro pendrive"
        return 1
    fi
    sync
    echo -e "\n${BLUE}🔍 Comprobando que se grabó bien...${NC}"
    if sudo cmp -n "$iso_bytes" "$USB_ISO" "$USB_DEV" > /dev/null 2>&1; then
        log_success "Pendrive listo y verificado"
    else
        log_error "La copia no coincide con la ISO: el pendrive puede estar dañado, prueba con otro"
        return 1
    fi
    if command -v udisksctl &> /dev/null && udisksctl power-off -b "$USB_DEV" &> /dev/null; then
        echo -e "${GREEN}✓ Expulsado: ya puedes sacarlo${NC}"
    else
        echo -e "${GREEN}✓ Ya puedes sacarlo${NC}"
    fi
    echo -e "\n${CYAN}💡 Para arrancar desde el pendrive: enchúfalo, enciende la PC y pulsa la tecla del menú de"
    echo -e "   arranque (suele ser F12, F11, F10, F8 o Esc según la marca) y elige el USB.${NC}"
    echo -e "${CYAN}   Si no aparece, desactiva \"Secure Boot\" o activa el arranque USB en la BIOS.${NC}"
    if [ -n "$USB_ISO_SHA" ] && confirm "${CYAN}¿Borrar la ISO descargada para liberar espacio?${NC}"; then
        rm -f -- "$USB_ISO" && log_success "ISO borrada"
    fi
}

# ============================================================
# VENTOY: varios sistemas en un solo pendrive (opción 20 → 4)
# Ventoy (https://www.ventoy.net, GPL-3.0, de longpanda) se baja de su proyecto oficial en
# SourceForge y se comprueba con su sha256.txt. El pendrive lo elige este script con las
# mismas protecciones que la grabación con dd; después se usan las herramientas de Ventoy
# (Ventoy2Disk.sh y CreatePersistentImg.sh). Lo que suma el script:
# - Bajar las ISO de la misma lista de sistemas directo al pendrive, verificadas, con su
#   suma al lado para comprobarlas después sin internet
# - Nombres claros en el menú de arranque y persistencia (ventoy/ventoy.json)
# - Ver, comprobar y quitar las ISO del pendrive
# ============================================================
VENTOY_DIR=/var/cache/linux-ultimate-tools

# Deja en VENTOY_TOOL la carpeta del paquete oficial de Ventoy (lo baja y lo comprueba si hace falta)
ventoy_get_tool() {
    local rel ver base sums h tmp
    echo -e "${BLUE}🔍 Buscando la última versión de Ventoy...${NC}"
    rel=$(curl -sSfL -m 30 "https://sourceforge.net/projects/ventoy/rss?limit=40" 2>/dev/null \
        | grep -oE 'https://sourceforge\.net/projects/ventoy/files/v[0-9.]+/ventoy-[0-9.]+-linux\.tar\.gz/download' \
        | sed -E 's#^https://sourceforge\.net/projects/ventoy/files/##; s#/download$##' \
        | usb_sorted 'ventoy-[0-9.]+-linux\.tar\.gz' | tail -1)
    if [ -z "$rel" ]; then
        # Sin conexión: la última que ya se haya bajado antes
        VENTOY_TOOL=$(ls -d "$VENTOY_DIR"/ventoy-*/ 2>/dev/null | sort -V | tail -1)
        VENTOY_TOOL=${VENTOY_TOOL%/}
        if [ -n "$VENTOY_TOOL" ] && [ -f "$VENTOY_TOOL/Ventoy2Disk.sh" ]; then
            log_warning "Sin conexión: se usa Ventoy $(cat "$VENTOY_TOOL/ventoy/version" 2>/dev/null), que ya estaba bajado"
            return 0
        fi
        log_error "No se pudo consultar Ventoy en SourceForge (¿hay internet?)"
        return 1
    fi
    ver=${rel%%/*}
    ver=${ver#v}
    VENTOY_TOOL="$VENTOY_DIR/ventoy-$ver"
    if [ -f "$VENTOY_TOOL/Ventoy2Disk.sh" ]; then
        echo -e "   Ventoy ${GREEN}$ver${NC} (ya bajado)"
        return 0
    fi
    base="https://downloads.sourceforge.net/project/ventoy/v$ver"
    tmp=$(mktemp -d)
    echo -e "${BLUE}⬇ Descargando Ventoy $ver (oficial)...${NC}"
    if ! curl -fL --progress-bar -o "$tmp/ventoy.tar.gz" "$base/ventoy-$ver-linux.tar.gz" \
        || ! sums=$(curl -sSfL -m 30 "$base/sha256.txt"); then
        rm -rf -- "$tmp"
        log_error "No se pudo descargar Ventoy"
        return 1
    fi
    h=$(usb_sum_lookup "$sums" "ventoy-$ver-linux.tar.gz")
    if [ -z "$h" ] || [ "$(sha256sum "$tmp/ventoy.tar.gz" | awk '{print $1}')" != "${h,,}" ]; then
        rm -rf -- "$tmp"
        log_error "Ventoy no coincide con su suma oficial: no se usa"
        return 1
    fi
    if ! sudo mkdir -p "$VENTOY_DIR" || ! sudo tar -xzf "$tmp/ventoy.tar.gz" -C "$VENTOY_DIR" \
        || ! [ -f "$VENTOY_TOOL/Ventoy2Disk.sh" ]; then
        rm -rf -- "$tmp"
        log_error "No se pudo descomprimir Ventoy en $VENTOY_DIR"
        return 1
    fi
    rm -rf -- "$tmp"
    log_success "Ventoy $ver descargado y verificado (SHA-256 oficial)"
}

# ¿Está este programa del sistema? (en Debian, /usr/sbin no está en el PATH de los usuarios)
ventoy_has() {
    local d
    for d in /usr/sbin /sbin /usr/bin /bin; do
        [ -x "$d/$1" ] && return 0
    done
    return 1
}

# Ventoy necesita fdisk (o parted) para las particiones y mkfs.vfat (dosfstools) para la de arranque
ventoy_need_partitioner() {
    local pkgs=() names=()
    { ventoy_has fdisk || ventoy_has parted; } || { names+=(fdisk); pkgs+=(fdisk); }
    ventoy_has mkfs.vfat || { names+=(mkfs.vfat); pkgs+=(dosfstools); }
    [ ${#pkgs[@]} -eq 0 ] && return 0
    log_warning "Ventoy necesita ${names[*]} para preparar el pendrive y no está instalado"
    confirm "${CYAN}¿Instalar ${pkgs[*]}?${NC}" || return 1
    if command -v apt-get &> /dev/null; then
        run "No se pudo instalar ${pkgs[*]}" sudo apt-get install -y "${pkgs[@]}"
    elif command -v pacman &> /dev/null; then
        # En Arch fdisk viene en util-linux
        run "No se pudo instalar ${pkgs[*]}" sudo pacman -S --needed --noconfirm "${pkgs[@]/#fdisk/util-linux}"
    elif command -v dnf &> /dev/null; then
        run "No se pudo instalar ${pkgs[*]}" sudo dnf install -y "${pkgs[@]/#fdisk/util-linux}"
    elif command -v zypper &> /dev/null; then
        run "No se pudo instalar ${pkgs[*]}" sudo zypper --non-interactive install "${pkgs[@]}"
    else
        log_error "Instala ${pkgs[*]} con el gestor de paquetes de tu sistema"
        return 1
    fi
}

# Etiqueta de una partición (lsblk; si udev no la conoce, blkid)
ventoy_part_label() {
    local l
    l=$(lsblk -dno LABEL "$1" 2>/dev/null | sed 's/ *$//')
    [ -n "$l" ] || l=$(blkid -o value -s LABEL "$1" 2>/dev/null)
    echo "$l"
}

# Partición del disco con esa etiqueta
ventoy_find_part() {
    local p
    for p in $(lsblk -lnpo NAME "$1" 2>/dev/null | tail -n +2); do
        [ "$(ventoy_part_label "$p")" = "$2" ] && { echo "$p"; return 0; }
    done
    return 1
}

# Corre una herramienta de Ventoy desde su carpeta (así lo pide Ventoy)
ventoy_run() {
    local tool="$1"
    shift
    ( cd "$VENTOY_TOOL" && sudo bash "./$tool" "$@" )
}

# Pendrives que ya tienen Ventoy (mismo formato que usb_candidates)
ventoy_candidates() {
    local d
    while IFS= read -r d; do
        ventoy_find_part "${d%%|*}" Ventoy > /dev/null && ventoy_find_part "${d%%|*}" VTOYEFI > /dev/null && echo "$d"
    done < <(usb_candidates)
}

# Elige un pendrive con Ventoy y monta su partición de datos; deja USB_DEV y VENTOY_MNT
ventoy_pick_and_mount() {
    local part
    if [ -z "$(ventoy_candidates)" ] && [ -n "$(usb_candidates)" ]; then
        log_error "Ningún pendrive conectado tiene Ventoy: instálalo primero (opción 1 de este menú)"
        return 1
    fi
    echo -e "\n${CYAN}Pendrive con Ventoy:${NC}"
    usb_pick_device 0 ventoy_candidates || return 1
    part=$(ventoy_find_part "$USB_DEV" Ventoy)
    VENTOY_MNT=$(findmnt -rno TARGET -S "$part" 2>/dev/null | head -1)
    if [ -z "$VENTOY_MNT" ]; then
        udisksctl mount -b "$part" --no-user-interaction &> /dev/null
        VENTOY_MNT=$(findmnt -rno TARGET -S "$part" 2>/dev/null | head -1)
    fi
    if [ -z "$VENTOY_MNT" ]; then
        # Sin escritorio que lo monte: a mano (si el kernel no trae exFAT, con exfat-fuse)
        sudo mkdir -p /mnt/ventoy-ultimate-tools
        if sudo mount -o "uid=$(id -u),gid=$(id -g)" "$part" /mnt/ventoy-ultimate-tools 2>/dev/null \
            || { ventoy_has mount.exfat-fuse && sudo mount.exfat-fuse -o "uid=$(id -u),gid=$(id -g)" "$part" /mnt/ventoy-ultimate-tools; }; then
            VENTOY_MNT=/mnt/ventoy-ultimate-tools
        fi
    fi
    [ -n "$VENTOY_MNT" ] || { log_error "No se pudo abrir la partición de Ventoy ($part)"; return 1; }
    [ -w "$VENTOY_MNT" ] || { log_error "No se puede escribir en el pendrive ($VENTOY_MNT): ¿está protegido contra escritura?"; return 1; }
    echo -e "   Abierto en ${CYAN}$VENTOY_MNT${NC} · libre: ${GREEN}$(df -h --output=avail "$VENTOY_MNT" | tail -1 | tr -d ' ')${NC}"
}

# Imágenes que Ventoy puede arrancar, con la ruta relativa al pendrive
ventoy_list_images() {
    ( cd "$VENTOY_MNT" && find . -path ./ventoy -prune -o -path ./persistence -prune -o -type f \
        \( -iname '*.iso' -o -iname '*.img' -o -iname '*.wim' -o -iname '*.vhd' -o -iname '*.vhdx' -o -iname '*.efi' \) \
        -print 2>/dev/null | sed 's#^\.##' | sort )
}

# ventoy/ventoy.json con nombres claros (menu_alias) y persistencia, a partir de la lista propia del
# script (ventoy/linux-ultimate-tools.conf). Si tienes un ventoy.json hecho a mano, no se toca
ventoy_write_json() {
    local conf="$VENTOY_MNT/ventoy/linux-ultimate-tools.conf" json="$VENTOY_MNT/ventoy/ventoy.json"
    local mine="$VENTOY_MNT/ventoy/.ventoy.json.linux-ultimate-tools" kind img val sep aliases="" pers="" out
    mkdir -p "$VENTOY_MNT/ventoy"
    if [ -f "$json" ] && ! cmp -s "$json" "$mine"; then
        log_warning "El pendrive tiene un ventoy.json propio: no lo cambio (los nombres y la persistencia quedan sin configurar)"
        return 1
    fi
    [ -f "$conf" ] || touch "$conf"
    while IFS='|' read -r kind img val; do
        [ -f "$VENTOY_MNT$img" ] || continue
        [ "$kind" = persist ] && ! [ -f "$VENTOY_MNT$val" ] && continue
        img=${img//\\/\\\\}; img=${img//\"/\\\"}
        val=${val//\\/\\\\}; val=${val//\"/\\\"}
        case $kind in
            alias) aliases+="${aliases:+,}"$'\n'"        { \"image\": \"$img\", \"alias\": \"$val\" }" ;;
            persist) pers+="${pers:+,}"$'\n'"        { \"image\": \"$img\", \"backend\": \"$val\" }" ;;
        esac
    done < "$conf"
    out="{"
    sep=""
    [ -n "$aliases" ] && { out+=$'\n'"    \"menu_alias\": [$aliases"$'\n'"    ]"; sep=","; }
    [ -n "$pers" ] && out+="$sep"$'\n'"    \"persistence\": [$pers"$'\n'"    ]"
    out+=$'\n'"}"
    if [ -z "$aliases$pers" ]; then
        rm -f -- "$json" "$mine"
        return 0
    fi
    printf '%s\n' "$out" > "$json" && cp "$json" "$mine"
}

# Agrega o cambia una línea "tipo|imagen|valor" de la lista propia
ventoy_conf_set() {
    local conf="$VENTOY_MNT/ventoy/linux-ultimate-tools.conf" kind="$1" img="$2" val="$3"
    mkdir -p "$VENTOY_MNT/ventoy"
    touch "$conf"
    grep -vF -- "$kind|$img|" "$conf" > "$conf.tmp" 2>/dev/null
    [ -n "$val" ] && printf '%s|%s|%s\n' "$kind" "$img" "$val" >> "$conf.tmp"
    mv -f -- "$conf.tmp" "$conf"
}

# Nombre claro para el menú de Ventoy: el del sistema y su versión ("Ubuntu 26.04.1")
ventoy_alias_for() {
    local name="$1" file="$2" ver
    name=${name%%, última LTS}
    name=${name%% (*}
    ver=$(grep -oE '[0-9]+(\.[0-9]+)+|[0-9]{6,}' <<< "$file" | head -1)
    echo "$name${ver:+ $ver}"
}

# 1. Instalar Ventoy en un pendrive (lo borra)
ventoy_install() {
    local style answer opts=() info
    if $AUTO_MODE; then
        log_error "Instalar Ventoy borra un pendrive: siempre se confirma a mano"
        return 1
    fi
    ventoy_need_partitioner || return 1
    ventoy_get_tool || return 1
    usb_pick_device $((1024 * 1024 * 1024)) || return 1
    if ventoy_candidates | grep -q "^$USB_DEV|"; then
        echo -e "${YELLOW}ℹ Este pendrive ya tiene Ventoy. Para actualizarlo sin borrar las ISO usa la opción 5.${NC}"
    fi
    echo -e "\n${CYAN}Tipo de partición:${NC}"
    echo -e "  ${CYAN}1)${NC} MBR (recomendado: arranca en PCs viejas y nuevas)"
    echo -e "  ${CYAN}2)${NC} GPT (solo PCs nuevas con UEFI)"
    read -r -p "🔢 Opción [1]: " style
    case ${style:-1} in
        1) ;;
        2) opts+=(-g) ;;
        *) return 1 ;;
    esac
    if confirm "${CYAN}¿Activar la compatibilidad con Secure Boot? (recomendado)${NC}"; then
        opts+=(-s)
    else
        opts+=(-S)
    fi
    echo -e "\n${RED}${BOLD}⚠ SE VA A BORRAR TODO ESTE PENDRIVE:${NC}"
    echo -e "   ${BOLD}$USB_DEV${NC} — $USB_DEV_DESC"
    lsblk -no NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$USB_DEV" 2>/dev/null | sed 's/^/     /'
    [ "$USB_DEV_SIZE" -gt $((256 * 1024 * 1024 * 1024)) ] \
        && echo -e "${YELLOW}   ⚠ Es muy grande para ser un pendrive: ¿no será un disco externo con tus archivos?${NC}"
    read -r -p "✍ Para confirmar escribe BORRAR (cualquier otra cosa cancela): " answer
    [ "$answer" = BORRAR ] || { echo -e "${YELLOW}ℹ Cancelado: no se tocó nada${NC}"; return 0; }
    if ! usb_candidates | grep -q "^$USB_DEV|$USB_DEV_SIZE|"; then
        log_error "El pendrive cambió o se desconectó: no se tocó nada"
        return 1
    fi
    usb_unmount_dev "$USB_DEV" || return 1
    echo -e "\n${BLUE}🧰 Instalando Ventoy (no desconectes el pendrive)...${NC}"
    # Ventoy pregunta dos veces "Continue? (y/n)": ya se confirmó arriba con BORRAR
    printf 'y\ny\n' | ventoy_run Ventoy2Disk.sh -I "${opts[@]}" "$USB_DEV" | grep -v '^$' | sed 's/^/   /'
    sleep 3
    info=$(ventoy_run Ventoy2Disk.sh -l "$USB_DEV" 2>/dev/null)
    if ! grep -q 'Ventoy Version in Disk' <<< "$info"; then
        log_error "Ventoy no quedó instalado (detalles en $VENTOY_TOOL/log.txt)"
        return 1
    fi
    log_success "Ventoy instalado: $(grep 'Ventoy Version in Disk' <<< "$info" | cut -d: -f2 | tr -d ' ')"
    if [[ " ${opts[*]} " == *" -s "* ]]; then
        echo -e "${CYAN}💡 Con Secure Boot, la primera vez que arranques aparece una pantalla azul (MokManager):"
        echo -e "   elige \"Enroll key from disk\" → VTOYEFI → ENROLL_THIS_KEY_IN_MOKMANAGER.cer → Continue → Yes,"
        echo -e "   y reinicia. Se hace una sola vez por PC.${NC}"
    fi
    sleep 2
    confirm "${CYAN}¿Agregar sistemas al pendrive ahora?${NC}" && ventoy_add
    return 0
}

# 2. Agregar sistemas: descargarlos directo al pendrive o copiar ISOs que ya tienes
ventoy_add() {
    local option src dest free need img
    ventoy_pick_and_mount || return 1
    mkdir -p "$VENTOY_MNT/iso"
    while true; do
        echo -e "\n${CYAN}➕ Agregar al pendrive Ventoy${NC} (libre: ${GREEN}$(df -h --output=avail "$VENTOY_MNT" | tail -1 | tr -d ' ')${NC})"
        echo -e "  ${CYAN}1)${NC} ⬇ Descargar un sistema directo al pendrive (la misma lista de la opción 20, verificada)"
        echo -e "  ${CYAN}2)${NC} 📁 Copiar una ISO que ya tengo (se comprueba antes y después de copiar)"
        echo -e "  ${CYAN}0)${NC} Terminar"
        read -r -p "🔢 Opción: " option
        case $option in
            1)
                if usb_download_iso "$VENTOY_MNT/iso"; then
                    img=${USB_ISO#"$VENTOY_MNT"}
                    ventoy_conf_set alias "$img" "$(ventoy_alias_for "$USB_CHOSEN_NAME" "$USB_ISO_FILE")"
                    ventoy_write_json
                    sync
                    log_success "Agregado: $(basename "$USB_ISO")"
                fi ;;
            2)
                USB_ISO=""
                usb_pick_local_iso || continue
                src=$USB_ISO
                case $(realpath "$src") in
                    "$(realpath "$VENTOY_MNT")"/*) log_warning "Esa ISO ya está en el pendrive"; continue ;;
                esac
                usb_verify_local_iso "$src" || continue
                dest="$VENTOY_MNT/iso/$(basename "$src")"
                need=$(stat -c %s "$src")
                free=$(df -PB1 "$VENTOY_MNT" | awk 'NR == 2 {print $4}')
                if [ "$need" -gt "$free" ]; then
                    log_error "No entra: la ISO ocupa $(numfmt --to=iec "$need") y quedan $(numfmt --to=iec "$free")"
                    continue
                fi
                echo -e "${BLUE}📁 Copiando al pendrive...${NC}"
                if ! dd if="$src" of="$dest" bs=4M status=progress conv=fsync \
                    || ! { echo -e "${BLUE}🔍 Comprobando la copia...${NC}"; cmp -s "$src" "$dest"; }; then
                    rm -f -- "$dest"
                    log_error "La copia no salió bien (¿pendrive lleno o dañado?): se borró"
                    continue
                fi
                usb_write_sum_file "$dest" "$USB_VERIFIED_SUM"
                ventoy_conf_set alias "${dest#"$VENTOY_MNT"}" "$(ventoy_alias_for "$(ventoy_guess_name "$dest")" "$(basename "$dest")")"
                ventoy_write_json
                sync
                log_success "Copiada y comprobada: $(basename "$dest")" ;;
            *) break ;;
        esac
    done
    sync
    echo -e "${CYAN}💡 Al arrancar desde el pendrive, Ventoy muestra un menú con todos los sistemas.${NC}"
}

# Nombre del sistema de una ISO, si es de la lista (si no, el nombre del archivo)
ventoy_guess_name() {
    local name entry pattern dname
    name=$(basename "$1")
    for entry in "${USB_DISTROS[@]}"; do
        [[ "$entry" == "#"* ]] && continue
        pattern=$(usb_entry_pattern "$entry")
        if [[ "$name" =~ ^${pattern}$ ]]; then
            IFS='|' read -r _ dname _ <<< "$entry"
            echo "$dname"
            return
        fi
    done
    echo "${name%.*}"
}

# 3. Ver, comprobar y quitar las imágenes del pendrive
ventoy_manage() {
    local imgs=() i img choice expected got ok bad unknown f
    ventoy_pick_and_mount || return 1
    while true; do
        mapfile -t imgs < <(ventoy_list_images)
        echo -e "\n${CYAN}💿 Sistemas en el pendrive:${NC}"
        if [ ${#imgs[@]} -eq 0 ]; then
            echo -e "   ${YELLOW}(ninguno todavía: agrégalos con la opción 2)${NC}"
        fi
        i=1
        for img in "${imgs[@]}"; do
            printf "  ${CYAN}%2d)${NC} %s  ${YELLOW}(%s)${NC}%s\n" "$i" "$img" "$(du -h "$VENTOY_MNT$img" | cut -f1)" \
                "$(grep -q "^persist|$img|" "$VENTOY_MNT/ventoy/linux-ultimate-tools.conf" 2>/dev/null && echo "  💾 con persistencia")"
            i=$((i + 1))
        done
        echo -e "   Libre: ${GREEN}$(df -h --output=avail "$VENTOY_MNT" | tail -1 | tr -d ' ')${NC}"
        echo -e "\n  ${CYAN}c)${NC} Comprobar que todas estén enteras (con su suma oficial)"
        echo -e "  ${CYAN}q)${NC} Quitar una"
        echo -e "  ${CYAN}0)${NC} Volver"
        read -r -p "🔢 Opción: " choice
        case $choice in
            c|C)
                ok=0 bad=0 unknown=0
                for img in "${imgs[@]}"; do
                    echo -e "\n   ${BOLD}$img${NC}"
                    if ! usb_known_sum "$VENTOY_MNT$img"; then
                        echo -e "   ${YELLOW}? Sin suma conocida: no se puede comprobar${NC}"
                        unknown=$((unknown + 1))
                        continue
                    fi
                    expected=$USB_KNOWN_SUM
                    got=$(usb_hash_of "$VENTOY_MNT$img" ${#expected})
                    if [ "${got,,}" = "${expected,,}" ]; then
                        echo -e "   ${GREEN}✓ Entera${NC} ($USB_SUM_SRC)"
                        ok=$((ok + 1))
                    else
                        echo -e "   ${RED}✗ DAÑADA: no coincide con la suma oficial ($USB_SUM_SRC). Quítala y vuelve a agregarla${NC}"
                        bad=$((bad + 1))
                    fi
                done
                echo -e "\n   Enteras: ${GREEN}$ok${NC} · dañadas: ${RED}$bad${NC} · sin suma: ${YELLOW}$unknown${NC}" ;;
            q|Q)
                read -r -p "🔢 ¿Cuál quitar? (número, 0 = volver): " i
                [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -ge 1 ] && [ "$i" -le ${#imgs[@]} ] || continue
                img=${imgs[$((i - 1))]}
                confirm "${YELLOW}¿Quitar $img del pendrive?${NC}" || continue
                rm -f -- "$VENTOY_MNT$img"
                for f in "$VENTOY_MNT$img".sha256 "$VENTOY_MNT$img".sha512 "$VENTOY_MNT$img".md5; do
                    rm -f -- "$f"
                done
                f=$(grep "^persist|$img|" "$VENTOY_MNT/ventoy/linux-ultimate-tools.conf" 2>/dev/null | cut -d'|' -f3)
                if [ -n "$f" ] && [ -f "$VENTOY_MNT$f" ] && confirm "${YELLOW}¿Borrar también sus cambios guardados (persistencia, $(du -h "$VENTOY_MNT$f" | cut -f1))?${NC}"; then
                    rm -f -- "$VENTOY_MNT$f"
                fi
                ventoy_conf_set alias "$img" ""
                ventoy_conf_set persist "$img" ""
                ventoy_write_json
                sync
                log_success "Quitada: $img" ;;
            *) return 0 ;;
        esac
    done
}

# Tipo de persistencia que entiende un sistema live (vacío si no se conoce)
#   casper (Ubuntu y derivadas): etiqueta casper-rw; live-boot (Debian y derivadas): persistence
ventoy_persistence_kind() {
    case $(basename "$1") in
        ubuntu-*|kubuntu-*|xubuntu-*|lubuntu-*|ubuntu-mate-*|ubuntu-budgie-*|linuxmint-*|Zorin-OS-*|pop-os_*|neon-*) echo casper ;;
        debian-live-*|lmde-*|kali-linux-*-live-*) echo live-boot ;;
    esac
}

# 4. Persistencia: que el live guarde los cambios (programas, archivos, ajustes) entre reinicios
ventoy_persistence() {
    local imgs=() cands=() img i choice kind size free dat label opts
    ventoy_get_tool || return 1
    ventoy_pick_and_mount || return 1
    mapfile -t imgs < <(ventoy_list_images)
    for img in "${imgs[@]}"; do
        [ -n "$(ventoy_persistence_kind "$img")" ] && cands+=("$img")
    done
    if [ ${#cands[@]} -eq 0 ]; then
        log_warning "Ninguna ISO del pendrive admite persistencia con Ventoy de forma sencilla"
        echo -e "   Funciona con Ubuntu y sus sabores, Linux Mint, Zorin, Pop!_OS, KDE neon, Debian live, LMDE y Kali live."
        return 1
    fi
    echo -e "\n${CYAN}💾 ¿A cuál le guardo los cambios?${NC}"
    i=1
    for img in "${cands[@]}"; do
        printf "  ${CYAN}%d)${NC} %s\n" "$i" "$img"
        i=$((i + 1))
    done
    echo -e "  ${CYAN}0)${NC} Volver"
    read -r -p "🔢 Opción: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#cands[@]} ] || return 1
    img=${cands[$((choice - 1))]}
    kind=$(ventoy_persistence_kind "$img")
    dat="/persistence/$(basename "${img%.*}").dat"
    if [ -f "$VENTOY_MNT$dat" ]; then
        log_warning "Ya tiene persistencia ($(du -h "$VENTOY_MNT$dat" | cut -f1)): para cambiar el tamaño, quítala con la opción 3 y vuelve a crearla"
        return 1
    fi
    free=$(( $(df -PB1 "$VENTOY_MNT" | awk 'NR == 2 {print $4}') / 1048576 ))
    echo -e "\n${CYAN}Tamaño para los cambios${NC} (libre: ${free} MB):"
    echo -e "  ${CYAN}1)${NC} 2 GB   ${CYAN}2)${NC} 4 GB   ${CYAN}3)${NC} 8 GB   ${CYAN}4)${NC} 16 GB"
    read -r -p "🔢 Opción [2]: " choice
    case ${choice:-2} in
        1) size=2048 ;; 2) size=4096 ;; 3) size=8192 ;; 4) size=16384 ;; *) return 1 ;;
    esac
    if [ "$size" -gt $((free - 100)) ]; then
        log_error "No entra: necesita ${size} MB y quedan ${free} MB"
        return 1
    fi
    if [ "$kind" = casper ]; then
        label=casper-rw opts=()
    else
        label=persistence opts=(-c persistence.conf)
    fi
    mkdir -p "$VENTOY_MNT/persistence"
    echo -e "${BLUE}💾 Creando el archivo de persistencia (${size} MB, puede tardar unos minutos)...${NC}"
    if ! ventoy_run CreatePersistentImg.sh -s "$size" -t ext4 -l "$label" "${opts[@]}" -o "$VENTOY_MNT$dat" > /dev/null \
        || ! [ -f "$VENTOY_MNT$dat" ]; then
        rm -f -- "$VENTOY_MNT$dat"
        log_error "No se pudo crear la persistencia"
        return 1
    fi
    sync
    ventoy_conf_set persist "$img" "$dat"
    if ventoy_write_json; then
        log_success "Listo: $img guardará los cambios en $dat"
        echo -e "${CYAN}💡 Al arrancar, Ventoy pregunta si usar la persistencia: elige $(basename "$dat").${NC}"
    else
        echo -e "${CYAN}   Agrega a tu ventoy.json: \"persistence\": [{ \"image\": \"$img\", \"backend\": \"$dat\" }]${NC}"
    fi
}

# 5. Actualizar Ventoy en el pendrive (no borra las ISO)
ventoy_update() {
    local info old new
    ventoy_get_tool || return 1
    echo -e "\n${CYAN}Pendrive con Ventoy:${NC}"
    if [ -z "$(ventoy_candidates)" ] && [ -n "$(usb_candidates)" ]; then
        log_error "Ningún pendrive conectado tiene Ventoy"
        return 1
    fi
    usb_pick_device 0 ventoy_candidates || return 1
    info=$(ventoy_run Ventoy2Disk.sh -l "$USB_DEV" 2>/dev/null)
    old=$(grep 'Ventoy Version in Disk' <<< "$info" | cut -d: -f2 | tr -d ' ')
    new=$(cat "$VENTOY_TOOL/ventoy/version" 2>/dev/null)
    echo -e "   En el pendrive: ${YELLOW}${old:-?}${NC} · última: ${GREEN}$new${NC}"
    if [ -n "$old" ] && [ "$old" = "$new" ]; then
        log_success "Ya tiene la última versión de Ventoy"
        return 0
    fi
    confirm "${CYAN}¿Actualizar Ventoy? Las ISO y tus archivos del pendrive no se tocan${NC}" || return 0
    usb_unmount_dev "$USB_DEV" || return 1
    printf 'y\n' | ventoy_run Ventoy2Disk.sh -u "$USB_DEV" | grep -v '^$' | sed 's/^/   /'
    sleep 2
    info=$(ventoy_run Ventoy2Disk.sh -l "$USB_DEV" 2>/dev/null)
    if grep -q "Ventoy Version in Disk: *$new" <<< "$info"; then
        log_success "Ventoy actualizado a $new"
    else
        log_error "No se pudo actualizar (detalles en $VENTOY_TOOL/log.txt)"
        return 1
    fi
}

ventoy_menu() {
    local option
    while true; do
        clear
        echo -e "${BLUE}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║        🧰 VENTOY: VARIOS SISTEMAS EN UN SOLO PENDRIVE            ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo -e "Ventoy se instala una vez en el pendrive. Después los sistemas se copian como archivos y,"
        echo -e "al arrancar, eliges cuál probar o instalar. Puede guardar los cambios del live (persistencia)."
        echo -e "${YELLOW}Ventoy es de longpanda (ventoy.net, GPL-3.0): se baja de su sitio oficial y se verifica.${NC}\n"
        echo -e "  ${BLUE}1)${NC} 🧰 Instalar Ventoy en un pendrive (lo borra)"
        echo -e "  ${BLUE}2)${NC} ➕ Agregar sistemas (descargarlos directo al pendrive o copiar ISOs)"
        echo -e "  ${BLUE}3)${NC} 💿 Ver, comprobar y quitar los sistemas del pendrive"
        echo -e "  ${BLUE}4)${NC} 💾 Guardar los cambios del live (persistencia)"
        echo -e "  ${BLUE}5)${NC} 🔄 Actualizar Ventoy en el pendrive (no borra los sistemas)"
        echo -e "  ${BLUE}0)${NC} 🔙 Volver\n"
        read -r -p "📌 Opción (0-5): " option
        case $option in
            1) ventoy_install ;;
            2) ventoy_add ;;
            3) ventoy_manage ;;
            4) ventoy_persistence ;;
            5) ventoy_update ;;
            *) return 0 ;;
        esac
        pause
    done
}

main_menu() {
    $BOOT_ONLY && boot_only_menu
    while true; do
        print_header
        echo -e "${CYAN}📌 ¿Qué deseas hacer?${NC}\n"
        echo -e "  ${CYAN} 1)${NC} 🔄 ACTUALIZAR SISTEMA (pacman -Syu y Flatpak)"
        echo -e "  ${CYAN} 2)${NC} 🛡️ AUDITORÍA DE SEGURIDAD (Lynis y registro de auditoría)"
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

# Aviso del primer uso: qué licencia tiene, que no tiene garantía y que modifica el sistema.
# No es una condición de la licencia (la AGPL permite ejecutar el programa sin aceptarla):
# solo confirma que la persona entiende lo que hace el script. Se muestra una vez por versión del aviso.
NOTICE_VERSION=1
NOTICE_FILE="$STATE_DIR/aviso-primer-uso.txt"

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

notice_save() {
    mkdir -p "$STATE_DIR"
    printf 'version=%s\nfecha=%s\n' "$NOTICE_VERSION" "$(date '+%Y-%m-%d %H:%M')" > "$NOTICE_FILE"
}

SCRIPT_FAMILY=arch
# ¿Cuál de los tres scripts corresponde a este sistema? (ubuntu, debian o arch; vacío si ninguno)
# Linux Mint y Pop!_OS cuentan como Ubuntu; LMDE y Kali como Debian; Manjaro y EndeavourOS como Arch.
right_script_family() {
    local ids=" $(os_release_value ID) $(os_release_value ID_LIKE) "
    if [[ "$ids" == *" ubuntu "* ]]; then
        echo ubuntu
    elif [[ "$ids" == *" debian "* ]]; then
        echo debian
    elif [[ "$ids" == *" arch "* || "$ids" == *" archlinux "* || "$ids" == *" manjaro "* ]]; then
        echo arch
    fi
}

# Si se abrió el script de otra distribución, lo dice y ofrece abrir (o descargar) el correcto
offer_right_script() {
    local want name here path url answer
    want=$(right_script_family)
    [ -n "$want" ] && [ "$want" != "$SCRIPT_FAMILY" ] || return 0
    name="$want-ultimate-tools.sh"
    here=$(dirname "$(readlink -f "$0")")
    path="$here/$name"
    url="https://raw.githubusercontent.com/george0884/linux-ultimate-tools/main/$name"
    echo -e "${YELLOW}🐧 Detecté ${BOLD}$(os_release_value PRETTY_NAME)${NC}${YELLOW}: el script para este sistema es ${BOLD}$name${NC}"
    echo -e "${YELLOW}   Con este ($(basename "$0")) solo están el menú de arranque y descargar sistemas y crear un USB de instalación.${NC}\n"
    if [ -f "$path" ]; then
        read -r -p "¿Abrir $name ahora? (s/n): " answer
    else
        echo -e "${CYAN}   No está en esta carpeta. Se puede bajar del repositorio oficial del proyecto:${NC}"
        echo -e "${CYAN}   $url${NC}"
        [ -w "$here" ] || path="$HOME/$name"
        read -r -p "¿Descargarlo en $(dirname "$path") y abrirlo? (s/n): " answer
        if [[ "$answer" =~ ^([sSyY]|[sS][iIíÍ])$ ]]; then
            if ! curl -fsSL -o "$path" "$url"; then
                echo -e "${RED}❌ No se pudo descargar: sigue con este script${NC}\n"
                return 0
            fi
            chmod +x "$path"
        fi
    fi
    if [[ "$answer" =~ ^([sSyY]|[sS][iIíÍ])$ ]]; then
        # El aviso del primer uso ya se leyó en este script
        exec bash "$path" --entiendo
    fi
    echo -e "${YELLOW}ℹ Sigues con $(basename "$0")${NC}\n"
}

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
