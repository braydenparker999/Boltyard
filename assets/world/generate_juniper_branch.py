"""Original juniper foliage cutout. No sampled or third-party imagery.

The branch grows from the lower center toward the upper tip. Render at 2x
resolution, then antialias to 512 square for alpha-cutout vegetation cards.
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt

OUT = Path(__file__).resolve().parent
S = 1024
rng = np.random.default_rng(90217)
im = Image.new("RGBA", (S, S), (82, 96, 59, 0))
draw = ImageDraw.Draw(im)


def point_on(points, t):
    p0, p1, p2 = np.asarray(points, float)
    return (1-t)**2 * p0 + 2*(1-t)*t*p1 + t*t*p2


def tangent_on(points, t):
    p0, p1, p2 = np.asarray(points, float)
    v = 2*(1-t)*(p1-p0) + 2*t*(p2-p1)
    return v / max(np.linalg.norm(v), 1e-5)


def needle_spray(points, width, density=1.0, light=0):
    samples = max(10, int(np.linalg.norm(np.asarray(points[2])-points[0]) / 2.6*density))
    pts = [tuple(point_on(points, t)) for t in np.linspace(0, 1, 20)]
    draw.line(pts, fill=(77+light, 80+light, 52+light, 255), width=max(1, int(width)))
    for i in range(samples):
        t = float(rng.uniform(0.03, 1.0))
        pos = point_on(points, t)
        v = tangent_on(points, t)
        theta = math.atan2(v[1], v[0])
        # Repeated short fans form a juniper's overlapping, scale-like sprays.
        for side in [-1, 1]:
            ang = theta + side * rng.uniform(0.38, 1.30)
            length = rng.uniform(8, 21) * (0.70 + 0.30*math.sin(t*math.pi))
            shift = rng.uniform(-2, 2)
            start = pos + np.array([-v[1], v[0]]) * shift
            end = start + np.array([math.cos(ang), math.sin(ang)]) * length
            tone = float(rng.normal(0, 7)) + light + t*7
            palette = rng.choice(4, p=[.31,.33,.23,.13])
            color = [(70,88,48),(80,98,55),(92,107,63),(106,117,72)][palette]
            rgba = tuple(int(np.clip(c+tone, 0,255)) for c in color)+(255,)
            w = int(rng.choice([2,3,4], p=[.28,.57,.15]))
            perp = np.array([-math.sin(ang),math.cos(ang)]) * w*.5
            middle = start + (end-start)*0.32
            draw.polygon([tuple(start), tuple(middle+perp), tuple(end), tuple(middle-perp)], fill=rgba)
            if rng.random()<.19:
                tipstart=start+(end-start)*.67
                draw.line([tuple(tipstart),tuple(end)],fill=(rgba[0]+8,rgba[1]+8,rgba[2]+6,255),width=1)


def branch(points, width, needle=True, light=0):
    ts = np.linspace(0, 1, 24)
    for a,b in zip(ts[:-1],ts[1:]):
        p0,p1 = tuple(point_on(points,float(a))),tuple(point_on(points,float(b)))
        w=max(1,int(width*(1-a)*.77+width*.23))
        draw.line([p0,p1],fill=(87+light,83+light,57+light,255),width=w)
        if w>4:
            draw.line([(p0[0]-.7,p0[1]),(p1[0]-.7,p1[1])],fill=(113+light,105+light,70+light,255),width=max(1,w//4))
    if needle:
        needle_spray(points,width*.38,light=light)


# Slightly kinked central rachis, deliberately visible only near the narrow root.
stem=[(512,990),(536,545),(495,44)]
branch(stem,16,False)
primary=[]
for level,ty in enumerate(np.linspace(.11,.94,14)):
    for side in [-1,1]:
        t=float(np.clip(ty+rng.uniform(-.022,.022),.09,.97))
        root=point_on(stem,t)
        # The low shoulders are broad; upward-tapering shoots make an uneven fan.
        spread=(1-t)**.69*470 * rng.uniform(.86,1.10)
        rise=spread*rng.uniform(.23,.48)+34
        tip=np.array([root[0]+side*spread,root[1]-rise])
        tip=np.clip(tip,[31,28],[993,975])
        bend=np.array([root[0]+side*spread*.53,root[1]-rise*.19])
        curve=[root,bend,tip]
        primary.append((curve,side,t))
        branch(curve,max(2.3,6.8*(1-t)),True,light=int(rng.uniform(-3,4)))

# Feathery branchlets overlap in the core and separate toward the perimeter.
for curve,side,level in primary:
    n=int(np.linalg.norm(np.asarray(curve[2])-curve[0])/16)
    for i in range(n):
        t=float(np.clip((i+1)/(n+1)+rng.uniform(-.025,.025),.08,.97))
        root=point_on(curve,t)
        v=tangent_on(curve,t)
        theta=math.atan2(v[1],v[0])
        for direction in [-1,1]:
            length=rng.uniform(45,94)*(1-t*.50)*(1-level*.34)
            a=theta+direction*rng.uniform(.40,.96)
            end=root+np.array([math.cos(a),math.sin(a)])*length
            mid=root+np.array([math.cos(a-.13*direction),math.sin(a-.13*direction)])*length*.50
            sprig=[root,mid,end]
            needle_spray(sprig,2.0,1.05,light=int(rng.uniform(-4,5)))
            # Terminal secondary sprays add clustered, irregular silhouettes.
            for tt in [.32,.62,.81]:
                if rng.random()<.22:
                    continue
                subroot=point_on(sprig,tt)
                aa=a+rng.choice([-1,1])*rng.uniform(.40,.91)
                sublen=rng.uniform(17,33)*(1-tt*.22)
                subend=subroot+np.array([math.cos(aa),math.sin(aa)])*sublen
                submid=(subroot+subend)*.5
                needle_spray([subroot,submid,subend],1.1,.95,light=3)

# Narrow terminal growth keeps the card's outer tip pointed but irregular.
needle_spray([(495,165),(486,91),(495,37)],3,1.65,light=7)
for _ in range(24):
    t=float(rng.uniform(.19,.83))
    pos=point_on(stem,t)
    a=-math.pi/2+rng.uniform(-1.05,1.05)
    length=rng.uniform(30,75)
    end=pos+np.array([math.cos(a),math.sin(a)])*length
    needle_spray([pos,(pos+end)*.5,end],2,1.3,light=2)

im=im.resize((512,512),Image.Resampling.LANCZOS)
pixels=np.array(im)
# Color dilation prevents black fringes in mipmaps while retaining exact alpha.
transparent=pixels[:,:,3]<8
_, nearest=distance_transform_edt(transparent,return_indices=True)
rgb=pixels[:,:,:3]
rgb[transparent]=rgb[nearest[0][transparent],nearest[1][transparent]]
Image.fromarray(pixels).save(OUT/'juniper_branch.png',optimize=True)
alpha=pixels[:,:,3]
print('juniper_branch.png 512x512 RGBA; alpha coverage > 0.4:',round(float((alpha>102).mean()),3))
