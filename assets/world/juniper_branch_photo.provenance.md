# Juniper branch photo provenance

- Created: 2026-09-05
- Generator: built-in `image_gen.imagegen`, default tool mode.
- Asset: `juniper_branch_photo.png`
- Source: `/workspace/scratch/1af69a28693e/generated_images/exec-5cb230e7-9bdc-4a0d-a396-bbf58d65160a.png`
- Original image copied unchanged; no image transformations.
- Requested: 1024 × 1024 transparent foliage card. Returned: 1254 × 1254 RGBA PNG.
- Alpha verified directly with Pillow in read-only inspection: extrema 0–255, 928,850 fully transparent pixels, 643,552 partially transparent pixels, 114 fully opaque pixels, total 1,572,516 pixels. Genuine alpha exists around silhouette and through branch gaps.
- Visual inspection: realistic asymmetric juniper spray with woody root at bottom center, branches extending upward and outward, intricate green scales and visible fine brown twigs. No background, pot, text, or full tree.
- Card orientation: root at approximately (0.54, 0.98) in top-left-origin normalized image coordinates; growth points toward top of image. Subject alpha bounds: (11, 14) to (1239, 1239) pixels. Preserve alpha on import and use an appropriate foliage alpha cutout material.

## Final prompt

Use case: photorealistic-natural
Asset type: photorealistic botanical foliage card cutout for a realistic outdoor Godot game, square 1024 by 1024 PNG with genuine transparent alpha background.
Primary request: a single natural asymmetric juniper branch spray, photographed with exquisite real botanical detail. A thin woody cut branch begins at the bottom center of the image and branches grow upward and outward in a loose roughly triangular spread, extending left and right at different angles. The center has dense but airy intricate juniper foliage, with many tiny overlapping olive-green scale-like needles, cool darker interiors and slightly warmer fresh green tips. Fine twig bifurcations remain visible. This should feel like a freshly cut real small juniper spray photographed in a botanical studio, not a tree or an illustration.
Composition: one complete branch spray only, isolated and uncropped, nearly filling the square with a small transparent margin all around. Thin woody root anchored at bottom center, topmost sprays toward upper edge. All empty space around the spray and the many gaps between small branches must be actual transparent alpha.
Lighting: soft neutral diffuse photographic lighting with restrained color and realistic foliage detail. Suitable for game foliage textures, no baked ground shadow or dramatic directional sunlight.
Constraints: genuinely transparent background (RGBA PNG alpha channel), not white, not gray, not black, not a checkerboard image pretending to be transparency. No pot, no root ball, no full tree, no main tree trunk, no berries, no flowers, no background, no ground plane, no cast shadow, no text, logos or watermarks. Photographic botanical realism, not painted, not cartoon, not flat graphic, not procedural needle patterns.
