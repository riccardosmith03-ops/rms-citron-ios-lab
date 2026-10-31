Citron iPhoneOS prototype - portable build carrier V6

Status: four Mac attempts completed without an IPA. In the fourth, the real
Cubeb iOS backend and archive compiled, but the native link probe failed because
AudioUnit was requested as a standalone framework in the iPhoneOS SDK. V6 links
iOS through AudioToolbox/CoreFoundation and keeps desktop frameworks on macOS.
Native compile/link, full app packaging and device tests remain required.

The manual workflow uses a standard macos-26 runner, two compiler processes,
a 120 minute timeout and the fixed official Citron commit in NOTICE.txt.
It targets native arm64 iPhoneOS, minimum iOS 17.4, statically links the existing
iOS frontend, and embeds MoltenVK.framework. The IPA is UNSIGNED and is created
only after successful app compilation and Mach-O/package inspection.

V6 audio integration:
- Fetch the exact Cubeb source recorded by Mozilla for its reviewed iOS fix.
- Apply the complete official RemoteIO AudioUnit patch, with before/after hashes.
- Select iOS frameworks and the vendored Speex resampler; keep desktop helpers
  on macOS. Preserve source licenses in the packaged dependency notices.
- For iOS only, accept NOT_SUPPORTED from the minimum-latency query and retain
  Citron's actual stereo output stream-open suitability test. Other errors fail.
- First compile AND LINK the same patched backend against the real iPhoneOS SDK.
  Verify AudioUnit selection, arm64 and native IOS platform. This small link
  probe is NEVER RUN and NEVER INCLUDED in the IPA.
- Pass that exact patched source to the full app via CPM_cubeb_SOURCE.

The existing shader gates, genuine Sirit opcode366 builder, dependency archive
checks, ARM64/AAPCS Boost.Context selection, ownership test, runtime/JIT probe
and packaging gate remain. The existing Swift playback audio session remains.
Local source/patch/hash/syntax checks do not prove an Apple SDK build, audible
output, route changes, interruption recovery, JIT, GPU or game compatibility.

Build recipe with fresh empty work directories:
  bash scripts/build-ios-deps.sh /tmp/citron-ios-deps
  bash scripts/build-citron-ios.sh /tmp/fresh-pinned-source /tmp/citron-ios-deps /tmp/citron-ios-build
  python3 scripts/package-ios.py /tmp/citron-ios-build /tmp/citron-ios-deps/licenses dist

The project contains code and licenses, without credentials, signing material,
personal data, console firmware, keys or games. Signing, trust, installation
and real device tests are separate later work. Nothing is installed automatically.
Artifacts are retained for three days; no release or automatic push is enabled.

Previous attempt: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions/runs/41240447539
Current build status: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions
