"""Engine-independent resource and packaging checks; not a GDScript compiler."""
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
starter = json.loads((root / 'data/starter.json').read_text())
assert starter['version'] == 1
assert len(starter['parts']) == 21
cells = {(p['x'], p['y'], p['z']) for p in starter['parts']}
assert len(cells) == 21
assert sum(p['kind'] == 'wheel' for p in starter['parts']) == 4
assert sum(p['kind'] == 'seat' for p in starter['parts']) == 1
assert sum(p['kind'] == 'motor' for p in starter['parts']) == 1
ET.parse(root / 'art/icon.svg')
refs = 0
for path in list(root.rglob('*.gd')) + [root / 'project.godot', root / 'main.tscn', root / 'offroad_main.tscn', root / 'export_presets.cfg']:
    # Only complete static loads are file references in scripts. Output paths
    # and concatenated texture names are resolved by the engine runtime gate.
    pattern = r'\b(?:load|preload)\(\s*[\"\']res://([^\"\']+)[\"\']\s*\)' if path.suffix == '.gd' else r'res://([^"\n]+)'
    for resource in re.findall(pattern, path.read_text()):
        # Imported maps are optional private content. The map picker checks
        # height.bin before offering them; validate their art when installed.
        optional = next((name for name in ('utah', 'gridmap') if resource.startswith(f'assets/{name}/')), None)
        if optional and not (root / f'data/{optional}/height.bin').is_file():
            continue
        assert (root / resource).is_file(), f'Missing resource {resource} in {path.name}'
        refs += 1
for path in (root / 'shaders').glob('*.gdshader*'):
    for resource in re.findall(r'#include\s+"([^"]+)"', path.read_text()):
        assert (path.parent / resource).is_file(), f'Missing shader include {resource}'
        refs += 1
assert 'architectures/arm64-v8a=true' in (root / 'export_presets.cfg').read_text()
assert 'window/handheld/orientation=6' in (root / 'project.godot').read_text()
assert (root / 'tools/debug.keystore').stat().st_size > 1000
print(f'PASS: starter structure, icon XML, {refs} resource references, Android preset, development key')
print('Godot parser, runtime, physics, rendering, and APK installation require the engine/build workflow.')
