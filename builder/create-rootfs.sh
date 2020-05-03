#!/bin/env bash

root_dir="$(dirname "$(dirname "$(readlink -fm "$0")")")"
build_dir="$(dirname "$(readlink -fm "$0")")"/l4t
cwd="$(dirname "$(readlink -fm "$0")")"
tarballs=${build_dir}/tarballs/
unset img
unset imgSize
unset extPartNumber

distro_name=arch
if [[ ${distro_name} == "arch" ]]; then
	url=http://fl.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
else
	url=https://download.fedoraproject.org/pub/fedora/linux/releases/31/Server/aarch64/images/Fedora-Server-31-1.9.aarch64.raw.xz
fi
archive="$(echo ${url} | rev | cut -d/ -f1 | rev )"
hekate_version=5.2.0
nyx_version=0.9.0
pkg_types={*.pkg.*,*.rpm,*.deb}

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

cleanup() {
	echo -e "\nCleaning up old files\n"
	umount -R ${build_dir}/{tmp,{r,b}ootfs}/*
	
	[[ echo $(file $(echo l4t/tarballs/Fedora-Server-31-1.9.aarch64.raw) | sed 's/*ID=0x8{e,3}//g') != 0 ]] && \
	vgchange -an ${distro_name} && \
	sleep 3 && kpartx -dv ${tarballs}/${archive}*
	
	rm -rf ${build_dir}/{tmp,{r,b}ootfs,switchroot/,bootloader/}
	echo -e "\nDone cleaning files\n!" && exit 0
}

createImg() {
	size=$(du -hs -BM ${imgSize} | head -n1 | awk '{print int($1/4)*4 + 4 + 512;}')M
	echo "Estimated size: $size"
	dd if=/dev/zero of=${img} bs=1 count=0 seek=${size}
	exit 0
}

mountLoop() {
	losetup ${loop} ${img}
	[[ echo $(file $(echo l4t/tarballs/Fedora-Server-31-1.9.aarch64.raw) | sed 's/*ID=0x8{e,3}//g') != 0 ]] && \
	vgchange -ay ${distro_name}
	exit 0
}

umountLoop() {
	[[ echo $(file $(echo l4t/tarballs/Fedora-Server-31-1.9.aarch64.raw) | sed 's/*ID=0x8{e,3}//g') != 0 ]] && \
	vgchange -an ${distro_name}
	losetup -d ${loop}
	umount ${loop}
	exit 0
}

isArchiveOrImageFile() {
	[[ echo $(file $(echo l4t/tarballs/Fedora-Server-31-1.9.aarch64.raw) | sed 's/*ID=0x8{e,3}\|archive//g') != 0 ]] || \
	echo -e "\n\nNot an archive and doesn't contain ext{2,3,4} or LVM partition type...\n \
	Chroot preparation failed ! Exiting...\n" \
	&& exit 1

	[[ $(file "${tarballs}/${archive}" | grep XZ) != 0 ]] && \
	unxz "${tarballs}/${archive}"

	[[ $(file "${tarballs}/${archive}" | grep Zip) != 0 ]] && \
	unzip "${tarballs}/${archive}" -d ${build_dir}/rootfs/

	[[ $(file "${tarballs}/${archive}" | grep 7-zip) != 0 ]] && \
	7zip x "${tarballs}/${archive}" -o${build_dir}/rootfs/

	[[ $(file "${tarballs}/${archive}" | grep tar) != 0 ]] && \
	bsdtar xpf ${tarballs}/${archive} -C ${build_dir}/rootfs/

	# extPartNumber=
	# mountLoop
	# mount /dev/mapper/${distro_name}-root ${build_dir}/tmp
	# cp -prd ${build_dir}/tmp/* ${build_dir}/rootfs/
	# umount /dev/mapper/${distro_name}-root
	# umountLoop

	exit 0
}

prepareChroot() {
	echo -e "\nCreating build folders\n"
	mkdir -p ${build_dir}/{tmp/,bootfs/,rootfs/pkgs,switchroot/install/}

	echo -e "\nPreparing required files\n"
	if [[ ! -d ${tarballs} ]]; then
		wget ${url} -P ${tarballs}
		wget https://github.com/CTCaer/hekate/releases/download/v${hekate_version}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip -P ${tarballs}
	fi
	
	isArchiveOrImageFile || exit 1

	unzip ${tarballs}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip hekate_ctcaer_${hekate_version}.bin -d ${build_dir}/rootfs/
	unzip ${tarballs}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip bootloader/ -d ${build_dir}/bootfs/
	mv ${build_dir}/rootfs/hekate_ctcaer_${hekate_version}.bin ${build_dir}/rootfs/lib/firmware/reboot_payload.bin

	echo -e "/dev/mmcblk0p1	/boot	vfat	rw,relatime	0	2\n" >> ${build_dir}/rootfs/etc/fstab
	sed -i 's/^HOOKS=(\(.*\))$/HOOKS=(\1 resize-rootfs)/' ${build_dir}/rootfs/etc/mkinitcpio.conf

	cp /usr/bin/qemu-aarch64-static ${build_dir}/rootfs/usr/bin/

	[[ ${staging} == "yes" ]] && \
	cp -r ${root_dir}/pkgbuilds/*/${pkg_types} ${build_dir}/rootfs/pkgs/
	
	chmod +x ${cwd}/build-stage2.sh
	cp ${cwd}/{build-stage2.sh,base-pkgs} ${build_dir}/rootfs/

	mount --bind ${build_dir}/rootfs ${build_dir}/rootfs
	mount --bind ${build_dir}/bootfs ${build_dir}/rootfs/boot/
	exit 0
}

buildFilesystem() {
	# Install Packages and configs here
	arch-chroot ${build_dir}/rootfs/ ./build-stage2.sh
	rm -rf ${build_dir}/rootfs/{base-pkgs,build-stage2.sh/,pkgs/,usr/bin/qemu-aarch64-static}
	exit 0
}

packDistrbution() {
	imgSize=${build_dir}/rootfs/
	img=${build_dir}/switchroot/install/l4t.img
	loop=`losetup --find`
	
	createImg
	mountLoop
	
	mkfs.ext4 -F ${loop}
	mount ${loop} ${build_dir}/tmp

	cp -prd ${build_dir}/rootfs/* ${build_dir}/tmp/
	umountLoop
	
	cd ${build_dir}/switchroot/install/
	split -b4290772992 --numeric-suffixes=0 l4t.img l4t.
	rm -rf ${build_dir}/switchroot/install/l4t.img

	umount -R ${build_dir}/rootfs/{,boot/}

	mv ${build_dir}/bootfs/* ${build_dir}

	if [[ ${hekate} != "yes" ]]; then
		img=${root_dir}/l4t-${distro_name}.img
		imgSize=${build_dir}
		
		createImg
		mountLoop

		mkfs.vfat -F 32 ${loop}
		mount ${loop} ${build_dir}/tmp

		cp -r ${build_dir}/{switchroot,bootloader} ${build_dir}/tmp/
		
		umountLoop
		echo -e "Done!\n"
	else
		7z a ${root_dir}/SWR-L4T-"${distro_name}".7z ${build_dir}/*
	fi
	cleanup && echo -e "Done!\n" && exit 0
}

if [[ `whoami` != root ]]; then
	echo hey! run this as root. && exit 1
elif [[ ${docker} == "yes" && ($(groups "${USER}" | grep -q docker) != 0 || `whoami` == root) ]]; then
	echo -e "\n\nBuild using Docker\n"

	echo -e "\n\nBuilding Docker Image\n"
	docker image build -t l4t-builder:1.0 ${cwd}

	echo -e "\n\nRunning Docker Container\n"
	docker run --privileged --cap-add=SYS_ADMIN --rm -it -v ${cwd}:/root/builder/ l4t-builder:1.0 /root/builder/create-rootfs.sh \
	"$(echo "$options" | sed -e 's/--docker//g' | sed -e 's/-d//g')"

	exit 0
fi

[[ -d ${build_dir} ]] && cleanup && exit 1 || \
prepareChroot && buildFilesystem && \
packDistrbution