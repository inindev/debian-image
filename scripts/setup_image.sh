#!/bin/sh

# Copyright (C) 2024, John Clark <inindev@gmail.com>

set -e


main() {
    local media="${1:-debian/base_mmc_2g.img}"
    local mountpt="${2:-rootfs}"
    local lrev="${3:-0}"
    local outbin="${4:-outbin}"

    local dist_next='trixie'

    # check for media file
    test -e "$media" || { echo "error: unable to find media: $media"; exit 1; }
    trap "on_exit $mountpt" EXIT INT QUIT ABRT TERM

    # download file dependencies
    get_deps "$dist_next"
    [ '_deps_only' = "_$1" ] && exit 0

    # nanopi-r5c
    setup_image "$media" "$mountpt" 'stable' 'rk3568-nanopi-r5c.dtb' "$outbin" 'nanopi_hook'

    # nanopi-r5s
    setup_image "$media" "$mountpt" 'stable' 'rk3568-nanopi-r5s.dtb' "$outbin" 'nanopi_hook'

    # odroid-m1
    setup_image "$media" "$mountpt" 'stable' 'rk3568-odroid-m1.dtb' "$outbin"

    # radxa-e25
    setup_image "$media" "$mountpt" 'stable' 'rk3568-radxa-e25.dtb' "$outbin"

    # nanopc-t6
    setup_image "$media" "$mountpt" "$dist_next" 'rk3588-nanopc-t6.dtb' "$outbin"

    # orangepi-5
    setup_image "$media" "$mountpt" "$dist_next" 'rk3588s-orangepi-5.dtb' "$outbin"

    # orangepi-5-plus
    setup_image "$media" "$mountpt" "$dist_next" 'rk3588-orangepi-5-plus.dtb' "$outbin"

    # rock-5b
    setup_image "$media" "$mountpt" "$dist_next" 'rk3588-rock-5b.dtb' "$outbin"
}

setup_image() {
    local media="$1"
    local mountpt="$2"
    local kern_dist="$3"
    local dtb="$4"
    local outbin="${5:-outbin}"
    local hook="$6"

    local board="${dtb#*-}" ; board="${board%.*}"

    echo "${h1}configuring debian image for board ${yel}$board${rst}${bld}...${rst}"

    # copy image locally
    local tmp_img_name="$outbin/${board}.img.tmp"
    install -Dvm 644 "$media" "$tmp_img_name"
    mount_media "$tmp_img_name" "$mountpt"

    # set dtb and image name
    set_dtb "$mountpt" "$dtb"
    set_hostname "$mountpt" "$board"

    # install the kernel
    [ '_stable' != "_$kern_dist" ] && dist_kern_hook "$mountpt" "$kern_dist"
    sudo chroot "$mountpt" /usr/bin/apt update
    sudo chroot "$mountpt" /usr/bin/apt -y upgrade
    sudo chroot "$mountpt" /usr/bin/apt -y install linux-image-arm64
    sudo chroot "$mountpt" /usr/bin/apt clean

    # the final image name is based on distribution name
    local img_name=''
    get_img_name "$mountpt" "$board"

    # post setup hook
    [ -n "$hook" ] && "$hook" "$media" "$mountpt" "$board"

    # cleanup ssh keys
    sudo rm -fv "$mountpt/etc/ssh/ssh_host_"*

    unmount_media "$mountpt"

    # install u-boot
    install_uboot "$tmp_img_name" "$board"

    # rename to final name
    local out_img_name="$outbin/$img_name"
    mv "$tmp_img_name" "$out_img_name"

    echo "\n${cya}image $out_img_name is ready${rst}"
    echo "(use \"sudo mount -no loop,offset=16M $out_img_name /mnt\" to mount)\n"
}

nanopi_hook() {
    local media="$1"
    local mountpt="$2"
    local board="$3"

    sudo sed -i "/setup for expand fs/e cat configs/network_${board}.cfg" "$mountpt/etc/rc.local"
}

dist_kern_hook() {
    local mountpt="$1"
    local dist="$2"

    cat <<-EOF | sudo tee "$mountpt/etc/apt/preferences.d/99-${dist}-kernel"
	Package: *
	Pin: release n=bookworm*
	Pin-Priority: 600

	Package: linux-image-arm64
	Pin: release n=$dist
	Pin-Priority: 800

	EOF

    cat <<-EOF | sudo tee -a "$mountpt/etc/apt/sources.list"
	# linux-image*
	deb http://deb.debian.org/debian $dist main
	#deb-src http://deb.debian.org/debian $dist main

	EOF
}

set_dtb() {
    local mountpt="$1"
    local dtbname="$2"

    # some kernels require an external dtb
    [ -e "downloads/dtbs/$dtbname" ] && sudo install -vm 644 "downloads/dtbs/$dtbname" "$mountpt/boot" || true

    echo "${h1}installing device tree: $dtbname${rst}"
    sudo sed -i "s/<DTB_FILE>/$dtbname/g" "$mountpt/etc/kernel/postinst.d/dtb_cp"
    sudo sed -i "s/<DTB_FILE>/$dtbname/g" "$mountpt/etc/kernel/postinst.d/kernel_chmod"
    sudo sed -i "s/<DTB_FILE>/$dtbname/g" "$mountpt/etc/kernel/postrm.d/dtb_rm"
    sudo sed -i "s/<DTB_FILE>/$dtbname/g" "$mountpt/boot/mk_extlinux"
}

set_hostname() {
    local mountpt="$1"
    local board="$2"

    # hostname is <dist>-<board>
    # bookworm-odroid-m1
    local dist=$(cat "$mountpt/etc/os-release" | sed -rn 's/VERSION_CODENAME=(.*)/\1/p')
    local hostname="${dist}-${board}"

    echo "$hostname" | sudo tee "$mountpt/etc/hostname"
    sudo sed -i "s/\(127\.0\.1\.1\).*/\1\t$hostname/" "$mountpt/etc/hosts"
}

get_img_name() {
    local mountpt="$1"
    local board="$2"

    # <board>_<dist>-<ver>_<lrev>.img
    # odroid-m1_bookworm-12.4-1.img
    local dist=$(cat "$mountpt/etc/os-release" | sed -rn 's/VERSION_CODENAME=(.*)/\1/p')
    local ver=$(cat "$mountpt/etc/debian_version")
    [ 'trixie/sid' = "$ver" ] && ver='13'

    img_name="${board}_${dist}-${ver}.img"
}

install_uboot() {
    local media="$1"
    local board="$2"

    echo "${h1}installing u-boot: ${board}_idbloader.img & ${board}_u-boot.itb${rst}"
    sudo dd bs=4K seek=8 if="downloads/uboot/${board}_idbloader.img" of="$media" conv=notrunc
    sudo dd bs=4K seek=2048 if="downloads/uboot/${board}_u-boot.itb" of="$media" conv=notrunc,fsync
    echo "u-boot installed successfully"
}

get_deps() {
    local dist_next="$1"

    # download kernel
    if ! [ -d 'downloads/kernels' ]; then
        echo "${h1}downloading debian kernel...${rst}"
        mkdir -p "downloads/kernels"
        sh 'scripts/get_deb_kernel.sh' "$dist_next"
    fi

    # extract rk3568 dtbs from the kernel deb
    if ! [ -d "downloads/dtbs" ]; then
        echo "${h1}extracting rk3568 dtb files from $dist_next kernel package...${rst}"
        sh 'scripts/extract_dtbs.sh' "downloads/kernels/${dist_next}.deb" 'rk3568*.dtb'
        # use rk3568-odroid-m1.dtb from the bookworm debian kernel package
        rm -f 'downloads/dtbs/rk3568-odroid-m1.dtb'
    fi

    # get u-boot from local / remote
    if ! [ -d "downloads/uboot" ]; then
        echo "${h1}fetching u-boot...${rst}"
        sh 'scripts/get_uboot.sh'
    fi
}

mount_media() {
    local media="$1"
    local mountpt="$2"

    if [ -d "$mountpt" ]; then
        unmount_media "$mountpt"
    fi

    echo "${h1}mounting media: $media${rst}"
    mkdir -p "$mountpt"
    sudo mount -no loop,offset=16M "$media" "$mountpt"
    sudo mount -vt proc  '/proc'    "$mountpt/proc"
    sudo mount -vt sysfs '/sys'     "$mountpt/sys"
    sudo mount -vo bind  '/dev'     "$mountpt/dev"
    sudo mount -vo bind  '/dev/pts' "$mountpt/dev/pts"

    local part="$(/usr/sbin/losetup -nO name -j "$media")"
    echo "partition ${cya}$part${rst} successfully mounted on ${cya}$mountpt${rst}"
}

unmount_media() {
    local mountpt="$1"

    local mp mlist=''
    for mp in 'mnt' 'dev/pts' 'dev' 'sys' 'proc' ''; do
        mountpoint -q "$mountpt/$mp" && mlist="$mlist $mountpt/$mp"
    done

    [ -n "$mlist" ] && echo "${h1}unmounting mount points..."
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


rst='\033[m'
bld='\033[1m'
red='\033[31m'
grn='\033[32m'
yel='\033[33m'
blu='\033[34m'
mag='\033[35m'
cya='\033[36m'
h1="\n${blu}==>${rst} ${bld}"

cd "$(dirname "$(realpath "$0")")/.."
main "$@"

