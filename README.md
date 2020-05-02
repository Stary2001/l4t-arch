# L4T-Arch

Arch Linux arm64 repository for L4T.

## Scripts options

```
Usage: create-rootfs.sh [options]
Options:
 -d, --docker   Build using Docker
 -s, --staging	Install built local packages
 -h, --help		Show this help text
```

## Dependencies ( when building without docker option )

On a Arch Linux host install `qemu-user-static` from `AUR` and :

```sh
pacman -S qemu qemu-arch-extra arch-install-scripts parted dosfstools wget libarchive p7zip
```

## Building

- `git clone https://github.com/Stary2001/l4t-arch/`
- As root user run `./l4t-arch/builder/create-rootfs.sh`

## Building packages locally

**NOTE: All required packages for Arch to work are avalaible in the repository used in during the rootfs build.** \
**Therefore you should only build packages if you know what you're doing**

To build any packages go to the his directory ( e.g.: `cd pkgbuilds/gcc7`) and do `makepkg -s` as a regular user on a Arch host.

*Refer to archlinux documentation for more infos*
