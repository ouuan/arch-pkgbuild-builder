#!/bin/bash

# fail whole script if any command fails
set -eo pipefail

DEBUG=$4

if [[ -n $DEBUG && $DEBUG = true ]]; then
    set -x
fi

target=$1
pkgname=$2
command=$3

# assumes that package files are in a subdirectory
# of the same name as "pkgname", so this works well
# with "aurpublish" tool

if [[ ! -d $pkgname ]]; then
    echo "$pkgname should be a directory."
    exit 1
fi

if [[ ! -e $pkgname/PKGBUILD ]]; then
    echo "$pkgname does not contain a PKGBUILD file."
    exit 1
fi

sudo bash -c 'echo "
[multilib]
Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'

pkgbuild_dir=$(readlink "$pkgname" -f) # nicely cleans up path, ie. ///dsq/dqsdsq/my-package//// -> /dsq/dqsdsq/my-package

getfacl -p -R "$pkgbuild_dir" /github/home >/tmp/arch-pkgbuild-builder-permissions.bak

# '/github/workspace' is mounted as a volume and has owner set to root
# set the owner of $pkgbuild_dir  to the 'build' user, so it can access package files.
sudo chown -R build "$pkgbuild_dir"

# needs permissions so '/github/home/.config/yay' is accessible by yay
sudo chown -R build /github/home

# use more reliable keyserver
mkdir -p /github/home/.gnupg/
echo "keyserver hkp://keyserver.ubuntu.com:80" | tee /github/home/.gnupg/gpg.conf
sudo pacman -Syu

cd "$pkgbuild_dir"

# shellcheck disable=SC1091
source PKGBUILD

case $target in
pkgbuild)
    namcap PKGBUILD
    yay -Syu --noconfirm "${depends[@]}" "${makedepends[@]}"
    makepkg --syncdeps --noconfirm

    # shellcheck disable=SC1091
    source /etc/makepkg.conf # get PKGEXT

    files=("${pkgname}-${pkgver}-${pkgrel}-"*"${PKGEXT}")
    pkgfile="${files[0]}"
    echo "::set-output name=pkgfile::${pkgfile}"

    namcap "${pkgfile}"
    pacman -Qip "${pkgfile}"
    pacman -Qlp "${pkgfile}"
    ;;
run)
    yay -Syu --noconfirm "${depends[@]}" "${makedepends[@]}"
    makepkg --syncdeps --noconfirm --install
    eval "$command"
    ;;
srcinfo)
    makepkg --printsrcinfo | diff .SRCINFO - ||
        {
            echo ".SRCINFO is out of sync. Please run 'makepkg --printsrcinfo' and commit the changes."
            false
        }
    ;;
*)
    echo "Target should be one of 'pkgbuild', 'srcinfo', 'run'"
    ;;
esac

sudo setfacl --restore=/tmp/arch-pkgbuild-builder-permissions.bak
