Citron iPhoneOS prototype - portable build carrier V7

Status: five Mac attempts completed without an IPA. The fifth passed the real
Cubeb native iPhoneOS compile AND LINK probe and compiled that same backend in
the app project. It then stopped in input_common/drivers/udp_client.cpp because
Boost::headers did not expose the nested numeric_conversion include directory.
No audible output, device execution or game compatibility has been verified.

V7 repairs the existing legacy Boost::headers aggregator with an iOS-only
INTERFACE dependency on the real, header-only Boost::numeric_conversion target.
The exact Boost 1.87.0 cast.hpp hash and target existence are required. This
propagates the module's complete include/dependency interface to existing
legacy consumers, including Asio users, without copying or inventing headers.
The Boost release, component selection, CPU, graphics and audio code remain.
The source patch checks the exact post-series file before and after applying.

The manual workflow uses a standard macos-26 runner, two compiler processes,
a 120 minute timeout and the fixed official Citron commit in NOTICE.txt.
It targets native arm64 iPhoneOS, minimum iOS 17.4, statically links the existing
iOS frontend, and embeds MoltenVK.framework. The IPA is UNSIGNED and is created
only after successful app compilation and Mach-O/package inspection.

V6 audio integration retained:
- Pinned Cubeb source and complete official Mozilla RemoteIO AudioUnit patch.
- Native iOS AudioToolbox/CoreFoundation; desktop frameworks only on macOS.
- Vendored Speex, retained licenses and real output-stream suitability test.
- Native compile AND LINK probe, with arm64/iOS platform verification, is
  NEVER RUN and NEVER INCLUDED in the IPA. The app consumes the same source.
- The existing Swift playback audio session remains.

The genuine Sirit opcode366 builder, shader gates, dependency archive checks,
ARM64/AAPCS Boost.Context selection, ownership test, runtime/JIT probe and
packaging checks remain unchanged. Source/hash/syntax review does not prove a
successful V7 Apple SDK build, audible audio, JIT, GPU or game compatibility.

Build recipe with fresh empty work directories:
  bash scripts/build-ios-deps.sh /tmp/citron-ios-deps
  bash scripts/build-citron-ios.sh /tmp/fresh-pinned-source /tmp/citron-ios-deps /tmp/citron-ios-build
  python3 scripts/package-ios.py /tmp/citron-ios-build /tmp/citron-ios-deps/licenses dist

This project contains code and licenses without credentials, signing material,
personal data, console firmware, keys or games. Signing, trust, installation
and real device tests are separate later work. Nothing is installed automatically.
Artifacts are retained for three days; no release or automatic push is enabled.

Fifth attempt: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions/runs/41349094515
Current build status: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions
