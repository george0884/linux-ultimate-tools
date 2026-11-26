#@ partes/arranque.sh — Opción 19: GRUB, EFI, reparación desde Live USB, tarjeta de rescate y arranque detallado.
#@ Pieza para armar los scripts: no se ejecuta sola. Después de editarla corre "bash armar.sh".
#@ Cada "#@@ nombre" empieza una función o un bloque; las líneas "#@" no pasan a los scripts.
#@@ secure_boot_enabled

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
#@@ backup_grub_config

# Antes del primer cambio guarda /etc/default/grub para poder volver al original
backup_grub_config() {
    [ -f "$GRUB_DEFAULT_BACKUP" ] || sudo cp -p /etc/default/grub "$GRUB_DEFAULT_BACKUP"
}
#@@ set_grub_default

set_grub_default() {
    local value="$1"
    backup_grub_config
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sudo sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"$value\"|" /etc/default/grub
    else
        echo "GRUB_DEFAULT=\"$value\"" | sudo tee -a /etc/default/grub > /dev/null
    fi
}
#@@ grub_line_id

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
#@@ grub_entry_path

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
#@@ ensure_grub_saved

# Pasa GRUB a GRUB_DEFAULT=saved (una sola vez). Devuelve 2 si tuvo que regenerar grub.cfg.
ensure_grub_saved() {
    grep -Eq '^GRUB_DEFAULT="?saved"?$' /etc/default/grub && return 0
    set_grub_default saved
    run "No se pudo regenerar el menú" grub_update || return 1
    return 2
}
#@@ datos_boot_root

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
#@@ boot_os_value

# Valor de /etc/os-release del sistema de arranque (el actual o el montado)
boot_os_value() {
    (. "$BOOT_ROOT/etc/os-release" 2>/dev/null && eval "echo \"\${$1:-}\"")
}
#@@ boot_has_cmd

boot_has_cmd() {
    local d
    for d in /usr/sbin /usr/bin /sbin /bin; do
        [ -x "$BOOT_ROOT$d/$1" ] && return 0
    done
    return 1
}
#@@ on_target

# Ejecuta un comando como administrador en el sistema de arranque
on_target() {
    if [ -n "$BOOT_ROOT" ]; then
        sudo chroot "$BOOT_ROOT" "$@"
    else
        sudo "$@"
    fi
}
#@@ boot_detect

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
#@@ boot_find_esp

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
#@@ boot_find_efi_id

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
#@@ grub_available

# ¿Hay GRUB en este sistema? (Arch y EndeavourOS a veces usan systemd-boot)
grub_available() {
    boot_has_cmd "$GRUB_PREFIX-mkconfig" || boot_has_cmd update-grub
}
#@@ grub_required

grub_required() {
    grub_available && return 0
    if on_target bootctl is-installed &> /dev/null; then
        log_warning "$BOOT_DISTRO arranca con systemd-boot, no con GRUB: esta opción no aplica"
    else
        log_error "GRUB no está instalado en $BOOT_DISTRO"
    fi
    return 1
}
#@@ grub_uses_bls

# Menú de GRUB con entradas BLS (Fedora): los kernels no están en grub.cfg
grub_uses_bls() {
    sudo grep -q '^[[:space:]]*blscfg' "$BOOT_ROOT$GRUB_CFG" 2>/dev/null
}
#@@ grub_update

grub_update() { on_target "${GRUB_REGEN[@]}"; }
#@@ grub_set_default
grub_set_default() { on_target "$GRUB_PREFIX-set-default" "$@"; }
#@@ grub_editenv_list
grub_editenv_list() { on_target "$GRUB_PREFIX-editenv" "$GRUB_DIR/grubenv" list 2>/dev/null; }
#@@ grub_probe
grub_probe() { on_target "$GRUB_PREFIX-probe" "$@"; }
#@@ grub_packages

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
#@@ boot_pkg_supported

boot_pkg_supported() {
    [ "$BOOT_FAMILY" != otra ] && return 0
    log_error "No sé instalar paquetes en $BOOT_DISTRO: hazlo con su gestor de paquetes"
    return 1
}
#@@ boot_pkg_remove

boot_pkg_remove() {
    boot_pkg_supported || return 1
    case $BOOT_FAMILY in
        debian) on_target env DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@" ;;
        arch) on_target pacman -Rns --noconfirm "$@" ;;
        fedora) on_target dnf remove -y "$@" ;;
        suse) on_target zypper --non-interactive remove "$@" ;;
    esac
}
#@@ boot_grubd_owned

# Archivos de /etc/grub.d que instalan los paquetes: "paquete ruta" (aunque falten)
boot_grubd_owned() {
    case $BOOT_FAMILY in
        debian) dpkg-query -S '/etc/grub.d/*' 2>/dev/null | grep -v '^diversion' \
            | awk -F': ' '{n = split($1, p, ", "); for (i = 1; i <= n; i++) print p[i], $2}' ;;
        arch) pacman -Ql 2>/dev/null ;;
        fedora|suse) rpm -qa --filesbypkg 2>/dev/null ;;
    esac | awk '$2 ~ "^/etc/grub.d/[^/]+$" {print $1, $2}' | sort -u
}
#@@ grub_install_uefi

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
#@@ grub_install_bios

grub_install_bios() {
    on_target "$GRUB_PREFIX-install" --target=i386-pc --recheck "$1"
}
#@@ is_live_session

# Nombre de la sesión Live: Ubuntu (casper), Debian (live), Arch, Manjaro y Fedora
is_live_session() {
    local cmdline
    cmdline=$(cat /proc/cmdline 2>/dev/null)
    [[ "$cmdline" == *boot=casper* || "$cmdline" == *boot=live* || "$cmdline" == *archisobasedir* \
        || "$cmdline" == *misobasedir* || "$cmdline" == *rd.live.image* ]] && return 0
    [ -d /cdrom/casper ] || [ -d /run/archiso ] || [ "$(findmnt -no FSTYPE / 2>/dev/null)" = overlay ]
}
#@@ boot_option_ok


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
#@@ boot_option_reason

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
#@@ boot_option

# Imprime una opción solo si sirve en este equipo
boot_option() {
    boot_option_ok "$1" || return 0
    printf "  ${PURPLE}%2s)${NC} %s\n" "$1" "$2"
    [ -n "${3:-}" ] && echo -e "         $3"
    return 0
}
#@@ boot_section

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
#@@ grub_repair_menu

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
            1) submenu_run grub_diagnostic ;;
            2) submenu_run grub_normal_repair ;;
            3) submenu_run grub_full_repair; menu_pause ;;
            4) submenu_run grub_reinstall_to_disk ;;
            5) submenu_run esp_check_repair; menu_pause ;;
            6) submenu_run grub_default_entry_menu; menu_pause ;;
            7) submenu_run grub_os_prober_toggle; menu_pause ;;
            8) submenu_run uefi_boot_order_menu; menu_pause ;;
            9) submenu_run grub_customize_menu ;;
            10) submenu_run grub_live_repair ;;
            11) submenu_run grub_prompt_guide ;;
            12) submenu_run grub_rescue_guide ;;
            13) submenu_run grub_live_guide ;;
            14) submenu_run rescue_card_menu ;;
            15) submenu_run uefi_fallback_menu ;;
            16) submenu_run boot_verbose_menu; menu_pause ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}
#@@ boot_report

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
#@@ grub_diagnostic

grub_diagnostic() {
    grub_guide_header "📊 DIAGNÓSTICO DEL ARRANQUE"
    local report="$HOME/diagnostico-arranque.txt"
    boot_report | tee "$report"
    echo -e "\n${GREEN}💾 Informe guardado en: $report${NC}"
    echo -e "${YELLOW}   (sirve para pedir ayuda: compártelo si algo no arranca)${NC}"
    echo -e "\n${YELLOW}📌 Presiona Enter para volver...${NC}"
    read -r
}
#@@ grub_normal_repair

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
#@@ grub_reinstall_to_disk

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
#@@ grub_guide_header

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
#@@ guide_my_commands

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
#@@ grub_prompt_guide

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
#@@ grub_rescue_guide

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
#@@ grub_live_guide

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
#@@ datos_rescue_mnt

# ------------------------------------------------------------
# Reparación automática desde Live USB
# ------------------------------------------------------------

RESCUE_MNT="/mnt/rescate-arranque"
#@@ linux_partitions

# Particiones con sistema de archivos de Linux: "dispositivo|tamaño|tipo|etiqueta"
linux_partitions() {
    local dev fs
    while read -r dev; do
        fs=$(lsblk -dno FSTYPE "$dev" 2>/dev/null)
        case $fs in ext4|ext3|btrfs|xfs) ;; *) continue ;; esac
        echo "$dev|$(lsblk -dno SIZE "$dev" | tr -d ' ')|$fs|$(lsblk -dno LABEL "$dev")"
    done < <(lsblk -lnpo NAME,TYPE | awk '$2 == "part" || $2 == "lvm" || $2 == "crypt" {print $1}')
}
#@@ unlock_encrypted_partitions

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
#@@ rescue_umount

rescue_umount() {
    # De vuelta al sistema que está corriendo (el USB)
    [ "$BOOT_ROOT" = "$RESCUE_MNT" ] && boot_detect
    findmnt "$RESCUE_MNT" > /dev/null 2>&1 || return 0
    sudo umount -R "$RESCUE_MNT" 2>> "$LOG_FILE" || sudo umount -lR "$RESCUE_MNT" 2>> "$LOG_FILE"
}
#@@ rescue_grub_install

rescue_grub_install() {
    local uefi="$1" disk="$2"
    if $uefi; then
        run_visible "Falló la instalación de GRUB" grub_install_uefi
    else
        run_visible "Falló la instalación de GRUB" grub_install_bios "$disk"
    fi
}
#@@ set_grub_var

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
#@@ grub_menu_entries

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
#@@ grub_default_entry_menu

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
#@@ others_visible

others_visible() {
    grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub || [ -f "$GRUB_OTHERS_FIRST" ]
}
#@@ grub_os_prober_toggle

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
#@@ uefi_boot_order_menu

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
#@@ esp_check_repair

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
#@@ esp_fsck

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
#@@ regen_grub

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
#@@ grub_scripts

# Scripts de /etc/grub.d cuyo nombre contiene el texto dado, con cualquier número
# delante: Grub Customizer los renumera (37_uefi-firmware) o los cambia por *_proxy
grub_scripts() {
    local f
    for f in /etc/grub.d/[0-9][0-9]_*"$1"*; do
        [ -f "$f" ] && echo "$f"
    done
}
#@@ grub_scripts_hidden

# Oculto = existe y ninguno de sus scripts es ejecutable
grub_scripts_hidden() {
    local f found=false
    while IFS= read -r f; do
        found=true
        [ -x "$f" ] && return 1
    done < <(grub_scripts "$1")
    $found
}
#@@ grub_scripts_chmod

grub_scripts_chmod() {
    local mode="$1" f
    while IFS= read -r f; do
        sudo chmod "$mode" "$f"
    done < <(grub_scripts "$2")
}
#@@ grub_cfg_entries

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
#@@ grub_others_first_toggle

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
#@@ grub_remember_last_toggle

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
#@@ datos_boot_verbose_state

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
#@@ boot_strip_quiet

boot_strip_quiet() {
    local w words=() out=()
    read -r -a words <<< "$1"
    for w in "${words[@]}"; do
        [[ "$w" =~ $BOOT_QUIET_RE ]] || out+=("$w")
    done
    echo "${out[*]}"
}
#@@ grub_effective_var

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
#@@ boot_verbose_active

boot_verbose_active() { [ -f "$BOOT_VERBOSE_STATE" ]; }
#@@ grub_quote

# Valor entre comillas dobles, escapado para /etc/default/grub (parámetros como acpi_osi="Windows 2020")
grub_quote() {
    local v="$1"
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    v=${v//\$/\\\$}
    v=${v//\`/\\\`}
    printf '"%s"' "$v"
}
#@@ boot_verbose_on

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
#@@ boot_verbose_off

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
#@@ boot_verbose_menu

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
#@@ grub_kernel_params_menu

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
#@@ grub_customize_menu

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
            1) submenu_run grub_hide_entries ;;
            2) submenu_run grub_others_first_toggle ;;
            3) submenu_run grub_remember_last_toggle ;;
            4) submenu_run grub_appearance_menu ;;
            5) submenu_run grub_kernel_params_menu ;;
            6) submenu_run grub_restore_original ;;
            7) submenu_run undo_grub_customizer ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ Opción inválida${NC}"; sleep 1; continue ;;
        esac
        menu_pause
    done
}
#@@ remove_refind

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
#@@ uefi_distro_first

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
#@@ grub_full_repair

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
#@@ datos_rescue_card

# ------------------------------------------------------------
# Prepararse antes de que falle: tarjeta de rescate y arranque de respaldo
# ------------------------------------------------------------

RESCUE_CARD="$HOME/tarjeta-rescate-arranque.txt"
RESCUE_CARD_ESP="/boot/efi/tarjeta-rescate-arranque.txt"   # se ajusta a la partición EFI de cada distro
#@@ rescue_card_collect

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
#@@ rescue_card_write

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
#@@ mounted_usb_drives

# Pendrives montados: "carpeta|tamaño libre"
mounted_usb_drives() {
    findmnt -rno TARGET,SOURCE 2>/dev/null | awk '$1 ~ "^(/media/|/run/media/)" {print $1}' | while read -r dir; do
        dir=$(printf '%b' "$dir")   # findmnt escapa los espacios como \x20
        echo "$dir|$(df -h --output=avail "$dir" 2>/dev/null | tail -1 | tr -d ' ') libres"
    done
}
#@@ rescue_card_menu

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
#@@ rescue_card_refresh

# Actualiza la tarjeta si ya existe (después de cambiar GRUB o el kernel)
rescue_card_refresh() {
    [ -f "$RESCUE_CARD" ] || return 0
    is_live_session && return 0
    rescue_card_write 2>/dev/null || true
}
#@@ uefi_fallback_state

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
#@@ install_uefi_fallback

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
#@@ remove_uefi_fallback

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
#@@ uefi_fallback_menu

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
