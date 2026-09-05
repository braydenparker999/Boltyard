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
for path in list(root.rglob('*.gd')) + [root / 'project.godot', root / 'main.tscn', root / 'export_presets.cfg']:
    for resource in re.findall(r'res://([^"\n]+)', path.read_text()):
        assert (root / resource).is_file(), f'Missing resource {resource} in {path.name}'
        refs += 1
assert 'architectures/arm64-v8a=true' in (root / 'export_presets.cfg').read_text()
assert 'window/handheld/orientation=0' in (root / 'project.godot').read_text()
assert (root / 'tools/debug.keystore').stat().st_size > 1000
print(f'PASS: starter structure, icon XML, {refs} resource references, Android preset, development key')
print('Godot parser, runtime, physics, rendering, and APK installation require the engine/build workflow.')

