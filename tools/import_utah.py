"""Convert the supplied Utah Extra v9 terrain; never execute archived scripts.
Usage: python tools/import_utah.py /path/to/UtahExtraDS.zip
Requires numpy and Pillow. Imported assets are for the private evaluation build.
"""
import io,json,struct,sys,zipfile,hashlib
from pathlib import Path
import numpy as np
from PIL import Image,ImageFilter
root=Path(__file__).resolve().parents[1];out=root/'data/utah';art=root/'assets/utah'
out.mkdir(parents=True,exist_ok=True);art.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(sys.argv[1]) as z:
 objects=[]
 for n in z.namelist():
  if n.endswith('items.level.json'):
   for line in z.read(n).decode('utf-8-sig').splitlines():
    if line.strip():objects.append((n,json.loads(line)))
 block=next(o for _,o in objects if o.get('class')=='TerrainBlock')
 raw=z.read(block['terrainFile'].lstrip('/'));assert raw[0]==9
 size=struct.unpack_from('<I',raw,1)[0];assert size==2048
 count=size*size
 h=np.frombuffer(raw,'<u2',count,5).reshape(size,size).astype(np.float32)*float(block['maxHeight'])/65536
 # Remove the arbitrary source vertical offset, retaining relative elevations.
 source_layers=np.frombuffer(raw,'u1',count,5+count*2).reshape(size,size)
 layers=source_layers.copy();layers[layers>=14]=3
 # BeamNG (x,y,z) -> Godot (x,z,-y). Include the last outer grid edge.
 xx=np.minimum(np.arange(1025)*2,2047);yy=np.clip(2048-np.arange(1025)*2,0,2047)
 heights=h[np.ix_(yy,xx)].astype('<f4');heights.tofile(out/'height.bin')
 layers[np.ix_(yy,xx)].tofile(out/'surface.bin')
 # Bake the fourteen material identities into one broad color map; two tiled
 # detail maps keep the mobile shader at four texture samples per pixel.
 # Detail textures are mostly neutral modulation maps, not final albedo.
 # Assign physically darker sandstone, soil, vegetation and asphalt base colors.
 palette=np.asarray([[65,65,61],[133,112,91],[162,120,84],[145,108,77],
 [100,103,65],[114,107,71],[122,110,76],[131,111,76],[154,111,76],
 [144,106,75],[149,111,78],[172,132,94],[183,146,107],[87,70,54]],dtype=float)
 full_y=np.clip(2048-np.arange(2048),0,2047);mapped=layers[full_y]
 colors=palette[mapped]
 # Broad source macro texture supplies subtle irregular variation, not geometry.
 macro=Image.open(io.BytesIO(z.read('levels/utahextra/art/terrains/t_macro_rocky_b.png'))).convert('L').resize((2048,2048))
 variation=(np.asarray(macro,dtype=np.float32)/255-.5)*.24+1
 colors=np.clip(colors*variation[:,:,None],0,255).astype('uint8')
 Image.fromarray(colors).filter(ImageFilter.GaussianBlur(.7)).save(art/'ground_color.png')
 weights=np.isin(mapped,[8,9,10]).astype('uint8')*255
 Image.fromarray(weights).filter(ImageFilter.GaussianBlur(1)).save(art/'rock_mask.png')
 for target,source in [('rock','t_dirt_rocks_large_b.png'),('dirt','t_dirt_sandy_b.png')]:
  im=Image.open(io.BytesIO(z.read('levels/utahextra/art/terrains/'+source))).convert('RGB');im.thumbnail((1024,1024));im.save(art/(target+'.jpg'),quality=90)
 landmarks=[]
 wanted={'spawn_Crawl1':'CRAWL TRAILHEAD','spawn_Crawl2':'UPPER CRAWL','spawn_Scenic':'SCENIC RIDGE','spawn_Hillclimb':'HILLCLIMB','spawn_EBNorth':'NORTH OVERLOOK'}
 for _,o in objects:
  if o.get('name') in wanted and o.get('class')=='SpawnSphere':
   x,y,_=o['position'];landmarks.append({'id':o['name'],'name':wanted[o['name']],'x':x,'z':-y,'description':'Terrain preview / stock rock meshes pending'})
 routes=[]
 for n,o in objects:
  if '/ai_roads/crawling/' in n and o.get('nodes'):
   routes.append([[p[0],-p[1],p[3] if len(p)>3 else 3] for p in o['nodes']])
 manifest={'source':'Utah Extra 6.0 by DrowsySam','source_sha256':hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest(),'side':1025,'spacing':2,'origin':-1024,'extent':1024,'spawn':[-561.099121,238.796906],'landmarks':landmarks,'routes':routes,'notes':['Terrain-only private evaluation. Stock Utah cliffs, boulders, bridges, roads and vegetation are not included.','Source hole/special layer values are closed ground with dirt contacts in this prototype.','Vertical datum removed; full horizontal scale retained. Near render and contact triangles share the same 2 m grid.']}
 (out/'manifest.json').write_text(json.dumps(manifest,separators=(',',':')))
 print('Converted',heights.shape,'height range',float(heights.min()),float(heights.max()),'routes',len(routes),'landmarks',len(landmarks))
