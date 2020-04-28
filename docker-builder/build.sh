#!/usr/bin/bash

staging=no
options=$(getopt -o hs --long staging --long help -- "$@")

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo " -s, --staging	Install built local packages"
    echo " -h, --help		Show this help text"
}

[ $? -eq 0 ] || {
	usage
	exit 1
}

eval set -- "$options"
while true; do
    case "$1" in
    -s)
        staging=yes
        ;;
    --staging)
        staging=yes
        ;;
    -h|--help)
	usage
	exit 0
	;;
    --)
        shift
        break
        ;;
    esac
    shift
done

APP_ROOT="$(dirname "$(dirname "$(readlink -fm "$0")")")"
docker image build -t archl4tbuild:1.0 "$APP_ROOT"/docker-builder
if [[ $staging == "yes" ]]; then
	docker run --privileged --cap-add=SYS_ADMIN --rm -it -v "$APP_ROOT":/root/l4t-arch archl4tbuild:1.0 /root/l4t-arch/builder/create-rootfs.sh -s &&
	exit 0
fi
docker run --privileged --cap-add=SYS_ADMIN --rm -it -v "$APP_ROOT":/root/l4t-arch archl4tbuild:1.0 /root/l4t-arch/builder/create-rootfs.sh