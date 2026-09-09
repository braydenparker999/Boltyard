"""Pack shared collider templates and original Z-up placements for Godot/native."""
from pathlib import Path
import argparse, json, struct
import numpy as np
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"import_utah"))
from collision_policy import is_collidable_model
parser=argparse.ArgumentParser();parser.add_argument('conversion',type=Path);args=parser.parse_args();root=args.conversion
models=json.loads((root/'data/gridmap/scenery_models.json').read_text());placements=json.loads((root/'placements.json').read_text())
path=root/'data/gridmap/scenery_collision.bin';data=path.read_bytes();count=struct.unpack_from('<I',data,4)[0];offset=8
assert count==len(models)
for _ in range(count):
 offset+=8
 vertices,faces=struct.unpack_from('<II',data,offset);offset+=8+12*(vertices+faces)
assert offset<=len(data)
visual=[];collision=[];conversion=np.array([[1,0,0],[0,0,1],[0,-1,0]])
omitted=0
for model,pos,rotation,scale in placements:
 # These source models have only .link placeholders for their leaf/bark images.
 if any(part in models[model]["source"].lower() for part in ["/trees_oak/","/trees_aspen/"]):
  omitted+=1;continue
 basis=conversion@np.array(rotation).reshape(3,3)@np.diag(scale)@conversion.T
 origin=[pos[0],pos[2],-pos[1]]
 record=struct.pack('<I12f',model,*basis.T.flat,*origin);visual.append(record)
 if is_collidable_model(models[model]):collision.append(record)
(root/'data/gridmap/scenery_instances.bin').write_bytes(struct.pack('<I',len(visual))+b''.join(visual))
path.write_bytes(data[:offset]+struct.pack('<I',len(collision))+b''.join(collision))
(root/'data/gridmap/scenery.json').write_text(json.dumps({'models':models,'placements':len(visual),'colliders':len(collision)},indent=2))
report_path=root/'data/gridmap/import_report.json'
report=json.loads(report_path.read_text());report['omitted_untextured_foliage']=omitted;report['rendered_placements']=len(visual);report['colliders']=len(collision)
report_path.write_text(json.dumps(report,indent=2))
print(f'Packed {len(visual)} visuals and {len(collision)} colliders; {len(models)} shared models')
