#!/usr/bin/bash
uname -a

# Workaround for flakiness of `pt` mirror.
sed -i 's/mirror.archlinuxarm.org/de.mirror.archlinuxarm.org/g' ${build_dir}/rootfs/etc/pacman.d/mirrorlist
echo "[switch]\nSigLevel = Optional\nServer = https://9net.org/l4t-arch/" >> ${build_dir}/rootfs/etc/pacman.conf

pacman-key --init
pacman-key --populate archlinuxarm
# we won't be needing this
pacman -R linux-aarch64 --noconfirm

i=5
until [[ ${i} -gt 0 ]]; do
	pacman -Syu `cat base-pkgs` --noconfirm 
	echo "\n\n Packages installation failed, retrying !\netry attempts left : ${$((--i))}\n\n"
done

for pkg in `find /pkgs/*.pkg.* -type f`; do
	pacman -U $pkg --noconfirm
done

yes | pacman -Scc

systemctl enable r2p bluetooth lightdm

echo brcmfmac > /etc/suspend-modules.conf
sed -i 's/#keyboard=/keyboard=onboard/' /etc/lightdm/lightdm-gtk-greeter.conf

usermod -aG video,audio,wheel alarm
ldconfig