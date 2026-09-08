"""Apply the Android texture budget after Godot's first import; reimport afterwards."""
from pathlib import Path
root=Path(__file__).resolve().parents[2]
for p in (root/'assets/gridmap/tex').glob('*.import'):
 s=p.read_text().replace('mipmaps/generate=false','mipmaps/generate=true').replace('compress/mode=0','compress/mode=2')
 p.write_text(s)
