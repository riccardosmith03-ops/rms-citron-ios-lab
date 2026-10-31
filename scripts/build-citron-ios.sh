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

# Patch only the verified third-party API; CPM must consume this exact source.
sirit_dir="$deps/src/sirit-quad-swap"
[[ ! -e "$sirit_dir" ]] || { echo 'Refusing an existing Sirit source directory.' >&2; exit 8; }
git init -q "$sirit_dir"
git -C "$sirit_dir" config core.autocrlf false
git -C "$sirit_dir" remote add origin https://github.com/yuzu-mirror/sirit.git
git -C "$sirit_dir" fetch --depth=1 origin ab75463999f4f3291976b079d42d52ee91eebf3f
git -C "$sirit_dir" checkout --detach -q FETCH_HEAD
python3 - "$sirit_dir" <<'PY_SIRIT_QUAD_PATCH'
import hashlib,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]).resolve(strict=True)
expected_before={'include/sirit/sirit.h': '943e562be42e790f65ec2c011a77d5cecd4089d9ff3c29c3c0d9b2f44d52e2c3', 'src/instructions/group.cpp': '8601bf3b67c937c72744296bbad8dbe92bec8dc3e0bcd9a9fbe3063a28a69aac'}
expected_after={'include/sirit/sirit.h': '662acf6f3da25e8e0ce630f7bd8c18b45a65d1b8e9c4c3fec46648ee64e5dd1f', 'src/instructions/group.cpp': 'd4fa2e0a1687f3bc5b684019440e40a16b9e6f81a6a4b6f45dbd05e25ce110c5'}
patch="--- a/include/sirit/sirit.h\n+++ b/include/sirit/sirit.h\n@@ -1179,6 +1179,9 @@\n     /// group xor'ed with mask.\n     Id OpGroupNonUniformShuffleXor(Id result_type, Id scope, Id value, Id mask);\n \n+    /// Quad swap; direction is an unsigned constant Id with value 0, 1, or 2.\n+    Id OpGroupNonUniformQuadSwap(Id result_type, Id scope, Id value, Id direction);\n+\n     /// Evaluates a predicate for all active invocations in the group, resulting in\n     /// true if predicate evaluates to true for all active invocations in the\n     /// group, otherwise the result is false.\n--- a/src/instructions/group.cpp\n+++ b/src/instructions/group.cpp\n@@ -65,6 +65,12 @@\n                  << mask << EndOp{};\n }\n \n+Id Module::OpGroupNonUniformQuadSwap(Id result_type, Id scope, Id value, Id direction) {\n+    code->Reserve(6);\n+    return *code << OpId{spv::Op::OpGroupNonUniformQuadSwap, result_type} << scope << value\n+                 << direction << EndOp{};\n+}\n+\n Id Module::OpGroupNonUniformAll(Id result_type, Id scope, Id predicate) {\n    code->Reserve(5);\n    return *code << OpId{spv::Op::OpGroupNonUniformAll, result_type} << scope << predicate << EndOp{};\n"
assert subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()=='ab75463999f4f3291976b079d42d52ee91eebf3f'
assert not subprocess.check_output(['git','-C',str(root),'status','--porcelain']), 'Sirit source is not pristine'
for name,digest in expected_before.items():
 p=root/name
 assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(root)
 assert hashlib.sha256(p.read_bytes()).hexdigest()==digest, 'Unexpected Sirit source: '+name
assert hashlib.sha256(patch.encode('utf-8')).hexdigest()=='4ee183bfe1c5654389cddd03910c0844f1c1f5d1c5f7de5cf379e93de8362806'
subprocess.run(['git','-C',str(root),'apply','--check','-'],input=patch.encode('utf-8'),check=True)
subprocess.run(['git','-C',str(root),'apply','-'],input=patch.encode('utf-8'),check=True)
for name,digest in expected_after.items():
 assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest, 'Patched Sirit SHA mismatch: '+name
changed=set(subprocess.check_output(['git','-C',str(root),'diff','--name-only'],text=True).splitlines())
assert changed==set(expected_after), 'Unexpected Sirit modification'
subprocess.run(['git','-C',str(root),'diff','--check'],check=True)
print('Pinned Sirit quad-swap opcode366 builder patched; shader semantics and feature gates preserved.')
PY_SIRIT_QUAD_PATCH

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
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DBOOST_CONTEXT_ARCHITECTURE=arm64 -DBOOST_CONTEXT_ABI=aapcs \
    -DBUILD_TESTING=OFF -DDYNARMIC_TESTS=OFF \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \
    -DCITRON_USE_CPM=ON -DCITRON_CHECK_SUBMODULES=OFF \
    -DCPM_sirit_SOURCE="$sirit_dir" \
    -DCITRON_IOS_DEPS_PREFIX="$deps/prefix" \
    -DCITRON_IOS_MOLTENVK_XCFRAMEWORK="$xcf" \
    -DCITRON_IOS_BUNDLE_IDENTIFIER=org.citron.experimental-ios \
    -DGLSLANGVALIDATOR="$(command -v glslangValidator)" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
cmake --build "$build_dir" --config Release --target CitronIOS --parallel 2 -- \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    EXPANDED_CODE_SIGN_IDENTITY=
