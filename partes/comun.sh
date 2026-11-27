#@ partes/comun.sh — Base compartida por los tres scripts: mensajes, confirmaciones, barra de avance, menús de selección, RAM y swap, red, energía, temas, accesos directos, información del sistema y avisos.
#@ Pieza para armar los scripts: no se ejecuta sola. Después de editarla corre "bash armar.sh".
#@ Cada "#@@ nombre" empieza una función o un bloque; las líneas "#@" no pasan a los scripts.
#@@ log

# ============================================================
# FUNCIONES DE LOG Y PROGRESO
# ============================================================

log() {
    local msg="$1"
    echo -e "$msg"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOG_FILE"
}
#@@ log_info

log_info() { log "${BLUE}ℹ $1${NC}"; }
#@@ log_success
log_success() { log "${GREEN}✓ $1${NC}"; }
#@@ log_error
log_error() { log "${RED}✗ $1${NC}"; }
#@@ log_warning
log_warning() { log "${YELLOW}⚠ $1${NC}"; }
#@@ log_title
log_title() { log "\n${PURPLE}${BOLD}► $1${NC}\n"; }
#@@ clear

clear() {
    $AUTO_MODE || command clear
}
#@@ pause

pause() {
    $AUTO_MODE && return 0
    echo -e "\n${YELLOW}─────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}📌 Presiona Enter para continuar...${NC}"
    read -r
}
#@@ confirm

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
    # Dentro de una opción de un menú, 0 vuelve a ese menú en cualquier pregunta s/n
    if [ -n "${MENU_SUBSHELL:-}" ]; then
        echo -e -n "$prompt (s/n, 0 = volver al menú): "
    else
        echo -e -n "$prompt (s/n): "
    fi
    read -r response
    if [ "$response" = 0 ] && [ -n "${MENU_SUBSHELL:-}" ]; then
        echo -e "${YELLOW}↩ Volviendo al menú (lo que ya se hizo queda hecho)${NC}"
        sleep 1
        exit 2
    fi
    [[ "$response" =~ ^([sSyY]|[sS][iI]|[sS]í|[sS]Í)$ ]]
}
#@@ submenu_run

# Corre una opción de un submenú en su propio subshell: si en una pregunta s/n respondes 0, se
# vuelve a ESE submenú (no al menú principal). Devuelve 2 si se canceló con 0
submenu_run() {
    ( MENU_SUBSHELL=1; "$@" )
    MENU_RC=$?
    return $MENU_RC
}
#@@ menu_pause

# Pausa después de una opción, salvo que se haya cancelado con 0 (no hay nada que leer)
menu_pause() {
    if [ "${MENU_RC:-0}" = 2 ]; then
        MENU_RC=0
        return 0
    fi
    MENU_RC=0
    pause
}
#@@ run

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
#@@ progress_wanted

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
#@@ progress_draw

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
#@@ run_with_progress

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
#@@ set_terminal_title

# Nombre del script en la pestaña y la ventana de la terminal (Konsole muestra la carpeta si no)
set_terminal_title() {
    [ -t 1 ] || return 0
    printf '\033]0;%s\007\033]30;%s\007' "$1" "$1"
    trap 'printf "\033]30;\007"' EXIT
}
#@@ run_visible

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
#@@ set_sysctl

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
#@@ datos_whiptail_colors

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
#@@ checklist_tool

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
#@@ checklist_select

# Lista con casillas: barra espaciadora para marcar, Enter para aceptar.
# Entradas "paquete|descripción" o "paquete|descripción|ON" (casilla ya marcada);
# deja lo elegido en CHOSEN. Devuelve 1 si se cancela.
# Con CHECKLIST_NOTAGS=true no se muestra la columna de nombres internos.
# Si no hay dialog ni whiptail (o no es una terminal interactiva) se elige escribiendo números;
# LISTAS=numeros lo fuerza. En el celular (Termux) también son casillas: dialog va sin ratón para
# que tocar la pantalla siga abriendo el teclado.
checklist_select() {
    local title="$1" text="$2"
    shift 2
    local entries=("$@") args=() entry name desc status i=0 input num tool="" has_sys=false width
    CHOSEN=()
    width=$(tput cols 2>/dev/null || echo 80)

    [ -t 0 ] && [ -t 1 ] && [ "${LISTAS:-}" != numeros ] && tool=$(checklist_tool)
    if [ -n "$tool" ]; then
        local cols lines w h lh tagw=0 max_desc out notags="${CHECKLIST_NOTAGS:-}"
        cols=$(tput cols 2>/dev/null || echo 80)
        lines=$(tput lines 2>/dev/null || echo 24)
        # Ancho según la terminal (entre 60 y 120 columnas) y alto justo para la lista
        w=$((cols - 4))
        [ "$w" -gt 120 ] && w=120
        [ "$w" -lt 60 ] && w=$((cols < 62 ? cols - 2 : 60))
        if [ -z "$notags" ]; then
            for entry in "${entries[@]}"; do
                name=${entry%%|*}
                [ ${#name} -gt "$tagw" ] && tagw=${#name}
            done
            [ "$tagw" -gt 28 ] && tagw=28
        fi
        # Lo que queda para la descripción: así ningún renglón se sale del recuadro
        max_desc=$((w - tagw - 14))
        [ "$max_desc" -lt 12 ] && max_desc=12
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
            # --no-mouse: con el ratón activado, en Termux tocar la pantalla ya no abre el teclado
            out=$(DIALOGRC="${DIALOGRC:-$rc_file}" NCURSES_NO_UTF8_ACS=1 dialog --no-mouse --colors --title " $title " --ok-label "Aceptar" --cancel-label "Cancelar" \
                --separate-output ${notags:+--no-tags} \
                --checklist "$text\n\nEspacio: marcar/desmarcar · Flechas: moverse · Enter: aceptar" \
                0 0 0 "${args[@]}" 3>&1 1>&2 2>&3)
            local rc=$?
            rm -f "$rc_file"
            [ $rc -eq 0 ] || return 1
        else
            $has_sys && text="$text\n⚠ SISTEMA = herramienta del sistema o de tu distribución: quítala solo si sabes que no la usas"
            out=$(NEWT_COLORS="${NEWT_COLORS:-$WHIPTAIL_COLORS}" \
                whiptail --title "$title" --ok-button "Aceptar" --cancel-button "Cancelar" \
                --separate-output ${notags:+--notags} \
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
        if [ "$width" -lt 70 ]; then
            # Pantalla angosta: solo la descripción, recortada para que no se parta en dos renglones
            desc=${entry#*|}
            [ ${#desc} -gt $((width - 12)) ] && desc="${desc:0:$((width - 13))}…"
            printf "${CYAN}%2s)${NC} [%s] %s\n" "$i" "$status" "$desc"
        elif [ -n "$CHECKLIST_NOTAGS" ]; then
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
#@@ has_desktop

has_desktop() { [ "$FLAVOR" != server ]; }
#@@ desktop_only

# Aviso para las opciones que dependen de un escritorio concreto
desktop_only() {
    local needed="$1" what="$2"
    [[ " $needed " == *" $DESKTOP "* ]] && return 0
    log_warning "$what no está disponible en $FLAVOR_NAME ($DESKTOP_NAME)"
    return 1
}
#@@ print_pkgs_described
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
#@@ desktop_file_owners

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
#@@ detected_app_entries

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
#@@ flatpak_app_entries

# Apps de Flatpak instaladas: "flatpak:ID|📦 Nombre (Flatpak)"
flatpak_app_entries() {
    command -v flatpak &> /dev/null || return 0
    local id name
    flatpak list --app --columns=application,name 2>/dev/null | while IFS=$'\t' read -r id name; do
        [ -n "$id" ] && echo "flatpak:$id|📦 ${name:-$id} (Flatpak)"
    done
}
#@@ remove_flatpak_apps

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
#@@ system_app_pkgs

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
#@@ optimize_gpu_menu

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
            1) submenu_run optimize_nvidia ;;
            2) submenu_run optimize_amd ;;
            3) submenu_run optimize_intel ;;
            4) submenu_run auto_detect_gpu ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        menu_pause
        return 0
    done
}
#@@ enable_trim

enable_trim() {
    run "No se pudo habilitar fstrim.timer" sudo systemctl enable --now fstrim.timer \
        && log_success "TRIM automático semanal habilitado"
}
#@@ datos_swapfile

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
#@@ zram_swap_active

zram_swap_active() { swapon --noheadings --show=NAME 2>/dev/null | grep -q '^/dev/zram'; }
#@@ disk_swap_active
disk_swap_active() { swapon --noheadings --show=NAME 2>/dev/null | grep -qv '^/dev/zram'; }
#@@ swapfile_active
swapfile_active() { swapon --noheadings --show=NAME 2>/dev/null | grep -qx "$SWAPFILE"; }
#@@ swap_summary

# "8G (archivo /swapfile) + 15,6G (ZRAM)" o "ninguno"
swap_summary() {
    local out
    out=$(swapon --noheadings --show=NAME,TYPE,SIZE 2>/dev/null | awk '{
        kind = ($1 ~ /^\/dev\/zram/) ? "ZRAM" : ($2 == "file" ? "archivo " $1 : "partición " $1)
        printf "%s%s (%s)", sep, $3, kind; sep = " + " }')
    echo "${out:-ninguno}"
}
#@@ ram_swappiness_auto

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
#@@ apply_ram_tweaks

apply_ram_tweaks() {
    echo -e "${YELLOW}🔧 Ajustando el uso de la memoria...${NC}"
    set_sysctl vm.vfs_cache_pressure 50
    echo -e "  ${GREEN}✓ Caché de archivos optimizada (vfs_cache_pressure=50)${NC}"
    ram_swappiness_auto
}
#@@ suggest_swap_gb

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
#@@ create_swapfile

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
    if ! grep -qE "^[[:space:]]*${SWAPFILE}[[:space:]]" /etc/fstab; then
        echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
    fi
    mkdir -p "$STATE_DIR"
    echo "$(date '+%Y-%m-%d %H:%M')|${gb}G" > "$STATE_DIR/swapfile.txt"
    log_success "Archivo swap de $gb GB activo (se mantiene al reiniciar)"
    ram_swappiness_auto
}
#@@ remove_swapfile

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
    sudo sed -i "\\#^[[:space:]]*${SWAPFILE}[[:space:]]#d" /etc/fstab
    sudo rm -f -- "$SWAPFILE"
    rm -f "$STATE_DIR/swapfile.txt"
    log_success "Archivo swap quitado"
    ram_swappiness_auto
}
#@@ swappiness_manual

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
#@@ ram_status

ram_status() {
    echo -e "${YELLOW}📊 Memoria${NC}"
    free -h | sed 's/^/   /'
    echo -e "\n${YELLOW}💽 Swap${NC}"
    swapon --show 2>/dev/null | sed 's/^/   /' | grep . || echo "   (ninguno)"
    echo -e "\n   swappiness=$(cat /proc/sys/vm/swappiness) · vfs_cache_pressure=$(cat /proc/sys/vm/vfs_cache_pressure)"
}
#@@ disable_zram_auto

# Opción 15 → 5: quita ZRAM y ajusta el swappiness a lo que quede
disable_zram_auto() { disable_zram && ram_swappiness_auto; }
#@@ optimize_ram_menu

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
            1) submenu_run apply_ram_tweaks ;;
            2) submenu_run create_swapfile ;;
            3) submenu_run remove_swapfile ;;
            4) submenu_run enable_zram ;;
            5) submenu_run disable_zram_auto ;;
            6) submenu_run swappiness_manual ;;
            7) submenu_run ram_status ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        menu_pause
    done
}
#@@ tokyo_color_group

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
#@@ write_tokyo_night_colors

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
#@@ write_tokyo_night_konsole

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
#@@ save_theme_value

# Anota un ajuste del tema tal como estaba antes del primer cambio (para "Revertir")
save_theme_value() {
    local key="$1" value="$2"
    mkdir -p "$STATE_DIR"
    grep -qs "^$key=" "$THEME_BACKUP" || echo "$key=$value" >> "$THEME_BACKUP"
}
#@@ theme_value

theme_value() { sed -n "s/^$1=//p" "$THEME_BACKUP" 2>/dev/null | head -n1; }
#@@ kde_color_scheme

kde_color_scheme() { sed -n '/^\[General\]/,/^\[/ s/^ColorScheme=//p' "$HOME/.config/kdeglobals" 2>/dev/null | head -n1; }
#@@ install_tokyo_night_theme

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
#@@ datos_tokyo_gtk
# Tema GTK Tokyo Night de Fausto-Korpsvart (GPL-3.0): se baja de su repositorio oficial y se instala
# con su propio instalador en ~/.themes (y en ~/.config/gtk-4.0 para las apps nuevas de GNOME)
TOKYO_GTK_GIT="https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme"
TOKYO_GTK_TGZ="https://codeload.github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme/tar.gz/refs/heads/master"
TOKYO_GTK_NAME="Tokyonight-Dark"
TOKYO_TERMINAL_NAME="Tokyo Night"
# Para que las apps Qt (VLC, qBittorrent...) usen los colores del tema GTK
TOKYO_QT_ENV="$HOME/.config/environment.d/60-ultimate-tools-qt.conf"
#@@ install_tokyo_night_gnome

# Tokyo Night para GNOME: tema GTK (ventanas y apps de GNOME), modo oscuro y perfil de GNOME Terminal
install_tokyo_night_gnome() {
    local tmp f ok=false
    echo -e "${CYAN}🎨 Aplicando Tokyo Night a GNOME...${NC}"
    # Lo que necesita su instalador para armar el tema
    if command -v apt-get &> /dev/null; then
        apt_install_recorded sassc gtk2-engines-murrine gnome-themes-extra || return 1
    elif command -v pacman &> /dev/null; then
        pkg_install_recorded sassc gtk-engine-murrine gnome-themes-extra || return 1
    fi
    tmp=$(mktemp -d)
    if command -v git &> /dev/null; then
        git clone -q --depth 1 "$TOKYO_GTK_GIT" "$tmp/src" >> "$LOG_FILE" 2>&1
    fi
    if ! [ -f "$tmp/src/themes/install.sh" ]; then
        mkdir -p "$tmp/src"
        curl -sSfL -m 120 "$TOKYO_GTK_TGZ" 2>>"$LOG_FILE" | tar -xz --strip-components=1 -C "$tmp/src" 2>>"$LOG_FILE"
    fi
    if ! [ -f "$tmp/src/themes/install.sh" ]; then
        rm -rf -- "$tmp"
        log_error "No se pudo bajar el tema Tokyo Night (¿hay internet?)"
        return 1
    fi
    # Si ya tenías tu propio estilo para las apps nuevas de GNOME, se guarda una copia
    for f in gtk.css gtk-dark.css assets; do
        if [ -e "$HOME/.config/gtk-4.0/$f" ] && ! [ -L "$HOME/.config/gtk-4.0/$f" ] \
            && ! [ -e "$HOME/.config/gtk-4.0/$f.antes-de-ultimate-tools" ]; then
            mv "$HOME/.config/gtk-4.0/$f" "$HOME/.config/gtk-4.0/$f.antes-de-ultimate-tools"
        fi
    done
    echo -e "${BLUE}🔧 Armando el tema (un minuto)...${NC}"
    ( cd "$tmp/src/themes" && bash ./install.sh -c dark -l ) >> "$LOG_FILE" 2>&1 \
        && [ -d "$HOME/.themes/$TOKYO_GTK_NAME" ] && ok=true
    rm -rf -- "$tmp"
    if ! $ok; then
        log_error "No se pudo instalar el tema Tokyo Night (detalles en $LOG_FILE)"
        return 1
    fi
    save_theme_value gnome-estilo "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
    save_theme_value gnome-tema "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)"
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null
    run "No se pudo aplicar el tema" gsettings set org.gnome.desktop.interface gtk-theme "$TOKYO_GTK_NAME" || return 1
    log_success "Tema Tokyo Night aplicado (las apps abiertas lo toman al volver a abrirlas)"
    tokyo_night_qt
    tokyo_night_gnome_terminal
    echo -e "${CYAN}ℹ Para volver al tema anterior: opción 11 (Revertir)${NC}"
}
#@@ tokyo_night_qt

# Apps Qt en GNOME: el complemento oficial de Qt para GTK les pasa los colores del tema GTK (Qt 5 y Qt 6)
tokyo_night_qt() {
    local pkgs=() f
    if command -v apt-get &> /dev/null; then
        mapfile -t pkgs < <(available_pkgs qt5-gtk-platformtheme qt6-gtk-platformtheme)
        [ ${#pkgs[@]} -gt 0 ] && { apt_install_recorded "${pkgs[@]}" || return 1; }
    fi
    # Si ya elegiste otro tema para Qt (qt5ct, Kvantum...), no se toca
    for f in "$HOME"/.config/environment.d/*.conf; do
        [ -f "$f" ] && [ "$f" != "$TOKYO_QT_ENV" ] && grep -q '^QT_QPA_PLATFORMTHEME=' "$f" && {
            echo -e "${YELLOW}ℹ Ya elegiste un tema para las apps Qt en $f: no se cambia${NC}"
            return 0
        }
    done
    mkdir -p "$(dirname "$TOKYO_QT_ENV")"
    printf '%s\n' "# Linux Ultimate Tools (tema Tokyo Night): las apps Qt usan los colores del tema GTK" \
        "QT_QPA_PLATFORMTHEME=gtk3" > "$TOKYO_QT_ENV"
    log_success "Las apps Qt (VLC, qBittorrent...) usarán los colores Tokyo Night desde el próximo inicio de sesión"
}
#@@ tokyo_night_gnome_terminal

# Perfil "Tokyo Night" en GNOME Terminal, como predeterminado (el anterior queda anotado para Revertir)
tokyo_night_gnome_terminal() {
    local list uuid base
    if ! command -v gnome-terminal &> /dev/null || ! command -v dconf &> /dev/null; then
        command -v ptyxis &> /dev/null \
            && echo -e "${CYAN}ℹ En la terminal Ptyxis: Preferencias → Perfiles → elige una paleta oscura${NC}"
        return 0
    fi
    list=$(gsettings get org.gnome.Terminal.ProfilesList list 2>/dev/null)
    # Si ya existe, se reutiliza
    for uuid in $(grep -oE "[0-9a-f-]{36}" <<< "$list"); do
        [ "$(dconf read "/org/gnome/terminal/legacy/profiles:/:$uuid/visible-name")" = "'$TOKYO_TERMINAL_NAME'" ] && break
        uuid=""
    done
    if [ -z "$uuid" ]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
        base="/org/gnome/terminal/legacy/profiles:/:$uuid"
        dconf write "$base/visible-name" "'$TOKYO_TERMINAL_NAME'"
        dconf write "$base/use-theme-colors" false
        dconf write "$base/background-color" "'#1a1b26'"
        dconf write "$base/foreground-color" "'#c0caf5'"
        dconf write "$base/palette" "['#15161e', '#f7768e', '#9ece6a', '#e0af68', '#7aa2f7', '#bb9af7', '#7dcfff', '#a9b1d6', '#414868', '#f7768e', '#9ece6a', '#e0af68', '#7aa2f7', '#bb9af7', '#7dcfff', '#c0caf5']"
        if [ "$list" = "@as []" ] || [ -z "$list" ]; then
            list="['$uuid']"
        else
            list="${list%]}, '$uuid']"
        fi
        gsettings set org.gnome.Terminal.ProfilesList list "$list"
    fi
    save_theme_value gnome-terminal-perfil "$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null)"
    gsettings set org.gnome.Terminal.ProfilesList default "'$uuid'" \
        && log_success "GNOME Terminal usará Tokyo Night en las ventanas nuevas"
}
#@@ gnome_dark_mode

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
#@@ android_tools_installed

android_tools_installed() { [ -x "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" ]; }
#@@ enough_space

# Avisa si no hay espacio suficiente (en GB) en la carpeta dada
enough_space() {
    local dir="$1" need="$2" free
    free=$(df -BG --output=avail "$dir" 2>/dev/null | tail -1 | tr -dc '0-9')
    [ -z "$free" ] || [ "$free" -ge "$need" ] && return 0
    log_error "Hace falta unos $need GB libres en $dir y hay $free GB"
    return 1
}
#@@ check_sum

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
#@@ android_sdk_packages

# Paquetes de Google para la última versión estable de Android
android_sdk_packages() {
    local list platform build
    list=$("$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK" --list 2>/dev/null)
    platform=$(grep -oE '^ *platforms;android-[0-9]+ ' <<< "$list" | tr -d ' ' | sort -t- -k2 -n | tail -n1)
    build=$(grep -oE '^ *build-tools;[0-9.]+ ' <<< "$list" | tr -d ' ' | sort -V | tail -n1)
    echo platform-tools $platform $build
}
#@@ check_kvm

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
#@@ flatpak_latest_branch

# Última versión de un SDK de Flathub (las versiones con letras o "-" se ignoran)
flatpak_latest_branch() {
    flatpak remote-ls --system flathub --runtime --columns=application,branch 2>/dev/null \
        | awk -v app="$1" '$1 == app {print $2}' | grep -E '^[0-9]+(\.[0-9]+)?$' | sort -V | tail -n1
}
#@@ remove_flatpak_sdks

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
#@@ make_backup

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
#@@ docker_installed

docker_installed() { command -v docker &> /dev/null; }
#@@ docker_usage

# Tamaño ocupado por Docker (imágenes, contenedores, volúmenes)
docker_usage() {
    sudo docker system df 2>/dev/null | sed 's/^/   /'
    sudo du -sh /var/lib/docker 2>/dev/null | awk '{print "   Total en disco: " $1}'
}
#@@ remove_docker

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
#@@ seamonkey_installed
seamonkey_installed() { [ -x "$SEAMONKEY_DIR/seamonkey" ]; }
#@@ install_seamonkey

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
#@@ remove_seamonkey

remove_seamonkey() {
    seamonkey_installed || return 0
    [ "$SEAMONKEY_DIR" = /opt/seamonkey ] && sudo rm -rf -- /opt/seamonkey
    sudo rm -f /usr/local/bin/seamonkey /usr/local/share/applications/seamonkey.desktop
    rm -f "$STATE_DIR/seamonkey.txt"
    log_success "SeaMonkey quitado (tu perfil en ~/.mozilla/seamonkey no se toca)"
}
#@@ restore_theme

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
                value=$(theme_value gnome-terminal-perfil)
                [ -n "$value" ] && gsettings set org.gnome.Terminal.ProfilesList default "$value" 2>/dev/null
                log_success "Tema de GNOME restaurado"
            else
                echo -e "  ${GREEN}✓ El script no cambió el tema de GNOME${NC}"
            fi
            # Tema Tokyo Night: los enlaces de las apps nuevas de GNOME y el tema en ~/.themes
            local f
            for f in gtk.css gtk-dark.css assets; do
                if [ -L "$HOME/.config/gtk-4.0/$f" ] && [[ "$(readlink "$HOME/.config/gtk-4.0/$f")" == *Tokyonight* ]]; then
                    rm -f "$HOME/.config/gtk-4.0/$f"
                fi
                [ -e "$HOME/.config/gtk-4.0/$f.antes-de-ultimate-tools" ] && ! [ -e "$HOME/.config/gtk-4.0/$f" ] \
                    && mv "$HOME/.config/gtk-4.0/$f.antes-de-ultimate-tools" "$HOME/.config/gtk-4.0/$f"
            done
            if [ -f "$TOKYO_QT_ENV" ]; then
                rm -f "$TOKYO_QT_ENV"
                log_success "Las apps Qt vuelven a su aspecto anterior (desde el próximo inicio de sesión)"
            fi
            if compgen -G "$HOME/.themes/Tokyonight*" > /dev/null; then
                rm -rf -- "$HOME"/.themes/Tokyonight*
                log_success "Tema Tokyo Night quitado"
            fi
            ;;
        *) echo -e "  ${GREEN}✓ El script no cambia el tema de ${DESKTOP_NAME}${NC}" ;;
    esac
    rm -f "$THEME_BACKUP"
}
#@@ shutdown_menu

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
#@@ datos_plasma_appletsrc

# ============================================================
# OPCIÓN 6: QUITAR ACCESOS DIRECTOS (COLOR: CIAN)
# ============================================================

PLASMA_APPLETSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
#@@ desktop_dir

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
#@@ stop_plasmashell

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
#@@ start_plasmashell

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
#@@ taskmanager_applets

# IDs "contenedor applet" de los gestores de tareas del panel
taskmanager_applets() {
    [ -f "$PLASMA_APPLETSRC" ] || return 0
    awk '
        /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { g = $0; next }
        /^\[/ { g = "" }
        g != "" && /^plugin=org\.kde\.plasma\.(icontasks|taskmanager)$/ { gsub(/[^0-9]+/, " ", g); print g }
    ' "$PLASMA_APPLETSRC"
}
#@@ remove_desktop_shortcuts

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
#@@ remove_gnome_favorites

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
#@@ restore_gnome_favorites

restore_gnome_favorites() {
    if [ ! -f "$GNOME_FAVORITES_BACKUP" ]; then
        echo -e "  ${YELLOW}ℹ No hay copia del dock guardada${NC}"
        return 0
    fi
    run "No se pudo restaurar el dock" gsettings set org.gnome.shell favorite-apps "$(cat "$GNOME_FAVORITES_BACKUP")" \
        && rm -f "$GNOME_FAVORITES_BACKUP" && log_success "Dock restaurado"
}
#@@ remove_panel_launchers

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
#@@ restore_desktop_shortcuts

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
#@@ restore_panel_launchers

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
#@@ restore_all_shortcuts

# Opción 6 → 3
restore_all_shortcuts() { restore_desktop_shortcuts; restore_panel_launchers; }
#@@ remove_shortcuts_menu

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
            1) submenu_run remove_desktop_shortcuts ;;
            2) submenu_run remove_panel_launchers ;;
            3) submenu_run restore_all_shortcuts ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        menu_pause
    done
}
#@@ dns_provider_field

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
#@@ measure_dns

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
#@@ set_fastest_dns

set_fastest_dns() {
    if ! measure_dns; then
        log_error "Ningún DNS respondió (¿hay conexión a internet?)"
        return 1
    fi
    echo -e "${GREEN}🏆 Más rápido: $FASTEST_DNS${NC}"
    set_dns "$FASTEST_DNS"
}
#@@ bbr_algorithm

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
#@@ enable_bbr

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
#@@ disable_bbr

disable_bbr() {
    sudo rm -f "$BBR_MODULES_FILE"
    sudo sed -i '/^net\.core\.default_qdisc/d; /^net\.ipv4\.tcp_congestion_control/d' "$SYSCTL_FILE" 2>/dev/null
    # Valores por defecto de Ubuntu
    run "No se pudo restaurar TCP" sudo sysctl -w net.ipv4.tcp_congestion_control=cubic net.core.default_qdisc=fq_codel \
        && log_success "TCP vuelve a la configuración por defecto (cubic)"
}
#@@ disable_wifi_powersave

# El ahorro de energía del Wi-Fi causa picos de latencia y microcortes
disable_wifi_powersave() {
    printf '[connection]\nwifi.powersave = 2\n' | sudo tee "$NM_WIFI_CONF" > /dev/null
    run "No se pudo recargar NetworkManager" sudo systemctl reload NetworkManager \
        && log_success "Ahorro de energía del Wi-Fi desactivado (se aplica al reconectar)"
}
#@@ enable_wifi_powersave

enable_wifi_powersave() {
    sudo rm -f "$NM_WIFI_CONF"
    run "No se pudo recargar NetworkManager" sudo systemctl reload NetworkManager \
        && log_success "Ahorro de energía del Wi-Fi restaurado"
}
#@@ toggle_bbr

# Opción 16 → 4: activa BBR, o lo desactiva si ya está activo
toggle_bbr() {
    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == bbr* ]]; then
        confirm "${BLUE}BBR ya está activo. ¿Desactivarlo?${NC}" && disable_bbr
    else
        enable_bbr
    fi
}
#@@ toggle_wifi_powersave

# Opción 16 → 5: quita el ahorro de energía del Wi-Fi, o lo restaura si ya estaba quitado
toggle_wifi_powersave() {
    if [ -f "$NM_WIFI_CONF" ]; then
        confirm "${BLUE}El ahorro del Wi-Fi ya está desactivado. ¿Restaurarlo?${NC}" && enable_wifi_powersave
    else
        disable_wifi_powersave
    fi
}
#@@ network_menu

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
                    submenu_run set_dns "${entry%%|*}"
                else
                    log_error "Opción inválida"
                fi
                ;;
            2) submenu_run set_fastest_dns ;;
            3) submenu_run reset_dns ;;
            4) submenu_run toggle_bbr ;;
            5) submenu_run toggle_wifi_powersave ;;
            6) submenu_run install_recommended_drivers ;;
            7) submenu_run update_firmware ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        menu_pause
    done
}
#@@ is_laptop

# ============================================================
# OPCIÓN 17: ENERGÍA Y RENDIMIENTO (COLOR: AMARILLO)
# ============================================================

is_laptop() {
    ls /sys/class/power_supply/BAT* &> /dev/null
}
#@@ current_power_profile

current_power_profile() {
    if command -v tlp &> /dev/null && systemctl is-enabled --quiet tlp 2>/dev/null; then
        echo "TLP"
    elif command -v powerprofilesctl &> /dev/null; then
        powerprofilesctl get 2>/dev/null
    else
        echo "desconocido"
    fi
}
#@@ power_profiles_available

# Perfiles de power-profiles-daemon: performance | balanced | power-saver
power_profiles_available() {
    powerprofilesctl list 2>/dev/null | grep -oE '^[ *]*[a-z-]+:' | tr -d ' *:' | tr '\n' ' '
}
#@@ set_gaming_power

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
#@@ enable_power_saving

# Portátil: TLP. Escritorio: perfil de ahorro de power-profiles-daemon
enable_power_saving() {
    if is_laptop; then
        install_tlp
    else
        set_power_profile power-saver
    fi
}
#@@ baloo_cmd

baloo_cmd() {
    command -v balooctl6 || command -v balooctl
}
#@@ disable_baloo

# Baloo indexa todos los archivos para la búsqueda: consume CPU, disco y batería
disable_baloo() {
    local cmd
    cmd=$(baloo_cmd) || { echo -e "  ${YELLOW}ℹ Baloo no está instalado${NC}"; return 0; }
    run "No se pudo desactivar Baloo" "$cmd" disable && log_success "Indexador de archivos Baloo desactivado"
}
#@@ gnome_indexer_unit

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
#@@ indexer_disabled

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
#@@ disable_indexer

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
#@@ enable_indexer

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
#@@ enable_baloo

enable_baloo() {
    local cmd
    cmd=$(baloo_cmd) || { log_error "Baloo no está instalado"; return 1; }
    run "No se pudo activar Baloo" "$cmd" enable && log_success "Indexador de archivos Baloo activado"
}
#@@ enable_steam_play

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
#@@ steam_play_vdf

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
#@@ remove_proton_ge

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
#@@ install_tlp_confirm

# Opción 17 → 4
install_tlp_confirm() { confirm "${YELLOW}¿Instalar TLP?${NC}" && install_tlp; }
#@@ toggle_indexer

# Opción 17 → 5: desactiva el indexador de archivos, o lo vuelve a activar
toggle_indexer() {
    if indexer_disabled; then
        enable_indexer
    else
        disable_indexer
    fi
}
#@@ install_gaming_set

# Opción 17 → 6: GameMode y MangoHud, y si quieres Steam y Proton-GE
install_gaming_set() {
    install_gaming_tools
    if steam_installed; then
        enable_steam_play
    elif has_desktop && confirm "${YELLOW}¿Instalar Steam (incluye Proton para juegos de Windows)?${NC}"; then
        install_steam
    fi
    if has_desktop && confirm "${YELLOW}¿Instalar Proton-GE (versión de la comunidad, más compatible)?${NC}"; then
        install_proton_ge
    fi
}
#@@ power_menu

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
            1) submenu_run set_power_profile performance ;;
            2) submenu_run set_power_profile balanced ;;
            3) submenu_run set_power_profile power-saver ;;
            4) submenu_run install_tlp_confirm ;;
            5) submenu_run toggle_indexer ;;
            6) submenu_run install_gaming_set ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        menu_pause
    done
}
#@@ sysctl_default

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
#@@ restore_sysctl_defaults

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
#@@ datos_info_quiet

# ============================================================
# OPCIÓN 3: INFORMACIÓN DEL SISTEMA Y HARDWARE (COLOR: CIAN)
# ============================================================

# Cada sección imprime texto sin colores: así sirve para la pantalla, para buscar
# y para guardar el informe. Con INFO_QUIET=true no pregunta ni descarga nada.
INFO_QUIET=false
#@@ info_title

info_title() {
    echo ""
    echo "▶ $1"
}
#@@ cpu_temperature

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
#@@ info_summary

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
#@@ info_cpu_ram

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
#@@ info_gpu

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
#@@ info_temps

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
#@@ info_network

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
#@@ info_battery

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
#@@ info_usb

info_usb() {
    info_title "USB Y PERIFÉRICOS"
    if command -v lsusb &> /dev/null; then
        lsusb | sed 's/^Bus [0-9]* Device [0-9]*: ID [0-9a-f:]* /  /' | grep -vi 'root hub'
    else
        echo "  (usbutils no está instalado)"
    fi
}
#@@ info_diagnostics

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
#@@ privacy_filter

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
#@@ info_search

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
#@@ info_save_report

info_save_report() {
    local file
    file="$HOME/informe-sistema-$(date +%Y%m%d-%H%M).txt"
    echo -e "${CYAN}⏳ Reuniendo toda la información...${NC}"
    info_full_report 2>/dev/null | privacy_filter > "$file"
    log_success "Informe guardado en: $file"
    echo -e "${CYAN}ℹ Se ocultaron números de serie, MAC, IP, UUID, usuario, nombre del equipo y red Wi-Fi.${NC}"
    echo -e "${CYAN}  Revísalo antes de compartirlo.${NC}"
}
#@@ info_htop

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
#@@ datos_notice_version

# Aviso del primer uso: qué licencia tiene, que no tiene garantía y que modifica el sistema.
# No es una condición de la licencia (la AGPL permite ejecutar el programa sin aceptarla):
# solo confirma que la persona entiende lo que hace el script. Se muestra una vez por versión del aviso.
NOTICE_VERSION=1
NOTICE_FILE="$STATE_DIR/aviso-primer-uso.txt"
#@@ notice_save

notice_save() {
    mkdir -p "$STATE_DIR"
    printf 'version=%s\nfecha=%s\n' "$NOTICE_VERSION" "$(date '+%Y-%m-%d %H:%M')" > "$NOTICE_FILE"
}
#@@ right_script_family
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
#@@ offer_right_script

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
