"""Visual-only 26 m sandstone study. Blender 4.2, CPU Cycles. No runtime exports.
Run: blender -b -t 4 --python tools/blender/rock_study.py
Reuses mesh/stone helpers from build_canyon.py without invoking its exporter.
"""
import bpy, bmesh, math, random, ast, os
from pathlib import Path
from mathutils import Vector, noise
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(os.environ.get('CRAWL_STUDY_OUT',str(ROOT/'build/rock-study')));OUT.mkdir(parents=True,exist_ok=True)
random.seed(2613)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
source=ast.parse((Path(__file__).parent/'build_canyon.py').read_text())
helpers=[n for n in source.body if isinstance(n,ast.FunctionDef) and n.name in ['smooth','mesh_object','bv','stone']]
exec(compile(ast.Module(body=helpers,type_ignores=[]),'canyon_helpers','exec'))
rocks=[]
def N(x,y,z=0):return noise.noise_vector(Vector((x,y,z)))[0]
def material(name,sand=False):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF');p.inputs['Roughness'].default_value=.88
 geo=n.new('ShaderNodeNewGeometry');pos=geo.outputs['Position']
 tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=1.25;tex.inputs['Detail'].default_value=4;l.new(pos,tex.inputs['Vector'])
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.16;ramp.color_ramp.elements[1].position=.85
 ramp.color_ramp.elements[0].color=(.19,.104,.051,1) if not sand else (.29,.20,.12,1)
 ramp.color_ramp.elements[1].color=(.52,.36,.21,1) if not sand else (.48,.34,.21,1)
 l.new(tex.outputs['Fac'],ramp.inputs[0]);col=ramp.outputs['Color']
 if not sand:
  im=n.new('ShaderNodeTexImage');im.image=bpy.data.images.load(str(ROOT/'assets/world/terrain_rock_photo.png'),check_existing=True);im.projection='BOX';im.projection_blend=.25
  scale=n.new('ShaderNodeVectorMath');scale.operation='SCALE';scale.inputs[3].default_value=.38;l.new(pos,scale.inputs[0]);l.new(scale.outputs[0],im.inputs['Vector'])
  mix=n.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=.34;l.new(col,mix.inputs[1]);l.new(im.outputs['Color'],mix.inputs[2]);col=mix.outputs[0]
  wave=n.new('ShaderNodeTexWave');wave.wave_type='BANDS';wave.bands_direction='Z';wave.inputs['Scale'].default_value=2.3;wave.inputs['Distortion'].default_value=3.4;wave.inputs['Detail Scale'].default_value=.6;l.new(pos,wave.inputs['Vector'])
  bands=n.new('ShaderNodeMixRGB');bands.blend_type='MULTIPLY';bands.inputs[0].default_value=.13;l.new(col,bands.inputs[1]);l.new(wave.outputs['Color'],bands.inputs[2]);col=bands.outputs[0]
 l.new(col,p.inputs['Base Color'])
 fine=n.new('ShaderNodeTexNoise');fine.inputs['Scale'].default_value=65 if sand else 22;fine.inputs['Detail'].default_value=3;l.new(pos,fine.inputs['Vector'])
 bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.45;bump.inputs['Distance'].default_value=.016 if sand else .034;l.new(fine.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs['Normal'],p.inputs['Normal'])
 return m
mat=material('Sandstone / bedding and exposed fractures');sandmat=material('Deposited sand',True)
# Shared sloping bedding surfaces, eroded into a continuous floor.
steps=[(3.8,.31,.23),(7.4,.47,.19),(11.9,.33,.34),(15.0,.59,.26),(20.1,.42,.35),(24.0,.35,.4)]
def floor(x,y):
 h=.065*y+.028*x+.12*N(x*.5,y*.38)
 for k,(at,rise,w) in enumerate(steps):
  edge=at+.6*math.sin(x*.55+k)+.13*x+.28*N(x*.8,k*2)
  h+=rise*smooth(edge,edge+w+.5*smooth(-1,4,x),y)
 h+=.22*math.sin(x*.46+y*.14)+.65*smooth(3,10,abs(x))
 # Long oblique joints and local water-scoured dishes.
 for k in [-3.8,1.6,5.2]:h-=.14*math.exp(-((x-k-.16*y)/.16)**2)
 for xx,yy in [(-2,8),(3,15),(-1,22)]:h-=.24*math.exp(-((x-xx)**2/1.2+(y-yy)**2/2.8))
 return h
verts=[];faces=[];nx=201;ny=271
for j in range(ny):
 y=-1+j*.11
 for i in range(nx):
  x=-11+i*.11;verts.append((x,y,floor(x,y)))
for j in range(ny-1):
 for i in range(nx-1):
  a=j*nx+i;faces.append((a,a+1,a+nx+1,a+nx))
ob=mesh_object('Continuous fractured bedrock / 26m study',verts,faces);ob.data.materials.append(mat)
for p in ob.data.polygons:p.use_smooth=True
# Asymmetric buttresses with continuous uneven layers, vertical joint recesses,
# planar faces and localized chipped lips. One closed solid per joint block.
beds=[0,.34,.48,1.15,1.32,2.25,2.38,2.53,3.75,3.95,4.15,5.5,5.65,6.6,7.05,7.4,8.2,8.7]
recess=[.0,.04,.18,.06,.30,.08,.32,.14,.03,.10,.39,.15,.32,.14,.05,.22,.11,.25]
for side in [-1,1]:
 ends=[-2,3.7,9.0,15.5,21.0,28.8] if side==-1 else [-2,5.8,13.2,18.8,24.7,29]
 for section,(a,b) in enumerate(zip(ends,ends[1:])):
  vs=[];fs=[];rows=47;nv=len(beds)
  for j in range(rows):
   t=j/(rows-1);y=a+(b-a)*t
   joint=.40*math.exp(-(t/.045)**2)+.34*math.exp(-((1-t)/.045)**2)
   # Large angled faces: slight irregularity, no repeated sine-wave lobes.
   front=6.3+side*.65+1.2*N(y*.18,side*3)+.42*abs(2*t-1)
   top=.82+.15*N(y*.27,side*4)+(.12 if side<0 else 0)
   for k,z in enumerate(beds):
    warp=.10*N(y*.4,z*.23)+.04*y
    chip=.10*N(y*2.8,z*1.9)
    x=side*(front+joint+recess[k]+z*.08+chip)
    vs.append((x,y,floor(side*6,y)+z*top+warp-.4))
   vs.extend([(side*13,y,vs[-nv][2]),(side*13,y,vs[-1][2]-.2)])
  st=nv+2
  for j in range(rows-1):
   a0=j*st;b0=a0+st
   for k in range(nv-1):fs.append((a0+k,b0+k,b0+k+1,a0+k+1))
   fs.extend([(a0,b0,b0+nv,a0+nv),(a0+nv,a0+nv+1,b0+nv+1,b0+nv),(a0+nv-1,b0+nv-1,b0+nv+1,a0+nv+1)])
  fs.append(tuple(list(range(nv))+[nv+1,nv]));e=(rows-1)*st;fs.append(tuple([e+k for k in range(nv)]+[e+nv+1,e+nv]))
  ob=mesh_object('Jointed cliff %d / %d'%(side,section),vs,fs);ob.data.materials.append(mat)
  bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
  bevel=ob.modifiers.new('Worn bedding corners','BEVEL');bevel.width=.085;bevel.segments=2
  bevel.limit_method='ANGLE';bevel.angle_limit=.45
# Fallen plate-shaped pieces, related to the same bed thickness; settle into floor.
for k in range(42):
 y=random.uniform(0,27);side=random.choice([-1,1]);x=side*random.uniform(4.3,6.8)
 w=random.uniform(.4,1.8);d=random.uniform(.65,2.2);h=random.uniform(.16,.5)
 stone('Detached bed slab %02d'%k,x,-y,w,d,h,floor(x,y)-h*.18,random.uniform(-.5,.5))
# A few larger embedded slabs create asymmetric wheel lines near the camera.
for k,(x,y,w,d,h) in enumerate([(-2.8,4.8,3.8,3.7,.65),(2.7,9.4,3.0,4.3,.53),(-3.6,14.3,3.3,4.2,.76)]):
 stone('Embedded crawling shelf %d'%k,x,-y,w,d,h,floor(x,y)-.25,random.uniform(-.35,.35))
# Neutral outdoor light and real perspective. No painted background or imagegen.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.world.use_nodes=True;n=scene.world.node_tree.nodes;l=scene.world.node_tree.links
sky=n.new('ShaderNodeTexSky');sky.sky_type='NISHITA';sky.sun_elevation=math.radians(38);sky.sun_rotation=math.radians(135);sky.altitude=500;sky.air_density=1.1
l.new(sky.outputs[0],n.get('Background').inputs[0]);n.get('Background').inputs[1].default_value=.10
bpy.ops.object.light_add(type='SUN',location=(-8,-8,14));sun=bpy.context.object;sun.rotation_euler=(math.radians(25),math.radians(-30),math.radians(-35));sun.data.energy=1.25;sun.data.angle=math.radians(8)
scene.view_settings.view_transform='AgX';scene.view_settings.exposure=-1.25;scene.view_settings.look='AgX - Medium High Contrast';scene.render.image_settings.file_format='PNG'
bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='Driving-height review camera';scene.camera=cam
scene.render.resolution_percentage=100
for name,loc,target,res in [('01-driving-view',(.3,-.4,4.3),(-.3,12,1.4),(900,1300)),('02-rock-detail',(-.5,5.5,4.4),(-4.5,11.0,2.4),(1200,850))]:
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=29 if name.startswith('01') else 37
 scene.render.resolution_x,scene.render.resolution_y=res;scene.render.filepath=str(OUT/(name+'.png'))
 bpy.ops.render.render(write_still=True)
 print('REVIEW RENDER:',scene.render.filepath,flush=True)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'rock-study.blend'),compress=True)
print('STUDY COMPLETE',len(bpy.data.objects),'objects',flush=True)
