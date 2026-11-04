V16 PRIVATE iOS VMA64 SOURCE CANDIDATE — NOT BUILT OR DEVICE TESTED
The only new runtime policy in this candidate is CITRON_IOS's Vulkan allocator
preferredLargeHeapBlockSize=64 MiB. Other platforms retain0, selecting VMA3.1's
default256 MiB for large heaps. This is a preferred block quantum, not a hard
memory cap; resource allocation sizes, guest RAM, GC thresholds, dirty readbacks,
retirement/fence lifetimes, staging ring, FPS, audio and lifecycle are unchanged.
V15's layout-copy-elision and the existing five host tests remain byte-for-byte
in this carrier; the separate NSO direct-decode experiment is not included.

Smaller blocks may reduce overreservation or empty-block retention, while increasing
allocation count, allocator/driver overhead or fragmentation. VMA's preferred
dedicated-allocation cutoff changes from half256=128 MiB to half64=32 MiB for
affected default pools; this is a heuristic with existing allocation fallbacks.
It does not resize or truncate resources. Heap-size-based small-pool behavior and
driver-required dedicated allocations remain VMA's existing policy. VMA statistics
for blockBytes-allocationBytes are not measured process-residency savings.
No memory reduction, Mario crash fix or stable commercial gameplay is claimed.
Real Mac compilation, artifact review and controlled on-device measurements are
still required. The historical design notes below describe earlier additions.

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


LOCAL LAZY-ZERO GUEST-BACKING CANDIDATE â€” NOT BUILT OR DEVICE TESTED
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


V12 BOUNDED RENDER DIAGNOSTICS — NOT BUILT OR DEVICE TESTED
No renderer workaround or compatibility/performance improvement is implemented.
The iOS build records only fixed numeric stage counters and relative monotonic
times for up to30seconds per launch. The one recorder writes at most32 explicitly
fflush'ed snapshots and128KiB to citron/log/render-stage-probe.jsonl. It replaces
only that regular, singly-linked, own-UID file. The FileManager-provided own Documents
anchor is retained at initialization; fixed citron and log directory components are
opened with openat/O_NOFOLLOW and checked for own-UID directories;
links/special files are refused before truncation. No fsync, per-instruction trace,
guest data, game name/path, guest/host address or arbitrary diagnostic text is stored.
I/O/start failures disable diagnostics and do not alter launch results.

Schema v1: v=version; g=monotonic launch generation; t_us=elapsed snapshot time;
r=0 initial/1 periodic/2 window end/3 native end; enabled=0 or1.
s holds14 rows [enter,exit,first_enter_us,last_enter_us,first_exit_us,last_exit_us]:
0LaunchSetup,1SystemLoad,2RunEmulation,3SystemRun,4GpfifoSubmit,5GpuListProcess,
6QueueBuffer,7AcquireFramebuffer,8RequestComposite,9FencesReady,10Composite,
11GetRenderFrame,12Present,13FirstFrame. GpuListProcess means a dispatch returned,
which may suspend at a guest semaphore; it does not mean all GPU work completed.
RunEmulation normally remains entered while the session runs. FencesReady means
all guest acquire fences (or zero fences) allowed that composite callback to run.
c holds12 counters: QueueSuccess,AcquireSuccess,CompositeFenceTotal,
PartialMapChunks,PartialMapPages,UnmappedReadChunks,UnmappedReadBytes,
UnmappedWriteChunks,UnmappedWriteBytes,CompositeEmpty,CompositeSkipped,CompositeHidden.
Missing-device-access counts are copy chunks/bytes, separate from holes found at map
time. Composite exits and the existing first-frame hook do not prove visible pixels.

Snapshots overlap relaxed counter updates and are approximate, not atomic frame
histories. Entry/exit differences alone do not establish a stall. Calls crossing
the30second cutoff have censored exits. Hook timestamps/counter updates are limited
to that window; recorder scheduling/I/O can delay the final snapshot. Missed periods
are skipped rather than emitted in a burst. The first late hook also disables further
hooks, without reading origin/window before an accepted lease. No probing changes
guest execution.

Start follows the existing Stop/full-worker join. End follows kernel/GPU/CPU/service
teardown and detached-task drainage; it disables hooks and joins the private-CV
recorder outside session/GPU/logger locks. State reuse is refused while a captured
Scope lease survives. The control handshake is sequentially consistent; counters
stay relaxed. Deferred fence callbacks and owned workers retain their creator's
generation, including nested hooks, so stale callbacks cannot become a new launch.

The existing Mac build script has host-owned tests for concurrent counters,
generation/stale callbacks, live-scope reset refusal, prompt interrupted shutdown,
deadline censoring, numeric schema/size/record bounds and file/link/special-file
refusal. These tests do not run an emulator or GPU. A Mac test pass is not an iOS
runtime proof. Future artifact review and separately authorized device validation
must first recheck the original homebrew, Stop and Restart. No commercial title
fault cause, playable state, frame output or memory-pressure diagnosis is claimed.

Experimental V13 iOS memory profile:
  Only the CITRON_IOS Vulkan shared texture/buffer-cache target is capped at
  512 MiB, after the existing device reserve calculation. Existing cleanup
  thresholds, ages, resource ownership and readback guards remain unchanged.
  The iOS staging stream ring is capped at 32 MiB, with its existing 32 sync
  regions and ordinary-staging fallback. Desktop/Android behavior is unchanged.
  Guest RAM remains 4 GiB; no FPS, guest timing, ASTC or resolution setting changes.
  This is a source experiment: allocator block sizes and other memory remain
  independent, and lower allocation/footprint or compatibility is not established.
  Mac compilation, artifact inspection and device measurements remain required.

V14 local memory diagnostics (PID + six gauges; GC counters deferred):
  Schema2 adds this process's numeric PID to every record. The original14stages
  and12counters keep their meanings. Optional m[6] is texture-cache ownedbytes,
  buffer-cache ownedbytes, sharedcache targetbytes, VMA allocationbytes, VMA
  blockbytes, and sample elapsedmicroseconds. An absent array means no coherent
  sample is available; it does not mean zero memory. Sampling uses an accepted
  launchgeneration lease and atmost1Hz GPU-owner work; the recorder does not
  call GPU/allocator APIs, wait or spin. Publication is coherent but the allocator
  and cache counts are estimates sampled at different points, not residency.
  VMA3.1 allocationbytes and blockbytes are distinct. They exclude guest/JIT and
  allocations made outside that VMAallocator. Cachebytes can fall before delayed
  destruction releases resources. PID strengthens processattribution; filemtime
  and elapsedtime alone do not establish wallclockalignment or gameplay.
  V13's512MiB cachetarget/32MiB stagingring, all GC policies, guestRAM, timing,
  dependencies, lifecycle and old probe counters remain unchanged. VMA blocksize
  preference remains unchanged. This candidate has not been built or device-tested.

V15 private layout-sizing candidate (not built or device-tested):
  For iOS/no-NCE layout-only NSO calls without NSO patches, retain the same
  payload reads/decompression and actual resulting segment lengths, including
  replacement/shrink, arguments, BSS and alignment. Avoid the unused program
  image's allocations, copies and zero-fill during that pass. Real loading,
  patch-present image materialization and NCE retain the normal image path.
  HasNSOPatch is sampled earlier for layout-only calls. Filesystem scan, log and
  exception timing can differ; concurrent mod-directory changes cannot have
  identical timing across layout and real loading. Unsupported 32-bit size
  overflow or oversized arguments are refused, without claiming parity with
  invalid/OOM behavior.
  The build script now compiles and runs the frozen C++ differential test of
  the actual size helper on the Mac host immediately after patch application,
  before iOS work. It compares 2056 bounded old-image cases plus boundaries.
  This does not exercise the full loader or actual LZ4 decoder. The C++ test
  has not been compiled/run for this candidate yet; Mac CI must pass it.
  V14 diagnostics, memory policies, guest RAM, FPS/audio and lifecycle remain
  unchanged. Title-specific allocation sizes and runtime savings are unmeasured;
  this is an efficiency candidate, not a proven Mario crash or gameplay fix.
