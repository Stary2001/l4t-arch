#!/usr/bin/bash
uname -a

pacman-key --init
pacman-key --populate archlinuxarm

pacman -Syu --noconfirm
pacman -U xorg-server-1.19.6-2-aarch64.pkg.tar.xz --noconfirm
#pacman -S xorg-server-tegra --noconfirm
pacman -S switch-configs --noconfirm
pacman -S tegra-bsp --noconfirm
pacman -S `cat base-pkgs` --noconfirm
pacman -S `cat optional-pkgs` --noconfirm

systemctl enable r2p

systemctl enable lightdm
sed -i 's/#keyboard=/keyboard=onboard/' /etc/lightdm/lightdm-gtk-greeter.conf

pacman -Scc --noconfirm

mv /reboot_payload.bin /lib/firmware/
gpasswd -a alarm audio
gpasswd -a alarm video
