"""Restore original Utah ground identities, images and material parameters."""
import argparse,json,zipfile,struct,io
from pathlib import Path
import numpy as np
from PIL import Image,ImageFilter
ap=argparse.ArgumentParser();ap.add_argument('archive',type=Path);args=ap.parse_args()
root=Path(__file__).resolve().parents[2];out=root/'assets/utah/materials';out.mkdir(parents=True,exist_ok=True)
z=zipfile.ZipFile(args.archive);defs=json.loads(z.read('levels/utahextra/art/terrains/main.materials.json'));defs={v['internalName']:v for v in defs.values() if v.get('class')=='TerrainMaterial'}
b=z.read('levels/utahextra/utheTerrain.ter');side=struct.unpack_from('<I',b,1)[0];off=5+side*side*3;n=struct.unpack_from('<I',b,off)[0];off+=4;names=[]
for i in range(n):length=b[off];off+=1;names.append(b[off:off+length].decode());off+=length
assert n==14
# This image is already oriented like the game X/Z map. The asphalt regions
# were checked against the independently converted surface-material grid.
(root/'assets/utah/ground_color.png').write_bytes(z.read('levels/utahextra/art/terrains/t_terrain_base_b.png'))
layers=np.frombuffer(b,dtype=np.uint8,count=side*side,offset=5+side*side*2).reshape(side,side)
y=np.clip(2048-np.arange(2048),0,2047);layers=layers[y].copy();layers[layers>=14]=3
weights=np.stack([np.asarray(Image.fromarray((layers==i).astype('uint8')*255).filter(ImageFilter.GaussianBlur(1.3))) for i in range(n)])
order=np.argsort(weights,axis=0);a=order[-1];c=order[-2];wa=np.take_along_axis(weights,a[None],axis=0)[0].astype(float);wc=np.take_along_axis(weights,c[None],axis=0)[0].astype(float)
mask=np.stack([a,c,np.rint(255*wa/np.maximum(1,wa+wc))],axis=-1).astype('uint8');Image.fromarray(mask).save(out/'blend.png')
records=[]
for i,name in enumerate(names):
 d=defs[name]
 def read(key,fallback):
  path=d.get(key,fallback).lstrip('/');return Image.open(io.BytesIO(z.read(path))).convert('RGB').resize((512,512),Image.Resampling.LANCZOS)
 color=read('baseColorDetailTex','');normal=read('normalDetailTex','');rough=read('roughnessDetailTex','')
 color.save(out/f'color_{i}.png');rgba=np.dstack([np.asarray(normal),np.asarray(rough)[:,:,0]]);Image.fromarray(rgba).save(out/f'normal_{i}.png')
 records.append({'name':name,'scale':d.get('baseColorDetailTexSize',5),'strength':d.get('baseColorDetailStrength',[.25])[0],'normal_strength':d.get('normalDetailStrength',[.35])[0],'source_color':d['baseColorDetailTex'],'source_normal':d['normalDetailTex'],'source_roughness':d['roughnessDetailTex']})
(root/'data/utah/ground_materials.json').write_text(json.dumps(records,indent=2));print('Restored',len(records),'original material layers with color, normal and roughness')
