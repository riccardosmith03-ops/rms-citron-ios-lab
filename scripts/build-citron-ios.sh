#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'Mac/Xcode required.' >&2; exit 78; }
[[ $# == 3 ]] || { echo 'usage: build-citron-ios.sh <fresh-source> <deps-work> <new-build-dir>' >&2; exit 2; }
source_dir="$1"; deps="$2"; build_dir="$3"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
[[ ! -e "$build_dir" ]] || { echo 'Refusing to reuse the build directory.' >&2; exit 3; }
[[ "$(git -C "$source_dir" rev-parse HEAD)" == c3aa70f81e15ea97ee85b6a9a71cbf75d370851e ]]
[[ -z "$(git -C "$source_dir" status --porcelain)" ]] || { echo 'Source checkout is not clean.' >&2; exit 4; }
while IFS= read -r patch_name; do
    [[ -n "$patch_name" && "$patch_name" != \#* ]] || continue
    [[ "$patch_name" != */* && "$patch_name" == *.patch ]] || exit 5
    patch_file="$project_dir/patches/$patch_name"
    [[ -f "$patch_file" ]] || { echo "Missing candidate patch: $patch_name" >&2; exit 6; }
    git -C "$source_dir" apply --check "$patch_file"
    git -C "$source_dir" apply "$patch_file"
done < "$project_dir/patches/series.txt"

# Only this small submodule is needed here; CPM otherwise fetches an unpatched copy.
git -C "$source_dir" submodule update --init --depth=1 -- externals/oaknut
[[ "$(git -C "$source_dir/externals/oaknut" rev-parse HEAD)" == 94c726ce0338b054eb8cb5ea91de8fe6c19f4392 ]]
git -C "$source_dir/externals/oaknut" apply --check "$project_dir/patches/oaknut-jit-errors.patch"
git -C "$source_dir/externals/oaknut" apply "$project_dir/patches/oaknut-jit-errors.patch"

# This ownership test runs as a HOST Mac process, with iPhoneOS flags explicitly unset.
env -u SDKROOT -u IPHONEOS_DEPLOYMENT_TARGET -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    xcrun --sdk macosx clang++ -std=c++23 \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -I "$source_dir/src" "$project_dir/tests/virtual-buffer-ownership.cpp" \
    -o "$deps/build/ownership-host-test"
"$deps/build/ownership-host-test"

# CPM handles dependencies; these vendored files must still exist in the fixed tree.
for required in externals/dynarmic/CMakeLists.txt externals/glad/CMakeLists.txt \
    externals/stb/stb_dxt.cpp externals/tz/tz/tz.cpp \
    externals/demangle/ItaniumDemangle.cpp externals/FidelityFX-FSR/ffx-fsr/ffx_a.h; do
    [[ -f "$source_dir/$required" ]] || { echo "Missing required vendored source: $required" >&2; exit 7; }
done
xcf="$deps/moltenvk/MoltenVK/MoltenVK/dynamic/MoltenVK.xcframework"
[[ -f "$xcf/ios-arm64/MoltenVK.framework/MoltenVK" ]]
export CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
export CODE_SIGN_IDENTITY='' EXPANDED_CODE_SIGN_IDENTITY=''
cmake -S "$source_dir" -B "$build_dir" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \
    -DCITRON_USE_CPM=ON -DCITRON_CHECK_SUBMODULES=OFF \
    -DCITRON_IOS_DEPS_PREFIX="$deps/prefix" \
    -DCITRON_IOS_MOLTENVK_XCFRAMEWORK="$xcf" \
    -DCITRON_IOS_BUNDLE_IDENTIFIER=org.citron.experimental-ios \
    -DGLSLANGVALIDATOR="$(command -v glslangValidator)" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
cmake --build "$build_dir" --config Release --target CitronIOS --parallel 2 -- \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    EXPANDED_CODE_SIGN_IDENTITY=
