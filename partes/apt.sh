#@ partes/apt.sh — Lo que comparten Ubuntu y Debian (apt): instalar y quitar programas, kernels, navegadores, Flatpak, Steam, firmware....
#@ Pieza para armar los scripts: no se ejecuta sola. Después de editarla corre "bash armar.sh".
#@ Cada "#@@ nombre" empieza una función o un bloque; las líneas "#@" no pasan a los scripts.
#@@ free
free() { LC_ALL=C command free "$@"; }
#@@ apt_update

# 'apt update' solo una vez por sesión (o si el sistema lo hizo hace menos de 30 min).
# Tras añadir o quitar un repositorio hay que llamarlo con "force".
apt_update() {
    if [ "$1" != "force" ]; then
        $APT_LISTS_FRESH && return 0
        if [ -n "$(find /var/lib/apt/periodic/update-success-stamp -mmin -30 2>/dev/null)" ]; then
            APT_LISTS_FRESH=true
            return 0
        fi
    fi
    run "Falló 'apt update'" sudo apt-get update || return 1
    APT_LISTS_FRESH=true
}
#@@ apt_install
apt_install() { run "No se pudo instalar: $*" sudo env DEBIAN_FRONTEND=noninteractive apt-get install "${APT_OPTS[@]}" "$@"; }
#@@ apt_purge
apt_purge() { run "No se pudo eliminar: $*" sudo env DEBIAN_FRONTEND=noninteractive apt-get purge "${APT_OPTS[@]}" "$@"; }
#@@ apt_install_recorded

# Instala y anota en INSTALLED_LIST los paquetes que NO estaban instalados antes,
# para poder quitarlos después desde "Deshacer optimizaciones" (opción 10).
# Acepta nombres de paquete y rutas a archivos .deb.
apt_install_recorded() {
    local new=() arg name
    for arg in "$@"; do
        [[ "$arg" == -* ]] && continue
        name=$arg
        [[ "$arg" == *.deb ]] && name=$(dpkg-deb -f "$arg" Package 2>/dev/null)
        [ -n "$name" ] || continue
        installed_pkgs "$name" | grep -qx -- "$name" || new+=("$name")
    done
    apt_install "$@" || return 1
    if [ ${#new[@]} -gt 0 ]; then
        mkdir -p "$STATE_DIR"
        printf '%s\n' "${new[@]}" >> "$INSTALLED_LIST"
        sort -u -o "$INSTALLED_LIST" "$INSTALLED_LIST"
    fi
}
#@@ forget_installed

# Quita paquetes del registro de instalados
forget_installed() {
    local p
    for p in "$@"; do
        [ -f "$INSTALLED_LIST" ] && sed -i "/^${p//./\\.}\$/d" "$INSTALLED_LIST"
        [ -f "$INSTALL_ORIGIN" ] && sed -i "/^${p//./\\.}|/d" "$INSTALL_ORIGIN"
    done
    return 0
}
#@@ record_installed

# Anota en el registro un programa instalado por el script, con la fecha y de dónde salió
record_installed() {
    local pkg="$1" origin="$2"
    mkdir -p "$STATE_DIR"
    echo "$pkg" >> "$INSTALLED_LIST"
    sort -u -o "$INSTALLED_LIST" "$INSTALLED_LIST"
    [ -f "$INSTALL_ORIGIN" ] && sed -i "/^${pkg//./\\.}|/d" "$INSTALL_ORIGIN"
    echo "$pkg|$(date '+%Y-%m-%d %H:%M')|$origin" >> "$INSTALL_ORIGIN"
}
#@@ install_origin

# "origen, fecha" de un programa del registro (vacío si no está anotado)
install_origin() {
    [ -f "$INSTALL_ORIGIN" ] || return 0
    awk -F'|' -v p="$1" '$1 == p {o = $3 ", instalado el " $2} END {if (o) print o}' "$INSTALL_ORIGIN"
}
#@@ installed_pkgs

# Lista los paquetes instalados que coinciden con los patrones dados
installed_pkgs() {
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "$@" 2>/dev/null | awk '$1 ~ /^.i/ {print $2}'
}
#@@ purge_and_record

# Elimina paquetes y anota todo lo que apt quita (también dependencias) para poder revertir
purge_and_record() {
    local removed
    removed=$(LC_ALL=C apt-get -s purge "$@" 2>/dev/null | awk '/^(Purg|Remv) / {print $2}')
    apt_purge "$@" || return 1
    if [ -n "$removed" ]; then
        mkdir -p "$STATE_DIR"
        echo "$removed" >> "$REMOVED_LIST"
        sort -u -o "$REMOVED_LIST" "$REMOVED_LIST"
    fi
}
#@@ flavor_meta_pkgs

# Dependencias y recomendaciones del meta-paquete del sabor (las apps originales)
flavor_meta_pkgs() {
    [ -n "$FLAVOR_META" ] || return 0
    apt-cache depends "$FLAVOR_META" 2>/dev/null \
        | awk '$1 ~ /^\|?(Depends|Recommends):$/ && $2 !~ /^</ {print $2}' | sort -u
}
#@@ remove_flavor_meta

# ============================================================
# OPCIÓN 12: CONFIGURAR SISTEMA (COLOR: VERDE)
# ============================================================

remove_flavor_meta() {
    if [ -z "$FLAVOR_META" ] || ! installed_pkgs "$FLAVOR_META" | grep -qx -- "$FLAVOR_META"; then
        echo -e "  ${YELLOW}ℹ El meta-paquete de ${FLAVOR_NAME} ya no está instalado${NC}"
        return 0
    fi
    # Sin el meta-paquete, sus apps quedan "huérfanas" y 'apt autoremove' (opción 1)
    # las borraría. Se marcan como instaladas manualmente para conservarlas.
    local kd_pkgs
    # shellcheck disable=SC2046  # listas de paquetes: se separan a propósito
    mapfile -t kd_pkgs < <(installed_pkgs $(flavor_meta_pkgs))
    [ ${#kd_pkgs[@]} -gt 0 ] && run "No se pudieron proteger las apps de ${FLAVOR_NAME}" sudo apt-mark manual "${kd_pkgs[@]}"
    purge_and_record "$FLAVOR_META" && log_success "Se eliminó $FLAVOR_META (las apps se conservan)"
}
#@@ disable_mandb

# man-db reindexa los manuales tras cada instalación: es lo más lento de apt/dpkg
disable_mandb() {
    echo "man-db man-db/auto-update boolean false" | sudo debconf-set-selections
    sudo rm -f /var/lib/man-db/auto-update
    log_success "Indexación de manuales desactivada (apt será más rápido)"
}
#@@ enable_mandb

enable_mandb() {
    echo "man-db man-db/auto-update boolean true" | sudo debconf-set-selections
    sudo touch /var/lib/man-db/auto-update
    log_success "Indexación de manuales activada"
}
#@@ kernel_versions

# Versiones de kernel instaladas que contienen el texto dado (de menor a mayor)
kernel_versions() {
    installed_pkgs 'linux-image-[0-9]*' | sed 's/^linux-image-//' | grep -- "$1" | sort -V
}
#@@ purge_kernel_pkgs

# Elimina paquetes de kernel, salvo los del kernel en uso: esos se apuntan
# en KERNEL_CLEANUP_FILE y se borran en la próxima ejecución, tras reiniciar.
purge_kernel_pkgs() {
    local running pkgs=() pending=() p
    running=$(uname -r)
    for p in "$@"; do
        if [[ "$p" == *"$running"* ]]; then
            pending+=("$p")
        else
            pkgs+=("$p")
        fi
    done

    if [ ${#pending[@]} -gt 0 ]; then
        mkdir -p "$STATE_DIR"
        printf '%s\n' "${pending[@]}" >> "$KERNEL_CLEANUP_FILE"
        sort -u -o "$KERNEL_CLEANUP_FILE" "$KERNEL_CLEANUP_FILE"
        KERNEL_PENDING_CLEANUP=true
        log_warning "El kernel en uso ($running) se eliminará al reiniciar y volver a abrir el script"
    fi
    [ ${#pkgs[@]} -eq 0 ] && return 0
    apt_purge "${pkgs[@]}"
}
#@@ grub_select

grub_select() {
    local target="$1" cfg="/boot/grub/grub.cfg" regenerated=false _ rc
    ensure_grub_saved
    rc=$?
    [ "$rc" -eq 1 ] && return 1
    [ "$rc" -eq 2 ] && regenerated=true

    if [ "$target" = "0" ]; then
        run "No se pudo fijar el kernel por defecto" sudo grub-set-default 0
        return
    fi

    local path=""
    for _ in 1 2; do
        path=$(grub_entry_path "$target" "$cfg") && break
        $regenerated && break
        run "Falló update-grub" sudo update-grub || return 1
        regenerated=true
    done

    if [ -n "$path" ]; then
        run "No se pudo fijar el kernel por defecto" sudo grub-set-default "$path" \
            && log_success "GRUB arrancará por defecto: $target"
    else
        log_warning "No se encontró $target en GRUB; se arrancará el kernel más reciente"
        run "No se pudo fijar el kernel por defecto" sudo grub-set-default 0
    fi
}
#@@ x86_64_level

# Nivel de microarquitectura x86-64 soportado por la CPU (para XanMod)
x86_64_level() {
    local out
    out=$(/lib64/ld-linux-x86-64.so.2 --help 2>/dev/null)
    if grep -q 'x86-64-v3 (supported' <<< "$out"; then
        echo 3
    elif grep -q 'x86-64-v2 (supported' <<< "$out"; then
        echo 2
    fi
}
#@@ available_pkgs

# Paquetes de la lista que tienen versión disponible en los repositorios
available_pkgs() {
    apt-cache policy "$@" 2>/dev/null | awk '/^[^ ]/ {p = $1; sub(/:$/, "", p)} /^  Candidate:/ && $2 != "(none)" {print p}'
}
#@@ os_release_value

os_release_value() {
    # shellcheck disable=SC1091
    (. /etc/os-release && eval "echo \"\$$1\"")
}
#@@ cleanup_pending_kernels

# Al iniciar el script: borra los kernels que no se pudieron quitar porque estaban en uso
cleanup_pending_kernels() {
    [ -s "$KERNEL_CLEANUP_FILE" ] || return 0
    local running pkgs
    running=$(uname -r)
    # shellcheck disable=SC2046  # listas de paquetes: se separan a propósito
    mapfile -t pkgs < <(installed_pkgs $(cat "$KERNEL_CLEANUP_FILE") | grep -vF -- "$running")
    if grep -qF -- "$running" "$KERNEL_CLEANUP_FILE"; then
        log_warning "Sigues usando un kernel marcado para eliminar ($running): reinicia y elige el nuevo"
        return 0
    fi
    if [ ${#pkgs[@]} -gt 0 ]; then
        echo -e "${YELLOW}🧹 Kernels anteriores pendientes de eliminar:${NC}"
        printf '  • %s\n' "${pkgs[@]}"
        confirm "${YELLOW}¿Eliminarlos ahora?${NC}" || return 0
        apt_purge "${pkgs[@]}" || return 1
    fi
    rm -f "$KERNEL_CLEANUP_FILE"
    if [ -f "$GRUB_TEMP_PIN_FILE" ]; then
        grub_select 0
        rm -f "$GRUB_TEMP_PIN_FILE"
    fi
    log_success "Kernels anteriores eliminados"
}
#@@ advanced_kernel_tweaks

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
            run "Falló update-grub" sudo update-grub && log_success "Mitigaciones habilitadas (requiere reinicio)"
        fi
    elif confirm "${BLUE}¿Deshabilitar mitigaciones de Spectre/Meltdown? (+rendimiento, riesgo alto)${NC}"; then
        sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mitigations=off"/' /etc/default/grub
        run "Falló update-grub" sudo update-grub && log_success "Mitigaciones deshabilitadas (requiere reinicio)"
    fi

    if confirm "${BLUE}¿Habilitar TRIM automático para SSD?${NC}"; then
        enable_trim
    fi

    echo -e "${GREEN}✓ Ajustes avanzados aplicados${NC}"
}
#@@ enable_zram

enable_zram() {
    echo -e "${YELLOW}📦 Configurando ZRAM...${NC}"
    apt_update
    apt_install_recorded zram-tools || return 1
    printf 'ALGO=zstd\nPERCENT=50\n' | sudo tee /etc/default/zramswap > /dev/null
    run "No se pudo reiniciar zramswap" sudo systemctl restart zramswap.service \
        && log_success "ZRAM configurado (50% de RAM como compresión)"
    ram_swappiness_auto
}
#@@ install_custom_software

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
        apt_update
        if ! apt_install_recorded alacritty; then
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
#@@ android_studio_installed
android_studio_installed() {
    [ -x "$ANDROID_STUDIO_DIR/bin/studio" ] || [ -x "$ANDROID_STUDIO_DIR/bin/studio.sh" ] \
        || snap list android-studio &> /dev/null
}
#@@ install_android_studio_google

# Android Studio oficial de Google: la página de descargas tiene el enlace y su SHA-256
install_android_studio_google() {
    local html url file sum tmp old=""
    enough_space "$HOME" 2 && enough_space /opt 4 || return 1
    command -v wget &> /dev/null || { apt_update; apt_install wget; }
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
#@@ install_android_studio

install_android_studio() {
    if ! has_desktop; then
        log_warning "Android Studio necesita un escritorio (este sistema no tiene)"
        return 1
    fi
    if [ "$(dpkg --print-architecture)" != amd64 ]; then
        log_warning "Android Studio para Linux solo existe para PC de 64 bits (amd64)"
        return 1
    fi
    echo -e "\n${BLUE}🤖 ANDROID STUDIO - para programar apps de Android (con emulador)${NC}"
    echo -e "${CYAN}  Ocupa unos 3 GB, más el SDK y los emuladores que bajes (unos 10 GB en total).${NC}"
    echo -e "${CYAN}  La primera vez que lo abras, un asistente baja el SDK a $ANDROID_SDK${NC}"
    echo -e "${CYAN}  (si ya instalaste las herramientas para compilar APK, las usa).${NC}\n"
    echo -e "  ${BLUE}1)${NC} Versión oficial de Google (recomendado): en $ANDROID_STUDIO_DIR, se actualiza"
    echo -e "     desde el propio Android Studio (Ayuda → Buscar actualizaciones)"
    echo -e "  ${BLUE}2)${NC} Snap: se actualiza solo con el sistema (lo empaqueta la comunidad, no Google)"
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
#@@ remove_android

# Quita Android Studio y/o el SDK (las claves de firma de ~/.android nunca se tocan)
remove_android() {
    local found=false
    if android_studio_installed; then
        found=true
        if confirm "${RED}¿Quitar Android Studio?${NC}"; then
            if snap list android-studio &> /dev/null; then
                run "No se pudo quitar el snap" sudo snap remove android-studio
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
#@@ install_flatpak

install_flatpak() {
    if ! has_desktop; then
        log_warning "Flatpak es para apps de escritorio (este sistema no tiene)"
        return 1
    fi
    apt_update
    local pkgs=(flatpak)
    # Para ver e instalar Flatpaks desde la tienda del escritorio
    case $DESKTOP in
        kde) installed_pkgs plasma-discover | grep -qx plasma-discover && pkgs+=(plasma-discover-backend-flatpak) ;;
        *) installed_pkgs gnome-software | grep -qx gnome-software && pkgs+=(gnome-software-plugin-flatpak) ;;
    esac
    apt_install_recorded "${pkgs[@]}" || return 1
    run "No se pudo agregar Flathub" sudo flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
    log_success "Flatpak y Flathub listos (cierra sesión y vuelve a entrar para ver las apps en el menú)"
    [ ${#pkgs[@]} -gt 1 ] && log_info "También puedes instalar Flatpaks desde la tienda de aplicaciones de tu escritorio"
    return 0
}
#@@ install_flatpak_builder

install_flatpak_builder() {
    command -v flatpak &> /dev/null && flatpak remotes 2>/dev/null | grep -qw flathub || install_flatpak || return 1
    apt_install_recorded flatpak-builder || return 1
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
#@@ docker_remove_programs

docker_remove_programs() {
    local pkgs=()
    mapfile -t pkgs < <(installed_pkgs "${DOCKER_PKGS[@]}" docker-ce docker-ce-cli containerd.io)
    [ ${#pkgs[@]} -gt 0 ] || { echo -e "${YELLOW}ℹ No hay paquetes de Docker instalados${NC}"; return 0; }
    confirm "${RED}¿Quitar ${pkgs[*]}? (los datos en /var/lib/docker se conservan)${NC}" || return 0
    sudo systemctl stop docker.service docker.socket >> "$LOG_FILE" 2>&1
    run "No se pudo quitar Docker" sudo env DEBIAN_FRONTEND=noninteractive apt-get remove "${APT_OPTS[@]}" "${pkgs[@]}" || return 1
    forget_installed "${pkgs[@]}"
    log_success "Docker quitado (tus imágenes y volúmenes siguen en /var/lib/docker)"
}
#@@ docker_nuclear

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
    mapfile -t pkgs < <(installed_pkgs "${DOCKER_PKGS[@]}" docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin containerd runc)
    if [ ${#pkgs[@]} -gt 0 ]; then
        apt_purge "${pkgs[@]}"
        forget_installed "${pkgs[@]}"
        run "Falló la limpieza de dependencias" sudo env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" autoremove --purge
    fi

    echo -e "${RED}[3/4] Borrando datos y configuración...${NC}"
    sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /run/docker.sock "$HOME/.docker"

    echo -e "${RED}[4/4] Quitando el grupo docker...${NC}"
    getent group docker > /dev/null && sudo groupdel docker >> "$LOG_FILE" 2>&1

    log_success "Docker eliminado por completo"
    [ -d "$BACKUP_DIR" ] && echo -e "${CYAN}💾 Respaldos en: $BACKUP_DIR${NC}"
}
#@@ dev_nuclear

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
    mapfile -t pkgs < <(installed_pkgs openjdk-21-jdk-headless openjdk-17-jdk-headless \
        android-sdk-platform-tools-common flatpak-builder)
    if [ ${#pkgs[@]} -gt 0 ]; then
        apt_purge "${pkgs[@]}" && forget_installed "${pkgs[@]}"
        run "Falló la limpieza de dependencias" sudo env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" autoremove --purge
    fi
    echo ""
    log_success "Herramientas de desarrollo eliminadas"
    [ -d "$BACKUP_DIR" ] && echo -e "${CYAN}💾 Respaldos en: $BACKUP_DIR${NC}"
}
#@@ migrate_snap_profiles

# ------------------------------------------------------------
# Navegadores sin Snap: Firefox (.deb oficial de Mozilla) y Brave (repositorio oficial de Brave)
# ------------------------------------------------------------

# Copia los perfiles de Firefox/Thunderbird del snap a la ubicación de la versión .deb
migrate_snap_profiles() {
    local pair app dir
    for pair in firefox:.mozilla thunderbird:.thunderbird; do
        app=${pair%%:*}
        dir=${pair#*:}
        if [ -d "$HOME/snap/$app/common/$dir" ] && [ ! -e "$HOME/$dir" ]; then
            cp -a "$HOME/snap/$app/common/$dir" "$HOME/$dir" \
                && log_success "Perfil de $app copiado a ~/$dir (marcadores y contraseñas)"
        fi
    done
}
#@@ install_firefox_deb

# Firefox .deb desde el repositorio oficial de Mozilla (el de Ubuntu instala el snap)
install_firefox_deb() {
    local status
    status=$(dpkg-query -W -f='${db:Status-Abbrev}|${Version}' firefox 2>/dev/null)
    # El paquete de Ubuntu es un "puente" al snap (versión 1:1snap1-...)
    if [[ "$status" == ?i* ]] && [[ "$status" != *snap* ]]; then
        echo -e "  ${GREEN}✓ Firefox .deb ya está instalado${NC}"
        return 0
    fi
    command -v wget &> /dev/null || { apt_update; apt_install wget; } || return 1
    sudo install -d -m 0755 /etc/apt/keyrings
    run "No se pudo descargar la clave de Mozilla" \
        sudo wget -qO /etc/apt/keyrings/packages.mozilla.org.asc https://packages.mozilla.org/apt/repo-signing-key.gpg || return 1
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
        | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
    # Prioridad alta para que no se use el paquete de Ubuntu que instala el snap
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        | sudo tee /etc/apt/preferences.d/mozilla > /dev/null
    if ! apt_update force; then
        log_error "No se pudo leer el repositorio de Mozilla: se quita"
        sudo rm -f /etc/apt/sources.list.d/mozilla.list /etc/apt/preferences.d/mozilla /etc/apt/keyrings/packages.mozilla.org.asc
        apt_update force
        return 1
    fi
    apt_install --allow-downgrades firefox || return 1
    record_installed firefox "repositorio de Mozilla (packages.mozilla.org)"
    log_success "Firefox .deb instalado (se puede quitar en la opción 10 → Quitar programas)"
}
#@@ firefox_mozilla_installed

# ¿Firefox viene del repositorio de Mozilla? (lo puso este script)
firefox_mozilla_installed() {
    firefox_nosnap_installed && [ -f /etc/apt/sources.list.d/mozilla.list ]
}
#@@ remove_mozilla_repo

# Quita el repositorio de Mozilla cuando ya no hay Firefox que lo use
remove_mozilla_repo() {
    sudo rm -f /etc/apt/sources.list.d/mozilla.list /etc/apt/preferences.d/mozilla \
        /etc/apt/keyrings/packages.mozilla.org.asc
    log_success "Repositorio de Mozilla quitado"
}
#@@ firefox_nosnap_installed

# ¿Está el Firefox sin Snap? (el .deb de Mozilla o el de la distribución, no el puente al snap)
firefox_nosnap_installed() {
    local status
    status=$(dpkg-query -W -f='${db:Status-Abbrev}|${Version}' firefox 2>/dev/null)
    [[ "$status" == ?i* && "$status" != *snap* ]]
}
#@@ install_firefox

install_firefox() {
    echo -e "${BLUE}🦊 Firefox sin Snap (el .deb oficial de Mozilla, se actualiza con el sistema)${NC}"
    local had_snap=false
    command -v snap &> /dev/null && snap list firefox &> /dev/null && had_snap=true
    # Antes de nada se copian los marcadores y contraseñas del snap
    $had_snap && migrate_snap_profiles
    install_firefox_deb || return 1
    if $had_snap; then
        echo -e "${YELLOW}ℹ También sigue instalado el Firefox snap (tus datos ya se copiaron al nuevo)${NC}"
        if confirm "${BLUE}¿Quitar el Firefox snap para no tener dos?${NC}"; then
            run "No se pudo quitar el snap de Firefox" sudo snap remove firefox && log_success "Firefox snap quitado"
        fi
    fi
    if [ -n "$(installed_pkgs firefox-esr)" ]; then
        echo -e "${CYAN}ℹ Firefox ESR (el que trae Debian) queda instalado; puedes usar los dos o quitarlo después${NC}"
    fi
    echo -e "${CYAN}ℹ Si no lo ves en el menú, cierra sesión y vuelve a entrar${NC}"
}
#@@ brave_installed

brave_installed() {
    [ -n "$(installed_pkgs brave-browser)" ] \
        || { command -v flatpak &> /dev/null && flatpak info com.brave.Browser &> /dev/null; }
}
#@@ install_brave

# Brave desde su repositorio oficial. Si no se puede (sin conexión, arquitectura), Flathub.
install_brave() {
    echo -e "${BLUE}🦁 Brave (navegador basado en Chromium, con bloqueo de anuncios y rastreadores)${NC}"
    if brave_installed; then
        echo -e "  ${GREEN}✓ Brave ya está instalado${NC}"
        return 0
    fi
    local arch tmp ok=false
    arch=$(dpkg --print-architecture)
    if [ "$arch" = amd64 ] || [ "$arch" = arm64 ]; then
        command -v wget &> /dev/null || { apt_update; apt_install wget; }
        tmp=$(mktemp)
        if run "No se pudo descargar la clave de Brave" \
            wget -qO "$tmp" https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
            && [ -s "$tmp" ]; then
            sudo install -m 0644 "$tmp" "$BRAVE_KEYRING"
            echo "deb [arch=$arch signed-by=$BRAVE_KEYRING] https://brave-browser-apt-release.s3.brave.com/ stable main" \
                | sudo tee "$BRAVE_LIST" > /dev/null
            if apt_update force && apt_install_recorded brave-browser; then
                record_installed brave-browser "repositorio oficial de Brave (brave-browser-apt-release.s3.brave.com)"
                ok=true
            else
                # Se deja todo como estaba: sin un repositorio que hace fallar apt update
                log_warning "No se pudo instalar Brave desde su repositorio: se quita"
                sudo rm -f "$BRAVE_LIST" "$BRAVE_KEYRING"
                apt_update force
            fi
        fi
        rm -f "$tmp"
    else
        log_warning "Brave no tiene paquete para tu procesador ($arch)"
    fi
    if $ok; then
        log_success "Brave instalado (se actualiza con el sistema)"
        return 0
    fi
    # Alternativa: Flathub
    if confirm "${BLUE}¿Instalar Brave desde Flathub?${NC}"; then
        command -v flatpak &> /dev/null && flatpak remotes 2>/dev/null | grep -qw flathub || install_flatpak || return 1
        run_visible "No se pudo instalar Brave desde Flathub" sudo flatpak install -y --noninteractive flathub com.brave.Browser \
            && record_installed "flatpak:com.brave.Browser" "Flathub (com.brave.Browser)" \
            && log_success "Brave instalado desde Flathub"
        return
    fi
    return 1
}
#@@ chromium_flatpak_installed
chromium_flatpak_installed() { command -v flatpak &> /dev/null && flatpak info "$CHROMIUM_FLATPAK" &> /dev/null; }
#@@ chromium_deb_installed
# El paquete chromium de verdad (no el puente al snap de Ubuntu)
chromium_deb_installed() {
    local status
    status=$(dpkg-query -W -f='${db:Status-Abbrev}|${Version}' chromium 2>/dev/null)
    [[ "$status" == ?i* && "$status" != *snap* ]]
}
#@@ chromium_installed
chromium_installed() { chromium_deb_installed || chromium_flatpak_installed; }
#@@ install_chromium_flatpak

install_chromium_flatpak() {
    command -v flatpak &> /dev/null && flatpak remotes 2>/dev/null | grep -qw flathub || install_flatpak || return 1
    run_visible "No se pudo instalar Chromium desde Flathub" \
        sudo flatpak install -y --noninteractive flathub "$CHROMIUM_FLATPAK" || return 1
    record_installed "flatpak:$CHROMIUM_FLATPAK" "Flathub ($CHROMIUM_FLATPAK)"
    log_success "Chromium instalado desde Flathub (se actualiza con el sistema; se quita en 10 → Quitar programas)"
}
#@@ setup_edge_repo

# Repositorio oficial de Microsoft para Edge (como el de Google para Chrome)
setup_edge_repo() {
    [ -f "$EDGE_LIST" ] && return 0
    [ "$(dpkg --print-architecture 2>/dev/null)" = amd64 ] || { log_error "Microsoft Edge solo existe para PC de 64 bits (amd64)"; return 1; }
    run "No se pudo descargar la clave de Microsoft" \
        bash -c "set -o pipefail; wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o $EDGE_KEYRING" \
        || return 1
    echo "deb [arch=amd64 signed-by=$EDGE_KEYRING] https://packages.microsoft.com/repos/edge stable main" \
        | sudo tee "$EDGE_LIST" > /dev/null
}
#@@ tor_installed
tor_installed() {
    command -v torbrowser-launcher &> /dev/null \
        || { command -v flatpak &> /dev/null && flatpak info "$TOR_FLATPAK" &> /dev/null; }
}
#@@ install_tor
install_tor() {
    echo -e "${BLUE}🧅 Tor Browser (navegar de forma anónima por la red Tor)${NC}"
    if tor_installed; then
        echo -e "  ${GREEN}✓ Ya está instalado${NC}"
        return 0
    fi
    if declare -F available_pkgs > /dev/null && [ -n "$(available_pkgs torbrowser-launcher)" ]; then
        apt_install_recorded torbrowser-launcher || return 1
    elif declare -F pkg_install_recorded > /dev/null && ! declare -F apt_install_recorded > /dev/null; then
        pkg_install_recorded torbrowser-launcher || return 1
    else
        echo -e "${CYAN}ℹ Tu distribución no lo trae (en Debian está en 'contrib'): se instala desde Flathub${NC}"
        command -v flatpak &> /dev/null && flatpak remotes 2>/dev/null | grep -qw flathub || install_flatpak || return 1
        run_visible "No se pudo instalar Tor Browser desde Flathub" \
            sudo flatpak install -y --noninteractive flathub "$TOR_FLATPAK" || return 1
        record_installed "flatpak:$TOR_FLATPAK" "Flathub ($TOR_FLATPAK)" 2>/dev/null
    fi
    log_success "Tor Browser instalado: la primera vez que lo abras, descarga y verifica el navegador"
}
#@@ install_torbrowser_launcher

install_torbrowser_launcher() { install_tor; }
#@@ core_pkgs_removed_by

# ============================================================
# FUNCIONES DE EJECUCIÓN
# ============================================================

# Elimina todas las apps en una sola operación de apt (mucho más rápido que una a una:
# dpkg ejecuta sus tareas posteriores una sola vez). Si falla, reintenta de a una.
# Seguro: qué piezas esenciales (CORE_PKGS) arrastraría quitar estos paquetes
core_pkgs_removed_by() {
    LC_ALL=C apt-get -s purge "$@" 2>/dev/null | awk '/^(Purg|Remv) / {print $2}' \
        | grep -xF -f <(printf '%s\n' "${CORE_PKGS[@]}")
}
#@@ setup_spotify_repo

setup_spotify_repo() {
    [ -f /etc/apt/sources.list.d/spotify.list ] && return 0
    run "No se pudo descargar la clave de Spotify" \
        bash -c "set -o pipefail; wget -qO- https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg" \
        || return 1
    echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list > /dev/null
}
#@@ boot_pkg_installed

boot_pkg_installed() {
    case $BOOT_FAMILY in
        debian) installed_pkgs "$@" ;;
        arch) pacman -Qq "$@" 2>/dev/null ;;
        fedora|suse) rpm -q --qf '%{NAME}\n' "$@" 2>/dev/null | grep -v 'not installed' ;;
    esac
}
#@@ boot_pkg_install

boot_pkg_install() {
    boot_pkg_supported || return 1
    case $BOOT_FAMILY in
        debian)
            [ -z "$BOOT_ROOT" ] && apt_update
            on_target env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        arch) on_target pacman -S --needed --noconfirm "$@" ;;
        fedora) on_target dnf install -y "$@" ;;
        suse) on_target zypper --non-interactive install "$@" ;;
    esac
}
#@@ boot_pkg_reinstall

# Reinstala paquetes reponiendo los archivos que falten
boot_pkg_reinstall() {
    boot_pkg_supported || return 1
    case $BOOT_FAMILY in
        debian)
            [ -z "$BOOT_ROOT" ] && apt_update
            on_target env DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y \
                -o Dpkg::Options::=--force-confmiss "$@" ;;
        arch) on_target pacman -S --noconfirm "$@" ;;
        fedora) on_target dnf reinstall -y "$@" ;;
        suse) on_target zypper --non-interactive install --force "$@" ;;
    esac
}
#@@ update_firmware

# Firmware de BIOS/UEFI, SSD, docks, etc. desde LVFS
update_firmware() {
    apt_update
    command -v fwupdmgr &> /dev/null || apt_install fwupd || return 1
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
#@@ set_power_profile

set_power_profile() {
    local profile="$1"
    if ! command -v powerprofilesctl &> /dev/null; then
        if installed_pkgs tlp | grep -qx tlp; then
            log_error "Usas TLP: los perfiles de energía los maneja TLP (quítalo en la opción 10 para usar estos)"
            return 1
        fi
        # Xubuntu, Lubuntu y otros no lo traen: es el servicio estándar de perfiles de energía
        echo -e "${YELLOW}📦 Instalando power-profiles-daemon (perfiles de energía)...${NC}"
        apt_update
        apt_install_recorded power-profiles-daemon || return 1
        run "No se pudo iniciar power-profiles-daemon" sudo systemctl enable --now power-profiles-daemon || return 1
    fi
    if ! powerprofilesctl list 2>/dev/null | grep -q "$profile:"; then
        log_error "Tu equipo no admite el perfil '$profile' (disponibles: $(power_profiles_available))"
        return 1
    fi
    run "No se pudo cambiar el perfil de energía" powerprofilesctl set "$profile" \
        && log_success "Perfil de energía: $profile"
}
#@@ install_tlp

install_tlp() {
    echo -e "${YELLOW}ℹ TLP reemplaza a power-profiles-daemon: el selector de perfiles del escritorio desaparecerá${NC}"
    apt_update
    apt_install_recorded tlp tlp-rdw || return 1
    run "No se pudo activar TLP" sudo systemctl enable --now tlp \
        && log_success "TLP activado (para volver: sudo apt install power-profiles-daemon)"
}
#@@ install_gaming_tools

install_gaming_tools() {
    apt_update
    # GameMode: el juego pide máximo rendimiento al sistema. MangoHud: FPS y temperaturas en pantalla
    apt_install_recorded gamemode mangohud || return 1
    # Valor que usan SteamOS y Fedora: evita cierres en juegos modernos (Proton)
    set_sysctl vm.max_map_count 1048576
    configure_mangohud
    log_success "GameMode y MangoHud instalados (en Steam: gamemoderun mangohud %command%)"
}
#@@ steam_installed

steam_installed() {
    [ -n "$(installed_pkgs steam-launcher steam-installer steam)" ] \
        || flatpak info com.valvesoftware.Steam &> /dev/null
}
#@@ steam_dir

# Carpeta de datos de Steam (existe aunque todavía no se haya abierto)
steam_dir() {
    if [ -z "$(installed_pkgs steam-launcher steam-installer steam)" ] \
        && [ -d "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" ]; then
        echo "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    elif [ -d "$HOME/.steam/root" ]; then
        readlink -f "$HOME/.steam/root"
    else
        echo "$HOME/.local/share/Steam"
    fi
}
#@@ steam_supported

steam_supported() {
    if ! has_desktop; then
        log_warning "Steam necesita un escritorio (este sistema no tiene)"
        return 1
    fi
    if [ "$(dpkg --print-architecture)" != amd64 ]; then
        log_warning "Steam solo existe para PC de 64 bits (amd64)"
        return 1
    fi
}
#@@ steam_i386_libs

# Librerías gráficas de 32 bits: la mayoría de los juegos de Windows (Proton) las necesitan
steam_i386_libs() {
    local libs=() nv
    if [ -n "$(available_pkgs steam-libs-amd64)" ]; then
        libs+=(steam-libs-amd64:amd64 steam-libs-i386:i386)
    else
        libs+=(libgl1:i386 libgl1-mesa-dri:i386 mesa-vulkan-drivers:i386)
    fi
    # Con el driver de NVIDIA hace falta también su parte de 32 bits
    nv=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'libnvidia-gl-*' 2>/dev/null \
        | awk '$1 ~ /^.i/ && $2 ~ /^libnvidia-gl-[0-9]+(-server)?$/ {print $2; exit}')
    [ -n "$nv" ] && libs+=("$nv:i386")
    apt_install_recorded "${libs[@]}"
}
#@@ install_proton_ge

# Proton-GE: versión de la comunidad con arreglos para juegos y vídeos que el oficial aún no tiene
install_proton_ge() {
    steam_supported || return 1
    command -v wget &> /dev/null || { apt_update; apt_install wget; }
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
#@@ remove_installed_programs

remove_installed_programs() {
    local logged=() known=() entries=() p desc origin
    # shellcheck disable=SC2046  # lista de paquetes: se separa a propósito
    [ -f "$INSTALLED_LIST" ] && mapfile -t logged < <(installed_pkgs $(cat "$INSTALLED_LIST"))
    mapfile -t known < <(installed_pkgs "${SCRIPT_PROGRAMS[@]}")

    # Firefox del repositorio de Mozilla: se reconoce aunque se instalara antes del registro
    if firefox_mozilla_installed && ! printf '%s\n' "${logged[@]}" | grep -qx firefox; then
        logged+=(firefox)
        [ -n "$(install_origin firefox)" ] || {
            mkdir -p "$STATE_DIR"
            echo "firefox|$(date -r /etc/apt/sources.list.d/mozilla.list '+%Y-%m-%d %H:%M')|repositorio de Mozilla (packages.mozilla.org)" >> "$INSTALL_ORIGIN"
        }
    fi
    # Apps de Flathub que instala el script (se quitan con flatpak, no con apt)
    local fp flatpaks=()
    for fp in "$CHROMIUM_FLATPAK|Chromium" "com.brave.Browser|Brave"; do
        command -v flatpak &> /dev/null && flatpak info "${fp%%|*}" &> /dev/null || continue
        origin=$(install_origin "flatpak:${fp%%|*}")
        entries+=("flatpak:${fp%%|*}|${fp#*|} (Flathub) ${origin:+[$origin]}")
    done
    # SeaMonkey no es un paquete: se instaló en /opt
    seamonkey_installed && entries+=("opt:seamonkey|SeaMonkey (descarga oficial en $SEAMONKEY_DIR)")
    for p in "${logged[@]}"; do
        [[ "$p" == flatpak:* ]] && continue
        desc=$(dpkg-query -W -f='${binary:Summary}' "$p" 2>/dev/null)
        origin=$(install_origin "$p")
        entries+=("$p|${desc:-instalado por el script}${origin:+ [$origin]}")
    done
    for p in "${known[@]}"; do
        printf '%s\n' "${logged[@]}" | grep -qx -- "$p" && continue
        entries+=("$p|(sin registro: puede que ya lo tuvieras) $(dpkg-query -W -f='${binary:Summary}' "$p" 2>/dev/null)")
    done

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

    # Las apps de Flathub van aparte: el resto se quita con apt
    local sel=()
    for p in "${CHOSEN[@]}"; do
        if [[ "$p" == flatpak:* ]]; then flatpaks+=("${p#flatpak:}")
        elif [ "$p" = opt:seamonkey ]; then remove_seamonkey
        else sel+=("$p"); fi
    done
    CHOSEN=("${sel[@]}")
    for fp in "${flatpaks[@]}"; do
        origin=$(install_origin "flatpak:$fp")
        echo -e "${RED}📋 Se desinstalará de Flathub:${NC} $fp${origin:+ ${CYAN}($origin)${NC}}"
        if confirm "${RED}¿Desinstalar $fp?${NC}"; then
            run "No se pudo quitar $fp" sudo flatpak uninstall -y --noninteractive "$fp" \
                && forget_installed "flatpak:$fp" && log_success "Desinstalado: $fp (tus datos en ~/.var/app/$fp no se borran)"
        fi
    done
    [ ${#CHOSEN[@]} -gt 0 ] || return 0

    # Lo que apt quitaría de verdad: puede arrastrar otros paquetes que dependen de estos
    local extra=()
    mapfile -t extra < <(LC_ALL=C apt-get -s purge "${CHOSEN[@]}" 2>/dev/null \
        | awk '/^(Purg|Remv) / {print $2}' | grep -vxF -f <(printf '%s\n' "${CHOSEN[@]}"))
    echo -e "${RED}📋 Se desinstalarán:${NC}"
    for p in "${CHOSEN[@]}"; do
        origin=$(install_origin "$p")
        echo -e "  ${RED}•${NC} $p${origin:+ ${CYAN}($origin)${NC}}"
    done
    if printf '%s\n' "${CHOSEN[@]}" | grep -qx firefox; then
        echo -e "\n${YELLOW}ℹ Tus marcadores y contraseñas de ~/.mozilla no se borran${NC}"
        { [ -n "$(installed_pkgs firefox-esr brave-browser google-chrome-stable microsoft-edge-stable)" ] || chromium_installed || brave_installed || seamonkey_installed; } || echo -e "${YELLOW}⚠ No tienes otro navegador instalado: te quedarás sin ninguno${NC}"
    fi
    if [ ${#extra[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}⚠ También se quitarán porque dependen de ellos:${NC}"
        print_pkgs_described "${extra[@]}"
    fi
    echo ""
    if ! confirm "${RED}¿Desinstalar?${NC}"; then
        echo -e "${YELLOW}ℹ Cancelado: no se desinstaló nada${NC}"
        return 0
    fi

    apt_purge "${CHOSEN[@]}" || return 1
    # Sin Brave, su repositorio ya no hace falta
    if printf '%s\n' "${CHOSEN[@]}" | grep -qx brave-browser; then
        sudo rm -f "$BRAVE_LIST" "$BRAVE_KEYRING"
    fi
    # Sin Edge, el repositorio de Microsoft para Edge tampoco
    if printf '%s\n' "${CHOSEN[@]}" | grep -qx microsoft-edge-stable; then
        sudo rm -f "$EDGE_LIST" "$EDGE_KEYRING"
    fi
    # Sin Firefox, el repositorio de Mozilla tampoco
    if printf '%s\n' "${CHOSEN[@]}" | grep -qx firefox; then
        remove_mozilla_repo
        apt_update force
    fi
    forget_installed "${CHOSEN[@]}" "${extra[@]}"
    log_success "Desinstalado: ${CHOSEN[*]}"
    run "Falló la limpieza de dependencias" sudo env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" autoremove --purge

    # Sin TLP, el selector de energía del escritorio necesita power-profiles-daemon
    if printf '%s\n' "${CHOSEN[@]}" | grep -qx tlp; then
        apt_update
        apt_install power-profiles-daemon \
            && run "No se pudo activar power-profiles-daemon" sudo systemctl enable --now power-profiles-daemon \
            && log_success "Vuelve el selector de energía del escritorio"
    fi
}
#@@ disable_zram

disable_zram() {
    if ! installed_pkgs zram-tools | grep -qx zram-tools; then
        echo -e "  ${GREEN}✓ ZRAM no está instalado${NC}"
        return 0
    fi
    run "No se pudo detener ZRAM" sudo systemctl disable --now zramswap.service \
        && log_success "ZRAM desactivado"
    if confirm "${YELLOW}¿Desinstalar también zram-tools?${NC}"; then
        apt_purge zram-tools && forget_installed zram-tools
    fi
}
#@@ remove_tlp

remove_tlp() {
    if ! installed_pkgs tlp | grep -qx tlp; then
        echo -e "  ${GREEN}✓ TLP no está instalado${NC}"
        return 0
    fi
    local pkgs=()
    mapfile -t pkgs < <(installed_pkgs tlp tlp-rdw)
    apt_purge "${pkgs[@]}" || return 1
    forget_installed tlp tlp-rdw
    apt_update
    apt_install power-profiles-daemon \
        && run "No se pudo activar power-profiles-daemon" sudo systemctl enable --now power-profiles-daemon \
        && log_success "TLP quitado: vuelve el selector de energía del escritorio"
}
#@@ info_fastfetch

# Ejecuta fastfetch: el instalado o uno temporal que se borra al terminar
info_fastfetch() {
    if command -v fastfetch &> /dev/null; then
        fastfetch
        return
    fi
    $INFO_QUIET && return 0
    echo -e "${CYAN}ℹ fastfetch no está instalado. Se puede ver sin instalar: se descarga (~1,5 MB) a una${NC}"
    echo -e "${CYAN}  carpeta temporal desde su página oficial y se borra al terminar.${NC}"
    confirm "${CYAN}¿Verlo sin instalar?${NC}" || return 0
    local tmp arch
    arch=$(dpkg --print-architecture)
    [ "$arch" = arm64 ] && arch=aarch64
    tmp=$(mktemp -d)
    if run "No se pudo descargar fastfetch" wget -qO "$tmp/ff.tar.gz" \
        "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-$arch.tar.gz" \
        && tar -xzf "$tmp/ff.tar.gz" -C "$tmp"; then
        local ffbin=("$tmp"/fastfetch-linux-*/usr/bin/fastfetch)
        "${ffbin[0]}"
    fi
    rm -rf "$tmp"
}
#@@ info_disks

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
        apt_update
        apt_install_recorded smartmontools || return 1
    fi
    for disk in $(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" && $1 !~ /zram/ {print $1}'); do
        echo "  $disk"
        LC_ALL=C sudo smartctl -H -A "$disk" 2>/dev/null | grep -E \
            'overall-health|Percentage Used|Power On Hours|Power_On_Hours|^Temperature:|Temperature_Celsius|Media and Data Integrity|Reallocated_Sector|Wear_Leveling|Percent_Lifetime|Unsafe Shutdowns|Available Spare:' \
            | sed -e 's/SMART overall-health self-assessment test result:/Estado general:/' -e 's/  */ /g; s/^/    /'
    done
}
#@@ info_script_changes

info_script_changes() {
    local custom count
    info_title "CAMBIOS HECHOS POR ESTE SCRIPT"
    echo "  Kernel en uso: $(uname -r)"
    custom=$(installed_pkgs 'linux-image-[0-9]*' | grep -E 'liquorix|xanmod' | sed 's/^linux-image-//' | tr '\n' ' ')
    [ -n "$custom" ] && echo "  Kernels de terceros instalados: $custom"
    [ -n "$FLAVOR_META" ] && ! installed_pkgs "$FLAVOR_META" | grep -qx -- "$FLAVOR_META" \
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
        [ -s "$INSTALL_ORIGIN" ] && awk -F'|' '{print "    • " $1 ": " $3 " (" $2 ")"}' "$INSTALL_ORIGIN"
    fi
    show_tweaks_status | sed 's/\x1b\[[0-9;]*m//g' | grep -v '^$' | grep -v 'Estado actual' | sed 's/^ */  /'
    return 0
}
#@@ security_audit_lynis

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
        echo -e "  ${CYAN}1)${NC} Usarlo SIN INSTALAR (se baja el paquete oficial, ~230 KB, y se borra al terminar)"
        echo -e "  ${CYAN}2)${NC} Instalarlo (para usarlo cuando quieras; se quita en 10 → 1)"
        echo -e "  ${CYAN}0)${NC} Volver"
        read -r -p "🔢 Opción: " choice
        case $choice in
            1)
                tmp=$(mktemp -d)
                apt_update
                if ! (cd "$tmp" && run "No se pudo descargar Lynis" apt-get download lynis); then
                    rm -rf "$tmp"
                    return 1
                fi
                # Lynis exige que sus archivos sean de root cuando corre con sudo
                sudo dpkg-deb -x "$tmp"/lynis_*.deb "$tmp/x" || { rm -rf "$tmp"; return 1; }
                sudo cp -a "$tmp/x/etc/lynis/." "$tmp/x/usr/share/lynis/"
                sudo cp "$tmp/x/usr/sbin/lynis" "$tmp/x/usr/share/lynis/lynis"
                lynis_cmd=(env -C "$tmp/x/usr/share/lynis" sh ./lynis)
                ;;
            2)
                apt_update
                apt_install_recorded lynis || return 1
                record_installed lynis "repositorios oficiales de la distro"
                lynis_cmd=(lynis)
                ;;
            *) return 0 ;;
        esac
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
#@@ enable_audit

enable_audit() {
    echo -e "${CYAN}📝 Registro de auditoría (auditd, Linux Audit, GPL-2.0)${NC}"
    echo -e "   Anota quién y cuándo cambia usuarios, contraseñas, sudo, SSH, la hora, la red,"
    echo -e "   tareas programadas, servicios, repositorios y módulos del kernel."
    echo -e "   ${GREEN}No protege por sí solo: sirve para saber qué pasó si algo cambia.${NC}"
    echo -e "   Los registros van a /var/log/audit (auditd los rota solo, ~40 MB como máximo).\n"
    if ! command -v auditctl &> /dev/null; then
        confirm "${CYAN}¿Instalar auditd (~1 MB, se quita desde aquí mismo)?${NC}" || return 0
        apt_update
        apt_install_recorded auditd || return 1
        record_installed auditd "repositorios oficiales de la distro"
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
#@@ disable_audit

disable_audit() {
    if ! audit_rules_active && ! grep -qx auditd "$INSTALLED_LIST" 2>/dev/null; then
        echo -e "${YELLOW}ℹ El script no activó el registro de auditoría${NC}"
        return 0
    fi
    confirm "${RED}¿Quitar el registro de auditoría del script?${NC}" || return 0
    if audit_rules_active; then
        sudo rm -f "$AUDIT_RULES_FILE"
        command -v augenrules &> /dev/null && sudo augenrules --load >> "$LOG_FILE" 2>&1
        log_success "Reglas de auditoría del script quitadas"
    fi
    if grep -qx auditd "$INSTALLED_LIST" 2>/dev/null \
        && confirm "${RED}¿Desinstalar también auditd (lo instaló el script)?${NC}"; then
        apt_purge auditd && forget_installed auditd && log_success "auditd desinstalado"
        if [ -d /var/log/audit ] && confirm "${RED}¿Borrar también los registros guardados en /var/log/audit?${NC}"; then
            sudo rm -rf /var/log/audit && log_success "Registros borrados"
        fi
    fi
}
#@@ install_wine

# Wine: programas y juegos de Windows fuera de Steam. Del repositorio de la distro (estable), con
# la parte de 32 bits (muchos instaladores de Windows todavía son de 32 bits) y winetricks
install_wine() {
    local pkgs=(wine)
    if command -v wine &> /dev/null; then
        echo -e "  ${GREEN}✓ Wine ya está instalado ($(wine --version 2>/dev/null))${NC}"
        return 0
    fi
    echo -e "${BLUE}🍷 Instalando Wine...${NC}"
    if ! dpkg --print-foreign-architectures | grep -qx i386; then
        run "No se pudo activar la arquitectura de 32 bits" sudo dpkg --add-architecture i386 || return 1
        log_success "Arquitectura de 32 bits (i386) activada"
        apt_update force || return 1
    fi
    apt-cache policy wine32:i386 2>/dev/null | grep -q 'Candidate: [0-9]' && pkgs+=(wine32:i386)
    [ -n "$(available_pkgs winetricks)" ] && pkgs+=(winetricks)
    apt_install_recorded "${pkgs[@]}" || return 1
    log_success "Wine instalado: abre un programa de Windows con \"wine programa.exe\"$([[ " ${pkgs[*]} " == *" winetricks "* ]] && echo " (winetricks agrega lo que le falte)")"
}
