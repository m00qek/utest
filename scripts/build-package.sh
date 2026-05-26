#!/bin/sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)

SDK_ARCH=${SDK_ARCH:-x86-64}
SDK_VERSION=${SDK_VERSION:-24.10.6}
GIT_COMMIT=${GIT_COMMIT:-$(git -C "$ROOT" rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")}

PKG_NAME=$(grep '^PKG_NAME:=' "$ROOT/Makefile" | sed 's/^PKG_NAME:=//')
PKG_RELEASE=$(grep '^PKG_RELEASE:=' "$ROOT/Makefile" | sed 's/^PKG_RELEASE:=//')
PKG_SDK_DIR=/builder/package/$PKG_NAME

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

sed "s/^PKG_RELEASE:=.*/PKG_RELEASE:=${PKG_RELEASE}.${GIT_COMMIT}/" "$ROOT/Makefile" > "$TMPDIR/Makefile"

mkdir -p "$ROOT/bin"

docker run --rm \
    -v "$TMPDIR/Makefile:$PKG_SDK_DIR/Makefile:ro" \
    -v "$ROOT/src:$PKG_SDK_DIR/src:ro" \
    -v "$ROOT/LICENSE:$PKG_SDK_DIR/LICENSE:ro" \
    -v "$ROOT/bin:/builder/bin" \
    "openwrt/sdk:${SDK_ARCH}-${SDK_VERSION}" \
    bash -c "
        ./scripts/feeds update -a &&
        ./scripts/feeds install ucode &&
        make defconfig &&
        make package/$PKG_NAME/compile V=s
    "
