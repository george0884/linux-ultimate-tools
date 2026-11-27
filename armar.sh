#!/bin/bash
# ============================================================
# Arma los tres scripts a partir de las piezas de partes/
#
#   partes/comun.sh, usb.sh, arranque.sh, auditoria.sh   compartidas por los tres
#   partes/apt.sh                                         compartida por Ubuntu y Debian
#   partes/ubuntu.sh, debian.sh, arch.sh                  lo propio de cada uno y el orden
#
# Uso:
#   bash armar.sh              arma ubuntu-, debian- y arch-ultimate-tools.sh
#   bash armar.sh --comprobar  solo comprueba que los scripts del repositorio estén al día
#
# Quien usa el programa no necesita esto: baja un solo script, ya armado, como siempre.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

COMPARTIDAS=(partes/comun.sh partes/usb.sh partes/arranque.sh partes/auditoria.sh partes/apt.sh)
DISTROS=(ubuntu debian arch)

# Une las piezas: las líneas "#@parte pieza: nombres" se cambian por esas funciones o bloques
armar() {
    awk '
        # Primero las piezas compartidas: "#@@ nombre" empieza cada función o bloque
        FILENAME != distro {
            if ($0 ~ /^#@@ /) { cur = $2; if (cur in txt) { print "Repetido: " cur " en " FILENAME > "/dev/stderr"; exit 2 }
                                txt[cur] = ""; first[cur] = 1; next }
            if ($0 ~ /^#@/) next
            if (cur == "") next
            txt[cur] = txt[cur] (first[cur] ? "" : "\n") $0
            first[cur] = 0
            next
        }
        # Después la pieza de la distribución, en orden
        /^#@parte / {
            for (i = 3; i <= NF; i++) {
                if (!($i in txt)) { print "No existe la pieza: " $i > "/dev/stderr"; exit 2 }
                print txt[$i]
            }
            next
        }
        /^#@/ { next }
        { print }
    ' distro="partes/$1.sh" "${COMPARTIDAS[@]}" "partes/$1.sh"
}

comprobar=false
[ "${1:-}" = --comprobar ] && comprobar=true
estado=0

# La versión (partes/comun.sh) tiene que tener su entrada en CHANGELOG.md
version=$(sed -n 's/^UT_VERSION="\(.*\)"$/\1/p' partes/comun.sh)
if [ -z "$version" ]; then
    echo "✗ No encontré UT_VERSION en partes/comun.sh" >&2
    exit 1
fi
if ! grep -q "^## \[$version\]" CHANGELOG.md 2>/dev/null; then
    echo "✗ La versión $version no tiene su entrada en CHANGELOG.md (\"## [$version] — fecha\")" >&2
    exit 1
fi
echo "✓ Versión $version (con su entrada en CHANGELOG.md)"
for d in "${DISTROS[@]}"; do
    destino="$d-ultimate-tools.sh"
    tmp=$(mktemp)
    armar "$d" > "$tmp"
    if ! bash -n "$tmp"; then
        echo "✗ $destino armado tiene errores de sintaxis" >&2
        rm -f "$tmp"
        exit 1
    fi
    if $comprobar; then
        if cmp -s "$tmp" "$destino"; then
            echo "✓ $destino está al día"
        else
            echo "✗ $destino no coincide con las piezas: corre \"bash armar.sh\" y sube el resultado" >&2
            estado=1
        fi
        rm -f "$tmp"
    else
        cat "$tmp" > "$destino"
        rm -f "$tmp"
        chmod +x "$destino"
        echo "✓ $destino ($(wc -l < "$destino") líneas)"
    fi
done
exit $estado
