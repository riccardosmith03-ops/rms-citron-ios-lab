Citron iPhoneOS prototype - portable build carrier V9

Status: seven Mac attempts completed without an IPA. The seventh passed the
native audio compile/link probe and the previous Boost and iOS touch checks,
then failed at src/ios/native.cpp:410: CreateFactories is private and requires
two arguments. Packaging and IPA upload were skipped. No device execution,
audible output, JIT, GPU or game compatibility has been verified.

V9 changes only that obsolete call to the existing public
InitializeContentSystem(*vfs) entrypoint. Its default overwrite=true policy
and the pinned non-Android FS_READY initialization stage are preserved.
No core access level or signature changes, forced initialization stages,
new filesystem paths, key handling, or extra System::Initialize calls.
The pinned API header/implementation, post-series source, patch and result
are checked by exact hashes. Existing provider setup and launch/stop order
remain unchanged. This repairs a compiler error; runtime remains untested.

All V8 touch, V7 Boost and V6 audio integration, dependency pins, licenses,
runtime/JIT checks, build limits and packaging checks remain unchanged.
The manual workflow uses a standard macos-26 runner, two compiler processes
and a 120 minute timeout. Native arm64 iPhoneOS, minimum iOS 17.4; MoltenVK
is embedded. The IPA is UNSIGNED and created only after successful app
compilation and Mach-O/package inspection. There is no automatic install.

Build recipe with fresh empty work directories:
  bash scripts/build-ios-deps.sh /tmp/citron-ios-deps
  bash scripts/build-citron-ios.sh /tmp/fresh-pinned-source /tmp/citron-ios-deps /tmp/citron-ios-build
  python3 scripts/package-ios.py /tmp/citron-ios-build /tmp/citron-ios-deps/licenses dist

This project contains code and licenses without credentials, signing material,
personal data, console firmware, keys or games. Artifacts are retained for
three days; no release or automatic push is enabled. Signing, trust,
installation and real device testing are separate later work.

Seventh attempt: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions/runs/41358374509
Current build status: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions
