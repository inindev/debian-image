# Debian Image Builder for ARM Boards

This repository provides scripts to build **Debian** images for various Rockchip-based ARM single-board computers (SBCs). It creates bootable images based on Debian Trixie, with support for both traditional 512-byte and 4096-byte sector sizes.

The builder consists of two stages:
- **First stage**: Creates a base Debian rootfs image (`base_mmc_2g.img` or `base_mmc_2g_4k.img`).
- **Second stage**: Customizes the base image for specific boards, installs board-specific u-boot, DTBs, kernels, and configurations.

<br/>

## Features
- Builds minimal, clean Debian images using `debootstrap`.
- Supports **512-byte** and **4096-byte** logical sector sizes (via `SECTOR_SIZE=4096` environment variable).
- Board-specific customization: hostname, network config, device tree, kernel selection.
- Installs u-boot binaries from [inindev/uboot-rockchip](https://github.com/inindev/uboot-rockchip).
- Optional inindev custom kernel for newer boards (e.g., RK3576).
- Output images named like `<board>_<codename>-<version>[_4k].img` (e.g., `rock-5b_trixie-13_4k.img`).

<br/>

## Supported Boards
- rk3308-rock-s0
- rk3568-nanopi-r5c
- rk3568-nanopi-r5s
- rk3568-odroid-m1
- rk3568-radxa-e25
- rk3576-armsom-sige5
- rk3576-luckfox-omni3576
- rk3576-nanopi-m5
- rk3588-nanopc-t6
- rk3588s-orangepi-5
- rk3588-orangepi-5-plus
- rk3588-rock-5b

<br/>

## Requirements
- Linux host (script requires root privileges for loop devices and mounts).
- ARM64 architecture required for building.
- Installed tools: `debootstrap`, `wget`, `xz-utils`, `losetup`, `sfdisk`, `mkfs.ext4`, `dd`, `unzip`, `curl`, etc.

<br/>

## Usage
- Note: 4k sector images are for UFS media

### Build Base Image (First Stage)
```bash
cd debian/
# standard 512-byte sector image (default)
sh make_debian_img.sh

# 4096-byte (4K-native) sector image
SECTOR_SIZE=4096 sh make_debian_img.sh
```

Outputs:
- `base_mmc_2g.img` (512-byte)
- `base_mmc_2g_4k.img` (4096-byte)

### Build Board-Specific Images (Second Stage)
```bash
# from repository root
sh create_images.sh [path/to/base_image.img]

# example with 4K base image
sh create_images.sh debian/base_mmc_2g_4k.img
```

Outputs images in `outbin/` directory, compressed with xz.

### Clean
```bash
sh debian/make_debian_img.sh clean
```

<br/>

## Customization
- Board-specific network configs: `configs/network_<board>.cfg`
- Custom DTB overlays or functions: `configs/dtb_<board>.cfg`
- Additional overlays/firmware can be added in relevant directories.

<br/>

## Notes
- Images are designed for eMMC/SD card installation with 4k sector variants for UFS storage.
- flashing (as root): `xzcat image_name.xz > /dev/sdX`

<br/>

## License
GNU General Public License v3.0 (GPL-3.0) – see [LICENSE](LICENSE) file.
