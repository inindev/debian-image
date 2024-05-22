#!/bin/sh

# Copyright (C) 2024, John Clark <inindev@gmail.com>

set -e


main() {
    rm -rf 'downloads/uboot'
    mkdir -p 'downloads/uboot'

    # copy from local if available
    if [ -d '../uboot-rockchip/outbin' ]; then
        echo 'copying u-boot bins from local...'
        cp -uv '../uboot-rockchip/outbin/'*.img '../uboot-rockchip/outbin/'*.itb 'downloads/uboot'
        return
    fi

    local tmp="$(mktemp)"
    wget -O "$tmp" 'https://github.com/inindev/uboot-rockchip/releases/latest/download/sha256sums.txt'

    local line file sha
    while read line; do
        file=${line#*  }
        sha=${line%  *}
        get_file "$file" "$sha"
    done < "$tmp"

    rm -f "$tmp"
}

get_file() {
    local file="$1"
    local sha="$2"

    wget -P 'downloads/uboot' "https://github.com/inindev/uboot-rockchip/releases/latest/download/$file"
    [ "$sha" = $(sha256sum "downloads/uboot/$file" | cut -c1-64) ] || { echo "invalid hash for downloads/uboot/$file"; exit 5; }
}

cd "$(dirname "$(realpath "$0")")/.."
main "$@"

