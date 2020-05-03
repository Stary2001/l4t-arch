#!/bin/env bash
uname -a

# Pre install configurations
## Workaround for flakiness of `pt` mirror.
sed -i 's/mirror.archlinuxarm.org/de.mirror.archlinuxarm.org/g' /etc/pacman.d/mirrorlist
echo -e "[switch]\nSigLevel = Optional\nServer = https://9net.org/l4t-arch/" >> /etc/pacman.conf

# Configuring pacman
pacman-key --init
pacman-key --populate archlinuxarm

# Installation
## Removing linux-aarch64 as we won't be needing this
pacman -R linux-aarch64 --noconfirm

i=5
echo -e "\n\Begining packages installation !\nRetry attempts left : ${i}"
until pacman -Syu `cat base-pkgs` --noconfirm; do
	echo -e "\n\nPackages installation failed, retrying !\nRetry attempts left : ${i}"
	let --i
	[[ ${i} == 0 ]] && echo -e "\n\n${i} attempt left.\n Building failed !\n Exiting.." && exit 1
done

for pkg in `find /pkgs/*.pkg.* -type f`; do
	pacman -U $pkg --noconfirm
done

yes | pacman -Scc

# Post install configurations
systemctl enable r2p bluetooth lightdm NetworkManager

echo brcmfmac > /etc/suspend-modules.conf
sed -i 's/#keyboard=/keyboard=onboard/' /etc/lightdm/lightdm-gtk-greeter.conf

usermod -aG video,audio,wheel alarm
ldconfig