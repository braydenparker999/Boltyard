"""Vegetation is visual-only; preserve authored rock/structure collision."""
from pathlib import PurePosixPath

def is_collidable_model(model):
    source = model['source'].replace('\\', '/').lower()
    name = PurePosixPath(source).name
    vegetation = '/trees/' in source or '/vegetation/' in source or name.startswith(('juniper_', 'pine_', 'bush_', 'grass_'))
    return bool(model['collision_triangles']) and not vegetation
