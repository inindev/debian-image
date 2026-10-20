# Debian Image Builder for ARM Boards

This repository provides scripts to build **Debian** images for various Rockchip-based ARM single-board computers (SBCs). It creates bootable images based on Debian Trixie, with support for both traditional 512-byte and 4096-byte sector sizes.

The goal is to run stock Debian: the Debian kernel, no vendor BSP. Where mainline support is not yet sufficient for a board to be useful, a custom kernel is used until it is.

The builder consists of two stages:
- **First stage**: Creates a base Debian rootfs image (`base_mmc_2g.img` or `base_mmc_2g_4k.img`).
- **Second stage**: Builds one board-agnostic rootfs per kernel flavor from the base image, then makes each board's image by copying that rootfs and writing the board's u-boot to it.

<br/>

## Features
- Builds minimal, clean Debian images using `debootstrap`.
- Supports **512-byte** and **4096-byte** logical sector sizes (via `SECTOR_SIZE=4096` environment variable).
- Board-agnostic rootfs: every image carries all device trees, and u-boot picks the right one at boot.
- First-boot specialization: on first boot the image reads the board name from the device tree and sets the hostname and board-specific network config (see [How first boot works](#how-first-boot-works)).
- Installs u-boot binaries from [inindev/uboot-rockchip](https://github.com/inindev/uboot-rockchip).
- Debian's `linux-image-arm64` kernel on every board except rk3576, which needs a custom kernel until mainline support lands (see [Kernels](#kernels)).

<br/>

## Supported Boards
- rk3308-rock-s0
- rk3566-orangepi-cm4
- rk3568-nanopi-r5c
- rk3568-nanopi-r5s
- rk3568-odroid-m1
- rk3568-radxa-e25
- rk3576-armsom-sige5
- rk3576-luckfox-omni3576
- rk3576-nanopi-m5
- rk3588-nanopc-t6 (also boots the NanoPC-T6 LTS)
- rk3588s-orangepi-5
- rk3588-orangepi-5-plus
- rk3588-rock-5b

<br/>

## Kernels
The intent is to run the stock Debian kernel wherever mainline support allows it.

- **all boards except rk3576** — Debian's `linux-image-arm64`. The rk3588 was in the same position as the rk3576 for some time; mainline support is now sufficient to boot headless, so these run Debian kernels.
- **rk3576** — not yet mainlined enough to run the Debian kernel, so these images are built with a custom kernel from [inindev/linux-rockchip](https://github.com/inindev/linux-rockchip). They will move to the Debian kernel once mainline support lands.

Device trees the Debian kernel does not yet ship (currently `rk3566-orangepi-cm4*`) are taken from the inindev kernel package and installed to `/boot/dtbs/local`. A kernel install hook merges them into each kernel's dtb directory, so they work with either kernel.

As of this writing, the Debian kernel does not quite support graphics mode on these boards. For a desktop, compile a kernel from a more recent upstream release, or use one from [Collabora](https://www.collabora.com/) or [inindev/linux-rockchip](https://github.com/inindev/linux-rockchip).

<br/>

## Requirements
- Linux host. Run the scripts as a normal user with sudo access — they invoke `sudo` themselves for loop devices and mounts, and are not meant to be run as root.
- ARM64 architecture required for building.
- Installed tools: `debootstrap`, `wget`, `xz-utils`, `losetup`, `sfdisk`, `mkfs.ext4`, `dd`, `unzip`, `curl`, `ar` (binutils), etc.

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
sh create_images.sh [--no-compress] [board...]

# all boards from the default base image (debian/base_mmc_2g.img)
sh create_images.sh

# selected boards, globs allowed
sh create_images.sh rk3588-rock-5b 'rk3568*'

# from the 4K base image
DEB_MEDIA=debian/base_mmc_2g_4k.img sh create_images.sh 'rk3576*'
```

- `board...` — one or more board names or globs (default: all boards)
- `--no-compress` — leave images uncompressed
- `DEB_MEDIA=<img>` — use a different base image

Images are written to `outbin/` and compressed with xz. Existing images are reused or skipped, so a rerun only builds what is missing.

Output names are `<board>_<codename>-<version>[_ufs].img`, e.g. `rk3588-rock-5b_trixie-13.2.img`. Images built from the 4K base image get the `_ufs` suffix.

The board-agnostic rootfs is kept too:
- `rockchip_<codename>-<version>.img` — Debian kernel. From the 512-byte base it is shipped as an image of its own: it has no u-boot, and boots any supported board once that board's u-boot is written to it.
- `rockchip-mainline_<codename>-<version>[_ufs].img` — inindev kernel, used for rk3576 boards.

### Clean
```bash
sh debian/make_debian_img.sh clean
```

<br/>

## How first boot works
On first boot, `/etc/rc.local` regenerates the ssh host keys, expands the root partition and gives it a new UUID. It then reads the first (most specific) entry in `/proc/device-tree/compatible`, e.g. `friendlyarm,nanopc-t6-lts`, drops the vendor prefix, and uses the rest (`nanopc-t6-lts`) as the board name:

- **hostname** — `<codename>-<board>`, with any revision suffix like `-v1.4` dropped (e.g. `trixie-nanopc-t6-lts`).
- **network** — if `/etc/network-setup/<board>` exists, it is run. Otherwise the default network setup is kept.

To see which device tree a running board booted with, run `/boot/dtbs/dtb_info.sh`.

<br/>

## Customization
- **Board network configs**: `configs/network/<board>`, where `<board>` is the compatible name without the vendor prefix (see [How first boot works](#how-first-boot-works)). Every file in this directory is installed into every image at `/etc/network-setup/`, and is a shell fragment run by `rc.local` on first boot. The name must match exactly. When a board variant has its own compatible name but the same network hardware, add a symlink, e.g. `nanopc-t6-lts -> nanopc-t6`.
- **Device tree overlays**: `.dtbo` files placed in `debian/cache.<codename>/overlays/` are installed to `/boot/overlay/lib/`. To enable one on a board, copy it to `/boot/overlay/` and run `/boot/mk_extlinux` as root.
- **Kernel command line and boot menu**: edit the options at the top of `/boot/mk_extlinux`, then run it as root.

<br/>

## Notes
- Images are designed for eMMC/SD card installation with 4k sector variants for UFS storage.
- flashing (as root): `xzcat image_name.xz > /dev/sdX`

<br/>

## License
GNU General Public License v3.0 (GPL-3.0) – see [LICENSE](LICENSE) file.
