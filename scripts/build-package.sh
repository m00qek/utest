#!/bin/sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)

SDK_ARCH=${SDK_ARCH:-x86-64}
SDK_VERSION=${SDK_VERSION:-24.10.6}
GIT_COMMIT=${GIT_COMMIT:-$(git -C "$ROOT" rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")}

PKG_MAKEFILE="$ROOT/openwrt/ucode-utest/Makefile"
PKG_NAME=$(grep '^PKG_NAME:=' "$PKG_MAKEFILE" | sed 's/^PKG_NAME:=//')
PKG_VERSION=$(grep '^PKG_VERSION:=' "$PKG_MAKEFILE" | sed 's/^PKG_VERSION:=//')
PKG_SDK_DIR=/builder/package/$PKG_NAME

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# APK (25.x) requires version~githash format; opkg (24.x) tolerates it too
sed "s/^PKG_VERSION:=.*/PKG_VERSION:=${PKG_VERSION}~${GIT_COMMIT}/" "$PKG_MAKEFILE" > "$TMPDIR/Makefile"

mkdir -p "$ROOT/bin"
# The openwrt/sdk container below writes the built package into bin/ (mounted at
# /builder/bin) as its own build user, whose uid does not match the host user, so
# the directory must be group/other-writable for the build to drop its output.
# Scoped to this one throwaway output dir, not a broad permission change.
chmod 777 "$ROOT/bin"

docker run --rm \
    -v "$TMPDIR/Makefile:$PKG_SDK_DIR/Makefile:ro" \
    -v "$ROOT/src:$PKG_SDK_DIR/src:ro" \
    -v "$ROOT/LICENSE:$PKG_SDK_DIR/LICENSE:ro" \
    -v "$ROOT/bin:/builder/bin" \
    "openwrt/sdk:${SDK_ARCH}-${SDK_VERSION}" \
    bash -c "
        ./scripts/feeds update base &&
        ./scripts/feeds install ucode &&
        make defconfig &&
        make package/$PKG_NAME/compile V=s
    "
