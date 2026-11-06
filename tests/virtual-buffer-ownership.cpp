// Host-only ownership test; no iOS/game data.
// clang++ -std=c++23 -I runtime-patched/src runtime-virtual-buffer-test.cpp -o /tmp/citron-vbuf-test
#include <cassert>
#include <cstddef>
#include <cstdlib>
#include <utility>
#include "common/virtual_buffer.h"
namespace { std::size_t allocated = 0, freed = 0, live = 0; }
namespace Common {
void* AllocateMemoryPages(std::size_t size) noexcept {
    void* p = std::malloc(size);
    if (p) { ++allocated; ++live; }
    return p;
}
void FreeMemoryPages(void* p, std::size_t) noexcept {
    if (p) { std::free(p); ++freed; --live; }
}
}
void RunNsoZeroTailRegression();
int main() {
    {
        Common::VirtualBuffer<unsigned char> a(4);
        assert(a.data()); a[0] = 0x5a;
        auto* original = a.data();
        Common::VirtualBuffer<unsigned char> b(std::move(a));
        assert(!a.data() && a.size() == 0);
        assert(b.data() == original && b[0] == 0x5a && live == 1);
        Common::VirtualBuffer<unsigned char> c(8);
        assert(live == 2);
        c = std::move(b);
        assert(freed == 1 && live == 1);
        assert(!b.data() && b.size() == 0 && c.data() == original);
        c = std::move(c);
        assert(c.data() == original && c[0] == 0x5a && live == 1);
    }
    assert(live == 0 && allocated == 2 && freed == 2);
    RunNsoZeroTailRegression();
}

// SPDX-FileCopyrightText: Copyright 2026 RMS contributors
// SPDX-License-Identifier: GPL-2.0-or-later
// Append-only host regression function for the existing VirtualBuffer ownership
// test. Tests ACTUAL production eligibility/ownership helpers; the byte oracle
// models the unchanged vector/codec-result boundary, not the LZ4 codec itself.
#include "common/ios_initial_code_zero.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <random>
#include <vector>

#if defined(NDEBUG)
#error "NSO zero-tail regression requires active assertions (-UNDEBUG)."
#endif

namespace NsoZeroTailRegression {
namespace I = Common::IOS;
using Bytes = std::vector<std::uint8_t>;
struct Segment { std::uint32_t location, declared; Bytes decoded; bool compressed = false; };
struct Module { std::array<Segment, 3> segments; std::uint32_t bss = 0; Bytes arguments;
                bool patched = false, dump = false, actual_load = true; };
struct Image { Bytes prefix, dense; std::uint32_t full; bool exact; };

Image Build(const Module& module) {
    Bytes prefix;
    bool exact = true;
    std::uint64_t previous = 0;
    for (const auto& segment : module.segments) {
        // decoded is the unchanged ReadBytes/DecompressSegment result, including
        // short reads and failed/short decode outcomes. No codec is substituted.
        const auto end = std::uint64_t(segment.location) + segment.decoded.size();
        exact = exact && segment.decoded.size() == segment.declared &&
                segment.location >= previous && end <= std::numeric_limits<std::uint32_t>::max() &&
                segment.declared <= std::numeric_limits<std::uint32_t>::max() - 4095;
        previous = end;
        prefix.resize(segment.location + segment.decoded.size()); // legacy may shrink!
        std::copy(segment.decoded.begin(), segment.decoded.end(), prefix.begin() + segment.location);
    }
    if (!module.arguments.empty()) {
        constexpr std::uint32_t reserve = 0x9000, header = 0x20;
        assert(module.arguments.size() <= reserve - header);
        const auto at = prefix.size();
        prefix.resize(at + reserve);
        const std::uint32_t actual = static_cast<std::uint32_t>(module.arguments.size());
        // Real NSOArgumentHeader allocated_size/actual_size are little-endian.
        for (unsigned i = 0; i < 4; ++i) {
            prefix[at+i] = static_cast<std::uint8_t>(reserve >> (8*i));
            prefix[at+4+i] = static_cast<std::uint8_t>(actual >> (8*i));
        }
        std::copy(module.arguments.begin(), module.arguments.end(), prefix.begin()+at+header);
    }
    const auto full = static_cast<std::uint32_t>((std::uint32_t(prefix.size()) + module.bss + 4095u) & ~4095u);
    Bytes dense = prefix;
    dense.resize(full); // the legacy result, including zero BSS/padding and shrink semantics.
    if (module.patched && !dense.empty()) dense.back() = 0xa7; // IPS may modify BSS bytes.
    const bool data_supported = std::uint64_t(module.segments[2].declared) + module.bss <=
                                std::numeric_limits<std::uint32_t>::max() - 4095;
    return {std::move(prefix),std::move(dense),full,exact && data_supported};
}

bool Load(const Module& module, std::uint64_t base, Bytes& guest, I::InitialCodeZeroState& state,
          bool created, bool expect_admitted) {
    const auto image = Build(module);
    const auto candidate = I::NsoZeroTailFullSize(image.prefix.size(),module.bss,image.full,
                                                image.exact,module.actual_load,module.patched||module.dump);
    Bytes payload = candidate ? image.prefix : image.dense;
    const auto full = candidate ? *candidate : payload.size();
    const bool admitted = candidate && state.CanElideTail(base,payload.size(),full,created);
    if (candidate && !admitted) payload.resize(full);
    assert(admitted == expect_admitted);
    assert(base <= guest.size() && full <= guest.size()-base);
    std::copy(payload.begin(),payload.end(),guest.begin()+base);
    state.Consume(base,full,created,true);
    return admitted;
}

void Differential() {
    std::mt19937_64 rng(0x19c17a41);
    for (unsigned iteration = 0; iteration < 2048; ++iteration) {
        Module module;
        std::uint32_t at = 0;
        for (unsigned s = 0; s < 3; ++s) {
            at += static_cast<std::uint32_t>(rng()%97);
            const auto size = static_cast<std::uint32_t>(1+rng()%509);
            auto& segment=module.segments[s];
            segment={at,size,Bytes(size),bool(iteration&1)};
            for (std::size_t i=0;i<size;++i) segment.decoded[i]=std::uint8_t((i+s*71+iteration)%251);
            at += size;
        }
        module.bss=static_cast<std::uint32_t>(rng()%16385);
        if (iteration%7==0) module.arguments={'a','r','g',0,'z'};
        if (iteration%11==0) module.patched=true;
        if (iteration%13==0) module.dump=true;
        if (iteration%17==0) { // malformed overlap/non-monotonic resize behavior.
            module.segments[2].location=module.segments[0].location;
        }
        if (iteration%19==0) { // decoded/short-read result shorter than declared size.
            module.segments[1].decoded.resize(module.segments[1].declared/2);
        }
        if (iteration%23==0) { // failed decode outcome, preserving old dense fallback.
            module.segments[2].decoded.clear();
        }
        const auto image=Build(module);
        constexpr std::uint64_t guard=4096;
        Bytes expected(guard+image.full+guard,0x6d),guest=expected;
        std::fill_n(guest.begin()+guard,image.full,0); // actual initial-allocation contract.
        std::copy(image.dense.begin(),image.dense.end(),expected.begin()+guard);
        I::InitialCodeZeroState state;state.Arm(guard,image.full);
        const bool candidate=bool(I::NsoZeroTailFullSize(image.prefix.size(),module.bss,image.full,
            image.exact,true,module.patched||module.dump));
        Load(module,guard,guest,state,true,candidate);
        assert(guest==expected); // includes untouched guard bytes and exact argument reservation.
        // Lack of zero proof, non-Created state or nonzero initial contents MUST
        // rebuild the legacy dense payload, not rely on implicit zero bytes.
        guest.assign(expected.size(),0x6d);
        I::InitialCodeZeroState unarmed;
        Load(module,guard,guest,unarmed,true,false);
        assert(guest==expected);
        guest.assign(expected.size(),0x6d);state.Arm(guard,image.full);
        Load(module,guard,guest,state,false,false);
        assert(guest==expected);
    }
}

void Ownership() {
    I::InitialCodeZeroState state;
    assert(!state.CanElideTail(100,1,4096,true));
    state.Arm(100,40000);
    assert(state.CanElideTail(100,1,4096,true));
    state.Consume(100,4096,true,true); // dense NRO/KIP and sparse NSO consume identically.
    assert(!state.CanElideTail(100,1,4096,true));
    assert(!state.CanElideTail(4195,1,4096,true));
    assert(state.CanElideTail(4196,1,4096,true));
    state.Consume(4196,4096,true,false); // a failed copy permanently poisons eligibility.
    assert(!state.CanElideTail(8292,1,4096,true));
    state.Arm(100,40000);state.Invalidate(); // initializer failure before fresh mapping.
    assert(!state.CanElideTail(100,1,4096,true));
    state.Arm(100,40000);state.Consume(99,1,true,true); // out-of-order/out-of-range dense module.
    assert(!state.CanElideTail(100,1,4096,true));
    state.Arm(100,40000);state.Consume(100,4096,false,true);
    assert(!state.CanElideTail(4196,1,4096,true));
    state.Arm(std::numeric_limits<std::uint64_t>::max()-1,2);
    assert(!state.CanElideTail(0,1,4096,true));
    state.Arm(100,4096);
    assert(!state.CanElideTail(100,4096,4096,true));
    assert(!state.CanElideTail(100,1,4097,true));
    assert(!state.CanElideTail(101,1,4096,true));
    state.Arm(100,40000); // explicit new allocation/rearm, not reuse of prior contents.
    assert(state.CanElideTail(100,1,4096,true));
}

void BoundsAndSequentialLoads() {
    constexpr auto max=std::numeric_limits<std::uint32_t>::max();
    assert(!I::NsoZeroTailFullSize(max,1,0,true,true,false));
    assert(!I::NsoZeroTailFullSize(max-4095,0,max-4095,true,true,false));
    assert(!I::NsoZeroTailFullSize(4097,0,4096,true,true,false));
    assert(!I::NsoZeroTailFullSize(4096,0,4096,true,true,false));
    assert(!I::NsoZeroTailFullSize(1,4096,8192,true,false,false)); // V15 layout-only stays independent.
    assert(!I::NsoZeroTailFullSize(1,4096,8192,true,true,true)); // IPS/dump stays dense.
    assert(!I::NsoZeroTailFullSize(1,4096,8192,false,true,false));
    assert(I::NsoZeroTailFullSize(1,4096,8192,true,true,false)==8192);
    Module module{{Segment{0,4,Bytes{1,2,3,4}},Segment{16,2,Bytes{5,6}},Segment{32,2,Bytes{7,8}}},8000};
    const auto image=Build(module);constexpr std::uint64_t first=4096;
    Bytes guest(6*image.full+2*first,0x6d),expected=guest;
    std::fill(guest.begin()+first,guest.end()-first,0);
    I::InitialCodeZeroState state;state.Arm(first,guest.size()-2*first);
    // Dense producer first, followed by a sparse NSO and then an overlapping NSO.
    std::copy(image.dense.begin(),image.dense.end(),guest.begin()+first);
    std::copy(image.dense.begin(),image.dense.end(),expected.begin()+first);
    state.Consume(first,image.full,true,true);
    const auto second=first+image.full;
    std::copy(image.dense.begin(),image.dense.end(),expected.begin()+second);
    Load(module,second,guest,state,true,true);
    // Fill the untouched remaining zero allocation in the oracle too.
    std::fill(expected.begin()+second+image.full,expected.end()-first,0);
    assert(guest==expected);
    Load(module,first,guest,state,true,false); // overlap requires dense fallback and invalidation.
    assert(guest==expected);
    assert(!state.CanElideTail(second+image.full,1,image.full,true));
    std::atomic<unsigned> count{};
    unsigned records=0;
    for (unsigned i=0;i<100000;++i) {
        const auto slot=I::TakeInitialCodeDiagnostic(count);
        if(slot) {assert(slot==++records && slot<=16);}
    }
    assert(records==16 && count==16); // fixed bound, no counter wrap/re-enabled records.
}
} // namespace NsoZeroTailRegression

void RunNsoZeroTailRegression() {
    NsoZeroTailRegression::Differential();
    NsoZeroTailRegression::Ownership();
    NsoZeroTailRegression::BoundsAndSequentialLoads();
    std::puts("PASS_NSO_INITIAL_ZERO_TAIL_DIFFERENTIAL_2048_AND_OWNERSHIP_NOT_IOS_RUNTIME_PROOF");
}
