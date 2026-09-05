#!/bin/sh

# Copyright (C) 2026, John Clark <inindev@gmail.com>

set -euo pipefail


main() {
    # source media is overridden by env: DEB_MEDIA=... sh create_images.sh
    local deb_media="${DEB_MEDIA:-debian/base_mmc_2g.img}"

    local all_boards=$(cat <<- 'EOF'
	rk3308-rock-s0
	rk3566-orangepi-cm4
	rk3568-nanopi-r5c
	rk3568-nanopi-r5s
	rk3568-odroid-m1
	rk3568-radxa-e25
	rk3576-armsom-sige5
	rk3576-luckfox-omni3576
	rk3576-nanopi-m5
	rk3588-nanopc-t6
	rk3588s-orangepi-5
	rk3588-orangepi-5-plus
	rk3588-rock-5b
	EOF
    )

    # boards may be named on the command line, optionally as globs
    # (e.g. 'rk3588*'); with no arguments every board is built
    local no_compress='false'
    local args='' arg
    for arg in "$@"; do
        case "$arg" in
            --no-compress) no_compress='true' ;;
            -*) perr "unknown option: $arg"; usage "$all_boards"; exit 1 ;;
            *) args="$args $arg" ;;
        esac
    done

    local boards=''
    if [ -z "$args" ]; then
        boards="$all_boards"
    else
        local pat match
        for pat in $args; do
            match=''
            for board in $all_boards; do
                case "$board" in
                    $pat) match="$match $board" ;;
                esac
            done
            if [ -z "$match" ]; then
                perr "no such board: $pat"
                usage "$all_boards"
                exit 1
            fi
            boards="$boards$match"
        done
    fi

    local outbin='outbin'
    local dl_dir='downloads'
    local mountpt='rootfs'

    # check for media file
    if ! [ -e "$deb_media" ]; then
        perr "unable to find debian source media: $deb_media";
        echo "run: ${grn}sh debian/make_debian_img.sh${rst}\n"
        exit 1;
    fi

    # detect sector size
    local sector_size=$(detect_sector_size "$deb_media")
    case "$sector_size" in
        512|4096)
            echo "detected source image sector size: ${cya}$sector_size${rst} bytes"
            ;;
        *)
            perr "invalid or unsupported sector size detected in source image: $deb_media"
            echo "detected: $sector_size (expected 512 or 4096)"
            echo "run: ${grn}sh debian/make_debian_img.sh${rst}\n"
            exit 1
            ;;
    esac

    # download file dependencies
    get_deps "$boards" '' "$dl_dir"

    # 4k sector images target ufs media
    local suffix=''
    [ "$sector_size" = 4096 ] && suffix='_ufs'

    mkdir -p "$outbin"
    local built=''

    # build one generic rootfs per kernel flavor the selected boards need
    local flavor flavors=''
    for board in $boards; do
        flavor="$(board_flavor "$board")"
        case " $flavors " in
            *" $flavor "*) ;;
            *) flavors="$flavors $flavor" ;;
        esac
    done

    for flavor in $flavors; do
        psec "building generic rootfs: $flavor"
        generic_img=''
        build_rootfs "$deb_media" "$sector_size" "$mountpt" "$flavor" "$outbin" "$dl_dir" "$suffix"
        eval "generic_$flavor=\"\$generic_img\""
    done

    # the stock 512 rootfs is shipped as a board-agnostic image: it boots any
    # supported board once u-boot is written to it
    if [ -z "$suffix" ]; then
        case " $flavors " in
            *' stock '*) built="$built $outbin/$generic_stock" ;;
        esac
    fi

    # stamp each board: copy its flavor's rootfs and write u-boot to it
    for board in $boards; do
        psec "processing board: $board"
        img_name=''
        stamp_board "$board" "$outbin" "$dl_dir" "$suffix" \
            "$(eval echo "\$generic_$(board_flavor "$board")")"
        [ -n "$img_name" ] && built="$built $outbin/$img_name"
    done

    # compress only what this run built, leaving prior images untouched
    if [ "$no_compress" = 'true' ]; then
        echo "\n${cya}skipping compression (--no-compress)${rst}"
    elif [ -n "$built" ]; then
        phead 'compressing images'
        xz -z8v $built
    fi
}

# boards run the debian kernel unless mainline support is not yet sufficient
board_flavor() {
    case "$1" in
        rk3576*) echo 'mainline' ;;
        *)       echo 'stock' ;;
    esac
}

usage() {
    local all_boards="$1"

    echo "\nusage: sh create_images.sh [--no-compress] [board...]"
    echo "\n  board            one or more board names, globs allowed (default: all)"
    echo "  --no-compress    leave images uncompressed"
    echo "  DEB_MEDIA=<img>  override the source media path\n"
    echo "${bld}available boards:${rst}"
    local board
    for board in $all_boards; do
        echo "  $board"
    done
    echo
}

# build a board-agnostic rootfs for one kernel flavor; sets global generic_img
build_rootfs() {
    local deb_media="$1"
    local sector_size="$2"
    local mountpt="$3"
    local flavor="$4"
    local outbin="$5"
    local dl_dir="$6"
    local suffix="$7"

    local base="rockchip"
    [ "$flavor" = 'stock' ] || base="rockchip-${flavor}"

    # reuse an existing rootfs so repeated runs only stamp
    local existing="$(find "$outbin" -maxdepth 1 -name "${base}_*${suffix}.img" 2>/dev/null | head -n1)"
    if [ -n "$existing" ]; then
        generic_img="$(basename "$existing")"
        echo "generic rootfs already exists, reusing: ${cya}$generic_img${rst}"
        return
    fi

    echo "${h1}building generic ${yel}$flavor${rst}${bld} rootfs...${rst}"

    local tmp_img="${outbin}/${base}${suffix}.img.tmp"
    install -Dvm 644 "$deb_media" "$tmp_img"

    # dash does not run an EXIT trap on a signal, so name them explicitly
    trap "on_exit $mountpt" EXIT
    trap "on_exit $mountpt INT" INT
    trap "on_exit $mountpt QUIT" QUIT
    trap "on_exit $mountpt TERM" TERM
    mount_media "$tmp_img" "$mountpt" "$sector_size"

    setup_dtb "$mountpt"
    setup_hostname "$mountpt"
    setup_kernel "$mountpt" "$flavor" "$dl_dir"
    setup_network "$mountpt"

    # image name is based on distribution name (img_name is global)
    get_img_name "$mountpt" "$base" "$suffix"

    seal_image "$mountpt"
    unmount_media "$mountpt"

    mv "$tmp_img" "$outbin/$img_name"
    generic_img="$img_name"

    echo "\n${cya}generic rootfs $outbin/$generic_img is ready${rst}\n"
}

# specialize a generic rootfs for one board by writing its u-boot
stamp_board() {
    local board="$1"
    local outbin="$2"
    local dl_dir="$3"
    local suffix="$4"
    local generic="$5"

    echo "${h1}configuring debian image for board ${yel}$board${rst}${bld}...${rst}"

    # the generic name carries the distribution version, so reuse it
    local name="${generic#rockchip}"
    name="${name#-mainline}"
    name="${board}${name}"

    if [ -f "$outbin/$name" ] || [ -f "$outbin/${name}.xz" ]; then
        echo "image already exists, skipping..."
        return
    fi

    # the rootfs is board-agnostic: only u-boot differs
    install -Dvm 644 "$outbin/$generic" "$outbin/$name"
    install_uboot "$outbin/$name" "$board" "$dl_dir"

    img_name="$name"
    echo "\n${cya}image $outbin/$img_name is ready${rst}"
    echo "(use \"sudo mount -no loop,offset=16M $outbin/$img_name /mnt\" to mount)\n"
}

seal_image() {
    local mountpt="$1"

    phead "purging ssh keys"
    sudo rm -fv "$mountpt/etc/ssh/ssh_host_"*

    # reduce entropy in free space to enhance compression
    phead "reducing image entropy"
    cat /dev/zero > "$mountpt/tmp/zero.bin" 2> /dev/null || true
    sync
    rm -fv "$mountpt/tmp/zero.bin"
}

setup_network() {
    local mountpt="$1"

    # every image carries all board network configs: rc.local selects the
    # matching one on first boot using /proc/device-tree/compatible
    local net_src='configs/network'
    [ -d "$net_src" ] || return 0

    phead 'installing board network configs'
    sudo install -dm 755 "$mountpt/etc/network-setup"
    sudo cp -av "$net_src/." "$mountpt/etc/network-setup/"
    sudo chmod 644 "$mountpt/etc/network-setup/"*
}

setup_kernel() {
    local mountpt="$1"
    local flavor="$2"
    local dl_dir="$3"

    echo "${h1}updating packages...${rst}"
    sudo chroot "$mountpt" apt update

    case "$flavor" in
        mainline)
            phead "setting up kernel: ${yel}inindev"
            sudo cp "$dl_dir/kernel/inindev.deb" "$mountpt/tmp"
            sudo chroot "$mountpt" dpkg -i '/tmp/inindev.deb'
            sudo rm -f "$mountpt/tmp/inindev.deb"
            ;;
        *)
            phead "setting up kernel: ${yel}debian stable"
            sudo chroot "$mountpt" apt -y install linux-image-arm64
            ;;
    esac

    echo "${h1}upgrading packages...${rst}"
    sudo chroot "$mountpt" apt -y upgrade
    sudo chroot "$mountpt" apt clean
}

setup_dtb() {
    local mountpt="$1"

    # out-of-tree dtbs are installed version-independently to /boot/dtbs/local
    # and are overlaid onto each kernel's dtb directory by the dtb_cp hook
    local dtb_src='configs/dtbs'
    [ -d "$dtb_src" ] || return 0

    local dtbs="$(find "$dtb_src" -maxdepth 1 -name '*.dtb' 2>/dev/null | sort)"
    [ -n "$dtbs" ] || return 0

    echo "${h1}installing local device trees${rst}"
    sudo install -dm 755 "$mountpt/boot/dtbs/local/rockchip"

    local dtb
    for dtb in $dtbs; do
        sudo install -vm 644 "$dtb" "$mountpt/boot/dtbs/local/rockchip"
    done
}

setup_hostname() {
    local mountpt="$1"

    # images are board-generic: rc.local sets the real hostname on first boot
    # from /proc/device-tree/compatible
    local dist=$(cat "$mountpt/etc/os-release" | sed -rn 's/VERSION_CODENAME=(.*)/\1/p')
    local hostname="${dist}-rockchip"

    echo -n "${h1}configuring hostname: ${yel}"
    echo "$hostname" | sudo tee "$mountpt/etc/hostname"
    echo -n "${rst}"
    sudo sed -i "s/\(127\.0\.1\.1\).*/\1\t$hostname/" "$mountpt/etc/hosts"
}

get_img_name() {
    local mountpt="$1"
    local board="$2"
    local suffix="$3"

    local dist=$(cat "$mountpt/etc/os-release" | sed -rn 's/VERSION_CODENAME=(.*)/\1/p')
    local ver=$(cat "$mountpt/etc/debian_version")

    img_name="${board}_${dist}-${ver}${suffix}.img"
}

install_uboot() {
    local img_name="$1"
    local board="$2"
    local dl_dir="$3"

    phead "installing u-boot: ${board}.zip"
    local sha=$(unzip -p "$dl_dir/uboot/${board}.zip" "${board}/sha256sums.txt" | grep 'u-boot-rockchip.bin' | cut -c1-64)
    local tmpdir="$(mktemp -d)"
    unzip "$dl_dir/uboot/${board}.zip" "${board}/u-boot-rockchip.bin" -d "$tmpdir"
    test "$sha" = $(sha256sum "$tmpdir/${board}/u-boot-rockchip.bin" | cut -c1-64)
    sudo dd bs=4K seek=8 if="$tmpdir/${board}/u-boot-rockchip.bin" of="$img_name" conv=notrunc,fsync
    rm -rf "$tmpdir"
    echo "u-boot installed successfully"
}

get_deps() {
    local boards="$1"
    local uboot_ver="$2"
    local dl_dir="${3:-downloads}"

    mkdir -p "$dl_dir"

    phead 'downloading u-boot bins'
    get_uboot_bins "$boards" "$uboot_ver" "$dl_dir/uboot"

    phead 'downloading latest inindev kernel'
    get_inindev_kernel "$dl_dir/kernel"
}

get_uboot_bins() {
    local boards="$1"
    local uboot_ver="$2"
    local dl_dir="$3"

    local uboot_url="https://github.com/inindev/uboot-rockchip/releases"
    [ -z "$uboot_ver" ] && uboot_url="${uboot_url}/latest/download" || uboot_url="${uboot_url}/download/$uboot_ver"

    mkdir -p "$dl_dir"
    for board in $boards; do
        if [ -f "$dl_dir/${board}.zip" ]; then
            psec "skipping board (already downloaded): $board"
        else
            psec "downloading board: $board"
            wget -P "$dl_dir" "$uboot_url/${board}.zip" || { rc=$?; echo "failed to download ${board}.zip"; exit $rc; }
        fi
    done
}

get_inindev_kernel() {
    local dl_dir="$1"

    local latest='https://api.github.com/repos/inindev/linux-rockchip/releases/latest'
    local kurl=$(curl -s "$latest" | grep 'browser_download_url' | grep 'linux-image' | grep -v 'dbg' | grep -o 'https://[^"]*')
    local kfile="$(basename $kurl)"

    if ! [ -f "$dl_dir/$kfile" ]; then
        psec "downloading: $kfile"
        mkdir -p "$dl_dir"
        wget -P "$dl_dir" "$kurl"
    fi

    ln -sfv "$kfile" "$dl_dir/inindev.deb"
}

extract_dtbs() {
    local kern_deb="$1"
    local dtb_filter="$2"
    local dl_dir="$3"

    local tmpdir="$(mktemp -d)"

    ar x --output="$tmpdir" "$kern_deb" "data.tar.xz"
    tar -C "$tmpdir" --strip-components=4 --wildcards -xavf "$tmpdir/data.tar.xz" "./usr/lib/linux-image-*-arm64/rockchip/$dtb_filter"

    mkdir -p "$dl_dir"
    rm -f "$dl_dir/"*
    mv "$tmpdir/rockchip/"* "$dl_dir"
    echo "dtb files extracted to $dl_dir"

    rm -rf "$tmpdir"
}

detect_sector_size() {
    local media="$1"

    # check for "EFI PART" at offset 512 (512-byte sector)
    if dd if="$media" bs=1 skip=512 count=8 2>/dev/null | grep -q 'EFI PART'; then
        echo '512'
        return
    fi

    # check for "EFI PART" at offset 4096 (4096-byte sector)
    if dd if="$media" bs=1 skip=4096 count=8 2>/dev/null | grep -q 'EFI PART'; then
        echo '4096'
        return
    fi

    echo 'unknown'
}

mount_media() {
    local media="$1"
    local mountpt="$2"
    local sector_size="$3"

    if [ -d "$mountpt" ]; then
        unmount_media "$mountpt"
    fi

    echo "${h1}mounting media: ${yel}$media${rst}"
    mkdir -p "$mountpt"

    local lodev=$(sudo losetup -f)
    add_loop_dev "$lodev"

    sudo losetup --sector-size="$sector_size" -vP "$lodev" "$media"
    sync

    sudo mount "${lodev}p1" "$mountpt"

    local mp
    for mp in 'dev' 'dev/pts' 'proc' 'sys' 'run'; do
        sudo mount --bind "/$mp" "$mountpt/$mp" || {
            perr "failed to bind mount ${cya}/$mp${rst} to ${cya}$mountpt/$mp"
            sudo losetup -d "$lodev" 2>/dev/null || true
            remove_loop_dev "$lodev"
            return 1
        }
    done

    echo "partition successfully mounted on ${cya}$mountpt${rst}"
}

unmount_media() {
    local mountpt="$1"

    local mp mlist=''
    for mp in 'run' 'sys' 'proc' 'dev/pts' 'dev' ''; do
        mountpoint -q "$mountpt/$mp" && mlist="$mlist $mountpt/$mp"
    done

    [ -n "$mlist" ] && echo "${h1}unmounting mount points...${rst}"
    for mp in $mlist; do
        sudo umount -v "$mp"
    done

    # detach any loop device associated with this mountpt (find via back-reference)
    local attached=$(sudo losetup -l --noheadings | grep "$(realpath "$mountpt" 2>/dev/null || echo '')" | awk '{print $1}')
    for dev in $attached; do
        sudo losetup -d "$dev" 2>/dev/null || true
        remove_loop_dev "$dev"
    done

    rm -rf "$mountpt"
}

on_exit() {
    # capture before anything else runs and overwrites it
    local rc="$?"
    local mountpt="$1"
    local sig="${2:-}"

    unmount_media "$mountpt"

    # safety net: detach any remaining tracked loop devices
    for dev in $LOOP_DEVS; do
        [ -b "$dev" ] && sudo losetup -d "$dev" 2>/dev/null
    done
    LOOP_DEVS=""

    trap - EXIT INT QUIT TERM

    # for a signal, die from it: the shell sets the status and the caller
    # sees a killed process rather than one that merely exited
    [ -n "$sig" ] && kill -"$sig" $$

    exit "$rc"
}

# global tracking of loop devices (space-delimited string)
LOOP_DEVS=""

add_loop_dev() {
    LOOP_DEVS="$LOOP_DEVS $1"
}

remove_loop_dev() {
    LOOP_DEVS=$(echo "$LOOP_DEVS" | sed "s| $1||g")
}

phead() {
    local msg="$1"
    echo "\n${h1}$msg...${rst}"
}

psec() {
    local msg="$1"
    echo "\n${mag}=====  ${cya}$msg${mag}  =====${rst}"
}

perr() {
    local msg="$1"
    echo "\n${bld}${yel}error: $msg${rst}\n" >&2
}

# require linux
uname_s=$(uname -s)
if [ "$uname_s" != 'Linux' ]; then
    perr "this project requires a Linux system, but '$uname_s' was detected"
    exit 1
fi

# require arm64
uname_m=$(uname -m)
if [ "$uname_m" != 'aarch64' ]; then
    perr "this project requires an ARM64 architecture, but '$uname_m' was detected"
    exit 1
fi

rst='\033[m'
bld='\033[1m'
red='\033[31m'
grn='\033[32m'
yel='\033[33m'
blu='\033[34m'
mag='\033[35m'
cya='\033[36m'
h1="\n${blu}==>${rst} ${bld}"

cd "$(dirname "$(realpath "$0")")"
main "$@"
