"""Filter an existing 3.0 collider pack without changing any render placements."""
from pathlib import Path
import argparse, json, struct
from collision_policy import is_collidable_model

def filtered(data, models):
    magic, count = struct.unpack_from('<II', data)
    if magic != 0x33545542 or count != len(models):
        raise ValueError('Unexpected collider format')
    offset = 8
    for _ in range(count):
        vertices, faces = struct.unpack_from('<II', data, offset)
        offset += 8 + 12 * (vertices + faces)
    template_end = offset
    count = struct.unpack_from('<I', data, offset)[0]
    offset += 4
    if len(data) != offset + 52 * count:
        raise ValueError('Truncated or trailing collider data')
    kept = []
    for i in range(count):
        record = data[offset+i*52:offset+(i+1)*52]
        model = struct.unpack_from('<I', record)[0]
        if is_collidable_model(models[model]):
            kept.append(record)
    return data[:template_end] + struct.pack('<I', len(kept)) + b''.join(kept), count-len(kept)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('data_directory', type=Path)
    args = parser.parse_args()
    meta_path = args.data_directory / 'scenery.json'
    meta = json.loads(meta_path.read_text())
    path = args.data_directory / 'scenery_collision.bin'
    result, removed = filtered(path.read_bytes(), meta['models'])
    path.write_bytes(result)
    meta['colliders'] -= removed
    meta['vegetation_collision'] = False
    meta_path.write_text(json.dumps(meta, indent=2))
    print(f'Removed {removed} vegetation colliders; {meta["colliders"]} remain; visuals unchanged')
