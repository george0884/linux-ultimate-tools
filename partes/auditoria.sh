#@ partes/auditoria.sh — Opción 2: auditoría de seguridad con Lynis, registro de auditoría (auditd) y linaudit.
#@ Pieza para armar los scripts: no se ejecuta sola. Después de editarla corre "bash armar.sh".
#@ Cada "#@@ nombre" empieza una función o un bloque; las líneas "#@" no pasan a los scripts.
#@@ lynis_summary

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
#@@ audit_rules_active

# ------------------------------------------------------------
# auditd con reglas propias
# ------------------------------------------------------------
audit_rules_active() { [ -f "$AUDIT_RULES_FILE" ]; }
#@@ show_audit_events

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
#@@ datos_linaudit_git

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
#@@ linaudit_cleanup

# Borra la carpeta temporal de compilación (solo si es una de las creadas en /var/tmp/linaudit.*)
linaudit_cleanup() {
    case "$1" in
        /var/tmp/linaudit.?*) [ -d "$1" ] && rm -rf -- "$1" ;;
    esac
}
#@@ version_ge

# ¿La versión $1 es igual o más nueva que $2?
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }
#@@ linaudit_need_cc

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
#@@ linaudit_get_cargo

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
#@@ linaudit_build

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
#@@ linaudit_run

linaudit_run() {
    local bin="$1"
    echo -e "\n${CYAN}ℹ linaudit solo mira: no cambia nada. Pregunta qué tipo de equipo es (servidor, escritorio${NC}"
    echo -e "${CYAN}  o contenedor). En la pantalla final: ? muestra los atajos, y copia el arreglo, q sale.${NC}"
    pause
    sudo "$bin" --lang es
}
#@@ security_audit_linaudit

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
#@@ remove_linaudit

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
#@@ security_menu

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
