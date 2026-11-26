#@ partes/usb.sh — Opción 20: descargar sistemas (lista de distros y verificación), crear USB con dd y Ventoy.
#@ Pieza para armar los scripts: no se ejecuta sola. Después de editarla corre "bash armar.sh".
#@ Cada "#@@ nombre" empieza una función o un bloque; las líneas "#@" no pasan a los scripts.
#@@ datos_usb_distros

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
#@@ usb_download_dir

usb_download_dir() {
    local d
    d=$(xdg-user-dir DOWNLOAD 2>/dev/null)
    [ -n "$d" ] && [ "$d" != "$HOME" ] || d="$HOME/Descargas"
    [ -d "$d" ] || d="$HOME/Downloads"
    [ -d "$d" ] || { d="$HOME/Descargas"; mkdir -p "$d"; }
    echo "$d"
}
#@@ usb_norm_sums

# Las listas en formato BSD ("SHA256 (archivo) = hash", Fedora, Rocky, Void...) pasan a "hash  archivo"
usb_norm_sums() {
    sed -E 's/^(SHA|MD)[0-9]* \(([^)]+)\) = ([0-9a-fA-F]+)[[:space:]]*$/\3  \2/'
}
#@@ usb_pick_from_sums

# "hash archivo" de la versión más nueva que coincide con el patrón, dentro de una lista de sumas
usb_pick_from_sums() {
    local sums
    sums=$(usb_norm_sums <<< "$1")
    local pattern="$2"
    awk -v re="^${pattern}\$" '{f = $2; sub(/^\*/, "", f); if (f ~ re) print $1, f}' <<< "$sums" \
        | sort -k2,2V | tail -1
}
#@@ usb_first_hash

# Primera suma SHA-256 o SHA-512 de un archivo de suma (lo lee por la entrada)
usb_first_hash() {
    usb_norm_sums | grep -oiE '^[0-9a-f]+' | awk 'length($0) == 64 || length($0) == 128 {print; exit}'
}
#@@ usb_hash_of

# Suma de un archivo según el largo de la oficial: 128 = SHA-512, 32 = MD5 (Slackware), si no SHA-256
usb_hash_of() {
    case ${2:-64} in
        128) sha512sum "$1" ;;
        32) md5sum "$1" ;;
        *) sha256sum "$1" ;;
    esac | awk '{print $1}'
}
#@@ usb_hash_name

usb_hash_name() {
    case $1 in 128) echo SHA-512 ;; 32) echo MD5 ;; *) echo SHA-256 ;; esac
}
#@@ usb_check_signature

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
#@@ usb_index_names

# Nombres de los enlaces de una página índice de un servidor (las carpetas sin la "/" final)
usb_index_names() {
    curl -sSfL -m 30 "$1/" 2>/dev/null | grep -oiE 'href="[^"?#]+"' \
        | sed -E 's/^href="//I; s/"$//; s#/$##; s#.*/##'
}
#@@ usb_sorted

# De los nombres o rutas que llegan por la entrada, los que coinciden con el patrón (en su
# último tramo), ordenados de la versión más vieja a la más nueva según los números del nombre
usb_sorted() {
    local re="^$1\$" n base
    sort -u | while IFS= read -r n; do
        base=${n##*/}
        [[ "$base" =~ $re ]] && printf '%s\t%s\n' "$(sed 's/[^0-9.]//g' <<< "$base")" "$n"
    done | sort -t$'\t' -k1,1V | cut -f2
}
#@@ usb_resolve_download

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
#@@ usb_choose_distro

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
#@@ usb_download_iso

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
#@@ usb_write_sum_file

# Deja "suma  nombre" al lado de la ISO (.sha256, .sha512 o .md5 según el largo de la suma)
usb_write_sum_file() {
    local iso="$1" sum="${2,,}" ext
    [ -n "$sum" ] || return 0
    case ${#sum} in 128) ext=sha512 ;; 32) ext=md5 ;; *) ext=sha256 ;; esac
    printf '%s  %s\n' "$sum" "$(basename "$iso")" > "$iso.$ext" 2>/dev/null || true
}
#@@ usb_pick_local_iso

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
#@@ usb_entry_pattern

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
#@@ usb_official_sum_for

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
#@@ usb_sum_lookup

# Busca "nombre" en una lista de sumas ("hash  nombre" o "hash *nombre"); imprime el hash
usb_sum_lookup() {
    local sums="$1" name="$2" h
    h=$(usb_norm_sums <<< "$sums" | awk -v n="$name" '{f = $2; sub(/^\*/, "", f)} f == n {print $1; exit}')
    [ -n "$h" ] && { echo "$h"; return 0; }
    return 1
}
#@@ usb_known_sum

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
#@@ usb_verify_local_iso

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
#@@ usb_check_iso

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
#@@ usb_candidates

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
#@@ usb_pick_device

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
#@@ usb_unmount_dev

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
#@@ create_usb_menu

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
#@@ datos_ventoy_dir

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
#@@ ventoy_get_tool

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
#@@ ventoy_has

# ¿Está este programa del sistema? (en Debian, /usr/sbin no está en el PATH de los usuarios)
ventoy_has() {
    local d
    for d in /usr/sbin /sbin /usr/bin /bin; do
        [ -x "$d/$1" ] && return 0
    done
    return 1
}
#@@ ventoy_need_partitioner

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
#@@ ventoy_part_label

# Etiqueta de una partición (lsblk; si udev no la conoce, blkid)
ventoy_part_label() {
    local l
    l=$(lsblk -dno LABEL "$1" 2>/dev/null | sed 's/ *$//')
    [ -n "$l" ] || l=$(blkid -o value -s LABEL "$1" 2>/dev/null)
    echo "$l"
}
#@@ ventoy_find_part

# Partición del disco con esa etiqueta
ventoy_find_part() {
    local p
    for p in $(lsblk -lnpo NAME "$1" 2>/dev/null | tail -n +2); do
        [ "$(ventoy_part_label "$p")" = "$2" ] && { echo "$p"; return 0; }
    done
    return 1
}
#@@ ventoy_run

# Corre una herramienta de Ventoy desde su carpeta (así lo pide Ventoy)
ventoy_run() {
    local tool="$1"
    shift
    ( cd "$VENTOY_TOOL" && sudo bash "./$tool" "$@" )
}
#@@ ventoy_candidates

# Pendrives que ya tienen Ventoy (mismo formato que usb_candidates)
ventoy_candidates() {
    local d
    while IFS= read -r d; do
        ventoy_find_part "${d%%|*}" Ventoy > /dev/null && ventoy_find_part "${d%%|*}" VTOYEFI > /dev/null && echo "$d"
    done < <(usb_candidates)
}
#@@ ventoy_pick_and_mount

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
#@@ ventoy_list_images

# Imágenes que Ventoy puede arrancar, con la ruta relativa al pendrive
ventoy_list_images() {
    ( cd "$VENTOY_MNT" && find . -path ./ventoy -prune -o -path ./persistence -prune -o -type f \
        \( -iname '*.iso' -o -iname '*.img' -o -iname '*.wim' -o -iname '*.vhd' -o -iname '*.vhdx' -o -iname '*.efi' \) \
        -print 2>/dev/null | sed 's#^\.##' | sort )
}
#@@ ventoy_write_json

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
#@@ ventoy_conf_set

# Agrega o cambia una línea "tipo|imagen|valor" de la lista propia
ventoy_conf_set() {
    local conf="$VENTOY_MNT/ventoy/linux-ultimate-tools.conf" kind="$1" img="$2" val="$3"
    mkdir -p "$VENTOY_MNT/ventoy"
    touch "$conf"
    grep -vF -- "$kind|$img|" "$conf" > "$conf.tmp" 2>/dev/null
    [ -n "$val" ] && printf '%s|%s|%s\n' "$kind" "$img" "$val" >> "$conf.tmp"
    mv -f -- "$conf.tmp" "$conf"
}
#@@ ventoy_alias_for

# Nombre claro para el menú de Ventoy: el del sistema y su versión ("Ubuntu 26.04.1")
ventoy_alias_for() {
    local name="$1" file="$2" ver
    name=${name%%, última LTS}
    name=${name%% (*}
    ver=$(grep -oE '[0-9]+(\.[0-9]+)+|[0-9]{6,}' <<< "$file" | head -1)
    echo "$name${ver:+ $ver}"
}
#@@ ventoy_install

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
#@@ ventoy_add

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
#@@ ventoy_guess_name

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
#@@ ventoy_manage

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
#@@ ventoy_persistence_kind

# Tipo de persistencia que entiende un sistema live (vacío si no se conoce)
#   casper (Ubuntu y derivadas): etiqueta casper-rw; live-boot (Debian y derivadas): persistence
ventoy_persistence_kind() {
    case $(basename "$1") in
        ubuntu-*|kubuntu-*|xubuntu-*|lubuntu-*|ubuntu-mate-*|ubuntu-budgie-*|linuxmint-*|Zorin-OS-*|pop-os_*|neon-*) echo casper ;;
        debian-live-*|lmde-*|kali-linux-*-live-*) echo live-boot ;;
    esac
}
#@@ ventoy_persistence

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
#@@ ventoy_update

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
#@@ ventoy_menu

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
