#!/usr/bin/bash

root_dir="$(dirname "$(dirname "$(readlink -fm "$0")")")"
build_dir="$(dirname "$(readlink -fm "$0")")"/l4t
cwd="$(dirname "$(readlink -fm "$0")")"
tarballs=${cwd}/tarballs/
unset img
unset imgSize

distro_name=arch
url=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
archiveImage="$(echo ${url} | rev | cut -d/ -f1 | rev)"
hekate_version=5.2.0
nyx_version=0.9.0
pkg_types={*.pkg.*,*.rpm,*.deb}

raw=false
[[ $(echo ${archiveImage} | rev | cut -d. -f2 | rev) == "raw" ]] && raw=true

docker=no
hekate=no
staging=no
options=$(getopt -o dhs --long docker,staging,help:,hekate -- "$@")

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
	echo " -d, --docker		Build using docker"
	echo " --hekate			Create only a hekate flashable image file"
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

cleanup() {
	echo -e "\nCleaning up uneeded files\n"
	umount -R ${build_dir}/{tmp,{r,b}ootfs}/*
	rm -rf ${build_dir}/{tmp/,{b,r}ootfs/pkgs}
	if [[ ${hekate} == "yes" ]]; then
		rm -rf ${build_dir}
	fi
}

build() {
	echo -e "\nCleaning up old build\n"
	[[ -e ${build_dir} ]] && cleanup

	echo -e "\nCreating build folders\n"
	mkdir -p ${build_dir}/{tmp/,bootfs/,rootfs/pkgs,switchroot/install/}

	if [[ ${docker} == "yes" && ($(groups "${USER}" | grep -q docker && echo "true") == "true" || `whoami` == root) ]]; then
		echo "Build using Docker"
		docker image build -t l4t-builder:1.0 ${cwd}
		docker run --privileged --cap-add=SYS_ADMIN --rm -it -v ${cwd}:/root/builder/ l4t-builder:1.0 /root/builder/create-rootfs.sh \
		"$(echo "$options" | sed -e 's/--docker//g' | sed -e 's/-d//g')"
		exit
	elif [[ `whoami` != root ]]; then
		echo hey! run this as root.
		exit
	fi

	prepareImg() {
		size=$(du -hs -BM ${imgSize} | head -n1 | awk '{print int($1/4)*4 + 4 + 512;}')M
		echo "Estimated size: $size"
		dd if=/dev/zero of=${img} bs=1 count=0 seek=$size
		loop=`losetup --find`
		losetup ${loop} ${img}
	}

	echo -e "\nPreparing required files\n"
	if [[ ! -e ${tarballs}/${archiveImage} ]]; then
		wget ${url} -P ${tarballs}
	fi

	if [[ ${raw} == "true" ]]; then
		unxz ${tarballs}/${archiveImage}
	else
		bsdtar xpf ${tarballs}/${archiveImage} -C ${build_dir}/rootfs/
	fi

	if [[ ! -e ${tarballs}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip ]]; then
		wget https://github.com/CTCaer/hekate/releases/download/v${hekate_version}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip -P ${tarballs}
	fi

	unzip ${tarballs}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip hekate_ctcaer_${hekate_version}.bin -d ${build_dir}/rootfs/
	mv ${build_dir}/rootfs/hekate_ctcaer_${hekate_version}.bin ${build_dir}/rootfs/lib/firmware/reboot_payload.bin

	echo -e "/dev/mmcblk0p1	/boot	vfat	rw,relatime	0	2\n" >> ${build_dir}/rootfs/etc/fstab
	sed -i 's/^HOOKS=(\(.*\))$/HOOKS=(\1 resize-rootfs)/' ${build_dir}/rootfs/etc/mkinitcpio.conf

	cp /usr/bin/qemu-aarch64-static ${build_dir}/rootfs/usr/bin/

	if [[ ${staging} == "yes" ]]; then
		cp -r ${root_dir}/pkgbuilds/*/${pkg_types} ${build_dir}/rootfs/pkgs/
	fi
	
	chmod +x ${cwd}/build-stage2.sh
	cp ${cwd}/{build-stage2.sh,base-pkgs} ${build_dir}/rootfs/

	mount --bind ${build_dir}/rootfs ${build_dir}/rootfs
	mount --bind ${build_dir}/bootfs ${build_dir}/rootfs/boot/
	
	# Install Packages and configs here
	arch-chroot ${build_dir}/rootfs/ ./build-stage2.sh
	
	rm -rf ${build_dir}/rootfs/{base-pkgs,build-stage2.sh/,pkgs/,usr/bin/qemu-aarch64-static}

	imgSize=${build_dir}/rootfs/
	img=${build_dir}/switchroot/install/l4t.img
	
	prepareImg

	mkfs.ext4 ${loop}
	[[ ${raw} == true ]] && kpartx -a ${build_dir}/${archiveImage} && sleep 1 && vgchange -ay fedora && sleep 1
	mount ${loop} ${build_dir}/tmp

	cp -prd ${build_dir}/rootfs/* ${build_dir}/tmp/

	umount ${loop}
	losetup -d ${loop}

	cd ${build_dir}/switchroot/install/
	split -b4290772992 --numeric-suffixes=0 l4t.img l4t.

	umount -R ${build_dir}/rootfs/{,boot/}
	[[ ${raw} == true ]] && vgchange -an fedora && kpartx -d ${build_dir}/${archiveImage}

	mv ${build_dir}/bootfs/* ${build_dir}

	cleanup

	if [[ ${hekate} != "yes" ]]; then
		img=${root_dir}/l4t-${distro_name}.img
		imgSize=${build_dir}
		prepareImg
		mkfs.vfat -F 32 ${loop}
		mount ${loop} ${build_dir}/tmp
		cp -prd ${build_dir}/{switchroot,bootloader} ${build_dir}/tmp/
		umount ${loop}
		losetup -d ${loop}
	fi
	echo -e "Done!\n"
}

build
