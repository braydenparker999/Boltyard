from pathlib import Path
import json,zipfile,collections,re,xml.etree.ElementTree as ET,io
from PIL import Image
import argparse
ap=argparse.ArgumentParser();ap.add_argument('--original',type=Path,required=True);ap.add_argument('--donor',type=Path,required=True);ap.add_argument('--matches',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args();out=args.output;out.mkdir(parents=True,exist_ok=True)
r=json.load(open(args.matches));donor=zipfile.ZipFile(args.donor);src=zipfile.ZipFile(args.original)
models=sorted({x['donor'] for x in r['static_matches']+r['forest_matches'] if x['donor']});ids={p:i for i,p in enumerate(models)}
files={n.lower():n for n in donor.namelist()};names=collections.defaultdict(list)
for n in donor.namelist():names[Path(n).name.lower()].append(n)
def resolve(p):
 p=p.replace('\\','/').lower();p=p.split('/art/')[-1]
 exact=files.get('drycan/art/'+p)
 if exact:return exact
 hits=names[Path(p).name]
 return hits[0] if len(hits)==1 else None
materials={};textures={}
def texture(p):
 n=resolve(p)
 if not p or not n or n.endswith('/'):return ''
 if n in textures:return textures[n]
 try:
  im=Image.open(io.BytesIO(donor.read(n)));im.thumbnail((2048,2048));alpha=im.mode=='RGBA' and im.getextrema()[-1][0]<255
  dest='assets/utah/scenery/tex/'+re.sub('[^a-zA-Z0-9_]','_',n.rsplit('.',1)[0])+('.png' if alpha else '.jpg')
  (out/'assets/utah/scenery/tex').mkdir(parents=True,exist_ok=True)
  if alpha:im.save(out/dest)
  else:im.convert('RGB').save(out/dest,quality=92)
  textures[n]='res://'+dest;return textures[n]
 except Exception as e:print('TEXTURE FAILED',n,str(e));return ''
for n in donor.namelist():
 if n.endswith('.materials.json'):
  try:defs=json.loads(donor.read(n))
  except:continue
  for name,v in defs.items():
   stages=v.get('Stages',[{}]);stage=stages[0] if stages else {};entry={'color':texture(stage.get('colorMap','')),'normal':texture(stage.get('normalMap','')),'double':v.get('doubleSided',False),'alpha':v.get('alphaTest',False),'cutoff':v.get('alphaRef',80)/255.,'tint':stage.get('diffuseColor',[1,1,1,1])}
   materials[name]=entry;materials[v.get('mapTo',name)]=entry
for i,n in enumerate(models):
 xml=donor.read(n).decode('utf-8-sig')
 def replace(m):
  p=texture(m.group(1))
  return '<init_from>'+p+'</init_from>' if p else '<init_from></init_from>'
 xml=re.sub(r'<init_from>([^<]+\.(?:dds|png|jpg|jpeg|tga))</init_from>',replace,xml,flags=re.I)
 (out/f'model_{i}.dae').write_text(xml)
placements=[];staticref={x['reference'].lower():x['donor'] for x in r['static_matches']};forestref={x['type'].lower():x['donor'] for x in r['forest_matches']}
for n in src.namelist():
 if not(n.endswith('.forest4.json') or n.endswith('items.level.json')):continue
 for l in src.read(n).decode('utf-8-sig').splitlines():
  try:v=json.loads(l)
  except:continue
  forest=n.endswith('.forest4.json')
  if forest:p=forestref.get(v.get('type','').lower());pos=v.get('pos')
  else:
   if v.get('class')!='TSStatic':continue
   p=staticref.get(v.get('shapeName','').lower());pos=v.get('position')
  if not p or pos is None:continue
  scale=v.get('scale',1);scale=[scale]*3 if isinstance(scale,(float,int)) else scale
  placements.append([ids[p],pos,v.get('rotationMatrix',[1,0,0,0,1,0,0,0,1]),scale])
(out/'materials.json').write_text(json.dumps(materials));(out/'models.json').write_text(json.dumps(models));(out/'placements.json').write_text(json.dumps(placements));(out/'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
(out/'data/utah').mkdir(parents=True,exist_ok=True)
print('PREPARED',len(models),'models',len(placements),'placements',len(textures),'textures')
