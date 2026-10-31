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

# Mozilla's reviewed iOS RemoteIO implementation, on its corresponding Cubeb pin.
# This is an audio backend candidate; compile/link gates do not prove audible runtime output.
cubeb_dir="$deps/src/cubeb-ios-mozilla"
[[ ! -e "$cubeb_dir" ]] || { echo 'Refusing an existing Cubeb source directory.' >&2; exit 8; }
git init -q "$cubeb_dir"
git -C "$cubeb_dir" config core.autocrlf false
git -C "$cubeb_dir" remote add origin https://github.com/mozilla/cubeb.git
git -C "$cubeb_dir" fetch --depth=1 origin 46906c7bba281a9cc277881e9cf9e32909f8dbf2
git -C "$cubeb_dir" checkout --detach -q FETCH_HEAD
python3 - "$cubeb_dir" "$source_dir" <<'PY_CUBEB_IOS_PATCH'
import base64,hashlib,pathlib,subprocess,sys,zlib
root=pathlib.Path(sys.argv[1]).resolve(strict=True)
citron=pathlib.Path(sys.argv[2]).resolve(strict=True)
sha=lambda b:hashlib.sha256(b).hexdigest()
assert subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()=='46906c7bba281a9cc277881e9cf9e32909f8dbf2'
assert not subprocess.check_output(['git','-C',str(root),'status','--porcelain']), 'Cubeb source is not pristine'
expected_before={'src/cubeb_audiounit.cpp': '4285a1ec1bb65e502443b82e1f988ed7af9eb2957c985fe2168574e17ffe8b06', 'CMakeLists.txt': '7b1a53117f2520471ef4293f9b8107e04f7d60021580418e8d4255c69d481dda', 'include/cubeb/cubeb.h': 'db3eb7d8d5c4d45b5d86f9c0524ff7d041f0cc596c39097c59cdfc82702b18a8', 'src/cubeb-internal.h': '50d2c0be2945136ff66666dbd8fcedc338f8f1d66eb2d9b09e09399193683ae8'}
for name,digest in expected_before.items():
 p=root/name
 assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(root)
 assert sha(p.read_bytes())==digest, 'Unexpected Cubeb source: '+name
official=zlib.decompress(base64.b64decode('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'))
cmake_patch='--- a/CMakeLists.txt\n+++ b/CMakeLists.txt\n@@ -12,6 +12,16 @@\n option(BUNDLE_SPEEX "Bundle the speex library" OFF)\n option(LAZY_LOAD_LIBS "Lazily load shared libraries" ON)\n option(USE_SANITIZERS "Use sanitizers" ON)\n+\n+# Native iPhoneOS builds use the vendored resampler, never a host pkg-config library.\n+if(CMAKE_SYSTEM_NAME STREQUAL "iOS")\n+  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)\n+  set(BUILD_TESTS OFF CACHE BOOL "" FORCE)\n+  set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)\n+  set(BUILD_RUST_LIBS OFF CACHE BOOL "" FORCE)\n+  set(USE_SANITIZERS OFF CACHE BOOL "" FORCE)\n+  set(BUNDLE_SPEEX ON CACHE BOOL "" FORCE)\n+endif()\n \n if(NOT CMAKE_BUILD_TYPE)\n   set(CMAKE_BUILD_TYPE "RelWithDebInfo" CACHE STRING\n@@ -252,11 +262,16 @@\n \n check_include_files(AudioUnit/AudioUnit.h USE_AUDIOUNIT)\n if(USE_AUDIOUNIT)\n-  target_sources(cubeb PRIVATE\n-    src/cubeb_audiounit.cpp\n-    src/cubeb_osx_run_loop.cpp)\n+  target_sources(cubeb PRIVATE src/cubeb_audiounit.cpp)\n   target_compile_definitions(cubeb PRIVATE USE_AUDIOUNIT)\n-  target_link_libraries(cubeb PRIVATE "-framework AudioUnit" "-framework CoreAudio" "-framework CoreServices")\n+  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")\n+    # iOS AudioUnit functions are exported by AudioToolbox; AudioUnit is not\n+    # a standalone linkable framework in the iPhoneOS SDK.\n+    target_link_libraries(cubeb PRIVATE "-framework AudioToolbox" "-framework CoreFoundation")\n+  else()\n+    target_sources(cubeb PRIVATE src/cubeb_osx_run_loop.cpp)\n+    target_link_libraries(cubeb PRIVATE "-framework AudioUnit" "-framework CoreAudio" "-framework CoreServices")\n+  endif()\n endif()\n \n check_include_files(audioclient.h USE_WASAPI)\n'
sink_patch='--- a/src/audio_core/sink/cubeb_sink.cpp\n+++ b/src/audio_core/sink/cubeb_sink.cpp\n@@ -377,6 +377,14 @@\n \n     u32 latency{0};\n     const auto latency_error = cubeb_get_min_latency(ctx, &params, &latency);\n+#if defined(CITRON_IOS)\n+    // Mozilla\'s iOS AudioUnit backend has no min-latency query. Still require\n+    // the real output stream_init below; an unsupported query is not success.\n+    if (latency_error == CUBEB_ERROR_NOT_SUPPORTED) {\n+        latency = TargetSampleCount * 2;\n+        LOG_INFO(Audio_Sink, "iOS min latency unavailable; testing a real Cubeb output stream.");\n+    } else\n+#endif\n     if (latency_error != CUBEB_OK) {\n         LOG_ERROR(Audio_Sink, "Cubeb could not get min latency, it is not suitable.");\n         return false;\n'
assert len(official)==46513 and sha(official)=='f2fad209e32258161619f6f8b548ca9f8bf94b9267e7c9cef6fd5ab66c2e60c5'
for candidate in (official,cmake_patch.encode('utf-8')):
 subprocess.run(['git','-C',str(root),'apply','--check','-'],input=candidate,check=True)
 subprocess.run(['git','-C',str(root),'apply','-'],input=candidate,check=True)
expected_after={'src/cubeb_audiounit.cpp': 'eb6e1712fae65376c401573a4255d2c17242a916c60f9c1040cb008339c7afca', 'CMakeLists.txt': '0a40703002f29081064f6ab0bb3d8c3167508b3ce1ea426c321b092aaf3eb6b2'}
for name,digest in expected_after.items():
 assert sha((root/name).read_bytes())==digest, 'Patched Cubeb SHA mismatch: '+name
assert set(subprocess.check_output(['git','-C',str(root),'diff','--name-only'],text=True).splitlines())=={'src/cubeb_audiounit.cpp','CMakeLists.txt'}
subprocess.run(['git','-C',str(root),'diff','--check'],check=True)
sink=citron/'src/audio_core/sink/cubeb_sink.cpp'
assert sha(sink.read_bytes())=='f3a81cba5c126bfe3a6c93578b3cfb45e88b6b8c58ec23367d9edd22adcb488a', 'Unexpected Citron Cubeb sink source'
subprocess.run(['git','-C',str(citron),'apply','--check','-'],input=sink_patch.encode('utf-8'),check=True)
subprocess.run(['git','-C',str(citron),'apply','-'],input=sink_patch.encode('utf-8'),check=True)
assert sha(sink.read_bytes())=='0491b7d21bfb951a2d397b764320e8e45e4d53a1024180d593cb5c0f4dffb932', 'Citron iOS suitability SHA mismatch'
license_sources={'LICENSE': '44c6b5ae5ec3fe2fbc608b00e6f4896f4d2d5c7e525fcbaa3eaa3cf2f3d5a983', 'subprojects/speex/arch.h': '2300bce68c588270cdc684dc7f01377e5e251529f4545d93771e111c56d51b0f', 'subprojects/speex/fixed_generic.h': '306ee7453677fa6067f16c79d358c6c90a9d3d008850b493cdaa59c07e6375c1', 'subprojects/speex/resample.c': '9c3a1c64ecf3750af82c980d01ea73d3682f73c332a580465d1e787e5c54cd00', 'subprojects/speex/resample_neon.h': '7d3fd7af9a1ddde22518b9c7b4419073b72b2dfa5be4c3bc8796992bc87b3da0', 'subprojects/speex/resample_sse.h': '5a196d8e2d8ab5c956f5252f09f5ddc55aee1f99b1341af3fa54a1f4c2157924', 'subprojects/speex/speex_config_types.h': '24e3ffbf29e5519611a48e5acb959645b01d166dcb4369380d5f776c3f53d4cd', 'subprojects/speex/speex_resampler.h': '7e439ec0dd30c32216b3ced17135f8992e5aaf53389d3f5996a7d900c453e65f', 'subprojects/speex/stack_alloc.h': 'e8a2fc0874942d2c7177475fcc141fdd0c0156200b8a4e7656d4a20313e2e569'}
for name,digest in license_sources.items():
 assert sha((root/name).read_bytes())==digest, 'Cubeb/Speex license source mismatch: '+name
print('Mozilla pinned iOS RemoteIO patch applied; real Citron output-stream suitability test retained.')
PY_CUBEB_IOS_PATCH
mkdir -p "$deps/licenses/cubeb/speex-source-with-license-notices"
cp "$cubeb_dir/LICENSE" "$deps/licenses/cubeb/LICENSE"
cp "$cubeb_dir/subprojects/speex/"*.h "$cubeb_dir/subprojects/speex/resample.c" \
    "$deps/licenses/cubeb/speex-source-with-license-notices/"

# Compile AND LINK the same patched backend for the real iPhoneOS SDK first.
# This executable is never run on the host or phone, and is never packaged in the IPA.
probe_source="$deps/src/cubeb-ios-link-probe"
probe_build="$deps/build/cubeb-ios-link-probe"
[[ ! -e "$probe_source" && ! -e "$probe_build" ]] || exit 8
mkdir -p "$probe_source"
cat > "$probe_source/CMakeLists.txt" <<'CMAKE_CUBEB_PROBE'
cmake_minimum_required(VERSION 3.24)
project(CubebIOSLinkProbe LANGUAGES C CXX)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS" OR NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
  message(FATAL_ERROR "The Cubeb probe requires native arm64 iPhoneOS")
endif()
add_subdirectory("${CUBEB_IOS_SOURCE}" cubeb)
get_target_property(_cubeb_definitions cubeb COMPILE_DEFINITIONS)
if(NOT "USE_AUDIOUNIT" IN_LIST _cubeb_definitions)
  message(FATAL_ERROR "The iPhoneOS probe must compile the real AudioUnit backend")
endif()
add_executable(cubeb-ios-link-probe probe.c)
target_link_libraries(cubeb-ios-link-probe PRIVATE cubeb)
set_target_properties(cubeb-ios-link-probe PROPERTIES
  MACOSX_BUNDLE FALSE XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
CMAKE_CUBEB_PROBE
cat > "$probe_source/probe.c" <<'C_CUBEB_PROBE'
#include <cubeb/cubeb.h>
int main(void) {
  cubeb *context = 0;
  uint32_t channels = 0;
  int result = cubeb_init(&context, "Citron iPhoneOS link probe (not run)", 0);
  if (result != CUBEB_OK) return 1;
  result = cubeb_get_max_channel_count(context, &channels);
  cubeb_destroy(context);
  return result == CUBEB_OK && channels > 0 ? 0 : 2;
}
C_CUBEB_PROBE
cmake -S "$probe_source" -B "$probe_build" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_TOOLS=OFF \
    -DBUILD_RUST_LIBS=OFF -DUSE_SANITIZERS=OFF -DBUNDLE_SPEEX=ON \
    -DCUBEB_IOS_SOURCE="$cubeb_dir"
cmake --build "$probe_build" --target cubeb-ios-link-probe --parallel 2
xcrun lipo "$probe_build/cubeb-ios-link-probe" -verify_arch arm64
xcrun vtool -show-build "$probe_build/cubeb-ios-link-probe" | tee "$probe_build/platform.txt"
grep -Eq 'platform[[:space:]]+IOS$' "$probe_build/platform.txt"
echo 'Patched Cubeb native iPhoneOS compile+link gate passed; executable NOT RUN.'

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
    -DCPM_cubeb_SOURCE="$cubeb_dir" \
    -DCITRON_IOS_DEPS_PREFIX="$deps/prefix" \
    -DCITRON_IOS_MOLTENVK_XCFRAMEWORK="$xcf" \
    -DCITRON_IOS_BUNDLE_IDENTIFIER=org.citron.experimental-ios \
    -DGLSLANGVALIDATOR="$(command -v glslangValidator)" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
cmake --build "$build_dir" --config Release --target CitronIOS --parallel 2 -- \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    EXPANDED_CODE_SIGN_IDENTITY=
