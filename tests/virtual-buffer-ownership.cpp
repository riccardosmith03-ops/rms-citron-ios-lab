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
}
