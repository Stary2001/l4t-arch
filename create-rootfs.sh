#!/bin/env bash
if [[ ${distro_name} == "arch" ]]; then
	url=http://fl.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
else
	url=https://download.fedoraproject.org/pub/fedora/linux/releases/31/Server/aarch64/images/Fedora-Server-31-1.9.aarch64.raw.xz
fi

# Static
distro_name=arch
img=SWR-${distro_name}
cwd="$(dirname "$(readlink -fm "$0")")"
build_dir=${cwd}/${img}
archive="${cwd}/$(echo ${url} | rev | cut -d/ -f1 | rev )"
format="ext4"
loop=`losetup --find`
size=$(du -hs -BM ${cwd}/${img} | head -n1 | awk '{print int($1/4)*4 + 4 + 512;}')M
pkg_types=*.{pkg.*,rpm,deb}
# Hekate files
hekate_version=5.2.0
nyx_version=0.9.0
hekate_url=https://github.com/CTCaer/hekate/releases/download/v${hekate_version}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip
hekate_zip="${cwd}/$(echo ${hekate_url} | rev | cut -d/ -f1 | rev )"
hekate_bin=hekate_ctcaer_${hekate_version}.bin
# Options
docker=no
hekate=no
staging=no
options=$(getopt -o dhs --long docker,staging,help:,hekate -- "$@")

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
	echo " -d, --docker		Build with Docker"
	echo " --hekate			Build for Hekate"
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
	-d | --docker) docker=yes; shift ;;
	--hekate) hekate=yes; shift ;;
    -s | --staging) staging=yes; shift ;;
    -h | --help)
	usage
	exit 0
	;;
    -- ) shift; break ;;
    esac
done

PrepareChroot() {
	echo -e "\nCreating build folders\n"
	unzip ${cwd}/${hekate_zip} -d ${build_dir}
	mkdir -p ${build_dir}/{switchroot/install/pkgs,boot/}

	[[ ${staging} == "yes" ]] &&
	cp -r ${cwd}/pkgbuilds/*/${pkg_types} ${build_dir}/pkgs/
	cp ${cwd}/{build-stage2.sh,base-pkgs} ${build_dir}
	cp /usr/bin/qemu-aarch64-static ${build_dir}/usr/bin/
	mv ${hekate_bin} ${build_dir}/lib/firmware/reboot_payload.bin

	echo -e "/dev/mmcblk0p1	/boot	vfat	rw,relatime	0	2\n" >> ${build_dir}/etc/fstab
	sed -i 's/^HOOKS=((.*))$/HOOKS=(\1 resize-rootfs)/' ${build_dir}/etc/mkinitcpio.conf
	chmod +x ${cwd}/build-stage2.sh	

	mount --bind ${build_dir} ${build_dir} &&
	mount --bind  ${build_dir}/boot/ ${build_dir}/boot/
}

Chroot() {
	echo -e "\nPreparing required files\n"
	[[ ! -f ${hekate_zip} ]] && wget ${hekate_url}
	[[ ! -f ${archive} ]] && wget ${url} &&

	[[ $(file "${archive}" | sed -E 's/(ID=0x8(e|3)|archive)//g') != 0 ]] ||
		echo -e "\n\nNot an archive and doesn't contain ext{2,3,4} or LVM partition type...\
		\nChroot preparation failed ! Exiting...\n" && exit 1

	[[ $(file "${archive}" | grep XZ) != 0 ]] && unxz "${archive}"
	[[ $(file "${archive}" | grep Zip) != 0 ]] && unzip "${archive}" -d
	[[ $(file "${archive}" | grep 7-zip) != 0 ]] && 7zip x "${archive}" -o
	[[ $(file "${archive}" | grep tar) != 0 ]] && bsdtar xpf ${archive} -C 

	[[ *.{{raw,img,iso},0*} =~ ${archive} ]] && 
	archive="$(echo "${archive}" | sed 's/\.[^.]*$//')"
	# TODO Mount and copy files from image
	PrepareChroot
	# Install Packages and configs here
 	arch-chroot ${build_dir} ./build-stage2.sh &&
	rm -rf ${build_dir}/{base-pkgs,build-stage2.sh/,pkgs/,usr/bin/qemu-aarch64-static}
}

CreateImage() {
	dd if=${build_dir} of=${img}.img bs=4M &&

	losetup ${loop} ${img} &&
	[[ $(file "${archive}" | sed -E 's/ID=0x8(e|3)//g') != 0 ]] &&
		vgchange -ay ${distro_name} &&
	mount ${loop} ${rootfs} &&

	mkfs.${format} -F ${loop} &&
	if [[ ${hekate} != "yes" ]]; then
		rootfs=${cwd}/bootloader/ && format="vfat 32" &&
		CreateImage &&
		dd if=${rootfs}/${img}.img bs=1M count=99 skip=1 of=${cwd}/${img}.img
		dd if=${build_dir}/${img}.img bs=1M count=10 of=${cwd}/${img}.img oflag=append conv=notrunc
		exit 0
	fi

	split -b4290772992 --numeric-suffixes=0 ${build_dir}/${img}.img l4t. &&
	7z a ${img}.7z {bootloader,switchroot} &&

	umount -R ./*
	[[ $(file "${archive}" | sed -E 's/ID=0x8(e|3)//g') != 0 ]] &&
		vgchange -an ${distro_name} &&
	losetup -d ${loop} && umount ${loop} &&

	rm -rf ${build_dir}
	echo -e "\n\nEstimated size: ${size}" && echo -e "\n\nDone"
}

if [[ `whoami` == root ]]; then
	if [[ ${docker} == "yes" ]]; then
		echo -e "\n\nBuilding Docker Image\n"
		docker image build -t l4t-builder:1.0 ${cwd} &&
		echo -e "\n\nRunning Docker Container\n"
		docker run --privileged --cap-add=SYS_ADMIN --rm -it \
			-v ${cwd}:/root/builder/ l4t-builder:1.0 /root/builder/create-rootfs.sh \
			"$(echo "$options" | sed -e 's/--docker//g' | sed -e 's/-d//g')"
	fi
	cd ${cwd} && Chroot && CreateImage
fi
echo -e "\n\nHey! Run this as root." && exit 1