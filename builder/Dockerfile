FROM ubuntu:latest
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && apt-get upgrade -y
RUN apt-get install -y git xz-utils unzip qemu qemu-user-static arch-install-scripts parted dosfstools wget libarchive-tools lvm2 multipath-tools p7zip -y
RUN mkdir -p /root/builder/