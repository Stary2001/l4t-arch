#!/bin/bash

staging=no
options=$(getopt -o hs --long staging --long help -- "$@")

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo " -s, --staging	Install built local packages"
    echo " -h, --help		Show this help text"
}

[ $? -eq 0 ] || {
	usage
	exit 1
}

eval set -- "$options"
while true; do
    case "$1" in
    -s)
        staging=yes
        ;;
    --staging)
        staging=yes
        ;;
    -h|--help)
	usage
	exit 0
	;;
    --)
        shift
        break
        ;;
    esac
    shift
done

root_dir="$(dirname "$(dirname "$(readlink -fm "$0")")")"

cleanup(){
	umount -R ${root_dir}/tmp/mnt/*
	umount -R ${root_dir}/tmp/*
	rm -rf ${root_dir}/tmp/
}

prepare() {
	mkdir -p ${root_dir}/tarballs/
	mkdir -p ${root_dir}/tmp/arch-bootfs/
	mkdir -p ${root_dir}/tmp/arch-rootfs/pkgs
	mkdir -p ${root_dir}/tmp/mnt/rootfs/

	if [[ ! -e ${root_dir}/tarballs/ArchLinuxARM-aarch64-latest.tar.gz ]]; then
		wget -O ${root_dir}/tarballs/ArchLinuxARM-aarch64-latest.tar.gz http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
	fi

	if [[ ! -e ${root_dir}/tmp/arch-rootfs/reboot_payload.bin ]]; then
		wget https://github.com/CTCaer/hekate/releases/download/v5.1.3/hekate_ctcaer_5.1.3_Nyx_0.8.6.zip -P ${root_dir}/tmp/
		unzip ${root_dir}/tmp/hekate_ctcaer_5.1.3_Nyx_0.8.6.zip hekate_ctcaer_5.1.3.bin
		mv hekate_ctcaer_5.1.3.bin ${root_dir}/tmp/arch-rootfs/reboot_payload.bin
		rm ${root_dir}/tmp/hekate_ctcaer_5.1.3_Nyx_0.8.6.zip
	fi
}

setup_base(){
	cp ${root_dir}/builder/build-stage2.sh ${root_dir}/builder/base-pkgs ${root_dir}/tmp/arch-rootfs/

	if [[ $staging == "yes" ]]; then
		cp -r ${root_dir}/pkgbuilds/*/*.pkg.* ${root_dir}/tmp/arch-rootfs/pkgs/
	fi
	
	bsdtar xpf ${root_dir}/tarballs/ArchLinuxARM-aarch64-latest.tar.gz -C ${root_dir}/tmp/arch-rootfs/

	# Workaround for flakiness of `pt` mirror.
	sed -i 's/mirror.archlinuxarm.org/de.mirror.archlinuxarm.org/g' ${root_dir}/tmp/arch-rootfs/etc/pacman.d/mirrorlist

	echo "[switch]
SigLevel = Optional
Server = https://9net.org/l4t-arch/" >> ${root_dir}/tmp/arch-rootfs/etc/pacman.conf

	echo -e "/dev/mmcblk0p1	/boot	vfat	rw,relatime	0	2\n" >> ${root_dir}/tmp/arch-rootfs/etc/fstab

	cp /usr/bin/qemu-aarch64-static ${root_dir}/tmp/arch-rootfs/usr/bin/
	cp /etc/resolv.conf ${root_dir}/tmp/arch-rootfs/etc/
	
	mount --bind ${root_dir}/tmp/arch-rootfs ${root_dir}/tmp/arch-rootfs
	mount --bind ${root_dir}/tmp/arch-bootfs ${root_dir}/tmp/arch-rootfs/boot/
	arch-chroot ${root_dir}/tmp/arch-rootfs/ ./build-stage2.sh
	umount -R ${root_dir}/tmp/arch-rootfs/boot/
	umount -R ${root_dir}/tmp/arch-rootfs/

	rm ${root_dir}/tmp/arch-rootfs/etc/pacman.d/gnupg/S.gpg-agent*
	rm -rf ${root_dir}/tmp/arch-rootfs/{pkgbuilds,build-stage2.sh,pkgs}
	rm ${root_dir}/tmp/arch-rootfs/usr/bin/qemu-aarch64-static
}

buildimg(){
	size=$(du -hs ${root_dir}/tmp/arch-rootfs/ | head -n1 | awk '{print int($1+2);}')$(du -hs ${root_dir}/tmp/arch-rootfs/ | head -n1 | awk '{print $1;}' | grep -o '[[:alpha:]]')

	rm ${root_dir}/l4t-arch.img
	dd if=/dev/zero of=${root_dir}/l4t-arch.img bs=1 count=0 seek=$size
	
	loop=`losetup --find`
	losetup $loop ${root_dir}/l4t-arch.img

	mkfs.ext4 $loop
	mount $loop ${root_dir}/tmp/mnt/rootfs/

	cp -pdr ${root_dir}/tmp/arch-rootfs/* ${root_dir}/tmp/mnt/rootfs/
	umount $loop
	losetup -d $loop

	pushd ${root_dir}/tmp/arch-bootfs
	zip -r ${root_dir}/l4t-boot.zip *
	popd
}

if [[ `whoami` != root ]]; then
	echo hey! run this as root.
	exit
fi

cleanup
prepare
setup_base
buildimg
cleanup

echo "Done!\n"
