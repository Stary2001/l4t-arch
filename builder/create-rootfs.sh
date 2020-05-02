#!/usr/bin/bash

root_dir="$(dirname "$(dirname "$(readlink -fm "$0")")")"
build_dir=/${root_dir}/l4t/
url=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
archive=${url##*/}
hekate_version=5.2.0
nyx_version=0.9.0

docker=no
staging=no
options=$(getopt -o dhs --long docker --long staging --long help -- "$@")

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
	echo " -d, --docker		Build using docker"
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
	-d)
        docker=yes
        ;;
    --docker)
        docker=yes
        ;;
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
	case "$2" in
	-d)
        docker=yes
        ;;
    --docker)
        docker=yes
        ;;
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

buildWithDocker() {
	docker image build -t archl4tbuild:1.0 ${root_dir}
	if [[ ${staging} == "yes" ]]; then
		docker run --privileged --cap-add=SYS_ADMIN --rm -it -v ${root_dir}:/root/l4t-arch archl4tbuild:1.0 /root/l4t-arch/builder/create-rootfs.sh -s
		exit
	fi
	docker run --privileged --cap-add=SYS_ADMIN --rm -it -v ${root_dir}:/root/l4t-arch archl4tbuild:1.0 /root/l4t-arch/builder/create-rootfs.sh
}

cleanup() {
	umount -R ${build_dir}/{tmp,{r,b}ootfs}/*
	rm -rf ${build_dir}/
}

prepareFiles() {
	mkdir -p ${build_dir}/{{r,b}ootfs,tmp,switchroot/install/}

	if [[ ! -e ${root_dir}/${archive} ]]; then
		wget ${url} -P ${root_dir}
	fi

	bsdtar xpf ${build_dir}/${archive} -C ${build_dir}/rootfs/

	if [[ ! -e ${root_dir}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip ]]; then
		wget https://github.com/CTCaer/hekate/releases/download/v${hekate_version}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip -P ${root_dir}
	fi

	unzip ${build_dir}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip hekate_ctcaer_${hekate_version}.bin
	mv ${root_dir}/hekate_ctcaer_${hekate_version}.bin ${build_dir}/rootfs/lib/firmware/reboot_payload.bin
}

build() {
	echo -e "/dev/mmcblk0p1	/boot	vfat	rw,relatime	0	2\n" >> ${build_dir}/rootfs/etc/fstab
	sed -i 's/^HOOKS=(\(.*\))$/HOOKS=(\1 resize-rootfs)/' ${build_dir}/rootfs/etc/mkinitcpio.conf

	cp /usr/bin/qemu-aarch64-static ${build_dir}/rootfs/usr/bin/
	cp /etc/resolv.conf ${build_dir}/rootfs/etc/

	if [[ ${staging} == "yes" ]]; then
		cp -r ${root_dir}/pkgbuilds/*/*.pkg.* ${build_dir}/rootfs/pkgs/
	fi

	mount --bind ${build_dir}/rootfs ${build_dir}/rootfs
	mount --bind ${build_dir}/bootfs ${build_dir}/rootfs/boot/
	
	# Install Packages
	arch-chroot ${build_dir}/rootfs/ ./build-stage2.sh
	
	rm -rf ${build_dir}/rootfs/{base-pkgs,build-stage2.sh/,pkgs/,usr/bin/qemu-aarch64-static,etc/pacman.d/gnupg/S.gpg-agent*}

	size=$(du -hs -BM ${build_dir}/rootfs/ | head -n1 | awk '{print int($1/4)*4 + 4 + 512;}')M
	echo "Estimated rootfs size: $size"

	dd if=/dev/zero of=${build_dir}/switchroot/install/l4t.img bs=1 count=0 seek=$size
	
	loop=`losetup --find`
	losetup ${loop} ${build_dir}/switchroot/install/l4t.img

	mkfs.ext4 ${loop}
	mount ${loop} ${build_dir}/tmp

	cp -prd ${build_dir}/rootfs/* ${build_dir}/tmp/

	umount ${loop}
	losetup -d ${loop}

	cd ${build_dir}/switchroot/install/
	split -b4290772992 --numeric-suffixes=0 l4t.img l4t.
	rm ${build_dir}/switchroot/install/l4t.img
	
	umount -R ${build_dir}/rootfs/{,boot/}
	mv ${build_dir}/bootfs/* ${build_dir}/
	dd if=${build_dir}/ of=${root_dir}/l4t-arch.img bs=4M
}

if [[ `whoami` != root ]]; then
	echo hey! run this as root.
	exit
fi

echo "\nCleaning up old build\n"
cleanup
if [[ ${docker} == "yes" ]]; then
	echo "Build using Docker"
	buildWithDocker
	exit
fi
echo "\nPreparing required files\n"
prepareFiles
echo "\nBuilding Image\n"
build
echo "\nCleaning up after build\n"
cleanup
echo "Done!\n"