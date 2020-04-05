#!/usr/bin/bash
uname -a

pacman-key --init
pacman-key --populate archlinuxarm

# we won't be needing this
pacman -R linux-aarch64 --noconfirm

until pacman -Syu systemd-suspend-modules xorg-server-tegra switch-configs `cat base-pkgs` --noconfirm
# until pacman -Syu switch-boot-files-bin systemd-suspend-modules xorg-server-tegra switch-configs tegra-bsp linux-tegra gcc7 `cat base-pkgs` --noconfirm
do
	echo "Error check your build or let the script retry last cmd"
done

for pkg in `find /pkgs/*.pkg.* -type f`; do
	pacman -U $pkg --noconfirm
done

systemctl enable r2p
systemctl enable bluetooth
systemctl enable lightdm

echo brcmfmac > /etc/suspend-modules.conf
sed -i 's/#keyboard=/keyboard=onboard/' /etc/lightdm/lightdm-gtk-greeter.conf

yes | pacman -Scc

mv /reboot_payload.bin /lib/firmware/
gpasswd -a alarm audio
gpasswd -a alarm video

ldconfig
