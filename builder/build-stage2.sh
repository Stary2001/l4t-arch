#!/usr/bin/bash
uname -a

pacman-key --init
pacman-key --populate archlinuxarm

pacman -Syu --noconfirm
pacman -S xorg-server-tegra --noconfirm # important
pacman -S switch-configs --noconfirm
pacman -S tegra-bsp --noconfirm
pacman -S `cat base-pkgs` --noconfirm
pacman -S `cat optional-pkgs` --noconfirm

systemctl enable r2p
systemctl enable lightdm
systemctl enable alsa-restore

sed -i 's/#keyboard=/keyboard=onboard/' /etc/lightdm/lightdm-gtk-greeter.conf

yes | pacman -Scc

mv /reboot_payload.bin /lib/firmware/
gpasswd -a alarm audio
gpasswd -a alarm video

rm /boot/*
rm /mnt/hos_data/*

mkdir -p /mnt/hos_data
