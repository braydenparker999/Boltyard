#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
native_cache="${XDG_CACHE_HOME:-$HOME/.cache}/bolt-yard/native-4.4.1"
mkdir -p "$native_cache" bin build
if [[ ! -x "$native_cache/venv/bin/scons" ]]; then
  python3 -m venv "$native_cache/venv"
  "$native_cache/venv/bin/pip" install 'scons==4.8.1'
fi
if [[ ! -d "$native_cache/godot-cpp/.git" ]]; then
  git clone --depth 1 --branch godot-4.4.1-stable --recursive https://github.com/godotengine/godot-cpp.git "$native_cache/godot-cpp"
fi
test "$(git -C "$native_cache/godot-cpp" rev-parse HEAD)" = e4b7c25e721ce3435a029087e3917a30aa73f06b
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_soft_rig.cpp -o build/test-soft-rig
timeout 120 build/test-soft-rig | tee build/native-tests.log
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_road_drive.cpp -o build/test-road-drive
timeout 120 build/test-road-drive | tee build/road-drive-tests.log
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_crawling.cpp -o build/test-crawling
timeout 120 build/test-crawling | tee build/crawling-tests.log
for suite in imported_terrain crawlworks dynamic_objects linked_suspension expedition redstone tire_contacts rock_queries suspension_behavior recovery; do
  g++ -std=c++17 -O2 -Wall -Wextra -pedantic "native/test_${suite}.cpp" -o "build/test-${suite}"
  timeout 120 "build/test-${suite}" | tee "build/${suite}-tests.log"
done
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/benchmark_handling.cpp -o build/benchmark-handling
timeout 60 build/benchmark-handling | tee build/handling-benchmark.log
g++ -std=c++17 -O2 native/benchmark_contacts.cpp -o build/benchmark-contacts
timeout 120 build/benchmark-contacts | tee build/contact-benchmark.log
export BOLT_GODOT_CPP="$native_cache/godot-cpp"
profile_path="$PWD/native/build_profile.json"
(
  cd native
  "$native_cache/venv/bin/scons" platform=linux arch=x86_64 target=template_debug optimize=speed debug_symbols=no build_profile="$profile_path" -j2
  "$native_cache/venv/bin/scons" platform=android arch=arm64 target=template_debug optimize=speed debug_symbols=no build_profile="$profile_path" -j2
) 2>&1 | tee build/native-build.log
test -s bin/libboltyard.linux.x86_64.so
test -s bin/libboltyard.android.arm64.so
