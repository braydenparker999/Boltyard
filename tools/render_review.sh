#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Fast still review: reuse the Android job's engine and Linux godot-cpp cache.
# A cold cache builds only Linux; it never downloads Android templates or an SDK.
godot_version=4.4.1
review_cache="${XDG_CACHE_HOME:-$HOME/.cache}/bolt-yard"
engine_root="$review_cache/$godot_version"
native_cache="$review_cache/native-$godot_version"
godot_bin="$engine_root/engine/Godot_v${godot_version}-stable_linux.x86_64"
cpp_dir="$native_cache/godot-cpp"
cpp_library="$cpp_dir/bin/libgodot-cpp.linux.template_debug.x86_64.a"
profile_path="$PWD/native/build_profile.json"
mkdir -p "$engine_root" "$native_cache" bin build
touch build/.gdignore
exec > >(tee build/render-review.log) 2>&1
review_started=$SECONDS

if [[ ! -x "$godot_bin" ]]; then
  engine_zip="Godot_v${godot_version}-stable_linux.x86_64.zip"
  release_base="https://github.com/godotengine/godot-builds/releases/download/${godot_version}-stable"
  curl --fail --location --retry 3 "$release_base/$engine_zip" -o "$engine_root/$engine_zip"
  unzip -oq "$engine_root/$engine_zip" -d "$engine_root/engine"
  chmod +x "$godot_bin"
  rm "$engine_root/$engine_zip"
fi

if [[ ! -d "$cpp_dir/.git" ]]; then
  git clone --depth 1 --branch godot-4.4.1-stable --recursive \
    https://github.com/godotengine/godot-cpp.git "$cpp_dir"
fi
test "$(git -C "$cpp_dir" rev-parse HEAD)" = e4b7c25e721ce3435a029087e3917a30aa73f06b
if [[ ! -s "$cpp_library" || ! -s "$cpp_dir/gen/include/godot_cpp/classes/ref_counted.hpp" ]]; then
  if [[ ! -x "$native_cache/venv/bin/scons" ]]; then
    python3 -m venv "$native_cache/venv"
    "$native_cache/venv/bin/pip" install 'scons==4.8.1'
  fi
  (
    cd "$cpp_dir"
    "$native_cache/venv/bin/scons" platform=linux arch=x86_64 target=template_debug \
      optimize=speed debug_symbols=no build_profile="$profile_path" -j2
  ) 2>&1 | tee build/render-cpp-build.log
fi

# Recompile just this project's binding against the pinned cached static library.
# These defines match godot-cpp's template_debug ABI and binding checks.
g++ -std=c++17 -O2 -fPIC -fno-gnu-unique -shared -pthread \
  -DDEBUG_ENABLED -DDEBUG_METHODS_ENABLED -DHOT_RELOAD_ENABLED \
  -I"$cpp_dir/include" -I"$cpp_dir/gen/include" -I"$cpp_dir/gdextension" \
  native/binding.cpp "$cpp_library" -o bin/libboltyard.linux.x86_64.so \
  2>&1 | tee build/render-native-build.log
test -s bin/libboltyard.linux.x86_64.so

timeout 120 "$godot_bin" --headless --path . --editor --import \
  2>&1 | tee build/render-import.log
if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load script' build/render-import.log; then
  exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1
render_suite() {
  local suite="$1" completion="$2" limit="$3"
  local started=$SECONDS
  timeout "$limit" xvfb-run -a -s '-screen 0 1920x1440x24' "$godot_bin" \
    --path . --audio-driver Dummy --rendering-method gl_compatibility \
    --disable-vsync --fixed-fps 30 --script "tests/$suite.gd" \
    2>&1 | tee "build/render-$suite.log"
  if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:|FAIL:' "build/render-$suite.log"; then
    return 1
  fi
  grep -Eq "$completion" "build/render-$suite.log"
  printf 'RENDER SUITE: %s completed in %s seconds\n' "$suite" "$((SECONDS-started))"
}

timeout 90 "$godot_bin" --headless --path . --script tests/bedrock_contract.gd 2>&1 | tee build/bedrock-contract.log
render_suite bedrock_review "BEDROCK REVIEW: arch" 180
render_suite redstone_review "REDSTONE REVIEW:" 240
render_suite suspension_visuals "SUSPENSION VISUALS: 40 checks, 0 failures" 120
render_suite camera_views 'CAMERA VIEW: camera-rig-portrait.png' 300
render_suite expedition_worlds 'EXPEDITION WORLD CHECKS: [0-9]+ checks / 0 failures' 180
if [[ -f tests/tire_contact_visuals.gd ]]; then
  render_suite tire_contact_visuals 'TIRE CONTACT VISUALS:' 120
fi
test -s build/camera-rig-portrait.png
test -s build/expedition-rockies-contact-scale.png
test -s build/expedition-russia-contact-scale.png
test -s build/expedition-russia-lake.png
printf 'RENDER REVIEW: stills saved in %s seconds\n' "$((SECONDS-review_started))"
