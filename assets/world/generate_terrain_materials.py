"""Original, deterministic, seamless dry alpine terrain materials for Bolt Yard.

Run: python assets/world/generate_terrain_materials.py
Requires NumPy, SciPy, Pillow. No external source imagery is used.
"""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, map_coordinates
from scipy.spatial import cKDTree

OUT = Path(__file__).resolve().parent
SIZE = 1024
FINAL = 512
Y, X = np.mgrid[:SIZE, :SIZE].astype(np.float32)


def smooth(rng, sigma):
    n = gaussian_filter(rng.normal(size=(SIZE, SIZE)), sigma, mode="wrap")
    return (n / max(float(n.std()), 1e-7)).astype(np.float32)


def material_base(rng, color, variability=1.0):
    # Independent, bounded octaves; large patches are deliberately low contrast.
    macro = smooth(rng, 47) * 1.5 + smooth(rng, 16) * 2.0
    mid = smooth(rng, 4) * 2.0 + smooth(rng, 1.2) * 1.5
    grain = rng.normal(0, 1.3, size=(SIZE, SIZE))
    values = np.asarray(color, np.float32)[None, None, :] + (
        macro + mid + grain
    )[..., None] * variability * np.array([1.0, 0.92, 0.77])
    return np.clip(values, 0, 255).astype(np.uint8)


def periodic_draw(draw, kind, points, **kwargs):
    """Draw features over the torus, including strokes crossing a tile edge."""
    pts = list(points)
    xmin = min(p[0] for p in pts)
    xmax = max(p[0] for p in pts)
    ymin = min(p[1] for p in pts)
    ymax = max(p[1] for p in pts)
    shifts_x = [0] + ([SIZE] if xmin < 0 else []) + ([-SIZE] if xmax >= SIZE else [])
    shifts_y = [0] + ([SIZE] if ymin < 0 else []) + ([-SIZE] if ymax >= SIZE else [])
    for dx in shifts_x:
        for dy in shifts_y:
            shifted = [(float(x + dx), float(y + dy)) for x, y in pts]
            getattr(draw, kind)(shifted, **kwargs)


def stones(im, height, rng, count, size_range, base, amount=1.0):
    d = ImageDraw.Draw(im)
    hd = ImageDraw.Draw(height)
    for _ in range(count):
        cx, cy = rng.uniform(0, SIZE, 2)
        radius = rng.uniform(*size_range)
        elong = rng.uniform(0.55, 1.0)
        orientation = rng.uniform(0, math.tau)
        vertices = int(rng.integers(5, 9))
        angles = np.linspace(0, math.tau, vertices, endpoint=False)
        points = []
        for a in angles:
            rr = radius * rng.uniform(0.77, 1.13)
            lx, ly = math.cos(a) * rr, math.sin(a) * rr * elong
            points.append((cx + lx * math.cos(orientation) - ly * math.sin(orientation),
                           cy + lx * math.sin(orientation) + ly * math.cos(orientation)))
        tone = float(rng.uniform(-14, 17)) * amount
        color = tuple(int(np.clip(c + tone, 0, 255)) for c in base)
        # A low, warm occlusion rim helps pebbles read without sparkly highlights.
        rim = tuple(max(0, int(c - 12 * amount)) for c in color)
        periodic_draw(d, "polygon", points, fill=color, outline=rim, width=1)
        periodic_draw(hd, "polygon", points, fill=float(rng.uniform(0.035, 0.09)))
        if radius > 3.1:
            facet = [points[0], points[1], (cx, cy), points[-1]]
            periodic_draw(d, "polygon", facet,
                          fill=tuple(min(255, int(c + 6 * amount)) for c in color))
            periodic_draw(hd, "polygon", facet, fill=float(rng.uniform(0.06, 0.12)))


def save(name, rgb, h, roughness, normal_power=1.0):
    albedo = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).resize(
        (FINAL, FINAL), Image.Resampling.LANCZOS)
    albedo.save(OUT / f"terrain_{name}.png", optimize=True)
    # Filter before resampling; the 512² tangent maps remain seamless.
    small_h = np.asarray(Image.fromarray(h.astype(np.float32), mode="F").resize(
        (FINAL, FINAL), Image.Resampling.BILINEAR))
    dx = (np.roll(small_h, -1, 1) - np.roll(small_h, 1, 1)) * normal_power
    dy = (np.roll(small_h, -1, 0) - np.roll(small_h, 1, 0)) * normal_power
    vectors = np.stack([-dx, dy, np.ones_like(dx)], axis=-1)
    vectors /= np.linalg.norm(vectors, axis=-1, keepdims=True)
    normal = np.clip((vectors * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(normal).save(OUT / f"terrain_{name}_normal.png", optimize=True)
    rough = Image.fromarray(np.clip(roughness * 255, 0, 255).astype(np.uint8)).resize(
        (FINAL, FINAL), Image.Resampling.LANCZOS)
    rough.save(OUT / f"terrain_{name}_roughness.png", optimize=True)
    arr = np.asarray(albedo)
    return {"albedo": f"terrain_{name}.png", "normal": f"terrain_{name}_normal.png",
            "roughness": f"terrain_{name}_roughness.png",
            "mean_srgb_255": np.round(arr.mean(axis=(0, 1)), 1).tolist(),
            "size": [FINAL, FINAL]}


def dirt():
    rng = np.random.default_rng(40983)
    im = Image.fromarray(material_base(rng, [118, 98, 74], 0.88))
    h = smooth(rng, 10) * 0.017 + smooth(rng, 1.2) * 0.018
    height = Image.new("F", (SIZE, SIZE), 0)
    stones(im, height, rng, 11000, (0.45, 1.45), (120, 101, 78), 0.60)
    stones(im, height, rng, 1300, (1.4, 3.7), (123, 107, 85), 0.75)
    stones(im, height, rng, 90, (3.6, 9.0), (113, 105, 87), 0.90)
    # A few shallow fractures in compacted soil, with irregular short branches.
    d, hd = ImageDraw.Draw(im), ImageDraw.Draw(height)
    for _ in range(29):
        px, py = rng.uniform(0, SIZE, 2)
        theta = rng.uniform(0, math.tau)
        points = [(px, py)]
        for i in range(int(rng.integers(4, 10))):
            theta += rng.uniform(-0.72, 0.72)
            px += math.cos(theta) * rng.uniform(3, 10)
            py += math.sin(theta) * rng.uniform(3, 10)
            points.append((px, py))
        periodic_draw(d, "line", points, fill=(91, 77, 59), width=1)
        periodic_draw(hd, "line", points, fill=-0.048, width=2)
    h += gaussian_filter(np.asarray(height), 0.65, mode="wrap")
    rough = 0.92 + smooth(rng, 10) * 0.018 - np.asarray(height) * 0.30
    return save("dirt", np.asarray(im), h, rough, 4.6)


def grass():
    rng = np.random.default_rng(42037)
    patch = smooth(rng, 28)
    cover = np.clip(0.54 + patch * 0.15, 0.16, 0.86)
    soil = material_base(rng, [103, 91, 66], 0.82).astype(np.float32)
    green = np.array([76, 85, 51], dtype=np.float32)
    rgb = soil * (1 - cover[..., None]) + green * cover[..., None]
    im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))
    height = Image.new("F", (SIZE, SIZE), 0)
    stones(im, height, rng, 3000, (0.5, 1.6), (99, 92, 70), 0.50)
    stones(im, height, rng, 440, (1.4, 4.2), (115, 108, 85), 0.65)
    d, hd = ImageDraw.Draw(im), ImageDraw.Draw(height)
    palettes = [(91, 101, 60), (83, 96, 55), (111, 114, 69),
                (122, 116, 77), (133, 123, 84), (76, 84, 48)]
    # Tufts comprise curved, tapered fibers, not dots or streaked noise.
    for _ in range(5700):
        cx, cy = rng.uniform(0, SIZE, 2)
        if rng.random() > float(cover[int(cy) % SIZE, int(cx) % SIZE] + 0.27):
            continue
        blades = int(rng.integers(3, 8))
        tuft_angle = rng.uniform(0, math.tau)
        for _ in range(blades):
            theta = tuft_angle + rng.uniform(-1.2, 1.2)
            length = rng.uniform(3, 15)
            bend = rng.uniform(-0.42, 0.42)
            rootx, rooty = cx + rng.uniform(-2, 2), cy + rng.uniform(-2, 2)
            pts = [(rootx, rooty),
                   (rootx + math.cos(theta) * length * 0.52,
                    rooty + math.sin(theta) * length * 0.52),
                   (rootx + math.cos(theta + bend) * length,
                    rooty + math.sin(theta + bend) * length)]
            base = palettes[int(rng.integers(len(palettes)))]
            color = tuple(int(v + rng.uniform(-4, 4)) for v in base)
            periodic_draw(d, "line", pts, fill=color, width=int(rng.choice([1, 1, 2])))
            periodic_draw(hd, "line", pts, fill=float(rng.uniform(0.025, 0.055)), width=2)
        # Sparse dark tuft roots anchor blades to the soil.
        if rng.random() < 0.35:
            periodic_draw(d, "ellipse", [(cx-1.0, cy-0.8), (cx+1.0, cy+0.8)],
                          fill=(68, 72, 43))
    h = gaussian_filter(np.asarray(height), 0.62, mode="wrap")
    h += smooth(rng, 2) * 0.017 + smooth(rng, 12) * 0.020
    rough = 0.94 + smooth(rng, 16) * 0.015
    return save("grass", np.asarray(im), h, rough, 4.3)


def rock():
    rng = np.random.default_rng(78109)
    # Periodic offset makes horizontal bedding meander without a tile seam.
    warp = smooth(rng, 33) * 8 + smooth(rng, 11) * 2
    phase = (Y + warp + 7 * np.sin(X / SIZE * math.tau * 2)) / SIZE * math.tau * 23
    bedding = np.sin(phase) * 1.3 + np.sin(phase * 2) * 0.65
    fine_strata = np.sin((Y + warp * 0.32) / SIZE * math.tau * 137) * 0.72
    base = material_base(rng, [112, 104, 89], 0.9).astype(np.float32)
    base += (bedding + fine_strata)[..., None] * np.array([1.5, 1.25, 1.05])
    # A toroidal Voronoi field gives naturally fitted weathered slabs.
    points = rng.uniform(0, SIZE, (56, 2))
    tiled_points = np.concatenate([points + [dx, dy] for dx in [-SIZE, 0, SIZE]
                                  for dy in [-SIZE, 0, SIZE]], axis=0)
    # Sedimentary joints form elongated blocks rather than dry-mud polygons.
    metric = np.array([0.31, 1.0])
    tree = cKDTree(tiled_points * metric)
    wx = X + smooth(rng, 7) * 1.7
    wy = Y + smooth(rng, 9) * 2.6
    distances, indices = tree.query(np.stack([wx.ravel(), wy.ravel()], axis=1) * metric, k=2)
    nearest = (indices[:, 0] % len(points)).reshape(SIZE, SIZE)
    edge_dist = (distances[:, 1] - distances[:, 0]).reshape(SIZE, SIZE) * 0.5
    tones = rng.uniform(-3.0, 3.0, len(points))[nearest]
    gap = np.exp(-np.power(edge_dist / 0.68, 1.5))
    wear = np.exp(-np.power(edge_dist / 2.8, 1.45))
    # Some fractures are filled by weathering, avoiding a uniform crack lattice.
    fracture_presence = np.clip(smooth(rng, 15) * 0.50 + 0.70, 0.12, 1.0)
    gap *= fracture_presence
    # Fractures are subtle dark mineral seams, with broad rounded weathering.
    base += tones[..., None] * np.array([1.1, 0.95, 0.80])
    base -= gap[..., None] * np.array([14, 13, 10])
    base -= wear[..., None] * np.array([2.0, 1.8, 1.4])
    # Thin mineral beds receive intermittent warm gray and ochre deposits.
    mineral = np.power(np.clip(np.sin(phase + 0.8), 0, 1), 18)
    mineral *= np.clip(smooth(rng, 30) * 0.4 + 0.25, 0, 1)
    base += mineral[..., None] * np.array([5, 2.5, -1.5])
    im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    height = Image.new("F", (SIZE, SIZE), 0)
    stones(im, height, rng, 6800, (0.45, 1.6), (112, 104, 88), 0.50)
    # Small angular embedded inclusions remain within the stone's tonal range.
    stones(im, height, rng, 90, (2, 4.4), (116, 108, 91), 0.38)
    h = smooth(rng, 2.6) * 0.015 + smooth(rng, 13) * 0.025
    h += bedding * 0.013 + fine_strata * 0.005 - gap * 0.062 - wear * 0.028
    h += gaussian_filter(np.asarray(height), 0.75, mode="wrap") * 0.48
    rough = 0.88 + smooth(rng, 16) * 0.025 + gap * 0.035
    return save("rock", np.asarray(im), h, rough, 5.2)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    info = {"dirt": dirt(), "grass": grass(), "rock": rock()}
    (OUT / "terrain_materials.json").write_text(json.dumps(info, indent=2) + "\n")
    print(json.dumps(info, indent=2))
