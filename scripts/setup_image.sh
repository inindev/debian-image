#!/bin/sh

# Copyright (C) 2024, John Clark <inindev@gmail.com>

set -e


main() {
    local media="${1:-debian/mmc_2g.img}"
    local mountpt="${2:-rootfs}"

    test -e "$media" || { echo "error: unable to find media: $media"; exit 1; }
    trap "on_exit $mountpt" EXIT INT QUIT ABRT TERM

    local kern_deb='../downloads/linux-image-6.1.0-17-arm64_6.1.69-1_arm64.deb'

    setup_odroid_m1  "$media" "$mountpt"
}

setup_odroid_m1() {
    local media="$1"
    local mountpt="$2"

    # odroid-m1
    setup_image "$media" "$mountpt" "odroid-m1" 'rk3568-odroid-m1.dtb' 'linux-image-6.1.0-17-arm64_6.1.69-1_arm64.deb' '0' 'outbin'
}

setup_image() {
    local media="$1"
    local mountpt="$2"
    local board="$3"
    local dtb="$4"
    local kfile="$5"
    local rev="${6:-0}"
    local outbin="${7:-outbin}"

    # copy image locally
    mkdir -p "$outbin"
    local tmp_img_name="$outbin/${board}.img.tmp"
    cp "$media" "$tmp_img_name"
    mount_media "$tmp_img_name" "$mountpt"

    # set dtb and image name
    set_dtb "$mountpt" "$dtb"
    set_hostname "$mountpt" "$board"

    # install the kernel
    install_kernel "$mountpt" "$kfile"

    # the final image name is based on distribution name
    local img_name=''
    get_img_name "$mountpt" "$board" "$rev"

    unmount_media "$mountpt"

    local out_img_name="$outbin/$img_name"
    mv "$tmp_img_name" "$out_img_name"
    echo "\n${cya}image $out_img_name is ready${rst}"
    echo "(use \"sudo mount -no loop,offset=16M $out_img_name /mnt\" to mount)\n"
}

install_kernel() {
    local mountpt="$1"
    local kfile="$2"

    local kfpath="$(realpath "$kfile")"
    local kfname="$(basename "$kfpath")"
    local kdir="$(dirname "$kfpath")"

    echo "${h1}installing kernel $kfname${rst}"
    sudo mount -vo bind "$kdir" "$mountpt/mnt"
    sudo chroot "$mountpt" "/usr/bin/dpkg" -i "/mnt/$kfname"
    sudo umount "$mountpt/mnt"
    echo "kernel installed successfully"
}

set_dtb() {
    local mountpt="$1"
    local dtbname="$2"

    sudo sed -i "s/<DTB_FILE>/$dtbname/g" "$mountpt/etc/kernel/postinst.d/dtb_cp"
    sudo sed -i "s/<DTB_FILE>/$dtbname/g" "$mountpt/etc/kernel/postinst.d/kernel_chmod"
    sudo sed -i "s/<DTB_FILE>/$dtbname/g" "$mountpt/etc/kernel/postrm.d/dtb_rm"
    sudo sed -i "s/<DTB_FILE>/$dtbname/g" "$mountpt/boot/mk_extlinux"

    # some kernels require an external dtb
    [ -e "download/$dtbname" ] && install -vm 644 "download/$dtbname" "$mountpt/boot"
}

set_hostname() {
    local mountpt="$1"
    local board="$2"

    # hostname is <dist>-<board>
    # bookworm-odroid-m1
    local dist=$(cat "$mountpt/etc/os-release" | sed -rn 's/VERSION_CODENAME=(.*)/\1/p')
    local hostname="${dist}-${board}"

    echo "$hostname" | sudo tee "$mountpt/etc/hostname"
#    sudo sed -i "/127.0.1.1.*/s/.*/127.0.1.1\t$hostname/" "$mountpt/etc/hosts"
    sudo sed -i "s/\(127\.0\.1\.1\).*/\1\t$hostname/" "$mountpt/etc/hosts"
}

get_img_name() {
    local mountpt="$1"
    local board="$2"
    local rev="${3:-0}"

    # <board>_<dist>-<ver>_<rev>.img
    # odroid-m1_bookworm-12.4-1.img
    local dist=$(cat "$mountpt/etc/os-release" | sed -rn 's/VERSION_CODENAME=(.*)/\1/p')
    local ver=$(cat "$mountpt/etc/debian_version")

    img_name="${board}_${dist}-${ver}"
    if [ $rev -gt 0 ]; then
        img_name="${img_name}-${rev}"
    fi

    img_name="${img_name}.img"
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

cd "$(dirname "$(realpath "$0")")"
main "$@"

