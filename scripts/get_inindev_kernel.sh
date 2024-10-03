#!/bin/sh

# Copyright (C) 2024, John Clark <inindev@gmail.com>

set -e


main() {
    echo 'lookup latest inindev kernel'
    local latest='https://api.github.com/repos/inindev/linux-rockchip/releases/latest'
    local kurl=$(curl -s "$latest" | grep 'browser_download_url' | grep 'linux-image' | grep -v 'dbg' | grep -o 'https://[^"]*')
    local kfile="$(basename $kurl)"

    if ! [ -f "downloads/kernels/$kfile" ]; then
        echo "downloading: $kurl"
        mkdir -p 'downloads/kernels'
        wget -nc -P "downloads/kernels" "$kurl"
    fi

    ln -sfv "$kfile" 'downloads/kernels/inindev.deb'
}


cd "$(dirname "$(realpath "$0")")/.."
main "$@"

