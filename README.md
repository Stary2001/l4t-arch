# L4T-Arch

Arch Linux arm64 repository for L4T.

## Scripts options

```
Usage: create-rootfs.sh [options]
Options:
 -f, --force             Download setup files anyway
 --hekate                Build for Hekate
 -n, --no-docker         Build without Docker
 -s, --staging           Install built local packages
 --distro <name>         Select a distro to install
 -h, --help              Show this help text
```

## Building

On a Ubuntu host :
- `apt-get install -y git tar wget p7zip unzip parted xz-utils dosfstools lvm2 qemu qemu-user-static proot`
- `git clone https://github.com/Azkali/jet-factory`
- As root user run `./jet-factory/create-rootfs.sh`
