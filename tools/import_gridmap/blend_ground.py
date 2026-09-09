"""Soften visual layer transitions without changing the native material grid."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
root=Path(__file__).resolve().parents[2]
a=np.fromfile(root/'data/gridmap/surface.bin',dtype='u1').reshape(1025,1025)
w=np.stack([np.asarray(Image.fromarray((a==i).astype('uint8')*255).filter(ImageFilter.GaussianBlur(1.0))) for i in range(10)])
order=np.argsort(w,axis=0);first,second=order[-1],order[-2]
u=np.take_along_axis(w,first[None],0)[0].astype(float);v=np.take_along_axis(w,second[None],0)[0].astype(float)
out=root/'assets/gridmap/ground';out.mkdir(parents=True,exist_ok=True)
Image.fromarray(np.stack([first,second,np.rint(255*u/np.maximum(1,u+v))],axis=-1).astype('uint8')).save(out/'blend.png')
