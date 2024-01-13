#!/bin/sh

# Copyright (C) 2024, John Clark <inindev@gmail.com>

set -e


main() {
    local dist="${1:-stable}"

    local kpath="$(curl -s "https://packages.debian.org/$dist/kernel/linux-image-arm64" | grep -A1 'dep:' | sed -rn 's|.*<a href=\"(.*)\">.*|\1|p')"

    local kdir="$(dirname $kpath)"
    local kfile="$(basename $kpath)"

    local kpre="https://packages.debian.org${kdir}/arm64/${kfile}/download"
    local kurl="$(curl -s $kpre | sed -rn 's|.*href=\"(.*_arm64.deb)\".*|\1|p' | head -n1)"

    echo "fetching: $kurl"
    wget -P "downloads" "$kurl"
}


cd "$(dirname "$(realpath "$0")")/.."
main "$@"
