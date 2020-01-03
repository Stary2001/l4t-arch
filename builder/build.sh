if [[ `whoami` != root ]]; then
	echo hey! run this as root.
	exit
fi

mkdir -p tarballs

if [[ ! -e tarballs/ArchLinuxARM-aarch64-latest.tar.gz ]]; then
	wget -O tarballs/ArchLinuxARM-aarch64-latest.tar.gz http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
fi

if [[ ! -d 4.9.140+ ]]; then
	echo modules not found, exiting
	exit 0
fi

if [[ ! -e reboot_payload.bin ]]; then
	wget https://github.com/CTCaer/hekate/releases/download/v5.1.1/hekate_ctcaer_5.1.1_Nyx_0.8.4.zip
	unzip hekate_ctcaer_5.1.1_Nyx_0.8.4.zip hekate_ctcaer_5.1.1.bin
	mv hekate_ctcaer_5.1.1.bin reboot_payload.bin
	rm hekate_ctcaer_5.1.1_Nyx_0.8.4.zip
fi

umount -R build
rm -r build
rm arch-boot.tar.gz arch-root.tar.gz

mkdir build
cp tarballs/*.pkg.* build/
cp build-stage2.sh base-pkgs optional-pkgs build/
cp reboot_payload.bin build/reboot_payload.bin

bsdtar xf tarballs/ArchLinuxARM-aarch64-latest.tar.gz -C build
mkdir -p build/usr/lib/modules
cp -r 4.9.140+  build/usr/lib/modules
cat << EOF >> build/etc/pacman.conf
[switch]
SigLevel = Optional
Server = https://9net.org/l4t-arch/
EOF

echo -e "/dev/mmcblk0p1	/mnt/hos_data	vfat	rw,relatime	0	2\n/boot /mnt/hos_data/l4t-arch/	none	bind	0	0" >> build/etc/fstab

# cursed
mount --bind build build
arch-chroot build ./build-stage2.sh
umount build

cd build
rm etc/pacman.d/gnupg/S.gpg-agent*
#mv arch-boot.tar.gz ..
bsdtar -cz -f ../arch-root.tar.gz .
cd ..
