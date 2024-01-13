#!/bin/sh

# Copyright (C) 2024, John Clark <inindev@gmail.com>

set -e


main() {
    local kern_deb="$1"
    local dtb_filter="${2:-rk3568*.dtb}"

    kern_deb="$(realpath "$kern_deb")"
    if ! [ -e "$kern_deb" ]; then
        echo "file $kern_deb not found"
        exit 4
    fi

    local tmpdir="$(mktemp -d)"

    ar x --output="$tmpdir" "$kern_deb" "data.tar.xz"
    tar -C "$tmpdir" --strip-components=4 --wildcards -xavf "$tmpdir/data.tar.xz" "./usr/lib/linux-image-*-arm64/rockchip/$dtb_filter"

    cd "$(dirname "$(realpath "$0")")/.."
    mkdir -p 'downloads'
    rm -rf 'downloads/dtbs'
    mv "$tmpdir/rockchip" 'downloads/dtbs'
    echo 'dtb files extracted to \033[36mdownloads/dtbs\033[m'

    rm -rf "$tmpdir"
}


main "$@"
