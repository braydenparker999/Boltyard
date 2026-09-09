#!/usr/bin/env python3
"""Build a compact, optional Ranger appearance from the owner's supplied ZIP.

No BeamNG runtime, JBeam solver, scripts or external part packs are imported.
Original mesh normals, UVs, material maps and authored rear-slot offsets are
retained. The generated private assets are deliberately excluded from git.
Requires numpy and Pillow. Usage: python3 tools/import_ranger.py path/to/mod.zip
"""
import argparse
from collections import defaultdict
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET
import zipfile

import numpy as np
from PIL import Image

NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}
PREFIX = "nix_83_ranger_"
PARTS = """frame cab cage cab_parts fender_L fender_R bed bed_pan tailgate
tailgate_handle door_L door_R door_parts_L door_parts_R hood hood_pan valance
valance_pan headlight_L headlight_R headlight_glass_L headlight_glass_R grille
grille_pan door_glass_L door_glass_R mirror_L mirror_R mirror_base_L mirror_base_R
wipers cab_pan fender_pan_L fender_pan_R interior bench dash dash_trim
rockslider_L rockslider_R fender_marker_L fender_marker_R valance_marker_L
valance_marker_R radsupport taillight_L taillight_R windshield backlight
backlight_frame fuel_tank crawler_bumper_F crawler_bumper_R roofrack bumper_F bumper_F_pan prerunner_bumper_F""".split()
# Slot offsets in the standard frame/bed JBeam; the DAE contains unshifted parts.
REAR_SHIFT = {"tailgate", "tailgate_handle", "taillight_L", "taillight_R", "crawler_bumper_R"}


def relaxed_json(raw):
    raw = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/',
                 lambda m: m[0] if m[0].startswith('"') else '', raw)
    return json.loads(re.sub(r',\s*([}\]])', r'\1', raw))


class GLB:
    def __init__(self):
        self.data = bytearray()
        self.doc = {"asset": {"version": "2.0", "generator": "Bolt Yard Ranger appearance importer"},
                    "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [],
                    "materials": [], "accessors": [], "bufferViews": [], "images": [],
                    "textures": [], "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]}

    def view(self, data, target=None):
        self.data.extend(b'\0' * (-len(self.data) % 4))
        view = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(data)}
        if target:
            view["target"] = target
        self.doc["bufferViews"].append(view)
        self.data.extend(data)
        return len(self.doc["bufferViews"]) - 1

    def accessor(self, array, kind):
        array = np.asarray(array, dtype='<u4' if kind == 'SCALAR' else '<f4')
        item = {"bufferView": self.view(array.tobytes(), 34963 if kind == 'SCALAR' else 34962),
                "componentType": 5125 if kind == 'SCALAR' else 5126, "count": len(array), "type": kind}
        if kind == 'VEC3':
            item.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
        self.doc["accessors"].append(item)
        return len(self.doc["accessors"]) - 1

    def texture(self, image, name):
        output = io.BytesIO()
        image.save(output, format='PNG', optimize=True)
        self.doc["images"].append({"name": name, "bufferView": self.view(output.getvalue()), "mimeType": "image/png"})
        self.doc["textures"].append({"source": len(self.doc["images"]) - 1, "sampler": 0})
        return len(self.doc["textures"]) - 1

    def save(self, path):
        self.doc["buffers"] = [{"byteLength": len(self.data)}]
        raw = json.dumps(self.doc, separators=(',', ':')).encode()
        raw += b' ' * (-len(raw) % 4)
        self.data.extend(b'\0' * (-len(self.data) % 4))
        path.write_bytes(struct.pack('<III', 0x46546c67, 2, 28 + len(raw) + len(self.data)) +
                         struct.pack('<II', len(raw), 0x4e4f534a) + raw +
                         struct.pack('<II', len(self.data), 0x004e4942) + self.data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--output', type=Path, default=Path('assets/ranger'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    archive = zipfile.ZipFile(args.archive)
    root = ET.fromstring(archive.read('vehicles/nix_83_ranger/nix_83_ranger.dae'))
    definitions = relaxed_json(archive.read('vehicles/nix_83_ranger/nix_83_ranger.materials.json').decode())
    materials = {v.get('mapTo', k): v for k, v in definitions.items()}
    glb = GLB()
    material_ids = {}
    missing = set()

    def read_map(path, limit=1024):
        if not path:
            return None
        path = path.lstrip('/')
        if path not in archive.namelist():
            missing.add(path)
            return None
        image = Image.open(io.BytesIO(archive.read(path))).convert('RGB')
        image.thumbnail((limit, limit), Image.Resampling.LANCZOS)
        return image

    def material(symbol):
        if symbol in material_ids:
            return material_ids[symbol]
        definition = materials.get(symbol, {})
        stages = definition.get('Stages', [{}])
        stage = stages[0]
        pbr = {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": stage.get('metallicFactor', 0.0),
               "roughnessFactor": stage.get('roughnessFactor', 0.65)}
        item = {"name": symbol, "pbrMetallicRoughness": pbr}
        size = 2048 if symbol == PREFIX + 'body' else 1024
        base = read_map(stage.get('baseColorMap'), size)
        normal = read_map(stage.get('normalMap'), size)
        ao = read_map(stage.get('ambientOcclusionMap'), size)
        rough = read_map(stage.get('roughnessMap'), size)
        metal = read_map(stage.get('metallicMap'), size)
        if base:
            pbr['baseColorTexture'] = {"index": glb.texture(base, symbol + '_base')}
        elif 'glass' in symbol or 'windshield' in symbol or 'backlight' in symbol:
            pbr.update(baseColorFactor=[.14, .20, .23, .23], metallicFactor=0.0, roughnessFactor=.12)
            item.update(alphaMode='BLEND', doubleSided=True)
        elif 'headlight' in symbol:
            pbr.update(baseColorFactor=[.78, .80, .77, 1], metallicFactor=.75, roughnessFactor=.18)
            missing.add('material:' + symbol)
        elif 'signal' in symbol:
            pbr.update(baseColorFactor=[.80, .30, .035, 1], metallicFactor=0.0, roughnessFactor=.25)
            missing.add('material:' + symbol)
        else:
            # Shared BeamNG mechanical materials are absent from the archive.
            pbr.update(baseColorFactor=[.10, .12, .13, 1], metallicFactor=.65, roughnessFactor=.48)
            missing.add('material:' + symbol)
        if normal:
            item['normalTexture'] = {"index": glb.texture(normal, symbol + '_normal')}
        if any(x is not None for x in [ao, rough, metal]):
            dims = (size, size)
            def channel(image, fallback):
                return image.resize(dims, Image.Resampling.LANCZOS).getchannel('R') if image else Image.new('L', dims, fallback)
            orm = Image.merge('RGB', (channel(ao, 255), channel(rough, 165), channel(metal, 0)))
            index = glb.texture(orm, symbol + '_orm')
            pbr.update(metallicRoughnessTexture={"index": index}, roughnessFactor=1, metallicFactor=1)
            item['occlusionTexture'] = {"index": index}
            if symbol == PREFIX + 'body':
                # Runtime paint uses the original second UV palette and base
                # opacity mask, preserving seams and the original two-tone areas.
                for name, image in [('body_base', base), ('body_normal', normal), ('body_orm', orm),
                                    ('body_palette', read_map(stages[1].get('colorPaletteMap'), size)),
                                    ('body_opacity', read_map(stages[1].get('opacityMap'), size))]:
                    if image:
                        image.save(args.output / (name + '.png'), optimize=True)
        material_ids[symbol] = len(glb.doc['materials'])
        glb.doc['materials'].append(item)
        return material_ids[symbol]

    # Proper handedness: BeamNG +X left / -Y forward / +Z up -> Godot +X
    # right / -Z forward / +Y up. Geometry stays in authored metres here.
    rotation = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], dtype=np.float64)
    geometries = {g.get('name').removesuffix('Mesh').removeprefix(PREFIX): g
                  for g in root.findall('c:library_geometries/c:geometry', NS)}
    transforms = {}
    for node in root.findall('.//c:visual_scene/c:node', NS):
        instance = node.find('c:instance_geometry', NS)
        matrix = node.find('c:matrix', NS)
        if instance is not None:
            transforms[instance.get('url').lstrip('#')] = np.fromstring(matrix.text, sep=' ').reshape(4, 4) if matrix is not None else np.eye(4)
    batches = defaultdict(list)
    counts = {}
    bounds = []
    for name in PARTS:
        if name not in geometries:
            raise ValueError('Selected geometry missing: ' + name)
        geometry = geometries[name]
        mesh = geometry.find('c:mesh', NS)
        sources = {}
        for source in mesh.findall('c:source', NS):
            stride = int(source.find('c:technique_common/c:accessor', NS).get('stride'))
            sources[source.get('id')] = np.fromstring(source.find('c:float_array', NS).text, sep=' ').reshape(-1, stride)
        vertices = {v.get('id'): v.find('c:input', NS).get('source').lstrip('#') for v in mesh.findall('c:vertices', NS)}
        transform = transforms.get(geometry.get('id'), np.eye(4))
        count = 0
        for triangles in mesh.findall('c:triangles', NS):
            inputs = triangles.findall('c:input', NS)
            stride = 1 + max(int(x.get('offset')) for x in inputs)
            indices = np.fromstring(triangles.find('c:p', NS).text, sep=' ', dtype=np.int32).reshape(-1, stride)
            attributes = {}
            for source in inputs:
                semantic, set_id = source.get('semantic'), source.get('set', '0')
                key = {'VERTEX': 'POSITION', 'NORMAL': 'NORMAL'}.get(semantic)
                if semantic == 'TEXCOORD' and set_id in ['0', '1']:
                    key = 'TEXCOORD_' + set_id
                if not key:
                    continue
                ref = source.get('source').lstrip('#')
                data = sources[vertices[ref] if semantic == 'VERTEX' else ref][indices[:, int(source.get('offset'))]].copy()
                if key == 'POSITION':
                    data = data @ transform[:3, :3].T + transform[:3, 3]
                    if name in REAR_SHIFT:
                        data[:, 1] -= .23
                    data = data @ rotation.T
                    # Measured front/rear wheel-arch centers: -1.489593/+1.2494815.
                    data[:, 2] += .12005575
                    bounds.append(data)
                elif key == 'NORMAL':
                    data = data @ np.linalg.inv(transform[:3, :3]) @ rotation.T
                    data /= np.maximum(np.linalg.norm(data, axis=1)[:, None], 1e-12)
                else:
                    data = data[:, :2]
                    data[:, 1] = 1 - data[:, 1]
                attributes[key] = data
            symbol = triangles.get('material', 'mechanical')
            group = {'roofrack':'roofrack','crawler_bumper_F':'front_bumper','bumper_F':'front_stock','bumper_F_pan':'front_stock','prerunner_bumper_F':'front_tube'}.get(name,'body')
            batches[group, symbol].append(attributes)
            count += len(indices) // 3
        counts[name] = count
    for group in ['body', 'front_bumper', 'front_stock', 'front_tube', 'roofrack']:
        primitives = []
        for (batch_group, symbol), arrays in batches.items():
            if batch_group != group:
                continue
            # Deduplicate complete normal/UV tuples; authored hard edges remain.
            keys = sorted(set.intersection(*(set(a) for a in arrays)))
            combined = {k: np.concatenate([a[k] for a in arrays]).astype('<f4') for k in keys}
            wide = np.concatenate([combined[k] for k in keys], axis=1)
            unique, inverse = np.unique(wide, axis=0, return_inverse=True)
            attributes = {}
            offset = 0
            for key in keys:
                width = combined[key].shape[1]
                attributes[key] = glb.accessor(unique[:, offset:offset+width], 'VEC' + str(width))
                offset += width
            primitives.append({"attributes": attributes, "indices": glb.accessor(inverse, 'SCALAR'), "material": material(symbol)})
        glb.doc['meshes'].append({"name": group, "primitives": primitives})
        glb.doc['nodes'].append({"name": group, "mesh": len(glb.doc['meshes']) - 1})
        glb.doc['scenes'][0]['nodes'].append(len(glb.doc['nodes']) - 1)
    glb.save(args.output / 'ranger.glb')
    cloud = np.concatenate(bounds)
    report = {'source_sha256': hashlib.sha256(args.archive.read_bytes()).hexdigest(), 'triangles': sum(counts.values()),
              'parts': counts, 'draw_surfaces': len(batches), 'source_wheelbase': 2.7390745,
              'bounds': [cloud.min(axis=0).tolist(), cloud.max(axis=0).tolist()],
              'fallbacks': sorted(missing), 'physics': 'Bolt Yard rigid chassis and linked axles; cosmetic mesh has no separate collision'}
    (args.output / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'parts'}, indent=2))


if __name__ == '__main__':
    main()
