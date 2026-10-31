Citron iPhoneOS prototype — portable build carrier

Status: two Mac attempts completed without an IPA. The second passed CMake
configuration and reached real ARM64/iPhoneOS C++ compilation, then failed on
a missing Sirit quad-swap builder. This V4 revision still needs a successful build
and device tests.
This folder contains no account credentials, personal data, games or console keys.
Do not present its existence or a future successful build as proof that games work.

The manual GitHub Actions workflow uses a standard macos-26 runner, the fixed
official Citron commit in NOTICE.txt, candidate local patches, two parallel compiler
processes and a 120 minute timeout. It builds native arm64 code for minimum iOS 17.4,
links the existing iOS frontend statically, embeds MoltenVK.framework, and
creates an UNSIGNED IPA only after inspecting the generated Mach-O products.
There is no automatic device installation, publication, release or repository push.

The candidate series includes the runtime/JIT probe, ownership fix and pinned
Oaknut error handling. The first Mac attempt exposed dependency test configuration
and architecture-check defects. This revision disables dependency tests, selects
ARM64/AAPCS for Boost.Context, and makes archive architecture checks fail closed.
This revision also checks out the exact Sirit pin, verifies both source hashes,
applies the genuine opcode366 builder with git apply checks and post-patch hashes,
and supplies it through documented CPM_sirit_SOURCE. Shader gates are unchanged.
Local checks passed; V4 still requires a new Mac build and subsequent device tests.
Additional compiler, linker or runtime errors may appear.

Build recipe:
1. Obtain a fresh full checkout of the pinned upstream commit (the workflow does this).
2. Build OpenSSL/FFmpeg for iPhoneOS, not for the host Mac, using build-ios-deps.sh.
3. Apply patches/series.txt and run build-citron-ios.sh.
4. Inspect/package with package-ios.py. The artifact carries license texts and hashes.
5. Signing, trust, installation and actual device/game tests are separate later work.

Local Mac invocation example, using newly chosen empty work/build directories:
  bash scripts/build-ios-deps.sh /tmp/citron-ios-deps
  bash scripts/build-citron-ios.sh /tmp/fresh-pinned-source /tmp/citron-ios-deps /tmp/citron-ios-build
  python3 scripts/package-ios.py /tmp/citron-ios-build /tmp/citron-ios-deps/licenses dist

GitHub Actions resource facts (check current documentation before dispatch):
Standard GitHub-hosted runners in public repositories are free. Private/internal
repository usage consumes included compute and can incur charges; artifact storage
has separate allowances. Larger runners have different billing. This project uses
a standard runner and retains artifacts for 3 days. The first attempt failed
during CMake configuration (missing Catch2 for dependency tests), before app
compilation or packaging. That run did not validate the archive architecture
checks, which are corrected in this revision.
First attempt: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions/runs/41228434324
Current run status: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions
https://docs.github.com/en/actions/reference/runners/github-hosted-runners
https://docs.github.com/en/billing/concepts/product-billing/github-actions
https://docs.github.com/en/actions/tutorials/store-and-share-data

Second attempt: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions/runs/41231489323
Latest attempt status: https://github.com/riccardosmith03-ops/rms-citron-ios-lab/actions
