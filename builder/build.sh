#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
distro=0
setup_base(){

	mkdir -p tarballs
	
	if [[ ! -e tarballs/ArchLinuxARM-aarch64-latest.tar.gz ]]; then
		wget -O tarballs/ArchLinuxARM-aarch64-latest.tar.gz http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
	fi

	if [[ ! -e reboot_payload.bin ]]; then
		wget https://github.com/CTCaer/hekate/releases/download/v5.0.1/hekate_ctcaer_5.0.1_Nyx_0.8.1.zip
		unzip hekate_ctcaer_5.0.1_Nyx_0.8.1.zip hekate_ctcaer_5.0.1.bin
		mv hekate_ctcaer_5.0.1.bin reboot_payload.bin
		rm hekate_ctcaer_5.0.1_Nyx_0.8.1.zip
	fi

	umount -R build
	rm -r build
	rm arch.tar.gz

	mkdir build
	cp tarballs/*.pkg.* build/
	cp build-stage2.sh base-pkgs optional-pkgs build/
	cp reboot_payload.bin build/reboot_payload.bin

	bsdtar xf tarballs/ArchLinuxARM-aarch64-latest.tar.gz -C build

	cat << EOF >> build/etc/pacman.conf
	[switch]
	SigLevel = Optional
	Server = https://9net.org/l4t-arch/
EOF

	# cursed
	mount --bind build build
	arch-chroot build ./build-stage2.sh
}

package_build() {
	umount build

	cd build
	rm etc/pacman.d/gnupg/S.gpg-agent*
	if [ $1 -eq 1 ]; then	
		bsdtar -cz -f ../arch.tar.gz .

	elif [ $1 -eq 2 ]; then
		bsdtar -cz -f ../black-arch.tar.gz .

	elif [ $1 -eq 3 ]; then
		bsdtar -cz -f ../manjaro.tar.gz .

	elif [ $1 -eq 4 ]; then
		bsdtar -cz -f black-manjaro.tar.gz .

	fi
	
}

build_options() {
	echo -e "##################################"
	echo -e "#Choose Which ARCH Disto to Build#"
	echo -e "##################################"
	echo -e "#[1] - Arch Linux                #"
	echo -e "#[2] - BlackArch Linux           #"
	#echo -e "#[3] - Manjaro Linux             #"
	#echo -e "#[4] - BlackArch-Manjaro Mix     #"
	echo -e "#[0] - Exit                      #"
	echo -e "##################################"
	echo -e "Enter Choice: "
	read distro
}
	

add_blackarch(){
	wget https://blackarch.org/strap.sh	
	chmod +x strap.sh
	mv strap.sh build/	
	arch-chroot build ./strap.sh
	arch-chroot build pacman -S blackarch
}

add_manjaro(){
	echo -e "${RED}Manjaro Currently Not available.${NC}"
	echo -e "This currently builds default ARCH for the Switch"
}
	
if [[ `whoami` != root ]]; then
	echo -e hey! run this as ${RED}root${NC}.
	exit
fi

build_options
distro=$((distro))

if [ $distro -eq 0 ]; then
	exit
fi

if [ $distro -gt 4 -o $distro -lt 1 ]; then
	echo "Please choose an availble option"
	build_options
fi

setup_base

#Do extra stuff for Manjaro and Blackarch.
if [[ $distro -gt 1 ]]; then
	if [[ $distro == "2" ]]; then
		add_blackarch
	fi
fi


#elif [[ $distro == "3" ]]; then
#	add_manjaro()	

#elif [[ $distro == "4" ]]; then
#	add_manjaro()
#	add_blackarch() 	
#fi
#fi    

package_build $distro
