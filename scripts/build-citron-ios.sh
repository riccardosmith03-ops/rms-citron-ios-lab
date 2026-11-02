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
# Own anonymous guest-backing lazy-zero candidate: exact pinned source only.
python3 - "$source_dir" <<'PY_IOS_LAZY_ZERO_BEFORE'
import hashlib,pathlib,sys
r=pathlib.Path(sys.argv[1])
assert hashlib.sha256((r/'src/common/host_memory.cpp').read_bytes()).hexdigest()=='58708c10cf1d09a6ed49b41db2811cec294daab0ba53543fcd2a5d94284677f1','Unexpected guest-backing source'
assert not (r/'src/common/ios_lazy_zero.h').exists(),'Lazy-zero helper already exists'
PY_IOS_LAZY_ZERO_BEFORE
# Bind every probe input to the fixed upstream archive.
python3 - "$source_dir" <<'PY_IOS_RENDER_PROBE_BEFORE'
import hashlib,pathlib,sys
r=pathlib.Path(sys.argv[1]).resolve(strict=True)
assert not (r/'src/common/ios_render_probe.h').exists(),'Render probe already exists'
for name,digest in {'src/ios/native.cpp': 'f8f0785c8e2cf29daeb90413aa6a1a6a03a4c8d5d953b3437a52a99ad23a9a63', 'src/ios/emu_window/emu_window.cpp': 'd0170574e314bdd3ce3557ef1f32a839158bb277a8f42d7eaaa4f0f7d6a55619', 'src/core/hle/service/nvdrv/devices/nvhost_gpu.cpp': 'c0c993cce4195a5fdd55f37336c7619b4a32596c31055b29d0969b3cd7cf31bf', 'src/video_core/gpu_thread.cpp': '75ff6a99b796c0d9e68c2f1d50b28e38a7b6d662fc6c9a1248ba8177fd9438d6', 'src/core/hle/service/nvnflinger/buffer_queue_producer.cpp': '27364ed5ee8c8498b21812c8323d03e0a07bec15d568051696f82315e3f86844', 'src/core/hle/service/nvnflinger/hardware_composer.cpp': '992b598ed983d54ab321fa5e6efb786addd8b18b3d69e4bcbee774b122b18a88', 'src/video_core/gpu.cpp': 'e64963691c095af20b2ba1b8b816cc84134ac83ac7ba3a083d592f83eda3e616', 'src/video_core/renderer_vulkan/renderer_vulkan.cpp': '4bab97368bafd6523a4351a74efbfa6b466e6342939213c7da38ac7d9e3b879c', 'src/video_core/renderer_vulkan/vk_present_manager.cpp': 'd790f6631b9ac0dde726c89d917df90444f7f6941f853cc8e01ee510f3c09f36', 'src/core/device_memory_manager.inc': '6b0fb8f1114c63646f8c467fa6461788741193fc3e63fbed974c34e83570a538', 'src/ios/jit_icache_callbacks_ios.cpp': '290474791f6d28c6502bbe4c3985ed7c0f01ff3682e15a84fd6903fcd4b2e4d8'}.items():
 p=r/name
 assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(r)
 assert hashlib.sha256(p.read_bytes()).hexdigest()==digest,'Unexpected render-probe source: '+name
PY_IOS_RENDER_PROBE_BEFORE

while IFS= read -r patch_name; do
    [[ -n "$patch_name" && "$patch_name" != \#* ]] || continue
    [[ "$patch_name" != */* && "$patch_name" == *.patch ]] || exit 5
    patch_file="$project_dir/patches/$patch_name"
    [[ -f "$patch_file" ]] || { echo "Missing candidate patch: $patch_name" >&2; exit 6; }
    git -C "$source_dir" apply --check "$patch_file"
    git -C "$source_dir" apply "$patch_file"
done < "$project_dir/patches/series.txt"

# Bind the complete numeric-only probe and hook sources before building.
python3 - "$source_dir" <<'PY_IOS_RENDER_PROBE_AFTER'
import hashlib,pathlib,sys
r=pathlib.Path(sys.argv[1]).resolve(strict=True)
for name,digest in {'src/ios/native.cpp': '4d7cf88f177aec469c72ed651ed903025494d5aee6a2ed064a29c6e1dd11177e', 'src/ios/emu_window/emu_window.cpp': 'f12d486c2bc2c6744ef4b58fcd68f6b9fa3c13b618cf2d4cce11d3d09291410a', 'src/core/hle/service/nvdrv/devices/nvhost_gpu.cpp': 'b4100833090b1c8069eb56b026de4935e3b9cbd8258f97bc8cf96eb342278308', 'src/video_core/gpu_thread.cpp': '68a0dae863b143765d968598c760193b4f0d034e46590c970faa16b40ca18d14', 'src/core/hle/service/nvnflinger/buffer_queue_producer.cpp': 'a308d2b1f86d40ef0739a0a9043a4b48fe24b20f5c77deb61f47c1253b029b94', 'src/core/hle/service/nvnflinger/hardware_composer.cpp': '16452f72b00f005d5c98abfa24fc2e2bcf8ef9eaa06abfbd5734c57c417efa6d', 'src/video_core/gpu.cpp': 'bf00efab550e4528d07b639a2a886e1f99ee34cfa5910c17a8951c8c2fa885ee', 'src/video_core/renderer_vulkan/renderer_vulkan.cpp': '5fac00a19a35dd09554e7a255257eabeecaef2415a65b9f41c67ab69055a9578', 'src/video_core/renderer_vulkan/vk_present_manager.cpp': '2b9eb2464bc3eb4a4683c0d0b5a9a6522b78efdfaae7da95a22dd24860d83108', 'src/core/device_memory_manager.inc': '9202e645c29abfbf8c0ae81cec8b5445d79b8d84f45ff77219173a3e14772509', 'src/ios/jit_icache_callbacks_ios.cpp': '5a06b39329d23a189fc40fbb454b2b86dd1b6ec117d3a55e5fb2b5ae1c64f939', 'src/common/ios_render_probe.h': '515af9202b1513590f661029c0f875dc0adcb813b0c417ab7ee18f38a1ebcd21'}.items():
 p=r/name
 assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(r)
 assert hashlib.sha256(p.read_bytes()).hexdigest()==digest,'Unexpected render-probe source: '+name
PY_IOS_RENDER_PROBE_AFTER


# Bind the embedded lazy-zero helper and its owning generic backend before compiling.
python3 - "$source_dir" <<'PY_IOS_LAZY_ZERO_AFTER'
import hashlib,pathlib,sys
r=pathlib.Path(sys.argv[1])
for name,digest in {'src/common/host_memory.cpp':'47b0545cc70e114b6fbb50ded0772bbf1abf93f68fcd6f21decc833908a688e9','src/common/ios_lazy_zero.h':'115672dc8bb320631fb7dfdf226742358b66ac64d2cbe4211f5ebaa197521b4e'}.items():
 assert hashlib.sha256((r/name).read_bytes()).hexdigest()==digest,'Unexpected lazy-zero source: '+name
PY_IOS_LAZY_ZERO_AFTER


# Use the pinned public filesystem initialization entrypoint on iOS.
python3 - "$source_dir" <<'PY_IOS_CONTENT_SYSTEM_API'
import hashlib,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]).resolve(strict=True)
expected_api={'src/core/hle/service/filesystem/filesystem.h': '809236450ccbeade9b347eef9e19a13c54d8ae60c45d78aee6631a196c47a826', 'src/core/hle/service/filesystem/filesystem.cpp': '8f42ba0d6e1c17b7c1b9fa1ac23103a1c878e25b643bdd1eede4241745d1f529'}
for name,digest in expected_api.items():
 p=root/name
 assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(root)
 assert hashlib.sha256(p.read_bytes()).hexdigest()==digest, 'Unexpected pinned filesystem API: '+name
p=root/'src/ios/native.cpp'
assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(root)
assert hashlib.sha256(p.read_bytes()).hexdigest()=='4d7cf88f177aec469c72ed651ed903025494d5aee6a2ed064a29c6e1dd11177e', 'Unexpected post-series iOS native source'
patch='--- a/src/ios/native.cpp\n+++ b/src/ios/native.cpp\n@@ -407,7 +407,7 @@\n     system.SetContentProvider(std::make_unique<FileSys::ContentProviderUnion>());\n     system.RegisterContentProvider(FileSys::ContentProviderUnionSlot::FrontendManual,\n                                    manual_provider.get());\n-    system.GetFileSystemController().CreateFactories(*vfs);\n+    system.GetFileSystemController().InitializeContentSystem(*vfs);\n }\n \n Core::SystemResultStatus EmulationSession::InitializeEmulation(const std::string& filepath,\n'
assert hashlib.sha256(patch.encode('utf-8')).hexdigest()=='2bb101b99ea16a2e8c00d80c9fd0962e12335acfbe7ea438e9b8c5e270146726', 'Embedded iOS content-system patch changed'
subprocess.run(['git','-c','core.autocrlf=false','-C',str(root),'apply','--check','-'],input=patch.encode('utf-8'),check=True)
subprocess.run(['git','-c','core.autocrlf=false','-C',str(root),'apply','-'],input=patch.encode('utf-8'),check=True)
assert hashlib.sha256(p.read_bytes()).hexdigest()=='fed6ea7cbc37380458ab6a908b9bfb9192d2d0dac7ac0ae03422c206353c444e', 'Patched iOS native source differs'
print('iOS content initialization now uses the pinned public entrypoint and its default overwrite policy; lifecycle and platform initialization stage preserved.')
PY_IOS_CONTENT_SYSTEM_API

# Match iOS touch bounds to the pinned frontend framebuffer-layout API.
python3 - "$source_dir" <<'PY_IOS_WINDOW_LAYOUT_API'
import hashlib,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]).resolve(strict=True)
expected_api={'src/core/frontend/emu_window.h': 'b0d2f6244156fe80b65c94e508a41fa81ae5d7214c13babc949706ab0100b3b5', 'src/core/frontend/framebuffer_layout.h': 'fb61473517fcaf093dbaa29ad25d5472d8c65af6fa6a1c7f3d0840c83668baba'}
for name,digest in expected_api.items():
 p=root/name
 assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(root)
 assert hashlib.sha256(p.read_bytes()).hexdigest()==digest, 'Unexpected pinned framebuffer API: '+name
p=root/'src/ios/emu_window/emu_window.cpp'
assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(root)
assert hashlib.sha256(p.read_bytes()).hexdigest()=='f12d486c2bc2c6744ef4b58fcd68f6b9fa3c13b618cf2d4cce11d3d09291410a', 'Unexpected post-series iOS window source'
patch='--- a/src/ios/emu_window/emu_window.cpp\n+++ b/src/ios/emu_window/emu_window.cpp\n@@ -21,16 +21,16 @@\n }\n \n void EmuWindow_IOS::OnTouchPressed(int id, float x, float y) {\n-    const u32 clamped_x = static_cast<u32>(std::clamp(x, 0.0f, static_cast<float>(Layout().ScreenWidth)));\n-    const u32 clamped_y = static_cast<u32>(std::clamp(y, 0.0f, static_cast<float>(Layout().ScreenHeight)));\n+    const u32 clamped_x = static_cast<u32>(std::clamp(x, 0.0f, static_cast<float>(GetFramebufferLayout().width)));\n+    const u32 clamped_y = static_cast<u32>(std::clamp(y, 0.0f, static_cast<float>(GetFramebufferLayout().height)));\n     const auto [touch_x, touch_y] = MapToTouchScreen(clamped_x, clamped_y);\n     IOS::EmulationSession::GetInstance().GetInputSubsystem().GetTouchScreen()->TouchPressed(\n         touch_x, touch_y, id);\n }\n \n void EmuWindow_IOS::OnTouchMoved(int id, float x, float y) {\n-    const u32 clamped_x = static_cast<u32>(std::clamp(x, 0.0f, static_cast<float>(Layout().ScreenWidth)));\n-    const u32 clamped_y = static_cast<u32>(std::clamp(y, 0.0f, static_cast<float>(Layout().ScreenHeight)));\n+    const u32 clamped_x = static_cast<u32>(std::clamp(x, 0.0f, static_cast<float>(GetFramebufferLayout().width)));\n+    const u32 clamped_y = static_cast<u32>(std::clamp(y, 0.0f, static_cast<float>(GetFramebufferLayout().height)));\n     const auto [touch_x, touch_y] = MapToTouchScreen(clamped_x, clamped_y);\n     IOS::EmulationSession::GetInstance().GetInputSubsystem().GetTouchScreen()->TouchMoved(touch_x,\n                                                                                          touch_y,\n'
assert hashlib.sha256(patch.encode('utf-8')).hexdigest()=='77561bfa3a791bcd8669bb59d995b2cb759993f109d22e3aa3899aa6dba7bdaf', 'Embedded iOS window patch changed'
subprocess.run(['git','-c','core.autocrlf=false','-C',str(root),'apply','--check','-'],input=patch.encode('utf-8'),check=True)
subprocess.run(['git','-c','core.autocrlf=false','-C',str(root),'apply','-'],input=patch.encode('utf-8'),check=True)
assert hashlib.sha256(p.read_bytes()).hexdigest()=='f4a0548477ee521a07be4bc26599cd6837aad4a7059e7f4ca84e33557d5c55f9', 'Patched iOS window source differs'
print('iOS touch bounds now use the pinned framebuffer width/height getter; surface updates and touch mapping preserved.')
PY_IOS_WINDOW_LAYOUT_API

# Preserve the legacy Boost::headers consumers, including nested numeric_conversion.
python3 - "$source_dir" <<'PY_BOOST_NUMERIC_INTERFACE'
import hashlib,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]).resolve(strict=True)
p=root/'CMakeModules/dependencies.cmake'
assert not p.is_symlink() and p.resolve(strict=True).is_relative_to(root)
assert hashlib.sha256(p.read_bytes()).hexdigest()=='b430edfd062d4812851ed344cc491c32deba17727cef208548ccb0c684f3e3c2', 'Unexpected post-series Boost dependency source'
patch='--- a/CMakeModules/dependencies.cmake\n+++ b/CMakeModules/dependencies.cmake\n@@ -78,6 +78,22 @@\n         get_target_property(_boost_headers_aliased "${_boost_headers_target}" ALIASED_TARGET)\n         if (_boost_headers_aliased)\n             set(_boost_headers_target "${_boost_headers_aliased}")\n+        endif()\n+        if (CITRON_IOS)\n+            # numeric/conversion is nested; expose its complete module interface.\n+            if (NOT TARGET Boost::numeric_conversion)\n+                message(FATAL_ERROR "Pinned Boost numeric_conversion target is missing")\n+            endif()\n+            set(_boost_numeric_cast\n+                "${Boost_SOURCE_DIR}/libs/numeric/conversion/include/boost/numeric/conversion/cast.hpp")\n+            if (NOT EXISTS "${_boost_numeric_cast}")\n+                message(FATAL_ERROR "Pinned Boost numeric_conversion header is missing")\n+            endif()\n+            file(SHA256 "${_boost_numeric_cast}" _boost_numeric_cast_sha256)\n+            if (NOT _boost_numeric_cast_sha256 STREQUAL "27b29239caffcc6d022e9241660d54ce9d6a0ed173992fb67b212d4f0f471348")\n+                message(FATAL_ERROR "Pinned Boost numeric_conversion header SHA256 differs")\n+            endif()\n+            target_link_libraries("${_boost_headers_target}" INTERFACE Boost::numeric_conversion)\n         endif()\n         file(GLOB _boost_header_include_dirs LIST_DIRECTORIES true\n             "${Boost_SOURCE_DIR}/libs/*/include")\n'
assert hashlib.sha256(patch.encode('utf-8')).hexdigest()=='88cd2e4c5352921483a5ea94c71b24346648ccef0ba171a63299eb081ea8dc6e', 'Embedded Boost dependency patch changed'
subprocess.run(['git','-c','core.autocrlf=false','-C',str(root),'apply','--check','-'],input=patch.encode('utf-8'),check=True)
subprocess.run(['git','-c','core.autocrlf=false','-C',str(root),'apply','-'],input=patch.encode('utf-8'),check=True)
assert hashlib.sha256(p.read_bytes()).hexdigest()=='9d1eff350256fd9f7ccecf739c47b541c539717bacef6949d072fc122a65c3d7', 'Patched Boost dependency source differs'
print('Pinned Boost numeric_conversion complete interface attached to legacy headers; no Boost version or runtime change.')
PY_BOOST_NUMERIC_INTERFACE

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
official=zlib.decompress(base64.b64decode('eNrtPe1W20iW/3mKCn2asY0w/gADccOMA07CmQQYDOnpyWa1wpZBG1nySDKEzXDOvsa+3j7J3ltfqpJKskwy0z1zts9MAKmqVHXrfte9tybedEq2tm69hDjbcTTeHi9u3BvbWUy8cBF4SXM8n5ObojdrW1tbxf3WNjc3S/r+4Q9kq9uz2j2yCT86u+QPf1gjP3jB2F9MXPLTvTtOwuhojayRRewFtyRwZm48d8YuiZNJH5//4E3J+8GxfT6y/2x/GF6OTs/P7PenZ/bl8E/Xp5fDE/ITabfarVZrjSSPc3fiTsn1aZB0O2SAU3kdRjMnee07tzGM94MbTLwpjLuJ414NLt8Mr3Do04u352fDtU3TCCfuvTd2T0/65tfnN/8Jq6Cvx2EQJ+LlZ+XtdfA5CB8Cckha0Aw+DoN4gcsGeOMmx4socoPkbRgnV97MJTNnfGc7N3HoLxLXTuAR7cUmvwnLEP2v7fPrK/vV9Yi0tKcAH3zYRgiyWY3vnIg0yMnp6GJwdfzW/tP18Hpovxu8Gr6Daa2H0W1zFv6X5/tOk27kej/T8+Ly9MPgamgP3ry5HL7B306GH06Ph/bZ4P0QhzjGboPb28i9dRKXQW1d7CFCbfDu/M0H+GsRpH8hgvRa1s4u2ewdWDt7gCCVP6sNle6tBAM8rc3iW4s0m806ee5//7YG/0w8wMoENyV+DMY1+eetm9i3fnjj+PZfF+7CrWXgC7M/vzy9+sV+e/rmrUVadUuMmPnv37+Sb/jPNCIhcv0//GDbHwY2YPvItuv95474VBeE8yJHOWS7Qa7cOEEidmdzL/LGju8/WiQOAZ/vXGcSu0lMInceRsCGyMwLvJnjEx9QJRg/kuTOSYgXk3s3eoRPN4gfPljkZpHAG3g8Cd2YBGFCHsLoM/ECMo+ccQII1iTvPJc4wYTEDo7ispEXMxyss9ujY00jZCtN0tgWOL3wkEbthIwGr4eUnbwD1Do7/sV+fQnoPAJ8bnf2+wXNB3/ON99td/optSm0fxGFczdKHgeTSeTGMTkZvh5cv7sCEr0A0uXIfHF5fjG8BDwZnJxcDkc44Fe2A4yNvHWiyYMTuWKwE3fqLPzkNJgvEkZplsZwRLvRGH6+oQhqrW2l4+mthr47A/bz3okTN3oCDrW0oRc8rbZaYFPfvtzzRfLbXy9d4OnIHrw7/bB8pWwx6TqpqIkHvnf/217h6Bl7iGuLf6Or4tQ4uBrYo/Pry+OVd85JnFG4iFLE1N/TBVJy/XXWJ+jv77tARqDff4WbUm+TOp5kyRM6DXuKGp597/gLl0LEDUAGqO/Y4gB77euzP56d/3yG2tiXVssS4g0kmNDTUFCwthQvWMu2lYpCaHvpjsNowj9BfO8zip6x0pWBnPXtWGrXC995vHHGn7XO8dx1PrtRrIww+mV0NXxvcx7KRtqxcITRIwAQ10f5ohgHeqI+1W6BJnVANtudlrXbRo3KCIz70JusEamv23ESuc4MfoRzG4DrRoHj15hSz16BJI2TWR3AGycOCF+Qw4lxACdKKo6QncPYD2OXN17t226ymJd2LFJcxEyoKfKTptIfqV9AVY+BMLbDqY14yD/EAYtPEMj4U5koMwfMI9lzIE5Ac2gYBjbXhWraHOi2Tay1FbTBIv5KYvwXpra1tlUODG0G+alTpBNL8CYGMGRgkNks+AfYFeiHog/o+sGtO7FRZ0TCWGnr09FiShUVR1PMqQJkjFxPQWum+eeHsgwciNDfEdIp43K/IEEQNkA4jznPTj8HzyjngsEX44Q1ZEwr26dB8PdDspHtTAhwL1x55CWogANZjBG1yAzsyC+0AQCPoOp8L8gsZlYpvJIslVs0HB9tpj7LZtpuj0PfZ9/IgR0+BcKgtMWhQOtg4fvzJKLj4zbAEgt7L2I3sqExTEjtVnlaIRVSz55XcXfTxEDAFZAaSIJtMgKeg/wfNjWcckSKSRLCr4k7pkYwDB3Tz5sYFIcSX7UTRc5jv7gxn7reGmfIkZRO6QpsKGrLkvguXPgTcuOC2ea7TuxOyMOdGxAv+d///h80x8BIg9lFJHBBJE+amqFMhwBcAph4wjpO4ZppNgZETHLGM3VOWFmXxWh4eTp4V+/z6XLXCVng9BBcgYtW5SOsFVs4SQhS+SeGHPy1zV4f8WZfj69fDV/B135BX8r1GYjb07PhyZNOE7yvIAOqdlFhu9+2OihsD3asLhW2SYiUBYZwzYPfvAkAEv6p42hPa/g/SeKCgwbTkBG65m8igG6HJjcSnVgR04Euio4jZlos/OhE5lxM2IiJbgBbapiO5PeM3JZpnI10VIc96q+ZhdM7/lH4e0wEDSo0rXBb/IUySZKfcy0LvQKhWWHmfMIFAyxbAsxsbBGD0BHDvUxhWfMmdSsHqRr/Ca+kEMNR4W+u4ojhvgq00pRkVYSIKdCW7pe57409/RUTajBHgAyIiaTOIQx65lmYuC/J+wUAbIb0qg/J6AfdMfRxc9zkymtmQJV9FnDv7QZXXju7HavbIZud3p7V7SE9FS4G5veOu48iFxgJbAFwK+YFws+I2UgaLhBonEeIZkfwKcpTMgLwa+vJ3DwJQfuwOXM19wEZDRPEdXNWBLvrzOa+G6H6MPapNrmReQWMGpYbPtaPiHzGgQVc2ovRxQWwcQnQtiNsACYxSCqEY7EcH8C0CEBZum0SDhm+lJsw9I9I/ODBDsNrLiC+Th0/drU1s4Y3i+kUZhd7/yU0N9T5k7RDmdDTidQR7uJUm0yFhIn1IcvH/ZUdxbpRdSO64krm/uLWCyqNScUHyF0miXLDZ6Rkg7z3vgCXpEbO1GGml2mbZ9gsv8X0sbK99G+xta8oeFHURih54R3syTbHAPSvPni+T8IxbCuTx4s5a4N7jYTgRbAWNiEY7jyAjXfGoFfgEqdROEuRI7mD5U7yk0fc3reTj58Aud3Z3GY7TidIdz1RH1NEoMSEgKR/AEe4eUzcuFmu/wD9cr4JuAzAHTvUf/yAvmCmyxP3HjA3Jg6AYhaCogvq0qSZn3BOGBwJ29hmGpJ43q/eURB09Z7sUw4671bvFlPnyir9+ARzHRVcZd4hJNs1cufEDBg1o2iiLDUCMxqMFHiydcSnxayfuQP8LG5GSBIvuArENaAuakA7ZHOn1cKDPnjEvufFoCTPYNdsxrts7Fx77YdO0tshyjPxcfRr4GkB6wVYS4mSNSTYMKaOfiB/LwKLxk88eMGeTbx7Lw6jWKCGWEf6EXJ4SPZbrRb529+yj9s98/NOp7WLzxUtINOi2zH33Nlpm5/zGRSPuL/fMfY8wDlyoG8Zzy63ys8ut8rPLtElsPqh5JY0cLfWqJjt7digdh+HwT3gquh5FZ45QRjXRANyBy/oAGLnuQHOJT39EL6+AZuDacfaX32lC6IaQTMdjAzgPKgxUynEbN0pqb1QXtaFgzP/hdqG9iczL0hmZBS2fYrze7s9q9Mlm3ugpcBPeJSa4thHqFRSBbLYeeY4lBYAnT5/SI36rJ8FOTQAVzpYgFKBQsbJF8DxDL2uy57rKo4YuO4S3x1+9x42eOYaPR1TJF74gzVZ7gmsMlo61jIXXd7lZysWlPETOZOAZGwyCkUHRGOU1LiXSbGuKO6hKwJ+lHgbpMsLGjFjkh8DXf1yMVRMMYo6+62etQMK7n57j593V10SV/WVGWMjYNQThq7aQ2YMbihO7I0N8sLwkrmp6zpXelE0Sh2HKRyEQ49jJQPF+R8pSmrWiWk7NW/ban42sY0LML39EPQaTnT0jxoVZvzJ1hH1hGnwqhlBpYhAnF4GPrX84mUnLpZpr3rKh+i7+G6RTEDnlJxoifudoyTb9y3mvUPTaRVfKnd38s6FjnBo8LyR+QIj1AvElsv1YQzCeu3HeR2EAjqT8AxfDkzw/7rdIrSYuLluEWX1CvqQFHZiv9N9VraXaAwGFdRmS7J1+tiO7iXFDi8vzy/Fa1hObivFV0nas4x9UozdSJkbSYmXFB14CAZET8UK1WZ++oTUwqwAVJ5JCJI7nFLbaBr6fviAmvQY5NlLPu0G2SI/o7mATYTRxIIqqMYKetQj6NiRa27PDppice6k7FlT6YDOwxsgzCQMkzu9Gbc9Bp2TCzC0tukfb19fbL8dXaD/Y+r56Zd/hkV4EXrHEzQ0ErTMIncL9EE6G9CNFLvPEo5KGkMydTyfPLjUSJLjienDMNi/Ng8ByVCwg5IZuA/1zEGa0CJzDjnF2ZqalITkGcjvVf7BBwUz9KXZnUfFQo/5Eff39qxuRqMoZ41sHjrtZgUJxUbDt6U8fPkyZeGklKJVmh65CbdC5HagqMQ9QDONOinGTgCmx3wOmEStVd9BZ5I78RyyrvrX1lOcXARouQPKrGseOMkOSFbGqMT7JAlInu+IBRUcF+K4y5fK4M22QqxQ8qhN1ryEZtkMjKJGQ6sXRpevMiXq9R4so4stwDY2SQzBknTk3DrAKx685E4bTqA/nYkggrRFObsiyvqegYFVTzYlonI9RNkwXTbrUrXiRmfxGvSFCfe1Fu250rMQGTlCil8EmkhPkiITEHxCshinWKZeU+gWCBvY31MmGPh6HpxYeAJxLU4EG89Ro5nOJa+wIJs6aB1YnT2yedA5sLqtEjaVOy/l5zVgWG4D2+COcw/s95mb3IVcOoBigMo5CCVv+ij9VIYITF2pUw+ZLPLvNQk1Kcm5r82eI+iDWwWsg3TbOXx4G8L7oA8+GLs+9b1xXEic+HMWERgS9A3bWsTJuRWEKmwWLasylFWOwUvRv1xR43JfSHIxZBYERgwnTBZSF7E2GYu9ECcCFp/Y6AqjfCkVpSObphe54ZzrJ3znnCnozakjO0OrnBDZbDLObs1vwNvwzRLooLZ4qnM7e4nJqtv31JlJz3js9JDQFK3h+vT8lsT8F+knobMGlBbPeXwAqHnVIye5QihcB5X7rferfUsJSl3lU0q39b6IY2rT1IF2u71jtfeybpYy40TjzveWUR1TSNdoBjwpBjdfQlRt2zOm7TPiU/iGn49GMOIiph9eW2aaiHMhimfsmIBzUhjhIavL0/npOro88WyAERER9wvzvcquSKr0VIWaHA65Hr0Ssd3CNZuyihBUhZhtZLsrNnJ3t3AjzdDRVMSqCARbfvhjRnuMqumO2R1fzYnxrMim3F7fi+CG16ByIOsBNS/lxX56ZsLNN2BM8Ia4URRGTRHkk+I0nTzbiE5rD+G/2e50O7mNKJcgRUtGmxePl+aJc+O78vwzwq6MuX1AV80lNe8bRHsvls590nh21M+hfdYK06NYeDhCyXG+3l49vKRzSMNezYGv7DjuNR7njqATXUfVENgVgmArBvqS3PI1u88cn5f3SarGHrKU/KDlZggVx6kkhs9KtpKxB0FhFoRXQHZPMtoAdEPKQtgesaNEtkcsCYQNGS/mmEQSy3DXTmefI/Vul59AVUXPCsbHBk7DyuCt7vUKwmEU6bBRYPdGars0iHo7vzrOrVIWVQ4pE2fi5zAIxZxYot6M7xzbyQm3UixNJKHFfOQmJ7nwQgvX3gTZ10a17BEGG+KCcrbkK9x0/MrxZreNIVuAN3u7GHOSw5tiaGSYFswVf4RTPQYpRZNidKipZMbCutnvFgLBIi2LnF2/e2dxPKyCsDRiuJ5HTI43RRFlOnbRQVShV4ZaBpEwc77IeLsxPE7SKKPki5XG5DSI0pK78o3nmzw68fzk/CX5+HHwga5iBDiG8a0x6Nnu5BTFF5hqn3BMTAJjzPhsMbtxo/PpMf/IJxyroX4W9q9Ds0MBhb6jPGI+o1dO7I1P3HgceXMajMsN5CnNTF0mvbTGIj5smcxiH2apr7+mrOInLHhmubGhb/RvSZqVsFvKKLqtHWu3A4yi2znAX3KMYual0fv6Wa3cXUUJ0kSJnHRFkbWhC6LiQxddOqfjyZRLOkBV6dzIxs4J9INNTUPhatrkmrP3LBfTKkqzZJ7TvDyTQQVbZmlHypTReeSCfAV2oMWd5I7QNR6UhqGYYysk78nNiELKPju/skfXFxfnl1fDE7qoBovcYKEghcusxm9EzMyUBwHCyN9BL04Hq8pWzkJAdMcf0Y6X0LFqMt+/rB5cTjS6aqDsHvsgqjglikF2LqgC5LYsVRCqq7IbmZmU6LJLmALHcUaLYCbGicIL9K9sllP6Mjo3BfBriWMs5CjTguldXO6/Y9HKDR62LKPOttkx551zj6Y2PUeNSPIQipB/C30hYxp/GOIrxFY3bLJYNZGyUcPKFf6jxUd8FYIu+qfj7q4FDDL6TNrUPdKpWxiBje8cgvUufFemLMzwiGwiTigj7/Yuwe/y8WgWPcj0OAyaXCbtt5hLZae1a7UPdJlUDo28sjf2VwS3zmdNn7mmx9OKk2qNebXNdTdyuMazMUZXw8vhOQ9p5MxS8ZMQjq/9vD7OjvppEzkfhcJO8UxKkIwyTbO2dCGWqqGSpfNK/AJlfTbXq5TyHEJ9FzFEigF5X2ZBGma9XX2C6gHrunCJUezZAY2GYY/BD1S+uassmvVpwoC1OgfBM1e+yqpzzr/o3qjkZDN+DFbQUpJSV1jXQ29XJCeRdFCZmL4vKTC06O5Z7X1Ei17P6rTyaFE8yW+HXZlex8Ly6doViDQII1k9Wo/9VSWgUIBPD0ObhfcyHUHmFmUyWixSlvqbdxNnU0v50aJqE4s9NQc3QQMluEke7J54Mej01EWMHjJmb1Hf/c3ilrRb+90e6I1bWxgRE7vuDOWL7zqfUf5QG5Hve69Fw1nbOwdtVqVp6VzTKbDXOAeHJ/5wINE4A3nAIPMl5ekhZivcelScTuRwsIqZF2NEA49mGlycWmJhCQpqJSZoDGvB/Ad+bM3NzRcUWMuzTzc2NJ1pSTeZuGTsViGpdMV+4ntVI8KuAwFNCrY0AWhKAhezP5zoMQ1sQgZcDUzGCIQiKkHXTpHbTT+FlRNYDrnvMAM9uOlJCxBKGZeMMeD5rmyCanBBGh/su6D6wvsM36KETmlq92CH0VSvs4f5ERpNMdanhIprJ0KqCaHFOfCEu8NqXDl3Tii8MlqQzpJOuQix5YaGac4Vz8srVWGIF4LxxrWCFFXBTNXxRKsjogywzEjOZmbmTeRMxTM5AM2xHy1u2GNMdCo1hlWj+Vut5epjMXParDDoykWxoYqnYjXVSs3CDG3UVepXqJn3itZYpjcqO9qcL+I7mjyRTiqj/mX3/4lRbK9zwM6Rer2uUSkuRrwqysuN7wSf7WzGY6baRyNNWlwBZvpkGqa0SkERJbjOt8vmM7hZBBOfe1YyOJ89gb+AHqfB6zB6RfucnvxajqFlmLwckU2JovqxzEYRnLKHNd9ySohz2VbNt8qAz1s/ZR5ehvi7AvEP8ohfjr3VjjwrT95ksFZbSCoySzCcryVHHoXMnU3xmHbLMPpfD8VXwOJGyk3IxpLVU/TNs91vwuAKUPzGLacIvIfxRYjAe73dlREYjI6QLgBtDy/A5jGtZsK5+fHrEY3Uu3RBV1RqN6HHL1dzwhDRknqAlZHYupQH2MOhaSpqmlkFbr1YMA5dXE/wGihrRflbFbW/YbgCCvgeIwpCkXzfjaL0xKrE5U7JRAWsgSbgB9sq7sRniFmjn5Ak8nuxnS+pQCh3bqAWnuJlqmRQq6a2tGDCs/UErXYQjsNoaW+H0dJ+az9HS+VTrRZfh2g/wNpDA0wKmdCD0Zpp0JiVKAKRJugFu15y20w+XM72C2dcWZt/DSjwz6nLS9bzfkGPfynkJQMq1PFHGcqQBrgB/4BkigCs048WwbJRsuWCO4q9Xtp0uT/ZuCyDhlUZAYjmUN876HGq6bZWppolvGFG0SQvupTgqzL+kMlyNpVcKUg6WiaCchNLl1aZshgNSND+ZumKH8SxocmNO8YTOXS0tWMZ8wjLF/Vilp7Op/Lo206tGRKY/RyiQEhKM0VfVS3b7Ezzqgrfd223s4pR/tsfW5/qadU0YWvvG2ztcqQvJhZa15BmmaDP3J5E3hQdizMQMzEtscnZ2K9OOELFoNUa86SidzrHRuxR/GsGXHC58teF43tTD+sXAQe1DeGPwpmhgOHYByAClMf401YK20nC5y3UUmH6lzAeVHT/Pj6rJTJN3SPLtOzsw1S0cduJYXqP2yb7B3nbpBxjV5FsZpO7DJOqHpOuYmALoNGF5BFb7racKrY7Vij010RwWo8TsyFpKiLNZWF5oCLwHIxDxvNZcjqWX8MLB5hIoDuIw+DpW40jp4cXCfThx08oHITiEixmfbK56cnN5K3zDIuXucBB+M4s0dNUfut9UtCYjq2pY9XMBk7YbIZ4iF80SS1z3ICwVZQxSjAHTIPabB/08llfeP+DE8HvEwyJtR0vmocTeYSSLmmDyx+MzIxopJp84nzJPAlYWJudRmap+YbnWj7DjwuLXlLzkvwIJAT9XtJHMCj7hY9FAwrxiUpfacqjJmKbyG4yQjeYhs1p5IF55D9SeaoMk1tZbmEF62JDiGBCHrvFjEC1aX+tqMqlSuVFLod8jODaP9zp8D3dDRV5xwqmFMWAYpnzjNMSzcACYuVbjNSq4vQSyjwLAzWRzMqUZygh3Iqxovp4phS9ey40Oy2W8LnZae3sFzn08qoh5QJFyqHIAF9yALPi8csKJy8lauTGBmmUqpfckcevJ9AiCdIil89URosAYwsyN7nEedTHb8YnXhxBvYIiqDrLS6FSctJz/+2O8iLYlnvK75cd83RaGN3VQ6Laa+eIqpw8VlcS6aL5SsDGydVrpQlvJqRnwxvJobga9rOSdQP3wU4zkAOx1uWhZepRKiqvYQC4qGb4ADDH/XwTrGw57+dzfdn2tPe6bHs66Hg9yBcVlKVMA9eJeCIrY3paETuMIxFxPVrbrSPfDW6Tu1odPdWtsmptKcxEPLd+SwdwdT3hJVOqraDk8rIgYD4VvZMe/YtZ0WEkPS/8sywB/TG5Y/Vx8SeJnSm9DWwLFCOV/+rGl7wGQSspUidHDEDZ3JzSPlhLNBs6Dx+vwSQMOTJsdVbRnWL1vAAqzqIRvvW0kmE+8ociWafbpRGenQ7wgGyEZ/m+ZrIs+fBqDWAsDCvXv5gDh5PJS74389AgzPdSszdLuxbAyRC1uxzmhi/k4F2as6RG+RZfiUdvnztmle3UtF+PBhYFLrvpwZnQOM/kDqs0yEp4XsLurpPF3FidE3cev1xjxdZkvJ8jawJQ4zObQi3icXg3Pj62yrx5cDws+pJ4Pn0rB8WSEl/c8SKhcZrYUnTEosKiKgye02BMntaXthel3Tv7u1anDcjX7ezyMNN8LXGlVoK8CeTY11THQ5AedKX0QhvyY75OmAVYTaNyLazvpqKbBcON+D04uaowRZXNZe1X2vQGKOJzSnNPlYQN+jSV4cu5Js6ZToLj69ryulhpQdPl/DVl9SpnTYWfs6BJPToP6Wtt2IVCAGS2BYe5dABajUPvw5U27OXyXw+VdAG1wgkuCLhptuaXjI0W80sLdPbFq8IZMUM+bafNgV2YyhWl7h5XlHY6baNzungj9XKfhfgECj9NiiZHh6TbMlTLHDITbOKlKZwqSWer/DebmVpHFZQz+p0fY8O4NA3px4W4N5ONbCkXm1Bck1iZwda6WSMrSI3IxsqFwdS7XUTu0lLlqagzlWsVyMQLobT4zu4ecB2r1zUebpfcIVYE12zuZwpl5eO5osJgZsCfNq8snKtO1M+2D9krrYPmM+JR4oUx4oiUaQV4WgoMwIZP2DDikVazK1u/8sWh2X+VKj1abHKRoa7gaVmdySJHSYkdkCkVZr7MIS4q5Qe65YsXL2A/hy/JaSLK68joeVZtke4/3s3QxLJ6wC3F3bTKKLyVx4swTeV9Cyy7L/QnxEO/yEzc/daklVOx7G+AfzJk7bVbHFl389k4VZCVJVQkvCyagywHyzmFU1Az3M9xMxOvEQmJqCljRMXVJoW+iozsSdFW9U1jqPcUUcbeVxLxzM3YiadepUnKrs3i4TM3KP5N/eZmyfeM/cQkFE5mpqxycqBJTBsZhmWRDWUNq1VhTQU3/QIaoKgcsWKeBaie3fI0mK6zt9tmJsJ+q70y2hXVKMNFoMNEA42c+Kkss280XUhxEGI2ZTAdaZsfyueK61SqHVucasNMPuMNQYYU9OJbHtf0fIn8kcCSsh2i6qyKiql3n21WXzte0o9qWQsVvKbkQEM+SKpXiUY2v4Zpmcs0q5GJ8IsWYD+bzrIRmLdNCbTThUXBtmwe6uaBKVudfZ+pGMpuxOPmLPVhC/f03l4HKQNIpLNjdTqrcmZJICn9G6vHy7p+22QwxttmeS04lCGn2+cgvVlANTvL8RJmqM1BJqLHDW+UHXtT0LHmmDIHCB9O5XhpDp5a6I8GwCLRwC/sDhNMW+eEhM/o/SVgo4qvyPGCkNYOxxrcAelgFyUDDUsFRuFDUyEgMYC4ZUfOB/if7djQWi2wPXY9f6qh4t0DuxplW1VU+MM0LLBMIdJ589+p1H1xoXsxcrbOvU7QBb45Fateviy9y22N3zjH/66J51Z6p1hNnh8VXUAmyZJeVJVtr99mtcbLawFtdPH6YSASMKd2s7o2K2uk3pWi5NbKzLccf826BqXAqWlVtPGuC8P9ReotDnqcE+0hYpa0LiW1MECT+DB4d3piXwzQNXQ1vEy9Ajgn4wy+rmX1a60BrLFheFx+qdqy8u+arBHp+FjeFtgCCKckZYawrcgNVWDWrawdvpJ2gjUskWnFbqZIvFBROAWkeeAFGspmJmNTq9hSAmRTC4Sy6fk/GMwaCta/sRh/GaDZh54LaSUtHYuJJ79jhpG4ZZgmlaMHE60iC2MjHczfxmopIKkiccscugpvXDdgJccV2fHoAs3fLFgVcvR20htwZcq3w4pCsi+IMRLnM95EG8hB/sMsgP+jWfGukNzOamXjVZA9ZSrmVBIEdEB2c6H4CD+7MG6KtiXPk2QlVcDVbz1Pnil3iJjlWelyMkKuwdUjakY2Re4166tMgkoJ3pQWYY8X9FbD6cLHj/JR6v3lZ1qr3jrP5dl+z9rdAXl2sNOzermjk7IhlIga1H7h/8sNHv3oUJQ2PPFirB9U2Ctnd+n5RGpWuRTzTTRPEg5wRhko0ZXHSz1Lha6aJddZVDh/pkM/Iyl2o2hOGqhWcy89FXkxsxjFhYpYlLzPqdidabilqslYoEzvZ3wUA1LjWml5k/J7osquB/im25xyTMF8UcBTnmf9uldNldw0tURsLLsYZcUjZzw+zow7cccRdROWdu2vgo1FSFhK4/+PT8/Gp7y3UL9apemHzqRWr+cr/1S7xq76JXLi7gv+YfVUUxUMmbtStIsvu619Vsq/297Z4ycoorwTd6bAv/KgSAQ2O4lT59Ebly40BvWw9eXnP//yF8SsEH7/yy9//rnJZhB9bH2Cb9bw7ox6jYb+Hx2Rzo6QT9HHtuF9u5e+7xje76evu5nXmsoQJ8vueDCUHM0k7eCg7FbegvLZlnDJNQRovuYzhiqVtOQVp4TB+a2lbrvtVsfq7uP29g6sne7SmtjKUqtK5pdkQ9TzHlwN7NH59aWhqLcU9JkC2CTdsQKXcINni7T61W9zWL6nNKnJcGhfZdUqEjA/RyxMtJX7Z2qwb1Y66jcXqZUn//r9p/JvpZCakqMAwO2bRUI5ejC83zBsX47zZq0fwu7RaTQIT5FfUuGd/J4VQR+7wsWC/VYuQUNRVYwjYuphIBagyKdSwvzoUjP2DGf/ke8GNToE8n1ki1jS7JGwns2sAKLfCqd4Wp/ekkd7vOCH8+nilsNmncJkHVa3zla1rgrSZef2xRcHCz1VC8demViy5KLTS6UC8ZyV7e0zSdXZNaTksmmLEKqMnqCrfngqN74RUpiFVxboFbQRg+Z2g5yFmATCk4hktBaGJ6J/fJEWbGP5RNRtEpPfBeHc/Z1ymwvGkDHQZk6NYcy/Ljww09SxbtwpOuKV4LDAfSDjG1H7TRTJK1gB3j3+YskqpSgtawS0UfCmxEKvcp1WI4N+kTvF67TG8Ku9SKb7apkNwt4LAXv8+jSYuF8IUJ+VxoqzUXFG/dSexW5IRvqhJZs0L+kgTky77YMDPAUCTMNzoZ0cppXMUFEKxUO8en3E42xoX/QhJjx7nnwWzYbBOET17Prq9X6qPLLCdB8/ydXQSZNDdc7ahVa02dPalpSGm8s2wRQRfKsUkmO3PehZFfQ2CYsUJQewQL5KJapoRgLoBLRHxZSg75YP9OwKVDKyz7P4foigIFhRcyYvfDssuc7hmIdGUdJXTj4qVGZjuUX5tAV5kKoG/uC8j5RAXjo+uwUJCx9gAW1WOkM9SM01OqqhK3fs1OiH+MFpt8Nz+7rd1q6xxFoxEpXYt/TChHvH8+l9CWnZcSMSVk/rKUTUamOoV5x4QfbKk5XHmKRs7J+aQKoifS6BzHSZzlsnlpEKCqLXs5m1euiDyI/r6zETU5Fsq1wUXn53TwltYZl9lhcLRJbudTZsoTFBMcM/LYhkr8OJRJrYVXFdxiOnxMIgsLZCZMqzqaYS8fzrcXmaJWQReYrRyt4ABFCMvcnH9qcV0J+H1PTz90jwVOwqd0uV4ye8NdwSBU8V45kh5MGe1UGnQBcw03xRVhE2Ze+UIpscTpXqffNxMR/fvnuAv3R/SpqVRX9dmbWnikmJhb1VEVVblUvSfJfhzImPz7loDVBRi5gvjDh7xj1rK3wjTRjQ409LPFYlmQ7Xp2dXAJbxHbvaS81z4BCjr8qUD44a6ez1zB9ewvqO5dJVuzDlIpz8xY3CmsRY5vDP1teR7j00HjIneGUVBSmx7rS59KC13HvG1OkCusKZ3IShD0Z+XJRebUqIZDGrely+8mbrSCtloLlb0dQMxrN5SXuLXFyefsA7oQdv3lwO3+BvHNnOBu+HRqrnHpbSjvzOgZzlk0cnhUdtprB0g8WM3cUjKiepd0zxEvh4z1SBD7hcGGmdlOL5DaWSfn1t82tFX9+TdPeZGe43L4Z8+2LyJbtlCfC0ViGLaTU3SsNp4rSkyzHNswnoHYDoQ2MBjkpco6gbTdjlySzqn9PS3r7VOQBa2u31rG7mXoRykJVe/sB8o9pxXFmisTTqhTNSj6/PvdbIx9zkHhqEkWhQIX8tt3m5eyF0RFnd1VeKGFWT2oquY5Pcn1bnodlKCa3O02LVedLP4SEbYAw83tw0xilom7ehdmTvPnqfFH+qhHy+YVH+dcX00lVK5ovKQ+GU0myt+PYSY/3abHEt6sH49kLajBmP8mc/xeUV3KTwkjIjIGpCLPZ2u0ws7u1QZVYj5fJLX8RK5OHrCldW8LmlV/M8ab5hxW/rQKNAuRGFjG/SC77nUQjm3sxicXd37vgzHhNwjy7/hrLwS7oeaUqI9XzLluTrBpYs3yJaZEIFEZuRrTm/fO5bNSY+q9/LYykdiodN3ddly2ND8fRkeVHLc6RxhstWWTdZdd3k+62bGNfNkB3pk3/TbBVcn/3x7PznsxUDqhn18toY3b29fN5mOdCkpl6NWjWjwJlM8kxBQFyHbyVpV0Yx6n0/BhtIm1cRv8pMLX+sRxmoWqZaSB3yMmOzaCoBQ55wHvOzuHQm+EyWCNpuNGlg5mFjW69cYsn3KIxwvTA0DbVTW+rv9D6566TzXXNNMiOkd/Qa+qYv9V7Gy2Tz/Y3N9JH4tfXQhOmywNIxehX4uIxJb2yzmzz/D5aavwE='))
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

# Host Mac-owned anonymous mmap semantics only: this is NOT an iOS runtime test.
cat > "$deps/build/ios-lazy-zero-host.cpp" <<'CPP_IOS_LAZY_ZERO_HOST'
// Host-owned anonymous memory only. A Mac pass is not an iOS runtime proof.
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <sys/mman.h>
#include <unistd.h>
#include "common/ios_lazy_zero.h"

int main() {
    using Common::IOS::ResetPrivateAnonymousToZero;
    using Common::IOS::ZeroResetStatus;
    const int native_page = getpagesize();
    assert(native_page > 0);
    const auto page = static_cast<std::size_t>(native_page);
    const auto size = 5 * page;
    auto* owned = static_cast<std::uint8_t*>(mmap(
        nullptr, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0));
    assert(owned != MAP_FAILED && owned != nullptr);
    std::memset(owned, 0x5A, size);

    // Both edges share host pages with bytes that must remain untouched.
    const auto offset = page - 3;
    const auto length = 2 * page + 6;
    assert(ResetPrivateAnonymousToZero(owned, size, offset, length).Succeeded());
    for (std::size_t i = 0; i < size; ++i) {
        assert(owned[i] == ((i >= offset && i < offset + length) ? 0 : 0x5A));
    }

    // Replacing previously dirty interior pages must produce actual zero bytes.
    std::memset(owned + page, 0xD3, 2 * page);
    assert(ResetPrivateAnonymousToZero(owned, size, page, 2 * page).Succeeded());
    for (std::size_t i = page; i < 3 * page; ++i) assert(owned[i] == 0);
    assert(owned[offset - 1] == 0x5A && owned[offset + length] == 0x5A);

    // A sub-page request must preserve every byte outside its requested range.
    std::memset(owned, 0x63, size);
    assert(ResetPrivateAnonymousToZero(owned, size, 7, 13).Succeeded());
    for (std::size_t i = 0; i < size; ++i)
        assert(owned[i] == ((i >= 7 && i < 20) ? 0 : 0x63));

    // Zero length includes the one-past-end position and must not clear data.
    assert(ResetPrivateAnonymousToZero(owned, size, 0, 0).Succeeded());
    assert(ResetPrivateAnonymousToZero(owned, size, size, 0).Succeeded());
    assert(owned[0] == 0x63 && owned[size - 1] == 0x63);

    // Rejected bounds are tested only against our valid owned mapping.
    assert(ResetPrivateAnonymousToZero(owned, size, size + 1, 0).status ==
           ZeroResetStatus::InvalidRange);
    assert(ResetPrivateAnonymousToZero(owned, size, size, 1).status ==
           ZeroResetStatus::InvalidRange);
    assert(ResetPrivateAnonymousToZero(owned, size, 1,
           std::numeric_limits<std::size_t>::max()).status == ZeroResetStatus::InvalidRange);
    assert(ResetPrivateAnonymousToZero(nullptr, size, 0, 0).status ==
           ZeroResetStatus::InvalidOwner);
    assert(ResetPrivateAnonymousToZero(owned, std::numeric_limits<std::size_t>::max(),
           0, 1).status == ZeroResetStatus::InvalidOwner);
    assert(ResetPrivateAnonymousToZero(owned + 1, size - 1, 0, 1).status ==
           ZeroResetStatus::InvalidOwner);
    assert(owned[0] == 0x63 && owned[size - 1] == 0x63);

    assert(ResetPrivateAnonymousToZero(owned, size, 0, size).Succeeded());
    for (std::size_t i = 0; i < size; ++i) assert(owned[i] == 0);
    assert(munmap(owned, size) == 0);
    std::puts("HOST_MAC_ANON_LAZY_ZERO_PASS_NOT_IOS_RUNTIME_PROOF");
}
CPP_IOS_LAZY_ZERO_HOST
env -u SDKROOT -u IPHONEOS_DEPLOYMENT_TARGET -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    xcrun --sdk macosx clang++ -std=c++23 -UNDEBUG \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -I "$source_dir/src" "$deps/build/ios-lazy-zero-host.cpp" \
    -o "$deps/build/ios-lazy-zero-host-test"
"$deps/build/ios-lazy-zero-host-test"

# Bounded render-probe fixtures run only as a HOST Mac process, never on iOS.
cat > "$deps/build/ios-render-probe-host.cpp" <<'CPP_IOS_RENDER_PROBE_HOST'
// Host-owned fixtures only; no emulator, device, guest memory or private data.
#define CITRON_RENDER_PROBE_HOST_TEST 1
#include "common/ios_render_probe.h"
#include <cassert>
#include <fstream>
#include <string>
#include <vector>
using namespace Common::IOS::RenderProbe;
namespace fs = std::filesystem;
static std::string Read(const fs::path& path) {
    std::ifstream input(path);
    return {std::istreambuf_iterator<char>{input}, std::istreambuf_iterator<char>{}};
}
static fs::path Log(const fs::path& documents) { return documents / "citron" / "log"; }
static void Sentinel(const fs::path& path) { std::ofstream(path) << "sentinel"; }
int main(int argc, char** argv) {
    assert(argc == 2);
    const fs::path root{argv[1]};
    assert(!fs::exists(root));
    fs::create_directories(root);
    const auto directory = [&](const char* leaf) { const auto p = root / leaf; fs::create_directories(Log(p)); return p; };
    Recorder recorder;
    auto first = directory("numeric");
    assert(recorder.Begin(first));
    const auto generation = CaptureGeneration();
    assert(generation != 0);
    std::vector<std::thread> producers;
    for (int i = 0; i < 4; ++i) producers.emplace_back([generation] {
        CallbackGeneration context{generation};
        for (int j = 0; j < 1000; ++j) {
            Event(Stage::GpfifoSubmit);
            Add(Counter::QueueSuccess);
        }
    });
    for (auto& producer : producers) producer.join();
    const auto& stats = Detail::state.stages[static_cast<std::size_t>(Stage::GpfifoSubmit)];
    assert(stats.enter.load() == 4000 && stats.exit.load() == 4000);
    assert(stats.first_enter_us.load() > 0 && stats.first_enter_us.load() <= stats.last_enter_us.load());
    assert(stats.first_exit_us.load() > 0 && stats.first_exit_us.load() <= stats.last_exit_us.load());
    assert(Detail::state.counters[static_cast<std::size_t>(Counter::QueueSuccess)].load() == 4000);
    auto end_started = Clock::now();
    recorder.End(); // Interrupt the otherwise30s private-CV wait.
    assert(Clock::now() - end_started < std::chrono::seconds(2));
    assert(fs::file_size(Log(first) / FileName) > 0);
    struct stat info{};
    assert(stat((Log(first) / FileName).c_str(), &info) == 0 && (info.st_mode & 0777) == 0600);

    // Ending with a live Scope does not deadlock and cannot permit State reuse.
    assert(recorder.Begin(directory("live-scope")));
    const auto stale_generation = CaptureGeneration();
    Scope held{Stage::RunEmulation};
    recorder.End();
    const auto refused = directory("refused");
    assert(!recorder.Begin(refused) && !fs::exists(Log(refused) / FileName));
    held.Close(); // A crossing exit is intentionally censored after disable.
    assert(Detail::state.active_scopes.load() == 0);
    assert(recorder.Begin(directory("stale-callback")));
    const auto fresh_generation = CaptureGeneration();
    assert(fresh_generation > stale_generation);
    {
        CallbackGeneration stale{stale_generation};
        Event(Stage::FirstFrame); // Nested hooks inherit the captured stale epoch.
        Add(Counter::QueueSuccess);
        { CallbackGeneration nested{fresh_generation}; Event(Stage::FirstFrame); }
        assert(CaptureGeneration() == stale_generation);
    }
    assert(CaptureGeneration() == fresh_generation);
    assert(Detail::state.stages[static_cast<std::size_t>(Stage::FirstFrame)].enter.load() == 1);
    assert(Detail::state.counters[static_cast<std::size_t>(Counter::QueueSuccess)].load() == 0);
    recorder.End();

    // Race old captured producers against End/next Begin. SC acquisition rechecks
    // plus the never-reset lease count protect origin/counter reset boundaries.
    assert(recorder.Begin(directory("race-old")));
    const auto old_generation = CaptureGeneration();
    std::atomic<bool> keep_running{true};
    std::thread old_callback([&] {
        CallbackGeneration context{old_generation};
        while (keep_running.load()) { Event(Stage::FirstFrame); Add(Counter::QueueSuccess); }
    });
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
    recorder.End();
    const auto race_new = directory("race-new");
    bool started = false;
    const auto retry_deadline = Clock::now() + std::chrono::seconds(2);
    while (!started && Clock::now() < retry_deadline) {
        started = recorder.Begin(race_new);
        if (!started) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(started);
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
    assert(Detail::state.stages[static_cast<std::size_t>(Stage::FirstFrame)].enter.load() == 0);
    assert(Detail::state.counters[static_cast<std::size_t>(Counter::QueueSuccess)].load() == 0);
    keep_running.store(false); old_callback.join(); recorder.End();

    assert(recorder.BeginForHostTest(directory("deadline"), 80'000, 10'000));
    Scope crossing{Stage::GetRenderFrame};
    const auto disabled_deadline = Clock::now() + std::chrono::seconds(2);
    while (CaptureGeneration() != 0 && Clock::now() < disabled_deadline)
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    assert(CaptureGeneration() == 0);
    const auto count = Detail::state.counters[0].load();
    Event(Stage::FirstFrame); Add(Counter::QueueSuccess);
    assert(Detail::state.counters[0].load() == count);
    crossing.Close(); recorder.End();
    assert(Detail::state.stages[static_cast<std::size_t>(Stage::GetRenderFrame)].exit.load() == 0);
    assert(recorder.RecordsForHostTest() <= MaxRecords);
    assert(fs::file_size(Log(root / "deadline") / FileName) <= MaxBytes);
    assert(!recorder.BeginForHostTest(root, 0, 1));
    assert(!recorder.BeginForHostTest(root, WindowUs + 1, IntervalUs));
    assert(!recorder.BeginForHostTest(root, 100, 1)); // Too many planned periods.

    // Reject links/special files BEFORE truncation. All fixtures belong to us.
    auto symlink_dir = directory("symlink-file");
    Sentinel(symlink_dir / "target");
    fs::create_symlink(symlink_dir / "target", Log(symlink_dir) / FileName);
    assert(recorder.Begin(symlink_dir)); recorder.End();
    assert(Read(symlink_dir / "target") == "sentinel" && fs::is_symlink(Log(symlink_dir) / FileName));
    auto hardlink_dir = directory("hardlink-file");
    Sentinel(hardlink_dir / "target");
    fs::create_hard_link(hardlink_dir / "target", Log(hardlink_dir) / FileName);
    assert(recorder.Begin(hardlink_dir)); recorder.End();
    assert(Read(hardlink_dir / "target") == "sentinel");
    auto fifo_dir = directory("fifo-file");
    assert(mkfifo((Log(fifo_dir) / FileName).c_str(), 0600) == 0);
    assert(recorder.Begin(fifo_dir)); recorder.End();
    auto real_dir = directory("real-directory");
    fs::create_directory_symlink(real_dir, root / "symlink-directory");
    assert(recorder.Begin(root / "symlink-directory")); recorder.End();
    assert(!fs::exists(Log(real_dir) / FileName));
    const auto ancestor = root / "symlink-citron";
    fs::create_directory(ancestor);
    fs::create_directory_symlink(real_dir / "citron", ancestor / "citron");
    assert(recorder.Begin(ancestor)); recorder.End();
    assert(!fs::exists(Log(real_dir) / FileName));
    const auto log_link = root / "symlink-log";
    fs::create_directories(log_link / "citron");
    fs::create_directory_symlink(Log(real_dir), log_link / "citron" / "log");
    assert(recorder.Begin(log_link)); recorder.End();
    assert(!fs::exists(Log(real_dir) / FileName));
    assert(Detail::state.active_scopes.load() == 0);
    std::puts("HOST_MAC_RENDER_PROBE_PASS_NOT_IOS_RUNTIME_PROOF");
}
CPP_IOS_RENDER_PROBE_HOST
python3 - "$deps/build/ios-render-probe-host.cpp" <<'PY_IOS_RENDER_PROBE_TEST_PIN'
import hashlib,pathlib,sys
assert hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()=='00b7d3b644650cb89b2d2ac07d5da0d1777043bbbc2b9cc30d5360c440416fe2'
PY_IOS_RENDER_PROBE_TEST_PIN
env -u SDKROOT -u IPHONEOS_DEPLOYMENT_TARGET -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS     xcrun --sdk macosx clang++ -std=c++23 -UNDEBUG -pthread     -isysroot "$(xcrun --sdk macosx --show-sdk-path)"     -I "$source_dir/src" "$deps/build/ios-render-probe-host.cpp"     -o "$deps/build/ios-render-probe-host-test"
"$deps/build/ios-render-probe-host-test" "$deps/build/ios-render-probe-fixtures"
python3 - "$deps/build/ios-render-probe-fixtures" <<'PY_IOS_RENDER_PROBE_SCHEMA'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1])
for leaf in ['numeric','live-scope','stale-callback','race-old','race-new','deadline']:
 p=root/leaf/'citron/log/render-stage-probe.jsonl'
 assert p.is_file() and not p.is_symlink() and p.stat().st_nlink==1
 data=p.read_bytes();assert 0<len(data)<=128*1024
 lines=data.splitlines();assert 1<=len(lines)<=32
 for line in lines:
  obj=json.loads(line);assert set(obj)=={'v','g','t_us','r','enabled','s','c'}
  assert all(type(obj[k]) is int for k in ['v','g','t_us','r','enabled'])
  assert obj['v']==1 and obj['g']>0 and obj['t_us']>=0 and obj['r'] in [0,1,2,3] and obj['enabled'] in [0,1]
  assert len(obj['s'])==14 and len(obj['c'])==12
  for row in obj['s']:
   assert len(row)==6 and all(type(x) is int and 0<=x<2**64 for x in row)
   assert all(x<=30_000_000 for x in row[2:])
  assert all(type(x) is int and 0<=x<2**64 for x in obj['c'])
 last=json.loads(lines[-1]);assert last['enabled']==0
 if leaf=='deadline':assert last['r'] in (2,3) and last['t_us']>=80_000
print('HOST_MAC_RENDER_PROBE_JSON_SCHEMA_PASS_NOT_IOS_RUNTIME_PROOF')
PY_IOS_RENDER_PROBE_SCHEMA

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
