"""Pack shared collider templates and original Z-up placements for Godot/native."""
from pathlib import Path
import argparse, json, struct
import numpy as np
parser=argparse.ArgumentParser();parser.add_argument('conversion',type=Path);args=parser.parse_args();root=args.conversion
models=json.loads((root/'data/utah/scenery_models.json').read_text());placements=json.loads((root/'placements.json').read_text())
path=root/'data/utah/scenery_collision.bin';data=path.read_bytes();count=struct.unpack_from('<I',data,4)[0];offset=8
assert count==len(models)
for _ in range(count):
 vertices,faces=struct.unpack_from('<II',data,offset);offset+=8+12*(vertices+faces)
assert offset<=len(data)
visual=[];collision=[];conversion=np.array([[1,0,0],[0,0,1],[0,-1,0]])
for model,pos,rotation,scale in placements:
 basis=conversion@np.array(rotation).reshape(3,3)@np.diag(scale)@conversion.T
 origin=[pos[0],pos[2]-100.207001,-pos[1]]
 record=struct.pack('<I12f',model,*basis.T.flat,*origin);visual.append(record)
 if models[model]['collision_triangles']:collision.append(record)
(root/'data/utah/scenery_instances.bin').write_bytes(struct.pack('<I',len(visual))+b''.join(visual))
path.write_bytes(data[:offset]+struct.pack('<I',len(collision))+b''.join(collision))
(root/'data/utah/scenery.json').write_text(json.dumps({'models':models,'placements':len(visual),'colliders':len(collision)},indent=2))
print(f'Packed {len(visual)} visuals and {len(collision)} colliders; {len(models)} shared models')
