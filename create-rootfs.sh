#!/bin/env bash

# Setup variables
docker=false
staging=false
hekate=false

pkg_types=*.{pkg.*,rpm,deb}
format=ext4
loop=`losetup --find`

# Folders
cwd="$(dirname "$(readlink -f "$0")")"
build_dir="${cwd}/build"
dl_dir="${cwd}/dl"

# Distro specific variables
selection=arch
img_url=http://fl.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
img_sig_url="${img_url}.md5"
img="${img_url##*/}"
img_sig="${img_sig_url##*/}"
validate_command="md5sum --status -c "${img_sig}""

# Hekate files
hekate_version=5.2.0
nyx_version=0.9.0
hekate_url=https://github.com/CTCaer/hekate/releases/download/v${hekate_version}/hekate_ctcaer_${hekate_version}_Nyx_${nyx_version}.zip
hekate_zip=${hekate_url##*/}
hekate_bin=hekate_ctcaer_${hekate_version}.bin

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
	echo " -d, --docker          	Build with Docker"
	echo " -f, --force             	Download setup files anyway"
	echo " --hekate                 Build for Hekate"
    echo " -s, --staging            Install built local packages"
    echo " -h, --help               Show this help text"
}

GetImgFiles() {
	# cd into download directory
	cd ${dl_dir}

	# Download file if it doesn't exist, or is forced to download.
	if [[ ! -f ${img} || $1 == "force" ]]; then 
		wget -q --show-progress ${img_url} -O "${dl_dir}/${img}"
	else
		echo "Image exists!"
	fi
	
	# Download signature file
	echo "Downloading signature file..."
	wget -q --show-progress ${img_sig_url} -O "${dl_dir}/${img_sig}"
	
	# Check image against signature
	echo "Validating image..."
	${validate_command}
	if [[ $? != "0" ]]; then
		echo "Image doesn't match signature, re-downloading..."
		GetImgFiles force
	else
		echo "Signature check passed!"
	fi
}

Main() {
	# Create directories
	mkdir -p ${dl_dir} 
	mkdir -p ${build_dir}/{switchroot/install/pkgs,boot/}

	echo "Downloading image..."
	GetImgFiles

	echo "Downloading Hekate..."
	wget -P ${dl_dir} -q --show-progress ${hekate_url} -O ${dl_dir}/${hekate_zip}
	
	# cd into script current working directory
	cd ${build_dir}
	
	echo "Extracting image..."
	[[ $(file -b --mime-type "${dl_dir}/${img}") == "application/gzip" ]] && tar xf ${dl_dir}/${img} -C ${build_dir}
	[[ $(file -b --mime-type "${dl_dir}/${img}") == "application/x-xz" ]] && unxz "${dl_dir}/${img}"
	[[ $(file -b --mime-type "${dl_dir}/${img}") == "application/zip" ]] && unzip -q -o"${dl_dir}/${img}" -d ${build_dir}
	[[ $(file -b --mime-type "${dl_dir}/${img}") == "application/x-7z-compressed" ]] && 7z e "${dl_dir}/${img}" -o${build_dir}
	
	echo "Extracting Hekate..."
	unzip -q -o ${dl_dir}/${hekate_zip} -d "${build_dir}/boot"

	echo "Copying files to rootfs..."
	[[ ${staging} == "yes" ]] && cp -r "${cwd}/install/${selection}/*/*/${pkg_types}" "${build_dir}/pkgs/"
	cp ${cwd}/install/${selection}/{build-stage2.sh,base-pkgs} ${build_dir}
	mv "${dl_dir}/${hekate_bin}" ${build_dir}/lib/firmware/reboot_payload.bin
	
	echo "Pre chroot setup..."
	echo -e "/dev/mmcblk0p1	/boot	vfat	rw,relatime	0	2\n" >> ${build_dir}/etc/fstab
	sed -r -i 's/^HOOKS=((.*))$/HOOKS=(\1 resize-rootfs)/' ${build_dir}/etc/mkinitcpio.conf
	chmod +x ${build_dir}/build-stage2.sh
	
	mount --bind ${build_dir} ${build_dir} &&
	mount --bind  "${build_dir}/boot/" "${build_dir}/boot/"
	
	echo "Chrooting..."
	cd ${cwd}
	arch-chroot ${build_dir} ./build-stage2.sh

	echo "Post chroot cleaning..."
	umount "${build_dir}/boot/" ${build_dir}
	rm -rf ${build_dir}/{base-pkgs,build-stage2.sh,pkgs/,usr/bin/qemu-aarch64-static}
	
	echo "Creating final "${format}" partition..."
	size=$(du -hs -BM "${build_dir}" | head -n1 | awk '{print int($1/4)*4 + 4 + 512;}')M
	dd if=/dev/zero of="${img}.${format}" bs=1 count=0 seek=${size} && losetup ${loop} "${img}.${format}"

	echo "Formating "${img}.${format}" to: "${format}"..."
	[[ $(file -b --mime-type "${dl_dir}/${img}") == "application/octet-stream" ]] &&
	[[ $(file -b "${dl_dir}/${img}" | sed -E 's/ID=0x8(e|3)//g') == 0 ]] && vgchange -ay ${selection}
	mount ${loop} ${build_dir} && mkfs.${format} -F ${loop}

	if [[ ${hekate} == "yes" ]]; then
		echo "Creating Hekate installable files..."
		split -b4290772992 --numeric-suffixes=0 "${img}.${format}" l4t.
	
		echo "Compressing hekate folder..."
		7z a "SWR-${img}.7z" ${build_dir}/{bootloader,switchroot}
	else
		echo "Creating fat32 image file..."
		size=$(du -hs -BM "${build_dir}/boot" | head -n1 | awk '{print int($1/4)*4 + 4 + 512;}')M
		loop=`losetup --find`
		dd if=/dev/zero of="${img}.fat32" bs=1 count=0 seek=${size} && losetup ${loop} "${img}.fat32"
		mount ${loop} "${build_dir}/boot" && mkfs.vfat 32 -F ${loop}
		
		echo "Creating final image: ${img}.img..."
		dd if="${img}.fat32" bs=1M count=99 skip=1 of="SWR-${img}.img"
		dd if="${img}.${format}" bs=1M count=10 of="SWR-${img}.img" oflag=append conv=notrunc
	fi

	echo "Cleaning up files..."
	[[ $(file -b "${dl_dir}/${img}" | sed -E 's/ID=0x8(e|3)//g') == 0 ]] && vgchange -an ${selection}	
	losetup -d ${loop}
	umount ${loop} ${build_dir}
	rm -r ${build_dir}
	echo "Done!"
}

# Parse arguments
options=$(getopt -n $0 -o dfhs --long docker,force,hekate,staging:,help -- "$@")

# Check for errors in arguments or if no name was provided
if [[ $? != "0" ]]; then usage; exit 1; fi

# Evaluate arguments
eval set -- "$options"
while true; do
    case "$1" in
	-d | --docker) docker=true; shift ;;
	-f | --force) force=true; shift ;;
    -s | --staging) staging=true; shift ;;
	--hekate) hekate=true; shift ;;
    ? | -h | --help) usage; exit 0 ;;
    -- ) shift; break ;;
    esac
done

echo "Cleaning up old Files..."
if [[ ${docker} == true ]]; then
	rm -rf ${build_dir}

	echo "Starting using Docker..."
	systemctl start docker.{socket,service}

	echo "Building Docker image..."
	docker image build -t l4t-builder:1.0 .
	
	echo "Running container..."
	docker run --privileged --cap-add=SYS_ADMIN --rm -it -v ${cwd}:/builder l4t-builder:1.0 /builder/create-rootfs.sh "$(echo "$options" | sed -E 's/-(d|-docker)//g')" ${selection}
	exit 0
fi
Main