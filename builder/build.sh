if [[ `whoami` != root ]]; then
	echo hey! run this as root.
	exit
fi

if [[ ! -e tarballs/ArchLinuxARM-aarch64-latest.tar.gz ]]; then
	wget -O tarballs/ArchLinuxARM-aarch64-latest.tar.gz http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
fi

if [[ ! -e reboot_payload.bin ]]; then
	wget https://github.com/CTCaer/hekate/releases/download/v5.0.1/hekate_ctcaer_5.0.1_Nyx_0.8.1.zip
	unzip hekate_ctcaer_5.0.1_Nyx_0.8.1.zip hekate_ctcaer_5.0.1.bin
	mv hekate_ctcaer_5.0.1.bin reboot_payload.bin
	rm hekate_ctcaer_5.0.1_Nyx_0.8.1.zip
fi

mkdir build
cp tarballs/*.pkg.* build/
cp build-stage2.sh build/
cp optional-pkgs build/
cp reboot_payload.bin build/reboot_payload.bin

bsdtar xf ../tarballs/ArchLinuxARM-aarch64-latest.tar.gz -C build

cat << EOF >> build/etc/pacman.conf
[switch]
Server = https://9net.org/l4t-arch/
EOF

# cursed
mount --bind build build
arch-chroot build ./build-stage2.sh
umount build

cd build
rm etc/pacman.d/gnupg/S.gpg-agent*
bsdtar -c . -f ../arch.tar
