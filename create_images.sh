#!/bin/sh

# Copyright (C) 2025, John Clark <inindev@gmail.com>

set -e


main() {
    local deb_media="${1:-debian/base_mmc_2g.img}"

    local boards=$(cat <<- 'EOF'
	rk3308-rock-s0
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

    local outbin='outbin'
    local dl_dir='downloads'
    local mountpt='rootfs'

    # check for media file
    if ! [ -e "$deb_media" ]; then
        perr "unable to find debian source media: $deb_media";
        echo "run: ${grn}sh debian/make_debian_img.sh${rst}\n"
        exit 1;
    fi

    # download file dependencies
    get_deps "$boards" 'v2025.07' "$dl_dir"

    # build images
    mkdir -p "$outbin"
    for board in $boards; do
        psec "processing board: $board"
        setup_image "$deb_media" "$mountpt" "$board" "$outbin" "$dl_dir"
    done

    # compress images
    xz -z8v "$outbin/"*".img"
}

setup_image() {
    local deb_media="$1"
    local mountpt="$2"
    local board="$3"
    local outbin="$4"
    local dl_dir="$5"

    echo "${h1}configuring debian image for board ${yel}$board${rst}${bld}...${rst}"

    if [ -f "$outbin/$board"*".img"* ]; then
        echo "image already exists, skipping..."
        return
    fi

    # copy image
    local tmp_img_name="$outbin/${board}.img.tmp"
    install -Dvm 644 "$deb_media" "$tmp_img_name"

    # mount image
    trap "on_exit $mountpt" EXIT INT QUIT ABRT TERM
    mount_media "$tmp_img_name" "$mountpt"

    # setups
    setup_dtb "$mountpt" "$board" "$dl_dir"
    setup_hostname "$mountpt" "$board"
    setup_kernel "$mountpt" "$board" "$dl_dir"
    setup_network "$mountpt" "$board"

    # the final image name is based on distribution name
    local img_name=''
    get_img_name "$mountpt" "$board"

    seal_image "$mountpt"
    unmount_media "$mountpt"

    # install u-boot
    install_uboot "$tmp_img_name" "$board" "$dl_dir"

    # rename to final name
    mv "$tmp_img_name" "$outbin/$img_name"

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
    local board="$2"

    # post setup: inject network config if file exists
    if [ -f "configs/network_${board}.cfg" ]; then
        phead "setting up networking for ${yel}$board"
        sudo sed -i "/setup for expand fs/e cat configs/network_${board}.cfg" "$mountpt/etc/rc.local"
    fi
}

setup_kernel() {
    local mountpt="$1"
    local board="$2"
    local dl_dir="$3"

    echo "${h1}updating packages...${rst}"
    sudo chroot "$mountpt" apt update

    case "$board" in
        rk3576*)
            phead "setting up kernel: ${yel}inindev"
            sudo cp "$dl_dir/kernel/inindev.deb" "$mountpt/tmp"
            sudo chroot "$mountpt" dpkg -i '/tmp/inindev.deb'
            sudo rm -f "$mountpt/tmp/inindev.deb"
            sudo chroot "$mountpt" apt -y install apparmor
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
    local board="$2"
    local dl_dir="$3"

    local dtb_file="${board}.dtb"

    # install downloaded dtb if present
    if [ -e "$dl_dir/dtbs/$dtb_file" ]; then
        sudo install -vm 644 "$dl_dir/dtbs/$dtb_file" "$mountpt/boot"
    fi

    local dtb_file="${board}.dtb"
    echo "${h1}configuring device tree: ${yel}$dtb_file${rst}"

    local dtb_cfg="configs/dtb_${board}.cfg"
    if [ -f "$dtb_cfg" ]; then
        dtb_file=$(head -n 1 "$dtb_cfg" | sed 's/ /\\ /g')
        local dtb_func=$(sed -n '3,$p' "$dtb_cfg" | sed ':a;N;$!ba;s/\n/\\n/g')
	sudo sed -i "/^get_dtb() {/,/^}/c\\$dtb_func" "$mountpt/boot/mk_extlinux"
    else
        sudo sed -i "s/<DTB_FILE>/$dtb_file/g" "$mountpt/boot/mk_extlinux"
    fi

    # replace <DTB_FILES> in kernel scripts
    sudo sed -i "s/<DTB_FILES>/$dtb_file/g" "$mountpt/etc/kernel/postinst.d/dtb_cp"
    sudo sed -i "s/<DTB_FILES>/$dtb_file/g" "$mountpt/etc/kernel/postinst.d/kernel_chmod"
    sudo sed -i "s/<DTB_FILES>/$dtb_file/g" "$mountpt/etc/kernel/postrm.d/dtb_rm"
}

setup_hostname() {
    local mountpt="$1"
    local board="$2"

    # hostname is <dist>-<board>
    # bookworm-odroid-m1
    local dist=$(cat "$mountpt/etc/os-release" | sed -rn 's/VERSION_CODENAME=(.*)/\1/p')
    local hostname="${dist}-${board}"

    echo -n "${h1}configuring hostname: ${yel}"
    echo "$hostname" | sudo tee "$mountpt/etc/hostname"
    echo -n "${rst}"
    sudo sed -i "s/\(127\.0\.1\.1\).*/\1\t$hostname/" "$mountpt/etc/hosts"
}

get_img_name() {
    local mountpt="$1"
    local board="$2"

    # <board>_<dist>-<ver>_<lrev>.img
    # odroid-m1_bookworm-12.4-1.img
    local dist=$(cat "$mountpt/etc/os-release" | sed -rn 's/VERSION_CODENAME=(.*)/\1/p')
    local ver=$(cat "$mountpt/etc/debian_version")

    img_name="${board}_${dist}-${ver}.img"
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

mount_media() {
    local media="$1"
    local mountpt="$2"

    if [ -d "$mountpt" ]; then
        unmount_media "$mountpt"
    fi

    echo "${h1}mounting media: ${yel}$media${rst}"
    mkdir -p "$mountpt"

    sudo mount -no loop,offset=16M "$media" "$mountpt"

    local mp
    for mp in 'dev' 'dev/pts' 'proc' 'sys' 'run'; do
        sudo mount --bind "/$mp" "$mountpt/$mp" || {
            perr "failed to bind mount ${cya}/$mp${rst} to ${cya}$mountpt/$mp"
            return 1
        }
    done

    local part="$(/usr/sbin/losetup -nO name -j "$media")"
    echo "partition ${cya}$part${rst} successfully mounted on ${cya}$mountpt${rst}"
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
    rm -rf "$mountpt"
}

on_exit() {
    local mountpt="$1"
    local rc="$?"

    unmount_media "$mountpt"

    trap - EXIT INT QUIT ABRT TERM
    exit "$rc"
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
