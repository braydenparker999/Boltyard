"""Blender 4.2 authoring source for the 128 m Bedrock Narrows section.
Run blender -b -t 2 --python tools/blender/build_canyon.py.
The .blend retains editable objects. GLB floor vertices and native collision
samples are exported from the SAME final Blender meshes, in Godot coordinates.
"""
import bpy, bmesh, math, random, json, hashlib
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/canyon'; OUT.mkdir(exist_ok=True)
GEN=ROOT/'native/generated'; GEN.mkdir(exist_ok=True)
random.seed(2405)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
base=[float(v) for v in (Path(__file__).parent/'canyon_base.txt').read_text().split()]
NX,NZ=129,257
X0,Z0,STEP=-32.,-144.,.5
floor_objects=[]; rocks=[]; rock_weights=[]
def smooth(a,b,x):
 t=max(0,min(1,(x-a)/(b-a))); return t*t*(3-2*t)
def center(z): return 5+4*math.sin((-z-16)*.044)
def foundation(x,z):
 gx=max(0,min(NX-1,(x-X0)/STEP)); gz=max(0,min(NZ-1,(z-Z0)/STEP))
 ix=min(NX-2,int(gx)); iz=min(NZ-2,int(gz)); u=gx-ix;v=gz-iz;i=iz*NX+ix
 if u+v<=1:return base[i]+u*(base[i+1]-base[i])+v*(base[i+NX]-base[i])
 return base[i+NX+1]+(1-u)*(base[i+NX]-base[i+NX+1])+(1-v)*(base[i+1]-base[i+NX+1])
def surface(x,z):
 t=-z-16; q=x-center(z)
 # A connected sloping bedrock bed. Each curved fracture crosses the entire
 # formation; weathered shoulders offer alternative wheel lines, not boxes.
 h=.078*t+.24*math.sin(t*.13)+.018*min(q*q,64)
 h+=.17*math.sin(q*.75+t*.18)+.075*math.sin(q*1.8-t*.61)
 for k,(s,rise) in enumerate([(9,.32),(16,.42),(24,.62),(33,.40),(38,.55),(47,.38),(55,.66),(64,.43),(72,.58),(81,.36),(91,.53),(102,.46),(112,.32)]):
  edge=s+1.5*math.sin(q*.17+k*1.41)+q*(.07 if k%2 else -.10)
  width=.6+1.2*smooth(1,7,abs(q+math.sin(k)*3))
  h+=rise*(smooth(edge,edge+width,t)-smooth(edge+4,edge+10,t))
 # Eroded longitudinal fissures; shallow rounded cuts at tire scale.
 for q0 in [-3.9,1.5,6.8]:
  line=q0+.48*math.sin(t*.12+q0)
  h-=.16*math.exp(-((q-line)/.38)**2)*smooth(7,15,t)
 # Full bedrock shoulders climb into the walls.
 h+=1.25*smooth(4,13,abs(q))+.23*math.sin(q*.36+t*.08)
 weight=smooth(0,9,t)*(1-smooth(114,128,t))*smooth(0,7,x-X0)*(1-smooth(57,64,x-X0))
 return foundation(x,z)*(1-weight)+h*weight
heights=[surface(X0+i*STEP,Z0+j*STEP) for j in range(NZ) for i in range(NX)]
for j in range(NZ):
 z=Z0+j*STEP
 for i in range(NX):
  x=X0+i*STEP;q=x-center(z)
  dust=.25+.7*math.exp(-((q+2+math.sin(z*.13))/1.4)**2)
  rock_weights.append(smooth(.28,.94,1-.55*dust))
def ground(x,z):
 ix=max(0,min(NX-1,round((x-X0)/STEP)));iz=max(0,min(NZ-1,round((z-Z0)/STEP)))
 return heights[iz*NX+ix]
def mesh_object(name,verts,faces):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);return ob
# Blender X/Y/Z maps to Godot X/Z/-Y. Blender Y points up the canyon.
def bv(x,y,z):return (x,-z,y)
mat=bpy.data.materials.new('Sandstone reference preview');mat.diffuse_color=(.48,.255,.14,1)
# Eight 16 m floor chunks, explicitly triangulated with the native diagonal.
for chunk in range(8):
 verts=[];faces=[];colors=[]
 for j in range(33):
  row=chunk*32+j;z=Z0+row*STEP
  for i in range(NX):
   x=X0+i*STEP;h=heights[row*NX+i];verts.append(bv(x,h,z))
   q=x-center(z);dust=.25+.7*math.exp(-((q+2+math.sin(z*.13)) / 1.4)**2)
   rock=rock_weights[row*NX+i]
   colors.append((rock,0,0,1))
 for j in range(32):
  for i in range(NX-1):
   a=j*NX+i;faces.extend([(a,a+NX,a+1),(a+1,a+NX,a+NX+1)])
 ob=mesh_object('BedrockFloor_%02d'%chunk,verts,faces);ob.data.materials.append(mat)
 attr=ob.data.color_attributes.new(name='COLOR_0',type='FLOAT_COLOR',domain='POINT')
 for i,c in enumerate(colors):attr.data[i].color=c
 for p in ob.data.polygons:p.use_smooth=True
 ob['collision']='Exact native height samples / 0.5m grid / same diagonal'
 floor_objects.append(ob)
# Rocks are editable, bevelled convex fracture pieces. Export the evaluated
# hulls, so there is no separate approximation of the supporting surfaces.
def stone(name,x,z,w,d,h,base_y,yaw=0,lean=0):
 n=8;verts=[]
 cut=[random.uniform(.15,.40) for _ in range(8)]
 ring=[(-1+cut[0],-1),(1-cut[1],-1),(1,-1+cut[2]),(1,1-cut[3]),(1-cut[4],1),(-1+cut[5],1),(-1,1-cut[6]),(-1,-1+cut[7])]
 tilt=random.uniform(-.10,.10)
 for layer,(scale,yy) in enumerate([(0.85,0),(1,.28),(random.uniform(.72,.94),1)]):
  for i,(u,v) in enumerate(ring):
   px=u*w*.5*scale+lean*yy;pz=v*d*.5*scale
   py=base_y+yy*h+(tilt*px if layer==2 else 0)
   xx=x+px*math.cos(yaw)+pz*math.sin(yaw);zz=z-px*math.sin(yaw)+pz*math.cos(yaw)
   verts.append(bv(xx-x,py-base_y,zz-z))
 ob=mesh_object(name,verts,[])
 ob.location=bv(x,base_y,z)
 bm=bmesh.new()
 for v in ob.data.vertices:bm.verts.new(v.co)
 hull=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
 bmesh.ops.delete(bm,geom=hull['geom_interior'],context='VERTS')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
 bpy.context.view_layer.objects.active=ob;ob.select_set(True)
 bevel=ob.modifiers.new('Weathered fracture edges','BEVEL');bevel.width=min(w,d,h)*random.uniform(.04,.085);bevel.segments=1
 if min(w,d,h)>.8:bpy.ops.object.modifier_apply(modifier=bevel.name)
 else:ob.modifiers.remove(bevel)
 # Re-hull removes numerical concavities before native signed-distance queries.
 bm=bmesh.new()
 for v in ob.data.vertices:bm.verts.new(v.co)
 hull=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
 bmesh.ops.delete(bm,geom=hull['geom_interior'],context='VERTS')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces))
 bm.to_mesh(ob.data);bm.free()
 ob.data.update()
 worst=max((v.co-ob.data.vertices[p.vertices[0]].co).dot(p.normal) for p in ob.data.polygons for v in ob.data.vertices)
 if worst>.0003:
  # Bevel's tolerance can leave a tiny non-supporting facet on small rubble.
  # Re-export its original fracture hull instead; visuals and contacts agree.
  bm=bmesh.new()
  for point in verts:bm.verts.new(point)
  hull=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
  bmesh.ops.delete(bm,geom=hull['geom_interior'],context='VERTS')
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces))
  bm.to_mesh(ob.data);bm.free();ob.data.update()
 ob.data.materials.append(mat);ob.select_set(False)
 ob['collision']='Final Blender convex mesh, exported verbatim'
 rocks.append(ob)
# Continuous closed cliff volumes. Front faces are a sculpted section through
# sedimentary beds; no separated wall bricks. Each chunk shares its border
# exactly with its neighbour and exports the very same concave collision mesh.
levels=[-1.8,0,.7,1.6,2.6,2.9,3.15,3.5,4.8,5.8,6.05,6.35,7.7,8.8,9.1,9.45,10.8,12.2,13.2,14.0]
def cliff_vertex(side,z,v):
 cx=center(z);t=-z
 # Broad buttresses, vertical erosion channels, and subtle bedding recesses.
 buttress=1.25*math.sin(t*.21+side)+.65*math.sin(t*.49+side*.4)
 groove=.40*math.exp(-(math.sin(t*.36)/.16)**2)
 bed=.32*math.sin(v*2.09)+.11*math.sin(v*4.2+t*.06)
 x=cx+side*(10.4+buttress+v*.12+bed+groove)
 top=1+.11*math.sin(t*.075)+.07*math.sin(t*.26+side)
 y=surface(cx+side*8,z)-.7+v*top+.18*math.sin(t*.17+v*.13)
 return bv(x,y,z)
for side in [-1,1]:
 for chunk in range(8):
  verts=[];faces=[];ny=len(levels);rows=17
  for j in range(rows):
   z=-32-(chunk*16+j)*.8
   for v in levels:verts.append(cliff_vertex(side,z,v))
   # Back lower and upper vertices make each section a closed solid volume.
   front_bottom=verts[-ny];front_top=verts[-1]
   verts.extend([bv(center(z)+side*26,front_bottom[2],z),bv(center(z)+side*26,front_top[2]-.8,z)])
  stride=ny+2
  for j in range(rows-1):
   a=j*stride;b=(j+1)*stride
   for k in range(ny-1):faces.append((a+k,b+k,b+k+1,a+k+1))
   faces.extend([(a,b,a+ny,b+ny),(a+ny,a+ny+1,b+ny+1,b+ny),(a+ny-1,b+ny-1,b+ny+1,a+ny+1)])
   # Bottom polygon winding is corrected by Blender below.
   faces[-3]=(a,b,b+ny,a+ny)
  faces.append(tuple(list(range(ny))+[ny+1,ny]))
  end=(rows-1)*stride;faces.append(tuple([end+k for k in range(ny)]+[end+ny+1,end+ny]))
  ob=mesh_object('Continuous_cliff_%d_%d'%(side,chunk),verts,faces)
  bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
  ob.data.materials.append(mat);ob['surface_mesh']=True;ob['collision']='Closed sculpted triangle mesh with native BVH';rocks.append(ob)
# Broken shoulder slabs extend out of the parent rock into the driving floor.
for k in range(20):
 z=random.uniform(-133,-29);side=-1 if k%2 else 1;x=center(z)+side*random.uniform(5.5,9.5)
 stone('Embedded_shelf_%02d'%k,x,z,random.uniform(3.2,6),random.uniform(3.5,7),random.uniform(.9,2.2),ground(x,z)-.55,random.uniform(-.5,.5))
# Rubble concentrated under cliff joints, leaving the central crawl line open.
for k in range(72):
 z=random.uniform(-133,-27);side=-1 if k%2 else 1;x=center(z)+side*random.uniform(4.3,10)
 s=random.uniform(.22,1.15)
 stone('Talus_%02d'%k,x,z,s*1.3,s*1.8,s*.72,ground(x,z)-s*.24,random.uniform(-3,3))
# A continuous concave arch volume with a real shaped opening, not a lintel box.
z=-93;cx=center(z);y=ground(cx,z)
outline=[(-12,-1),(-13,5),(-11,11),(-8,14),(-3,15),(3,14.5),(8,13.7),(12,10),(13,3),(12,-1),(6,-1),(6,4),(5.4,6.5),(3.5,8.6),(.5,9.2),(-3,8.7),(-5.5,6.1),(-6.2,3.5),(-6,-1)]
verts=[]
for depth in [-3.2,3.2]:
 for x,h in outline:verts.append(bv(cx+x,y+h,z+depth+.24*math.sin(x*.6)))
n=len(outline);faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
for i in range(n):j=(i+1)%n;faces.append((i,j,n+j,n+i))
ob=mesh_object('Sculpted_Window_Arch',verts,faces)
bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
ob.data.materials.append(mat);ob['surface_mesh']=True;ob['collision']='Closed arch volume with open passage';rocks.append(ob)
# Export final native samples and hulls. Quantize all geometry to 1 micrometre
# BEFORE GLB output so native and rendered positions stay within float error.
bpy.context.view_layer.update()
for ob in floor_objects+rocks:
 matrix=ob.matrix_world.copy()
 for v in ob.data.vertices:v.co=tuple(round(c,6) for c in matrix @ v.co)
 ob.matrix_world=Matrix.Identity(4)
def fl(v):
 s=f'{float(v):.6f}'.rstrip('0').rstrip('.');return s+('.0' if '.' not in s else '')+'f'
header=['#pragma once','// Generated by tools/blender/build_canyon.py. Do not edit.','namespace boltyard { namespace blender_canyon {',
 'constexpr int nx=129,nz=257; constexpr float x0=-32.f,z0=-144.f,step=.5f;',
 'inline constexpr float heights[]={']
for j in range(NZ):header.append(','.join(fl(heights[j*NX+i]) for i in range(NX))+',')
header+=['};','inline constexpr float rock_weights[]={']
for j in range(NZ):header.append(','.join(fl(rock_weights[j*NX+i]) for i in range(NX))+',')
header+=['};','inline bool contains(float x,float z){return x>=x0&&x<=x0+(nx-1)*step&&z>=z0&&z<=z0+(nz-1)*step;}',
 '''inline float sample(float x,float z,float *dx=nullptr,float *dz=nullptr,const float *values=heights){
 float gx=std::clamp((x-x0)/step,0.f,float(nx-1)),gz=std::clamp((z-z0)/step,0.f,float(nz-1));
 int ix=std::min(nx-2,int(gx)),iz=std::min(nz-2,int(gz)),i=iz*nx+ix;float u=gx-ix,v=gz-iz,a,b,h;
 if(u+v<=1){a=values[i+1]-values[i];b=values[i+nx]-values[i];h=values[i]+u*a+v*b;}
 else{a=values[i+nx+1]-values[i+nx];b=values[i+nx+1]-values[i+1];h=values[i+nx+1]-(1-u)*a-(1-v)*b;}
 if(dx){*dx=a/step;} if(dz){*dz=b/step;} return h;
 }''','}}']
(GEN/'canyon_floor.hpp').write_text('\n'.join(header)+'\n')
header=['#pragma once','// Final convex meshes exported from Bedrock Narrows.blend.','inline void append_blender_canyon_rocks(std::vector<CrawlRock>& out){']
tri_count=0
for ob in rocks:
 header+=['{CrawlRock r; r.surface=1.10f; r.surface_mesh='+('true' if ob.get('surface_mesh',False) else 'false')+'; r.vertices={']
 for v in ob.data.vertices:header.append('{'+','.join(fl(c) for c in (v.co.x,v.co.z,-v.co.y))+'},')
 header+=['};r.triangles={']
 for p in ob.data.polygons:header.append('{'+','.join(str(i) for i in p.vertices)+'},');tri_count+=1
 header+=['};for(auto p:r.vertices)r.center+=p;r.center*=1.f/r.vertices.size();',
 'for(auto t:r.triangles)r.triangle_normals.push_back((r.vertices[t[1]]-r.vertices[t[0]]).cross(r.vertices[t[2]]-r.vertices[t[0]]).normalized());',
 'for(auto p:r.vertices)r.reach=std::max(r.reach,(p-r.center).length());r.rebuild_queries();out.push_back(std::move(r));}']
header+=['}'];(GEN/'canyon_rocks.hpp').write_text('\n'.join(header)+'\n')
# Keep the actual editable Blender scene in source control. Source assets do not
# go in the APK; only the floor GLB and compiled native data do.
bpy.context.scene['description']='128m connected sandstone canyon, shared Blender/native geometry'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'tools/blender/bedrock_narrows.blend'),compress=True)
bpy.ops.object.select_all(action='DESELECT')
for ob in floor_objects:ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'bedrock_floor.glb'),export_format='GLB',use_selection=True,export_yup=True,export_normals=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=True)
manifest={'authoring':'Blender '+bpy.app.version_string,'length_m':128,'width_m':64,'floor_spacing_m':.5,'floor_triangles':65536,'collision_shapes':len(rocks),'convex_hulls':sum(not ob.get('surface_mesh',False) for ob in rocks),'concave_meshes':sum(bool(ob.get('surface_mesh',False)) for ob in rocks),'rock_triangles':tri_count,'floor_sha256':hashlib.sha256((OUT/'bedrock_floor.glb').read_bytes()).hexdigest(),'entry':[5,-28],'arch':[cx,-93],'coordinates':'Godot X,Y up,Z; Blender X,-Z,Y up','textures':'Existing generated terrain_rock_photo albedo; Poly Haven CC0 detail normal; see assets/world provenance files'}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print('CANYON EXPORT:',json.dumps(manifest))
