#!/usr/bin/env bash
set -euo pipefail

# Run on an Ubuntu GitHub runner after checkout and setup-java.
# Uses the official engine's precompiled Android template, without Gradle.
cd "$(dirname "$0")/.."
: "${JAVA_HOME:?Set JAVA_HOME to a JDK 17 installation}"
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
godot_version=4.4.1
build_root="${XDG_CACHE_HOME:-$HOME/.cache}/bolt-yard/4.4.1"
mkdir -p "$build_root" build
engine_zip="Godot_v${godot_version}-stable_linux.x86_64.zip"
templates_zip="Godot_v${godot_version}-stable_export_templates.tpz"
release_base="https://github.com/godotengine/godot-builds/releases/download/${godot_version}-stable"
godot_bin="$build_root/engine/Godot_v${godot_version}-stable_linux.x86_64"
if [[ ! -x "$godot_bin" ]]; then
  curl --fail --location --retry 3 "$release_base/$engine_zip" -o "$build_root/$engine_zip"
  unzip -oq "$build_root/$engine_zip" -d "$build_root/engine"
  chmod +x "$godot_bin"
  rm "$build_root/$engine_zip"
fi
templates_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${godot_version}.stable"
mkdir -p "$templates_dir"
if [[ ! -s "$templates_dir/android_debug.apk" || ! -s "$templates_dir/android_release.apk" ]]; then
  curl --fail --location --retry 3 "$release_base/$templates_zip" -o "$build_root/$templates_zip"
  unzip -oj "$build_root/$templates_zip" 'templates/android_debug.apk' 'templates/android_release.apk' -d "$templates_dir"
  rm "$build_root/$templates_zip"
fi

sdkmanager_bin="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$sdkmanager_bin" ]]; then
  printf '%s\n' 'Android command-line tools missing.' >&2
  exit 1
fi
"$sdkmanager_bin" 'platform-tools' 'build-tools;34.0.0' 'platforms;android-34' 'ndk;23.2.8568313'

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$config_dir"
python3 - "$config_dir/editor_settings-4.4.tres" <<'PY'
import json, os, sys
from pathlib import Path
text = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
text += 'export/android/java_sdk_path = ' + json.dumps(os.environ['JAVA_HOME']) + '\n'
text += 'export/android/android_sdk_path = ' + json.dumps(os.environ['ANDROID_HOME']) + '\n'
Path(sys.argv[1]).write_text(text)
PY
bash tools/build_native.sh
python3 tools/check_project.py | tee build/resource-checks.log
"$godot_bin" --headless --path . --editor --import 2>&1 | tee build/import.log
if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script' build/import.log; then
  exit 1
fi
timeout 120 "$godot_bin" --headless --path . --script tests/run.gd 2>&1 | tee build/tests.log
if grep -Eq 'SCRIPT ERROR|Parse Error|FAIL:' build/tests.log; then
  exit 1
fi
grep -Eq 'BOLT YARD: [0-9]+ checks, 0 failures' build/tests.log
timeout 120 "$godot_bin" --headless --path . --script tests/offroad.gd 2>&1 | tee build/offroad-tests.log
if grep -Eq 'SCRIPT ERROR|Parse Error|FAIL:' build/offroad-tests.log; then
  exit 1
fi
grep -Eq 'OFFROAD: [0-9]+ checks, 0 failures' build/offroad-tests.log
timeout 120 xvfb-run -a "$godot_bin" --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/capture.gd 2>&1 | tee build/capture.log
grep -q 'CAPTURE: workshop and driving views saved' build/capture.log
"$godot_bin" --headless --path . --export-debug Android build/bolt-yard-0.2.0-softbody.apk 2>&1 | tee build/export.log
test -s build/bolt-yard-0.2.0-softbody.apk
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('build/bolt-yard-0.2.0-softbody.apk') as archive:
    assert any(p.startswith('lib/arm64-v8a/') and 'boltyard' in p and p.endswith('.so') for p in archive.namelist()), 'Native softbody solver missing from APK'
    assert 'lib/arm64-v8a/libc++_shared.so' in archive.namelist(), 'C++ runtime missing from APK'
    assert any(p.endswith('boltyard.gdextension') for p in archive.namelist()), 'GDExtension registration missing from APK'
print('APK includes the native ARM64 soft-body solver.')
PY
"$ANDROID_HOME/build-tools/34.0.0/apksigner" verify --verbose build/bolt-yard-0.2.0-softbody.apk | tee build/signature.log
"$ANDROID_HOME/build-tools/34.0.0/aapt" dump badging build/bolt-yard-0.2.0-softbody.apk > build/package-info.log
sha256sum build/bolt-yard-0.2.0-softbody.apk > build/SHA256SUMS.txt
