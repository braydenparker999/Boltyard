#include "soft_rig.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace boltyard;

static void load_map(const char *path, size_t expected, bool authored) {
    std::ifstream file(path, std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(file)), {});
    assert(imported_scenery::load(bytes.data(), bytes.size()));
    assert(imported_scenery::instances.size() == expected);
    size_t checked=0;
    for (const auto &r : imported_scenery::instances) {
        assert(r.authored_surface == authored);
        assert(r.source >= imported_scenery::meshes.data());
        assert(r.source < imported_scenery::meshes.data()+imported_scenery::meshes.size());
        if (authored) {
            assert(r.surface >= 1.04f && r.surface <= 1.11f);
            assert(r.surface_id == 0 || r.surface_id == 1);
        }
        if (++checked > 1000) break;
        std::vector<const CrawlRock*> near;
        imported_scenery::near(r.center, 1, near);
        assert(std::find(near.begin(), near.end(), &r) != near.end());
    }
}
int main() {
    load_map("data/gridmap/scenery_collision.bin",860,true);
    load_map("data/utah/scenery_collision.bin",109772,false);
    load_map("data/gridmap/scenery_collision.bin",860,true);
    std::cout << "PASS: v4 authored materials, v3 compatibility, map reload and spatial queries\n";
}
