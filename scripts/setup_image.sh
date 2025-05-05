#!/bin/sh

# Copyright (C) 2024, John Clark <inindev@gmail.com>

set -e


main() {
    local media="${1:-debian/base_mmc_2g.img}"
    local mountpt="${2:-rootfs}"
    local lrev="${3:-0}"
    local outbin="${4:-outbin}"

    local dist_next='trixie'

    # download file dependencies
    get_deps "$dist_next"
    [ '_deps_only' = "_$1" ] && exit 0

    # check for media file
    test -e "$media" || { echo "error: unable to find media: $media"; exit 1; }
    trap "on_exit $mountpt" EXIT INT QUIT ABRT TERM

    # rock-s0
    setup_image "$media" "$mountpt" 'inindev' 'rk3308-rock-s0.dtb' "$outbin"

    # nanopi-r5c
    setup_image "$media" "$mountpt" 'stable' 'rk3568-nanopi-r5c.dtb' "$outbin"

    # nanopi-r5s
    setup_image "$media" "$mountpt" 'stable' 'rk3568-nanopi-r5s.dtb' "$outbin"

    # odroid-m1
    setup_image "$media" "$mountpt" 'stable' 'rk3568-odroid-m1.dtb' "$outbin"

    # radxa-e25
    setup_image "$media" "$mountpt" 'stable' 'rk3568-radxa-e25.dtb' "$outbin"

    # omni3576
    setup_image "$media" "$mountpt" 'inindev' 'rk3576-luckfox-omni3576.dtb' "$outbin"

    # sige5
    setup_image "$media" "$mountpt" 'inindev' 'rk3576-armsom-sige5.dtb' "$outbin"

    # nanopc-t6
    setup_image "$media" "$mountpt" "$dist_next" 'rk3588-nanopc-t6.dtb rk3588-nanopc-t6-lts.dtb' "$outbin"

    # orangepi-5
    setup_image "$media" "$mountpt" "$dist_next" 'rk3588s-orangepi-5.dtb' "$outbin"

    # orangepi-5-plus
    setup_image "$media" "$mountpt" "$dist_next" 'rk3588-orangepi-5-plus.dtb' "$outbin"

    # rock-5b
    setup_image "$media" "$mountpt" "$dist_next" 'rk3588-rock-5b.dtb' "$outbin"

    # compress images
    xz -z8v "$outbin/"*
}

setup_image() {
    local media="$1"
    local mountpt="$2"
    local kern_dist="$3"
    local dtb_files="$4"
    local outbin="${5:-outbin}"

    local dtb_file=$(echo "$dtb_files" | cut -d' ' -f1)
    local board_full="${dtb_file%.*}"
    local board="${board_full#*-}"

    echo "${h1}configuring debian image for board ${yel}$board${rst}${bld}...${rst}"

    if [ -f "$outbin/${board}"*".img" ]; then
        echo "image already exists, skipping..."
        return
    fi

    # copy image locally
    local tmp_img_name="$outbin/${board}.img.tmp"
    install -Dvm 644 "$media" "$tmp_img_name"
    mount_media "$tmp_img_name" "$mountpt"

    # set dtb and image name
    set_dtbs "$mountpt" "$dtb_files"
    set_hostname "$mountpt" "$board"

    # install the kernel
    # configure kernel distribution if not inindev or stable
    [ '_inindev' != "_$kern_dist" ] && [ '_stable' != "_$kern_dist" ] && setup_dist_kernel "$mountpt" "$kern_dist"

    echo "${h1}updating packages...${rst}"
    sudo chroot "$mountpt" apt update
    sudo chroot "$mountpt" apt -y upgrade

    echo "${h1}installing kernel...${rst}"
    if [ '_inindev' = "_$kern_dist" ]; then
        sudo cp "downloads/kernels/inindev.deb" "$mountpt/tmp"
        sudo chroot "$mountpt" dpkg -i '/tmp/inindev.deb'
        sudo rm -f "$mountpt/tmp/inindev.deb"
        sudo chroot "$mountpt" apt -y install apparmor
    else
        sudo chroot "$mountpt" apt -y install linux-image-arm64
    fi
    sudo chroot "$mountpt" apt clean

    # the final image name is based on distribution name
    local img_name=''
    get_img_name "$mountpt" "$board"

    # post setup: inject network config if file exists
    if [ -f "configs/network_${board}.cfg" ]; then
        sudo sed -i "/setup for expand fs/e cat configs/network_${board}.cfg" "$mountpt/etc/rc.local"
    fi

    # cleanup ssh keys
    echo "${h1}purging ssh keys...${rst}"
    sudo rm -fv "$mountpt/etc/ssh/ssh_host_"*

    # reduce entropy in free space to enhance compression
    echo "${h1}reducing entropy...${rst}"
    cat /dev/zero > "$mountpt/tmp/zero.bin" 2> /dev/null || true
    sync
    rm -fv "$mountpt/tmp/zero.bin"

    unmount_media "$mountpt"

    # install u-boot
    install_uboot "$tmp_img_name" "$board_full"

    # rename to final name
    local out_img_name="$outbin/$img_name"
    mv "$tmp_img_name" "$out_img_name"

    echo "\n${cya}image $out_img_name is ready${rst}"
    echo "(use \"sudo mount -no loop,offset=16M $out_img_name /mnt\" to mount)\n"
}

setup_dist_kernel() {
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

set_dtbs() {
    local mountpt="$1"
    local dtb_files="$2"

    # some kernels require an external dtb
    for dtb_file in ${dtb_files}; do
        [ -e "downloads/dtbs/$dtb_file" ] && sudo install -vm 644 "downloads/dtbs/$dtb_file" "$mountpt/boot" || true
    done

    # replace <DTB_FILES> in kernel scripts
    echo "${h1}configuring device tree: ${yel}$dtb_files${rst}"
    local dtb_files_escaped=$(echo "$dtb_files" | sed 's/ /\\ /g')
    sudo sed -i "s/<DTB_FILES>/$dtb_files_escaped/g" "$mountpt/etc/kernel/postinst.d/dtb_cp"
    sudo sed -i "s/<DTB_FILES>/$dtb_files_escaped/g" "$mountpt/etc/kernel/postinst.d/kernel_chmod"
    sudo sed -i "s/<DTB_FILES>/$dtb_files_escaped/g" "$mountpt/etc/kernel/postrm.d/dtb_rm"

    local token_count=$(echo "$dtb_files" | wc -w)
    if [ "$token_count" -lt 2 ]; then
        sudo sed -i "s/<DTB_FILE>/$dtb_files/g" "$mountpt/boot/mk_extlinux"
        return
    fi

    # multiple dtb files: install a selector function
    case "$dtb_files" in
        *nanopc-t6*)
            echo "setting up nanopc-t6 dtb selector"
            dtb_function=$(get_dtb_nanopct6 | sed ':a;N;$!ba;s/\n/\\n/g')
            sudo sed -i "/^get_dtb() {/,/^}/c\\$dtb_function" "$mountpt/boot/mk_extlinux"
            ;;
        *)
            echo "unhandled dtb selector: $dtb_files"
            exit 1
            ;;
    esac
}

get_dtb_nanopct6() {
    cat <<-EOF
	# see: https://github.com/friendlyarm/uboot-rockchip/blob/nanopi6-v2017.09/board/rockchip/nanopi6/hwrev.c
	#      https://github.com/u-boot/u-boot/commit/7cec3e701940064b2cfc0cf8b80ff24c391c55ec
	get_dtb() {
	    local adc12=\$(cat /sys/bus/iio/devices/iio:device0/in_voltage5_raw 2>/dev/null || echo 464)
	    local adc10=\$((adc12 >> 2))
	    # lts v7: 478-545
	    [ \$adc10 -ge 478 ] && [ \$adc10 -le 545 ] && echo 'rk3588-nanopc-t6-lts.dtb' || echo 'rk3588-nanopc-t6.dtb'
	}
	EOF
}

set_hostname() {
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
    [ 'trixie/sid' = "$ver" ] && ver='13'

    img_name="${board}_${dist}-${ver}.img"
}

get_deps() {
    local dist_next="$1"

    # download u-boot
    echo "${h1}downloading u-boot bins...${rst}"
    mkdir -p 'downloads/uboot'
    # 3308
    get_uboot_bin 'rk3308-rock-s0'
    # 3568
    get_uboot_bin 'rk3568-nanopi-r5c'
    get_uboot_bin 'rk3568-nanopi-r5s'
    get_uboot_bin 'rk3568-odroid-m1'
    get_uboot_bin 'rk3568-radxa-e25'
    # 3576
    get_uboot_bin 'rk3576-luckfox-omni3576'
    get_uboot_bin 'rk3576-armsom-sige5'
    # 3588
    get_uboot_bin 'rk3588-nanopc-t6'
    get_uboot_bin 'rk3588s-orangepi-5'
    get_uboot_bin 'rk3588-orangepi-5-plus'
    get_uboot_bin 'rk3588-rock-5b'


    # download kernels
    #echo "${h1}downloading debian kernel...${rst}"
    #sh 'scripts/get_deb_kernel.sh' "$dist_next"

    echo "${h1}downloading inindev kernel...${rst}"
    sh 'scripts/get_inindev_kernel.sh'

    # extract rk3568 dtbs from the kernel deb
    if ! [ -d "downloads/dtbs" ]; then
        echo "${h1}extracting rk3568 dtb files from inindev kernel package...${rst}"
        sh 'scripts/extract_dtbs.sh' "downloads/kernels/inindev.deb" 'rk3568*.dtb'
        # use rk3568-odroid-m1.dtb from the bookworm debian kernel package
        rm -f 'downloads/dtbs/rk3568-odroid-m1.dtb'
    fi

    # get u-boot from local / remote
    if ! [ -d "downloads/uboot" ]; then
        echo "${h1}fetching u-boot...${rst}"
        sh 'scripts/get_uboot.sh'
    fi
}

get_uboot_bin() {
    local board_full="$1"
    [ -f "downloads/uboot/${board_full}.zip" ] || wget -P 'downloads/uboot' "https://github.com/inindev/uboot-rockchip/releases/latest/download/${board_full}.zip"
}

install_uboot() {
    local media="$1"
    local board_full="$2"

    echo "${h1}installing u-boot: ${board_full}.zip${rst}"
    local sha=$(unzip -p "downloads/uboot/${board_full}.zip" "${board_full}/sha256sums.txt" | grep 'u-boot-rockchip.bin' | cut -c1-64)
    local tmpdir="$(mktemp -d)"
    unzip "downloads/uboot/${board_full}.zip" "${board_full}/u-boot-rockchip.bin" -d "$tmpdir"
    test "$sha" = $(sha256sum "$tmpdir/${board_full}/u-boot-rockchip.bin" | cut -c1-64)
    sudo dd bs=4K seek=8 if="$tmpdir/${board_full}/u-boot-rockchip.bin" of="$media" conv=notrunc,fsync
    rm -rf "$tmpdir"
    echo "u-boot installed successfully"
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
            echo "${red}error: failed to bind mount /$mp to $mountpt/$fs${rst}" >&2
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

