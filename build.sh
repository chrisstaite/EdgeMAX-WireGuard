#!/bin/bash

# https://dl.ubnt.com/firmwares/edgemax/v2.0.x/GPL.ER-e50.v2.0.0-beta.2.5147851.tar.bz2   mipsel
# https://dl.ubnt.com/firmwares/edgemax/v2.0.x/GPL.ER-e100.v2.0.0-beta.2.5147851.tar.bz2  mips    ERLite-3
# https://dl.ubnt.com/firmwares/edgemax/v2.0.x/GPL.ER-e200.v2.0.0-beta.2.5147851.tar.bz2  mips
# https://dl.ubnt.com/firmwares/edgemax/v2.0.x/GPL.ER-e300.v2.0.0-beta.2.5147851.tar.bz2  mips
# https://dl.ubnt.com/firmwares/edgemax/v2.0.x/GPL.ER-e1000.v2.0.0-beta.2.5147851.tar.bz2 mips

# The location of the router sources
ROUTER_SOURCES="https://dl.ubnt.com/firmwares/edgemax/v2.0.x/GPL.ER-e100.v2.0.0-beta.2.5147851.tar.bz2"

VERSION=stretch
CHROOT_ARCH=mips
if [[ $ROUTER_SOURCES == *"e50."* ]]; then
  CHROOT_ARCH=mipsel
fi
CHROOT_DIR=/tmp/$CHROOT_ARCH-chroot
MIRROR=http://ftp.us.debian.org/debian/

# Required dependencies to create the build environment
HOST_DEPENDENCIES="debootstrap qemu-user-static binfmt-support sbuild wget git tar bc texinfo flex bison"

# Required dependencies to build the system
GUEST_DEPENDENCIES="build-essential libmnl-dev libelf-dev pkg-config"

# The location of WireGuard
WIREGUARD_REPO="https://git.zx2c4.com/WireGuard"


# Install the required packages to make the build environment
sudo apt-get update
sudo apt-get install $HOST_DEPENDENCIES

# Make MIPS build environment in a chroot
sudo mkdir ${CHROOT_DIR}
sudo debootstrap --foreign --no-check-gpg --include=fakeroot,build-essential \
    --arch=${CHROOT_ARCH} ${VERSION} ${CHROOT_DIR} ${MIRROR}
sudo cp /usr/bin/qemu-mips-static ${CHROOT_DIR}/usr/bin/
sudo chroot ${CHROOT_DIR} ./debootstrap/debootstrap --second-stage
sudo sbuild-createchroot --arch=${CHROOT_ARCH} --foreign --setup-only \
    ${VERSION} ${CHROOT_DIR} ${MIRROR}
sudo chroot ${CHROOT_DIR} apt-get update
sudo chroot ${CHROOT_DIR} apt-get --allow-unauthenticated install \
    -qq -y ${GUEST_DEPENDENCIES}

# Get the sources to build
wget -qO- $ROUTER_SOURCES | tar -C $CHROOT_DIR -xj
tar -C $CHROOT_DIR/usr/src -xzf $CHROOT_DIR/source/kernel_*
git clone $WIREGUARD_REPO $CHROOT_DIR/WireGuard

# Get the Cavium SDK
wget -qO- https://github.com/Cavium-Open-Source-Distributions/OCTEON-SDK/blob/master/toolchain-build-54.tbz?raw=true | tar -xj -C $CHROOT_DIR/usr/src
patch -p0 -d $CHROOT_DIR/usr/src/toolchain/gits/gcc << EOF
--- ./gcc/doc/gcc.texi 2017-03-01 16:56:48.000000000 -0800
+++ ./gcc/doc/gcc.texi 2017-03-01 17:03:38.000000000 -0800
@@ -86,9 +86,15 @@
 @item GNU Press
 @tab Website: www.gnupress.org
 @item a division of the
-@tab General: @tex press@@gnu.org @end tex
+@tab General: 
+@tex 
+press@@gnu.org 
+@end tex
 @item Free Software Foundation
-@tab Orders:  @tex sales@@gnu.org @end tex
+@tab Orders:  
+@tex 
+sales@@gnu.org 
+@end tex
 @item 51 Franklin Street, Fifth Floor
 @tab Tel 617-542-5942
 @item Boston, MA 02110-1301 USA
@@ -108,6 +114,7 @@
 @sp 1
 @insertcopying
 @end titlepage
+
 @summarycontents
 @contents
 @page
EOF
# Build the toolchain - this fails, but builds GCC before it does, so it'll do
make -C $CHROOT_DIR/usr/src/toolchain RELEASE=1 linux || true

# Sort out the kernel config
VERSION=$( echo "$ROUTER_SOURCES" | grep -o 'ER-e[0-9]\{2,4\}' )
cp $CHROOT_DIR/usr/src/kernel/ubnt-config/$VERSION.config $CHROOT_DIR/usr/src/kernel/.config
PATH=$PATH:$CHROOT_DIR/usr/src/toolchain/minimal-mips64-octeon-linux-gnu/bin make -C $CHROOT_DIR/usr/src/kernel ARCH=$CHROOT_ARCH prepare scripts

# Build the kernel module
PATH=$PATH:$CHROOT_DIR/usr/src/toolchain/minimal-mips64-octeon-linux-gnu/bin make -C $CHROOT_DIR/WireGuard/src ARCH=$CHROOT_ARCH KENELDIR=$CHROOT_DIR/usr/src/kernel module

# Build the wg utility
sudo chroot ${CHROOT_DIR} bash -c "make -C WireGuard/src tools"

# Copy built binaries
cp $CHROOT_DIR/WireGuard/src/tools/wg $CHROOT_DIR/WireGuard/src/wireguard.ko .
