Citron iPhoneOS prototype - portable build carrier V10 lifecycle candidate

V9 was built and installed on an iPhone 11. Original homebrew checksum and
frame progress were verified on device. The user-supplied Peace Walker NSP
reaches loading but has shown a black screen so far; gameplay is unverified.
No commercial game or private runtime files are included in this carrier.

V10 changes only the two Swift lifecycle notification callbacks in patch0003:
both started and stopped enqueue their NotificationCenter posts through
DispatchQueue.main.async. This addresses a source-level circular wait during
Stop/Restart: main joins the worker while the worker waits to notify main.
The existing C ABI import/header correction remains intact. This new change
has not been built or tested on device. Native teardown still joins on main
and can take time; a failed launch can retain only the generic stopped error.

Cubeb -4 (NOT_SUPPORTED) from the iOS minimum-latency query is the expected
unsupported-query fallback to the real output-stream test. Audible tone,
interruptions and background/foreground audio recovery remain unverified.
The included MIT-licensed original homebrew smoke is source-only.

All dependency pins, build scripts, workflows, runtime/JIT checks, licenses,
and packaging gates are unchanged from the current 19-file public baseline.
Native arm64 iPhoneOS, minimum iOS 17.4, with embedded MoltenVK. The manual
macos-26 workflow uses two compiler processes and a 120 minute timeout.
An UNSIGNED IPA is produced only after compilation and package inspection.
There is no automatic install. V10 build and on-device validation are pending.

Build recipe with fresh empty work directories:
  bash scripts/build-ios-deps.sh /tmp/citron-ios-deps
  bash scripts/build-citron-ios.sh /tmp/fresh-pinned-source /tmp/citron-ios-deps /tmp/citron-ios-build
  python3 scripts/package-ios.py /tmp/citron-ios-build /tmp/citron-ios-deps/licenses dist

This source carrier contains no credentials, signing material, personal data,
console firmware, keys, games, private logs or runtime files. Preserve COPYING
and NOTICE.txt. Workflow artifacts are retained for three days; no release
or automatic push is enabled.

Build status: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions


LOCAL LAZY-ZERO GUEST-BACKING CANDIDATE — NOT BUILT OR DEVICE TESTED
The iOS generic backend retains the complete configured guest RAM size and VA
addresses. Zero initialization replaces only whole host pages inside the owned
private-anonymous allocation with fresh demand-zero mappings; partial page edges
are explicitly zeroed. Nonzero fills retain memset. No MADV_FREE/DONTNEED zero
assumption, fake guest capacity, or file/fastmem/GPU host-pointer alias is used.
The helper is restricted to the current generic backend with no fastmem arena.
Future host-pointer GPU imports or new backing aliases require revisiting this
contract before enabling that backend. Failed MAP_FIXED remaps may leave holes:
the process prints a fixed phase/errno diagnostic and exits87, with no fallback
access to the affected range. An initialized guest page still reads as zero.
The build runs a Mac-owned-anonymous-memory test of edges, interior zero bytes,
dirty/reclear, bounds and zero length. A Mac pass is not an iOS permission or
runtime proof. Future device validation must begin with the original homebrew
and recheck Stop/Restart before a separately observed commercial launch.
No memory-pressure termination cause or commercial-game compatibility is claimed.
