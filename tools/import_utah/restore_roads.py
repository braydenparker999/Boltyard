"""Bake source road/decal ribbons into terrain tiles, adding no runtime geometry.
Source splines use a Catmull-Rom reconstruction; albedo stage 0 is preserved.
"""
import argparse,json,zipfile,io,collections,math
from pathlib import Path
import numpy as np
from PIL import Image
ap=argparse.ArgumentParser();ap.add_argument('original',type=Path);ap.add_argument('donor',type=Path);args=ap.parse_args()
root=Path(__file__).resolve().parents[2];out=root/'assets/utah/roads';out.mkdir(parents=True,exist_ok=True)
z=zipfile.ZipFile(args.original);donor=zipfile.ZipFile(args.donor);defs={};files={}
for archive in [donor,z]:
 for path in archive.namelist():
  if path.lower().endswith(('.png','.dds','.jpg')):files[Path(path).name.lower()]=(archive,path)
  if path.endswith('.materials.json'):
   try:items=json.loads(archive.read(path))
   except (ValueError,UnicodeError):continue
   for key,value in items.items():defs[key.lower()]=value
roads=[]
for path in z.namelist():
 if path.endswith('items.level.json'):
  for line in z.read(path).decode('utf-8-sig').splitlines():
   if line.strip():
    obj=json.loads(line)
    if obj.get('class')=='DecalRoad':roads.append(obj)
textures={};missing=collections.Counter();skipped=0;restored=0
size=8192;ppm=size/2048.;canvas=np.zeros((size,size,4),dtype=np.uint8)
for road in sorted(roads,key=lambda x:x.get('renderPriority',10)):
 name=road.get('material','');key=name.lower()
 if key in ['road_invisible','defaultdecalroadmaterial','']:skipped+=1;continue
 if key not in textures:
  d=defs.get(key,{});stage=(d.get('Stages') or [{}])[0];file=files.get(Path(stage.get('colorMap','')).name.lower())
  if file:
   archive,path=file;im=Image.open(io.BytesIO(archive.read(path))).convert('RGBA');im.thumbnail((2048,2048));tex=np.asarray(im).astype(float)/255
   tex*=np.clip(np.array(stage.get('diffuseColor',[1,1,1,1])),0,1);textures[key]=(tex,path)
  else:textures[key]=None
 if textures[key] is None:missing[name]+=1;continue
 nodes=np.array(road.get('nodes',[]),dtype=float)
 if len(nodes)<2:continue
 # World X/Z and authored widths. Bake onto the actual terrain rather than
 # floating source elevations; missing bridges remain absent geometry.
 points=nodes[:,[0,1,3]].copy();points[:,1]*=-1
 samples=[]
 for i in range(len(points)-1):
  p0=points[max(0,i-1)];p1=points[i];p2=points[i+1];p3=points[min(len(points)-1,i+2)]
  count=max(1,int(np.ceil(np.linalg.norm(p2[:2]-p1[:2])/3)))
  for t in np.arange(count)/count:
   pos=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
   pos[2]=max(.02,p1[2]*(1-t)+p2[2]*t);samples.append(pos)
 samples.append(points[-1]);samples=np.array(samples)
 widths=samples[:,2];xy=(samples[:,:2]+1024)*ppm
 low=np.maximum(0,np.floor((xy-widths[:,None]*ppm*.6).min(0)).astype(int));high=np.minimum(size,np.ceil((xy+widths[:,None]*ppm*.6).max(0)).astype(int)+1)
 if np.any(high<=low):continue
 patch=np.zeros((high[1]-low[1],high[0]-low[0],4),dtype=np.uint8)
 texture,_=textures[key];th,tw=texture.shape[:2];lengths=np.linalg.norm(np.diff(samples[:,:2],axis=0),axis=1);total=lengths.sum();along=0.;texlength=max(.1,road.get('textureLength',5));fades=road.get('startEndFade',[0,0])
 for i,length in enumerate(lengths):
  if length<1e-5:continue
  a=xy[i];b=xy[i+1];delta=b-a;seg2=np.dot(delta,delta);w0=widths[i]*ppm;w1=widths[i+1]*ppm
  margin=max(w0,w1)*.55+1
  lo=np.maximum(low,np.floor(np.minimum(a,b)-margin).astype(int));hi=np.minimum(high,np.ceil(np.maximum(a,b)+margin).astype(int)+1)
  if np.any(hi<=lo):along+=length;continue
  yy,xx=np.mgrid[lo[1]:hi[1],lo[0]:hi[0]];dx=xx+.5-a[0];dy=yy+.5-a[1]
  t=(dx*delta[0]+dy*delta[1])/seg2;side=(-dx*delta[1]+dy*delta[0])/math.sqrt(seg2);width=np.maximum(.1,w0*(1-t)+w1*t);u=side/width+.5
  mask=(t>=0)&(t<1)&(u>=0)&(u<=1)
  if not mask.any():along+=length;continue
  distance=along+t[mask]*length;v=distance/texlength
  tx=np.clip((u[mask]*(tw-1)).astype(int),0,tw-1);ty=((v%1)*(th-1)).astype(int)
  color=texture[ty,tx].copy()
  fade=np.ones(len(color))
  if fades[0]>0:fade*=np.clip(distance/fades[0],0,1)
  if fades[1]>0:fade*=np.clip((total-distance)/fades[1],0,1)
  # Subpixel edge coverage keeps narrow lane markings visible at 0.25 m/pixel.
  color[:,3]*=fade*np.clip(np.minimum(u[mask],1-u[mask])*width[mask],0,1)
  view=patch[lo[1]-low[1]:hi[1]-low[1],lo[0]-low[0]:hi[0]-low[0]];view[mask]=np.rint(color*255).astype('uint8');along+=length
 dst=canvas[low[1]:high[1],low[0]:high[0]];mask=patch[:,:,3]>0
 if mask.any():
  src=patch[mask].astype(float)/255;old=dst[mask].astype(float)/255;alpha=src[:,3:4]+old[:,3:4]*(1-src[:,3:4]);rgb=(src[:,:3]*src[:,3:4]+old[:,:3]*old[:,3:4]*(1-src[:,3:4]))/np.maximum(alpha,1e-9)
  dst[mask]=np.rint(np.concatenate([rgb,alpha],axis=1)*255).astype('uint8')
 restored+=1
 if restored%500==0:print('Baked',restored,'roads',flush=True)
for y in range(8):
 for x in range(8):Image.fromarray(canvas[y*1024:(y+1)*1024,x*1024:(x+1)*1024]).save(out/f'road_{x}_{y}.png')
report={'source_records':len(roads),'restored_records':restored,'invisible_records_skipped':skipped,'missing_materials':dict(missing),'resolved_textures':{k:v[1] for k,v in textures.items() if v},'resolution_m':.25,'limitations':['Source spline reconstruction and first albedo stage; full original layered PBR is not reproduced.','Road textures do not replace missing bridge geometry.']}
(root/'data/utah/roads_report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
