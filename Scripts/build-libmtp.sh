#!/usr/bin/env bash
set -euo pipefail

LIBMTP_VERSION="1.1.21"
LIBUSB_VERSION="1.0.27"
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
BUILD_DIR="$REPO_ROOT/build/libmtp"
OUTPUT="$REPO_ROOT/Vendor/libmtp.xcframework"
OUTPUT_LIBUSB="$REPO_ROOT/Vendor/libusb.xcframework"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }
}
require curl
require tar
require pkg-config

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f "libusb-${LIBUSB_VERSION}.tar.bz2" ]; then
  curl -L -o "libusb-${LIBUSB_VERSION}.tar.bz2" \
    "https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2"
fi
if [ ! -d "libusb-${LIBUSB_VERSION}" ]; then
  tar xjf "libusb-${LIBUSB_VERSION}.tar.bz2"
fi

if [ ! -f "libmtp-${LIBMTP_VERSION}.tar.gz" ]; then
  curl -L -o "libmtp-${LIBMTP_VERSION}.tar.gz" \
    "https://sourceforge.net/projects/libmtp/files/libmtp/${LIBMTP_VERSION}/libmtp-${LIBMTP_VERSION}.tar.gz/download"
fi
if [ ! -d "libmtp-${LIBMTP_VERSION}" ]; then
  tar xzf "libmtp-${LIBMTP_VERSION}.tar.gz"
fi

build_for_arch() {
  local ARCH="$1"
  local PREFIX="$BUILD_DIR/install-${ARCH}"
  local CC_FLAGS="-arch ${ARCH} -mmacosx-version-min=15.4"
  # autoconf uses aarch64 not arm64
  local AUTOCONF_HOST
  if [ "$ARCH" = "arm64" ]; then
    AUTOCONF_HOST="aarch64-apple-darwin"
  else
    AUTOCONF_HOST="${ARCH}-apple-darwin"
  fi

  pushd "libusb-${LIBUSB_VERSION}"
  make distclean 2>/dev/null || true
  CFLAGS="$CC_FLAGS" LDFLAGS="$CC_FLAGS" ./configure \
    --prefix="$PREFIX" \
    --host="${AUTOCONF_HOST}" \
    --enable-shared --disable-static --disable-udev
  make -j"$(sysctl -n hw.ncpu)"
  make install
  popd

  pushd "libmtp-${LIBMTP_VERSION}"
  make distclean 2>/dev/null || true
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
  CFLAGS="$CC_FLAGS -I$PREFIX/include" \
  LDFLAGS="$CC_FLAGS -L$PREFIX/lib" \
    ./configure \
      --prefix="$PREFIX" \
      --host="${AUTOCONF_HOST}" \
      --enable-shared --disable-static \
      --without-doxygen
  make -j"$(sysctl -n hw.ncpu)"
  make install
  popd
}

create_xcframeworks() {
  local LIBMTP_DYLIB="$1"   # path to universal libmtp dylib
  local LIBUSB_DYLIB="$2"   # path to universal libusb dylib

  # Fix install names on universal libusb
  install_name_tool -id "@rpath/libusb-1.0.0.dylib" "$LIBUSB_DYLIB"

  # Fix libmtp's references to libusb from absolute build paths to @rpath
  local OLD_ARM64
  local OLD_X86
  OLD_ARM64=$(otool -L "$LIBMTP_DYLIB" | grep "install-arm64.*libusb" | awk '{print $1}' | head -1)
  OLD_X86=$(otool -L "$LIBMTP_DYLIB" | grep "install-x86_64.*libusb" | awk '{print $1}' | head -1)
  [ -n "$OLD_ARM64" ] && install_name_tool -change "$OLD_ARM64" "@rpath/libusb-1.0.0.dylib" "$LIBMTP_DYLIB"
  [ -n "$OLD_X86" ]   && install_name_tool -change "$OLD_X86"   "@rpath/libusb-1.0.0.dylib" "$LIBMTP_DYLIB"

  echo "==> libmtp linkage after fix:"
  otool -L "$LIBMTP_DYLIB" | head -8

  # Create libmtp xcframework
  rm -rf "$OUTPUT"
  xcodebuild -create-xcframework \
    -library "$LIBMTP_DYLIB" \
    -headers "$BUILD_DIR/install-arm64/include" \
    -output "$OUTPUT"
  echo "Built $OUTPUT"

  # Create libusb xcframework
  rm -rf "$OUTPUT_LIBUSB"
  xcodebuild -create-xcframework \
    -library "$LIBUSB_DYLIB" \
    -output "$OUTPUT_LIBUSB"
  echo "Built $OUTPUT_LIBUSB"
}

# Detect host architecture
HOST_ARCH="$(uname -m)"
echo "Host architecture: $HOST_ARCH"

# Build arm64 (primary target — Apple Silicon, required for FSKit on macOS 15.4+)
echo "==> Building arm64..."
build_for_arch arm64

# Attempt x86_64 build; skip if cross-compilation fails on Apple Silicon
if [ "$HOST_ARCH" = "arm64" ]; then
  echo "==> Attempting x86_64 build (cross-compilation on Apple Silicon)..."
  if build_for_arch x86_64 2>&1; then
    echo "==> x86_64 build succeeded, creating universal binaries"
    mkdir -p "$BUILD_DIR/universal/lib"
    lipo -create \
      "$BUILD_DIR/install-arm64/lib/libmtp.9.dylib" \
      "$BUILD_DIR/install-x86_64/lib/libmtp.9.dylib" \
      -output "$BUILD_DIR/universal/lib/libmtp.dylib"
    install_name_tool -id "@rpath/libmtp.dylib" "$BUILD_DIR/universal/lib/libmtp.dylib"

    lipo -create \
      "$BUILD_DIR/install-arm64/lib/libusb-1.0.0.dylib" \
      "$BUILD_DIR/install-x86_64/lib/libusb-1.0.0.dylib" \
      -output "$BUILD_DIR/universal/lib/libusb-1.0.0.dylib"

    create_xcframeworks \
      "$BUILD_DIR/universal/lib/libmtp.dylib" \
      "$BUILD_DIR/universal/lib/libusb-1.0.0.dylib"
  else
    echo "==> x86_64 cross-compilation failed (expected on Apple Silicon). Shipping arm64-only."
    mkdir -p "$BUILD_DIR/arm64only/lib"
    cp "$BUILD_DIR/install-arm64/lib/libmtp.9.dylib" "$BUILD_DIR/arm64only/lib/libmtp.dylib"
    install_name_tool -id "@rpath/libmtp.dylib" "$BUILD_DIR/arm64only/lib/libmtp.dylib"

    cp "$BUILD_DIR/install-arm64/lib/libusb-1.0.0.dylib" "$BUILD_DIR/arm64only/lib/libusb-1.0.0.dylib"

    create_xcframeworks \
      "$BUILD_DIR/arm64only/lib/libmtp.dylib" \
      "$BUILD_DIR/arm64only/lib/libusb-1.0.0.dylib"
  fi
else
  # On x86_64 host, also build x86_64 and create universal
  echo "==> Building x86_64..."
  build_for_arch x86_64
  mkdir -p "$BUILD_DIR/universal/lib"
  lipo -create \
    "$BUILD_DIR/install-arm64/lib/libmtp.9.dylib" \
    "$BUILD_DIR/install-x86_64/lib/libmtp.9.dylib" \
    -output "$BUILD_DIR/universal/lib/libmtp.dylib"
  install_name_tool -id "@rpath/libmtp.dylib" "$BUILD_DIR/universal/lib/libmtp.dylib"

  lipo -create \
    "$BUILD_DIR/install-arm64/lib/libusb-1.0.0.dylib" \
    "$BUILD_DIR/install-x86_64/lib/libusb-1.0.0.dylib" \
    -output "$BUILD_DIR/universal/lib/libusb-1.0.0.dylib"

  create_xcframeworks \
    "$BUILD_DIR/universal/lib/libmtp.dylib" \
    "$BUILD_DIR/universal/lib/libusb-1.0.0.dylib"
fi
