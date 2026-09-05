# Highland sky panorama provenance

- Created: 2026-09-05
- Generator: built-in `image_gen.imagegen`, default tool mode.
- Asset: `highland_sky_panorama.png`
- Source: `/workspace/scratch/1af69a28693e/generated_images/exec-8faba76b-cb2d-41a2-a561-8dd634402ff1.png`
- Original image copied unchanged; no image transformations.
- Requested: 2048 × 1024 full-sphere equirectangular sky. Returned: 1774 × 887 RGB PNG, exact 2:1 aspect ratio.
- Visual inspection: photographic blue sky, broken volumetric clouds with warm silver edges and subtle cool undersides, restrained warm horizon glow, softly neutral lower hemisphere, no landscape or text. Horizon falls close to the vertical middle. Exact panorama boundary continuity is not guaranteed by generation and should be checked in the sky material.

## Final prompt

Use case: photorealistic-natural
Asset type: project-ready 360-degree full-sphere equirectangular sky panorama texture for a realistic outdoor Godot Android game, 2:1 aspect ratio, ideally 2048 by 1024 pixels.
Primary request: an original beautiful photographic highland sky environment map at warm late afternoon. The upper hemisphere has clear deep natural blue near the zenith fading gradually to pale blue and delicate warm pale gold near the horizon. Scattered broken cumulus clouds have physically convincing luminous volumes: soft cool subtly gray cloud undersides and restrained warm silver edges, with fine wispy cirrus sparsely high overhead. Natural photographic cloud scale and lighting, crisp but atmospheric, not oversharpened or noisy.
Projection and framing: a true full 360-degree horizontal by 180-degree vertical latitude-longitude equirectangular projection, with the horizon exactly at the horizontal middle of the image. Match the left and right borders seamlessly for 360-degree wrap. Preserve correct polar distortion, stretched/compressed cloud details appropriate for equirectangular mapping near the top edge. This is a texture atlas viewed directly, not a sphere rendering, not a visible rectangular photograph inset in a scene.
Sky composition: keep the blue sky dominant with attractive varied gaps between moderately sized clouds, richer clouds toward the horizon, much quieter sparse high clouds toward zenith. One restrained pale-gold area on the horizon implies the sun direction. The sun itself must not appear as a bright hard white disk, and no large bloom, supernova rays, or lens flare is baked in.
Lower hemisphere: below the exact middle horizon, fade immediately into smooth neutral warm-gray atmospheric color, subdued and low-contrast, intended only for ambient reflections. No ground or visible terrain in this lower half.
Constraints: photorealistic actual sky photographic realism and physically natural light, not cartoon, illustration, painterly concept art, graphic cloud shapes or procedurally noisy patterns. No landscape, mountains, trees, rocks, grass, buildings, water, people, aircraft, objects, labels, text, logos or watermarks. No boundary line at the panorama seam.
