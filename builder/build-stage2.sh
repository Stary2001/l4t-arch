#!/usr/bin/bash
uname -a

pacman-key --init
pacman-key --populate archlinuxarm

# we won't be needing this
pacman -R linux-aarch64 --noconfirm

pacman -Syu --noconfirm
pacman -S xorg-server-tegra switch-configs tegra-bsp --noconfirm # important
pacman -S `cat base-pkgs` --noconfirm
pacman -S `cat optional-pkgs` --noconfirm

systemctl enable r2p
systemctl enable lightdm

sed -i 's/#keyboard=/keyboard=onboard/' /etc/lightdm/lightdm-gtk-greeter.conf

yes | pacman -Scc

mv /reboot_payload.bin /lib/firmware/
gpasswd -a alarm audio
gpasswd -a alarm video

rm -r /boot/*
rm -r /mnt/hos_data/*

mkdir -p /mnt/hos_data
