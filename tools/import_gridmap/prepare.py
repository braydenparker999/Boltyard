"""Read Gridmap Refresh data without executing its scripts. Private asset conversion."""
from pathlib import Path
import sys,json,re,struct,collections,xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
src=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
art=out/'assets/gridmap';data=out/'data/gridmap';art.mkdir(parents=True,exist_ok=True);data.mkdir(parents=True,exist_ok=True)
files={str(p.relative_to(src)).lower():p for p in src.rglob('*') if p.is_file()};byname=collections.defaultdict(list)
for p in files.values():byname[p.name.lower()].append(p)
missing=collections.Counter();resolved={}
def resolve(path):
 path=str(path or '').replace('\\','/').lstrip('/');p=files.get(path.lower())
 if p:return p
 hits=byname[Path(path).name.lower()]
 if len(hits)==1:return hits[0]
 if len(hits)>1 and len({p.read_bytes() for p in hits})==1:return hits[0]
 if '/levels/' in '/'+path:
  suffix='levels/'+path.split('/levels/')[-1] if '/levels/' in path else path
  p=files.get(suffix.lower())
  if p:return p
 # DDS virtual paths sometimes refer to PNG source art.
 for ext in ['.png','.dds','.jpg']:
  p=files.get(str(Path(path).with_suffix(ext)).lower())
  if p:return p
 return None
textures={}
def texture(path):
 if not path:return ''
 p=resolve(path)
 if not p:missing[str(path)]+=1;return ''
 if p in textures:return textures[p]
 try:
  im=Image.open(p);im.thumbnail((1024,1024));dest='assets/gridmap/tex/'+re.sub('[^a-zA-Z0-9_]','_',str(p.relative_to(src)).rsplit('.',1)[0])+'.png'
  (out/dest).parent.mkdir(exist_ok=True,parents=True);im.convert('RGBA' if 'A' in im.mode else 'RGB').save(out/dest);textures[p]='res://'+dest;return textures[p]
 except Exception as e:missing[str(path)+': '+str(e)]+=1;return ''
objects=[]
for p in src.rglob('items.level.json'):
 for line in p.read_text().splitlines():
  try:v=json.loads(line);v['_file']=str(p);objects.append(v)
  except ValueError:pass
forest={}
for p in src.rglob('*.cs'):
 for name,body in re.findall(r'(?:datablock|singleton)\s+TSForestItemData\s*\(([^)]+)\)\s*\{(.*?)\};',p.read_text(errors='ignore'),re.S):
  shape=re.search(r'shapeFile\s*=\s*"([^"]+)"',body)
  if shape:forest[name.lower()]=shape[1]
placements=[];missing_models=collections.Counter()
for v in objects:
 if v.get('class')!='TSStatic':continue
 path=v['shapeName'];p=resolve(path)
 if not p:missing_models[path]+=1;continue
 placements.append((p,v['position'],v.get('rotationMatrix',[1,0,0,0,1,0,0,0,1]),v.get('scale',[1,1,1])))
for p in src.rglob('*.forest4.json'):
 for line in p.read_text().splitlines():
  try:v=json.loads(line)
  except:continue
  path=forest.get(v['type'].lower(),v['type']+'.dae');shape=resolve(path)
  if not shape:missing_models[path]+=1;continue
  scale=v.get('scale',1);placements.append((shape,v['pos'],v.get('rotationMatrix',[1,0,0,0,1,0,0,0,1]),[scale]*3))
models=sorted({p[0] for p in placements});ids={p:i for i,p in enumerate(models)}
used=set()
for i,p in enumerate(models):
 root=ET.parse(p).getroot();ns={'c':'http://www.collada.org/2005/11/COLLADASchema'}
 for node in root.findall('.//c:library_materials/c:material',ns):used.add(node.attrib.get('name',node.attrib.get('id')))
 xml=p.read_text(encoding='utf-8-sig');xml=re.sub(r'<init_from>([^<]+\.(?:dds|png|jpg|tga))</init_from>',lambda m:'<init_from>'+texture(m[1])+'</init_from>',xml,flags=re.I)
 (out/f'model_{i}.dae').write_text(xml)
used.update(v.get('material','') for v in objects if v.get('class')=='DecalRoad')
material_defs={}
for p in src.rglob('*.materials.json'):
 try:d=json.loads(p.read_text())
 except:continue
 for name,v in d.items():
  if v.get('class')!='Material':continue
  material_defs[name]=v;material_defs[v.get('mapTo',name)]=v
materials={}
for name in used:
 v=material_defs.get(name,{})
 st=(v.get('Stages') or [{}])[0]
 materials[name]={'color':texture(st.get('baseColorMap') or st.get('colorMap')),'normal':texture(st.get('normalMap')),'roughness':texture(st.get('roughnessMap')),'tint':st.get('baseColorFactor') or st.get('diffuseColor') or [1,1,1,1], 'double':v.get('doubleSided',False),'alpha':v.get('alphaTest',False),'cutoff':v.get('alphaRef',80)/255,'blend':v.get('translucent',False),'ground':v.get('groundType','ROCK' if 'rock' in name.lower() else 'ASPHALT'),'roughness_factor':st.get('roughnessFactor',.85)}
 if not v:missing['MATERIAL '+name]+=1
block=next(v for v in objects if v.get('class')=='TerrainBlock');raw=resolve(block['terrainFile']).read_bytes();n=struct.unpack_from('<I',raw,1)[0];assert raw[0]==9 and n==1024
h=np.frombuffer(raw,'<u2',n*n,5).reshape(n,n).astype(np.float32)/32+block['position'][2]
layer=np.frombuffer(raw,'u1',n*n,5+n*n*2).reshape(n,n);off=5+n*n*3;k=struct.unpack_from('<I',raw,off)[0];off+=4;names=[]
for _ in range(k):l=raw[off];off+=1;names.append(raw[off:off+l].decode());off+=l
xx=np.minimum(np.arange(1025),1023);yy=np.clip(1024-np.arange(1025),0,1023)
h[np.ix_(yy,xx)].astype('<f4').tofile(data/'height.bin');layer[np.ix_(yy,xx)].tofile(data/'surface.bin')
terrain_defs=json.loads(next(src.rglob('art/terrains/main.materials.json')).read_text());tm=[]
# Native ids: dirt 0, dry rock 1, wet rock 2, mud 3, sand 4, wood 5, gravel 6.
grips={'ASPHALT':(1.05,0),'ROCK':(1.10,1),'GRASS':(.78,0),'DIRT':(.85,0),'MUD':(.55,3),'SAND':(.70,4),'ICE':(.12,0)}
for name in names:
 v=dict(terrain_defs[name])
 if name=='Mud':
  # Use actual bundled legacy pixels where the newer PBR files are .link stubs.
  if not resolve(v.get('baseColorDetailTex')):v['baseColorDetailTex']='levels/gridmap_remastered/art/terrains/terrain_mud_d.color.DDS'
  if not resolve(v.get('normalDetailTex')):v['normalDetailTex']='levels/gridmap_remastered/art/terrains/terrain_mud_n.normal.DDS'
 ground=v.get('groundmodelName','ASPHALT');g,kind=grips.get(ground,(1.05,0))
 tm.append({'name':name,'ground':ground,'grip':g,'surface':kind,'color':texture(v.get('baseColorDetailTex')),'base':texture(v.get('baseColorBaseTex')),'normal':texture(v.get('normalDetailTex')),'roughness':texture(v.get('roughnessDetailTex')),'scale':v.get('baseColorDetailTexSize',v.get('detailSize',2)), 'strength':v.get('baseColorDetailStrength',[.25])[0]})
spawns=[v for v in objects if v.get('class')=='SpawnSphere'];default=next(v for v in spawns if v['name']=='spawn_default')['position'];landmarks=[]
for v in spawns:
 p=v['position'];landmarks.append({'id':v['name'],'name':v['name'].replace('spawn_','').replace('_',' ').upper(),'x':p[0],'y':p[2],'z':-p[1],'description':'Original Gridmap Refresh spawn'})
manifest={'source':'Gridmap Refresh 1.0 by Bifdro / original assets by BeamNG','extent':512,'spacing':1,'spawn':[default[0],-default[1]],'landmarks':landmarks,'routes':[],'materials':tm}
(out/'models.json').write_text(json.dumps([str(p.relative_to(src)) for p in models]));(out/'placements.json').write_text(json.dumps([[ids[p],pos,rot,scale] for p,pos,rot,scale in placements]));(out/'materials.json').write_text(json.dumps(materials));(data/'manifest.json').write_text(json.dumps(manifest,indent=2));(data/'objects.json').write_text(json.dumps(objects));(data/'materials.json').write_text(json.dumps(materials))
(data/'import_report.json').write_text(json.dumps({'models':len(models),'placements':len(placements),'textures':len(textures),'missing_models':missing_models,'unresolved_material_paths':missing},indent=2))
(out/'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\ntextures/vram_compression/import_etc2_astc=true\n')
print('Prepared',len(models),'models',len(placements),'placements',len(textures),'textures; missing models',dict(missing_models),'unresolved textures',dict(missing))
