FROM archlinux:latest
RUN pacman -Syu --noconfirm
RUN pacman -S go base base-devel dhcpcd iproute2 git unzip qemu qemu-arch-extra arch-install-scripts parted dosfstools wget libarchive lvm2 multipath-tools p7zip --noconfirm
RUN useradd --shell=/bin/false build && usermod -L build
RUN echo "build ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers
RUN echo "root ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers
RUN mkdir /home/build && chown -R build:build /home/build && chmod 755 /home/build
RUN git clone https://aur.archlinux.org/yay.git && chown -R build:build yay
USER build
RUN cd yay && makepkg -s
USER root
RUN ls yay
RUN pacman -U /yay/*.pkg.tar.xz --noconfirm
USER build
RUN yay -S qemu-user-static-bin --noconfirm
USER root
RUN mkdir -p /root/builder/