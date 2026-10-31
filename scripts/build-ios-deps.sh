#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build-only script. No signing accounts, device installation, games or keys.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'A Mac/Xcode iPhoneOS toolchain is required.' >&2; exit 78; }
[[ $# == 1 ]] || { echo 'usage: build-ios-deps.sh <new-work-root>' >&2; exit 2; }
work="$1"
[[ ! -e "$work" ]] || { echo 'Refusing to reuse an existing dependency workspace.' >&2; exit 3; }
mkdir -p "$work/downloads" "$work/src" "$work/build" "$work/prefix" "$work/licenses"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
cc="$(xcrun --sdk iphoneos --find clang)"
cxx="$(xcrun --sdk iphoneos --find clang++)"
ar="$(xcrun --sdk iphoneos --find ar)"
ranlib="$(xcrun --sdk iphoneos --find ranlib)"
minimum=17.4
export IPHONEOS_DEPLOYMENT_TARGET="$minimum"

fetch_checked() {
    local url="$1" file="$2" digest="$3"
    curl --fail --location --retry 2 --connect-timeout 20 --max-time 300 "$url" -o "$file"
    printf '%s  %s\n' "$digest" "$file" | shasum -a 256 --check
}

fetch_checked \
  'https://codeload.github.com/openssl/openssl/tar.gz/a26d85337dbdcd33c971f38eb3fa5150e75cea87' \
  "$work/downloads/openssl.tar.gz" '41ff751b3577061c4f2cde2e9270d24181461a696c9fa7b2729c2d6b103f0520'
fetch_checked \
  'https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/140fd653aed8cad774f991ba083e2d01e86420c7' \
  "$work/downloads/ffmpeg.tar.gz" '5c4a9e51e706b8deba835f02ea70e1e1101187f601adae72b36ec2b17b6f15be'
fetch_checked \
  'https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-ios.tar' \
  "$work/downloads/moltenvk.tar" 'b5d947b1660e6e9fed40b9cd2387e160aaab9e80b775c0cef7e14059405178c1'
mkdir "$work/src/openssl" "$work/src/ffmpeg" "$work/moltenvk"
tar -xzf "$work/downloads/openssl.tar.gz" --strip-components=1 -C "$work/src/openssl"
tar -xzf "$work/downloads/ffmpeg.tar.gz" --strip-components=1 -C "$work/src/ffmpeg"
tar -xf "$work/downloads/moltenvk.tar" -C "$work/moltenvk"

mkdir "$work/build/openssl"
(
    cd "$work/build/openssl"
    perl "$work/src/openssl/Configure" ios64-xcrun no-shared no-dso no-tests \
        --prefix="$work/prefix/openssl" --libdir=lib \
        "-miphoneos-version-min=$minimum"
    make -j2 build_libs
    make install_sw
)

mkdir "$work/build/ffmpeg"
(
    cd "$work/build/ffmpeg"
    "$work/src/ffmpeg/configure" \
        --prefix="$work/prefix/ffmpeg" --target-os=darwin --arch=arm64 \
        --enable-cross-compile --sysroot="$sdk" --cc="$cc" --cxx="$cxx" \
        --ar="$ar" --ranlib="$ranlib" \
        --extra-cflags="-target arm64-apple-ios$minimum -arch arm64 -miphoneos-version-min=$minimum" \
        --extra-ldflags="-target arm64-apple-ios$minimum -arch arm64 -miphoneos-version-min=$minimum" \
        --enable-static --disable-shared --enable-pic --disable-programs \
        --disable-doc --disable-debug --disable-network --disable-autodetect \
        --disable-avdevice --disable-avformat \
        --disable-encoders --disable-muxers --disable-demuxers --disable-protocols \
        --disable-hwaccels --disable-videotoolbox --disable-audiotoolbox \
        --disable-decoders --enable-decoder=h264,hevc,vp8,vp9,av1 \
        --disable-parsers --enable-parser=h264,hevc,vp8,vp9,av1 \
        --enable-avcodec --enable-avfilter --enable-avutil --enable-swscale --enable-swresample
    make -j2
    make install
)

cp "$work/src/openssl/LICENSE.txt" "$work/licenses/OpenSSL-Apache-2.0.txt"
cp "$work/src/ffmpeg/COPYING.LGPLv2.1" "$work/licenses/FFmpeg-LGPL-2.1.txt"
cp "$work/moltenvk/MoltenVK/LICENSE" "$work/licenses/MoltenVK-Apache-2.0.txt"
find "$work/prefix" -name '*.a' -type f -exec xcrun lipo -verify_arch arm64 '{}' ';'
echo "iPhoneOS dependencies built at $work/prefix; runtime compatibility is untested."
