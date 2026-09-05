#!/bin/sh

# Copyright (C) 2026, John Clark <inindev@gmail.com>

# report the device tree the running board booted with, and the dtb file
# it came from
#
# u-boot selects the dtb at boot via its fdtfile env var, and that choice
# does not survive into linux, so the file is identified by matching this
# board's compatible property against the dtbs on disk

set -e


main() {
    [ -e /proc/device-tree/model ] || {
        echo 'no device tree found' >&2
        exit 1
    }

    local model="$(tr -d '\0' < /proc/device-tree/model)"
    local compat="$(tr '\0' '\n' < /proc/device-tree/compatible | head -n1)"

    echo "model:       $model"
    echo "compatible:  $compat"
    echo "device tree: $(find_dtb "$model")"
}

find_dtb() {
    local model="$1"
    local dtb_dir="/boot/dtbs/$(uname -r)/rockchip"

    [ -d "$dtb_dir" ] || { echo "$dtb_dir not found"; return; }

    # search on the whole compatible property, nuls matched as any-char:
    # a nul cannot be put in a shell variable, and the full list is far
    # more selective than any single entry within it
    local pat="$(tr '\0' '.' < /proc/device-tree/compatible)"

    local hits="$(grep -la "$pat" "$dtb_dir"/*.dtb 2>/dev/null)"
    case "$(echo "$hits" | wc -w)" in
        0) echo "no match for '$model' in $dtb_dir" ;;
        1) echo "$hits" ;;
        *) match_model "$model" "$hits" ;;
    esac
}

# a board's compatible list can be the tail of a variant's (cm4 is the
# suffix of cm4-v1.4), leaving more than one candidate: settle it on the
# model property, whose terminating nul is expressible in hex
match_model() {
    local model="$1"
    local want="$(printf '%s' "$model" | od -An -tx1 | tr -d ' \n')00"

    local dtb
    for dtb in $2; do
        if od -An -tx1 -v "$dtb" | tr -d ' \n' | grep -qF "$want"; then
            echo "$dtb"
            return
        fi
    done

    echo "no match for '$model'"
}

main "$@"
