from pathlib import Path
import json,zipfile,io,re
from PIL import Image
import argparse
ap=argparse.ArgumentParser();ap.add_argument('conversion',type=Path);ap.add_argument('donor',type=Path);args=ap.parse_args();p=args.conversion;m=json.load(open(p/'materials.json'));z=zipfile.ZipFile(args.donor);names={Path(n).name.lower():n for n in z.namelist() if '/images/' not in n};unknown=json.loads((p/'material-check.log').read_text().split('\n\n',1)[1]);count=0
for key in unknown:
 if key.lower() in m:m[key]=m[key.lower()];continue
 candidates=[key,key.replace('_bld_','_')]
 for name in candidates:
  n=names.get((name+'_d.dds').lower())
  if not n:continue
  entry={'double':False,'alpha':False,'cutoff':.3,'color':'','normal':''}
  for field,suffix in [('color','_d.dds'),('normal','_n.dds')]:
   path=names.get((name+suffix).lower())
   if not path:continue
   im=Image.open(io.BytesIO(z.read(path)));im.thumbnail((2048,2048));alpha=im.mode=='RGBA' and im.getextrema()[-1][0]<255
   dest=re.sub('[^a-zA-Z0-9_]','_',path.rsplit('.',1)[0])+('.png' if alpha else '.jpg');out=p/'assets/utah/scenery/tex'/dest
   if alpha:im.save(out)
   else:im.convert('RGB').save(out,quality=92)
   entry[field]='res://tex/'+dest
   if field=='color' and alpha:entry['alpha']=True
  m[key]=entry;count+=1;break
(p/'materials.json').write_text(json.dumps(m));print('Resolved',count,'additional exact texture names')
