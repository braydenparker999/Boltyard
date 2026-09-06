"""Original deterministic periodic RGB scalar shader data, no image source."""
from pathlib import Path
import numpy as np
from PIL import Image

SIZE = 512
rng = np.random.default_rng(104729)

def periodic_value_noise(cells):
    grid = rng.random((cells, cells))
    coordinates = np.arange(SIZE, dtype=np.float32) / SIZE * cells
    whole = coordinates.astype(np.int32)
    fraction = coordinates - whole
    fraction = fraction * fraction * (3 - 2 * fraction)
    ix, iy = np.meshgrid(whole, whole)
    fx, fy = np.meshgrid(fraction, fraction)
    a = grid[iy % cells, ix % cells]
    b = grid[iy % cells, (ix + 1) % cells]
    c = grid[(iy + 1) % cells, ix % cells]
    d = grid[(iy + 1) % cells, (ix + 1) % cells]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

channels = []
for channel in range(3):
    field = sum(periodic_value_noise(cells) * amplitude for cells, amplitude in
                [(4, .44), (8, .24), (16, .15), (32, .09), (64, .05), (128, .03)])
    channels.append(np.clip((field - .5) * 1.65 + .5, 0, 1))
image = (np.stack(channels, axis=-1) * 255).round().astype(np.uint8)
Image.fromarray(image, "RGB").save(Path(__file__).with_name("copper_mineral_noise.png"))
