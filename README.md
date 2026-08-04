# Debian Image Builder for ARM Boards

This repository provides scripts to build **Debian** images for various Rockchip-based ARM single-board computers (SBCs). It creates bootable images based on Debian Trixie, with support for both traditional 512-byte and 4096-byte sector sizes.

The goal is to run stock Debian: the Debian kernel, no vendor BSP. Where mainline support is not yet sufficient for a board to be useful, a custom kernel is used until it is.

The builder consists of two stages:
- **First stage**: Creates a base Debian rootfs image (`base_mmc_2g.img` or `base_mmc_2g_4k.img`).
- **Second stage**: Customizes the base image for specific boards, installs board-specific u-boot, DTBs, kernels, and configurations.

<br/>

## Features
- Builds minimal, clean Debian images using `debootstrap`.
- Supports **512-byte** and **4096-byte** logical sector sizes (via `SECTOR_SIZE=4096` environment variable).
- Board-specific customization: hostname, network config, device tree, kernel selection.
- Installs u-boot binaries from [inindev/uboot-rockchip](https://github.com/inindev/uboot-rockchip).
- Debian's `linux-image-arm64` kernel on every board except rk3576, which needs a custom kernel until mainline support lands (see [Kernels](#kernels)).
- Output images named like `<board>_<codename>-<version>[_4k].img` (e.g., `rk3588-rock-5b_trixie-13.2_4k.img`).

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

## Kernels
The intent is to run the stock Debian kernel wherever mainline support allows it.

- **all boards except rk3576** — Debian's `linux-image-arm64`. The rk3588 was in the same position as the rk3576 for some time; mainline support is now sufficient to boot headless, so these run Debian kernels.
- **rk3576** — not yet mainlined enough to run the Debian kernel, so these images are built with a custom kernel from [inindev/linux-rockchip](https://github.com/inindev/linux-rockchip). They will move to the Debian kernel once mainline support lands.

As of this writing, the Debian kernel does not quite support graphics mode on these boards. For a desktop, compile a kernel from a more recent upstream release, or use one from [Collabora](https://www.collabora.com/) or [inindev/linux-rockchip](https://github.com/inindev/linux-rockchip).

<br/>

## Requirements
- Linux host. Run the scripts as a normal user with sudo access — they invoke `sudo` themselves for loop devices and mounts, and are not meant to be run as root.
- ARM64 architecture required for building.
- Installed tools: `debootstrap`, `wget`, `xz-utils`, `losetup`, `sfdisk`, `mkfs.ext4`, `dd`, `unzip`, `curl`, etc.

<br/>

## Usage
- Note: rk3576 boards support UFS media, which requires a 4096-byte logical sector size — that is what the 4k image is for.

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
