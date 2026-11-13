// SPDX-FileCopyrightText: Copyright 2026 RMS contributors
// SPDX-License-Identifier: GPL-2.0-or-later
// Two host targets from this one file: exact V19 negative control before patches,
// then actual patched ObjectPool + InstStorage + production Inst lifetime defs.
#if defined(CITRON_SHADER_POOL_LEGACY_PROBE)
// SPDX-FileCopyrightText: Copyright 2026 RMS contributors
// SPDX-License-Identifier: GPL-2.0-or-later
// Run against the exact UNPATCHED V19 ObjectPool, not the candidate header.
#include <cassert>
#include <cstdio>
#include <memory>
#include <vector>
#include "shader_recompiler/object_pool.h"
struct NestedOwner {
    static inline unsigned destroyed = 0;
    std::unique_ptr<unsigned char[]> payload = std::make_unique<unsigned char[]>(4096);
    ~NestedOwner() { ++destroyed; }
};
int main() {
    unsigned char* saved[2]{};
    {
        Shader::ObjectPool<NestedOwner> legacy{2};
        saved[0] = legacy.Create()->payload.get();
        saved[1] = legacy.Create()->payload.get();
        legacy.ReleaseContents();
        assert(NestedOwner::destroyed == 0); // Concrete before-fix failure, not expected good behavior.
        // The legacy union destructor lost these owners. Free the captured arrays
        // directly for this negative-control process, without touching ended T slots.
        delete[] saved[0];
        delete[] saved[1];
    }
    assert(NestedOwner::destroyed == 0);
    std::puts("PASS_NEGATIVE_CONTROL_V19_OBJECT_POOL_SKIPS_OWNED_T_DESTRUCTION");
}

#else
// SPDX-FileCopyrightText: Copyright 2026 RMS contributors
// SPDX-License-Identifier: GPL-2.0-or-later
// Actual production ObjectPool and shared InstStorage trim helper. No Vulkan,
// guest, phone or physical-RAM claim. Assertions MUST stay active.
#include <algorithm>
#include <atomic>
#include <cassert>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <memory>
#include <new>
#include <stdexcept>
#include <vector>

#include "common/ios_shader_pool_storage.h"
#include "common/scope_exit.h"
#include "shader_recompiler/object_pool.h"
#include "shader_recompiler/frontend/ir/value.h"

#if defined(NDEBUG) || !defined(CITRON_IOS)
#error "Use -UNDEBUG -DCITRON_IOS=1 for the real production iOS pool methods."
#endif

// Exact production definitions, extracted by pinned source hash.
namespace Shader::IR {
Inst::Inst(IR::Opcode op_, u32 flags_) noexcept : op{op_}, flags{flags_} {
    if (op == Opcode::Phi) {
        std::construct_at(&phi_args);
    } else {
        std::construct_at(&args);
    }
}

Inst::~Inst() {
    if (op == Opcode::Phi) {
        std::destroy_at(&phi_args);
    } else {
        std::destroy_at(&args);
    }
}
}

namespace AllocationAudit {
struct alignas(std::max_align_t) Header { std::size_t bytes; };
inline std::atomic<bool> forbid{};
inline std::atomic<std::size_t> array_bytes{}, array_allocations{}, array_deletions{};
}

void* operator new(std::size_t n) {
    if (AllocationAudit::forbid.load()) throw std::bad_alloc{};
    if (void* p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc{};
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void* operator new[](std::size_t n) {
    using namespace AllocationAudit;
    if (forbid.load() || n > static_cast<std::size_t>(-1) - sizeof(Header)) throw std::bad_alloc{};
    auto* h = static_cast<Header*>(std::malloc(sizeof(Header) + (n ? n : 1)));
    if (!h) throw std::bad_alloc{};
    h->bytes = n;
    array_bytes.fetch_add(n);
    ++array_allocations;
    return h + 1;
}
void operator delete[](void* p) noexcept {
    if (!p) return;
    auto* h = static_cast<AllocationAudit::Header*>(p) - 1;
    AllocationAudit::array_bytes.fetch_sub(h->bytes);
    ++AllocationAudit::array_deletions;
    std::free(h);
}
void operator delete[](void* p, std::size_t) noexcept { ::operator delete[](p); }

namespace {
namespace I = Common::IOS;
struct OwnedNode {
    static inline std::size_t made{}, destroyed{}, live{}, owned_bytes{};
    std::size_t bytes;
    std::unique_ptr<unsigned char[]> payload;
    explicit OwnedNode(unsigned generation, bool fail = false)
        : bytes{32 + generation % 97}, payload{std::make_unique<unsigned char[]>(bytes)} {
        std::fill_n(payload.get(), bytes, static_cast<unsigned char>(generation));
        if (fail) throw std::runtime_error("intentional constructor failure after owned allocation");
        ++made; ++live; owned_bytes += bytes;
    }
    ~OwnedNode() noexcept { ++destroyed; --live; owned_bytes -= bytes; }
};
using Pool = Shader::ObjectPool<OwnedNode>;

void TrimWithoutAllocation(Pool& pool, std::size_t budget) {
    AllocationAudit::forbid = true;
    pool.ReleaseContentsAndTrim(budget);
    AllocationAudit::forbid = false;
    assert(OwnedNode::live == 0 && OwnedNode::owned_bytes == 0);
    assert(pool.StorageBytes() <= budget);
}

void DestructionAndReuse() {
    const auto outer_bytes = AllocationAudit::array_bytes.load();
    {
        Pool pool{4};
        for (unsigned i = 0; i < 12; ++i) (void)pool.Create(i);
        const auto full_storage = pool.StorageBytes();
        const auto two_chunks = full_storage / 3 * 2;
        assert(OwnedNode::live == 12 && full_storage > 0);
        const auto old_destroyed = OwnedNode::destroyed;
        TrimWithoutAllocation(pool, two_chunks);
        assert(OwnedNode::destroyed - old_destroyed == 12);
        const auto kept = pool.StorageBytes();
        assert(kept == two_chunks);
        const auto allocations = AllocationAudit::array_allocations.load();
        for (unsigned i = 0; i < 8; ++i) (void)pool.Create(10 + i);
        // Eight nested payload arrays; no new slot array while retained chunks suffice.
        assert(AllocationAudit::array_allocations.load() - allocations == 8);
        assert(pool.StorageBytes() == kept);
        TrimWithoutAllocation(pool, 0);
        assert(pool.StorageBytes() == 0);
        assert(AllocationAudit::array_bytes == outer_bytes);
        (void)pool.Create(99); // Empty/null-node storage lazily allocates and works again.
        assert(OwnedNode::live == 1);
        // Destructor must also destroy the actual active T, not only the union slot.
    }
    assert(OwnedNode::live == 0 && OwnedNode::owned_bytes == 0);
    assert(AllocationAudit::array_bytes == outer_bytes);

    {
        Pool pool{4};
        for (unsigned i = 0; i < 12; ++i) (void)pool.Create(i);
        const auto destroyed = OwnedNode::destroyed;
        pool.ReleaseContents(); // Also covers legacy squash/Chunk destructor paths on iOS.
        assert(OwnedNode::destroyed - destroyed == 12 && OwnedNode::live == 0);
        (void)pool.Create(1);
    }
    assert(OwnedNode::live == 0 && AllocationAudit::array_bytes == outer_bytes);
}

void ConstructorFailures() {
    const auto baseline = AllocationAudit::array_bytes.load();
    for (unsigned successes : {0u, 1u, 4u, 8u}) {
        Pool pool{4};
        for (unsigned i = 0; i < successes; ++i) (void)pool.Create(i);
        const auto made = OwnedNode::made, destroyed = OwnedNode::destroyed;
        bool threw = false;
        try { (void)pool.Create(17, true); } catch (const std::runtime_error&) { threw = true; }
        assert(threw && OwnedNode::made == made && OwnedNode::destroyed == destroyed);
        assert(OwnedNode::live == successes); // Failed slot MUST NOT be published as live.
        (void)pool.Create(21); // Retry reuses the still-uncommitted slot correctly.
        assert(OwnedNode::live == successes + 1);
        TrimWithoutAllocation(pool, 0);
        assert(OwnedNode::destroyed - destroyed == successes + 1);
        assert(AllocationAudit::array_bytes == baseline);
    }
}

void RepeatedLifetimes() {
    const auto baseline = AllocationAudit::array_bytes.load();
    Pool pool{8};
    const auto one_chunk = pool.StorageBytes();
    for (unsigned generation = 0; generation < 2048; ++generation) {
        const unsigned count = 1 + (generation * 17) % 513;
        for (unsigned i = 0; i < count; ++i) (void)pool.Create(generation + i);
        assert(OwnedNode::live == count);
        TrimWithoutAllocation(pool, generation % 7 == 0 ? 0 : one_chunk * 3);
    }
    TrimWithoutAllocation(pool, 0);
    assert(OwnedNode::made == OwnedNode::destroyed && OwnedNode::live == 0);
    assert(AllocationAudit::array_bytes == baseline);
}

void ActualSharedChunkPolicy() {
    // This SAME production helper is called by actual InstStorage after its existing
    // ReleaseContents. Track real arrays/deletes, not merely arithmetic policy output.
    const auto baseline = AllocationAudit::array_bytes.load();
    std::vector<std::unique_ptr<unsigned char[]>> chunks;
    constexpr std::size_t chunk_bytes = 1024 * 1024;
    for (unsigned i = 0; i < 12; ++i) chunks.push_back(std::make_unique<unsigned char[]>(chunk_bytes));
    const auto bytes = [chunk_bytes](const auto&) noexcept { return chunk_bytes; };
    assert(I::PoolStorageBytes(chunks, bytes) == 12 * chunk_bytes);
    const auto frees = AllocationAudit::array_deletions.load();
    AllocationAudit::forbid = true;
    I::TrimUnusedPoolChunks(chunks, I::INST_POOL_RETAIN_BYTES, bytes);
    AllocationAudit::forbid = false;
    assert(chunks.size() == 8 && AllocationAudit::array_deletions - frees == 4);
    assert(AllocationAudit::array_bytes == baseline + 8 * chunk_bytes);
    AllocationAudit::forbid = true;
    I::TrimUnusedPoolChunks(chunks, 0, bytes);
    AllocationAudit::forbid = false;
    assert(chunks.empty() && AllocationAudit::array_bytes == baseline);
    constexpr auto max = static_cast<std::size_t>(-1);
    assert(I::SaturatingStorageSum(max, 1) == max);
    assert(I::SaturatingStorageProduct(max, 2) == max);
}

struct CompiledOutput { std::vector<unsigned char> owned_metadata; };
enum class BuildResult { Success, Null, Throw };
std::unique_ptr<CompiledOutput> WrapperFixture(Pool& pool, BuildResult result, unsigned kind) {
    pool.ReleaseContentsAndTrim(4096);
    auto cleanup = MakeScopeGuard([&] {
        AllocationAudit::forbid = true;
        pool.ReleaseContentsAndTrim(4096);
        AllocationAudit::forbid = false;
    });
    auto* ir = pool.Create(kind + 37);
    if (result == BuildResult::Throw) throw std::runtime_error("builder failure");
    if (result == BuildResult::Null) return nullptr;
    auto output = std::make_unique<CompiledOutput>();
    output->owned_metadata.assign(ir->payload.get(), ir->payload.get() + ir->bytes);
    pool.ReleaseContentsAndTrim(4096);
    cleanup.Cancel();
    return output;
}

void WrapperOwnershipAndFailureFixture() {
    // Lifetime fixture for the source-proven outer graphics/compute wrappers. This
    // is NOT a test of Vulkan constructors, queues or shader result equivalence.
    for (unsigned kind : {0u, 1u}) {
        Pool pool{4};
        assert(!WrapperFixture(pool, BuildResult::Null, kind) && OwnedNode::live == 0);
        bool threw = false;
        try { (void)WrapperFixture(pool, BuildResult::Throw, kind); }
        catch (const std::runtime_error&) { threw = true; }
        assert(threw && OwnedNode::live == 0);
        auto output = WrapperFixture(pool, BuildResult::Success, kind);
        const auto expected = output->owned_metadata;
        assert(!expected.empty() && OwnedNode::live == 0);
        std::promise<void> ready;
        auto signal = ready.get_future().share();
        auto worker = std::async(std::launch::async,
            [owned = std::move(output), signal] { signal.wait(); return owned->owned_metadata; });
        TrimWithoutAllocation(pool, 0); // Worker only owns the copied result, never IR pointers.
        ready.set_value();
        assert(worker.get() == expected);
    }
}
void ActualInstStorage() {
    namespace IR = Shader::IR;
    IR::InstStorage storage;
    assert(storage.Size() == 0 && storage.StorageBytes() == 0);
    (void)storage.Emplace(IR::Opcode::Identity, 0);
    const auto one_chunk = storage.StorageBytes();
    assert(one_chunk > 0);
    storage.ReleaseContentsAndTrim(0);
    const std::size_t target_chunks = Common::IOS::INST_POOL_RETAIN_BYTES / one_chunk + 3;
    const std::size_t count = target_chunks * IR::InstStorage::chunk_size + 17;
    for (std::size_t i = 0; i < count; ++i) {
        const auto index = storage.Emplace(i % 13 ? IR::Opcode::Identity : IR::Opcode::Phi, 0);
        assert(index == i && storage.IndexOf(storage.At(index)) == index);
    }
    assert(storage.Size() == count && storage.StorageBytes() > Common::IOS::INST_POOL_RETAIN_BYTES);
    assert(storage.StorageBytes() == (target_chunks + 1) * one_chunk);
    AllocationAudit::forbid = true;
    storage.ReleaseContentsAndTrim(Common::IOS::INST_POOL_RETAIN_BYTES);
    AllocationAudit::forbid = false;
    const auto retained = storage.StorageBytes();
    assert(storage.Size() == 0 && retained <= Common::IOS::INST_POOL_RETAIN_BYTES);
    assert(retained % one_chunk == 0);
    const auto kept_count = retained / one_chunk * IR::InstStorage::chunk_size;
    AllocationAudit::forbid = true;
    for (std::size_t i = 0; i < kept_count; ++i) {
        assert(storage.Emplace(IR::Opcode::Identity, 0) == i);
    }
    storage.ReleaseContentsAndTrim(0);
    AllocationAudit::forbid = false;
    assert(storage.Size() == 0 && storage.StorageBytes() == 0);
    for (unsigned generation = 0; generation < 128; ++generation) {
        for (unsigned i = 0; i < 100; ++i) (void)storage.Emplace(IR::Opcode::Phi, 0);
        AllocationAudit::forbid = true;
        storage.ReleaseContentsAndTrim(generation % 2 ? one_chunk : 0);
        AllocationAudit::forbid = false;
        assert(storage.Size() == 0 && storage.StorageBytes() <= one_chunk);
    }
    std::puts("PASS_ACTUAL_IR_INST_STORAGE_TRIM_REUSE_WITH_PINNED_LIFETIME_DEFINITIONS");
}

} // namespace

int main() {
    DestructionAndReuse();
    ConstructorFailures();
    RepeatedLifetimes();
    ActualSharedChunkPolicy();
    ActualInstStorage();
    WrapperOwnershipAndFailureFixture();
    assert(OwnedNode::made == OwnedNode::destroyed && OwnedNode::live == 0);
    std::puts("PASS_IOS_SHADER_OBJECT_POOL_OWNED_DESTRUCTION_2048_LIFETIMES_AND_NOALLOC_TRIM");
    std::puts("PASS_IOS_SHADER_POOL_WRAPPER_ASYNC_ERROR_FIXTURE_NOT_VULKAN_RUNTIME_PROOF");
}

#endif
