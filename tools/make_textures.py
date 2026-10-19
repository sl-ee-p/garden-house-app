#!/usr/bin/env python3
"""Turns the website's panel finish textures into the app's assets.

Input is the website repo (design/signature), whose tools/panel_textures.py
rectifies the brochure's panel photos into assets/img/finiture/tex/<id>.webp
(512 x 160 px = 0.6 m x 0.25 m of board). For each finish this writes:

  * assets/textures/<id>.jpg: the tile pre-mirrored into 2 x 2 (1024 x 320 px
    = 1.2 m x 0.5 m), so plain REPEAT wrapping is seamless in every renderer,
    and JPEG because core glTF (the AR export) doesn't allow WebP;
  * assets/textures/<id>_n.jpg: a normal map of the same tile, so the grain
    and the embossing catch the light. The relief is guessed from the photo:
    log-luminance, high-passed, taken as height;
  * assets/finiture/<id>.webp: the brochure photo thumbnail for the picker.

Usage: python3 -I tools/make_textures.py ~/garden-house-redesign
(needs Pillow and numpy; run from the app's root)
"""

import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

# Same ids as panelFinishes in lib/palette.dart.
IDS = [
    "piano-goffrato-ral9010", "doga-goffrato-ral9010", "doga-liscio-ral9010",
    "doga-liscio-ral1013", "doga-liscio-ral7035", "doga-liscio-ral9006",
    "piano-liscio-ral9006", "doga-polygrain-ral7016", "piano-polygrain-ral7016",
    "doga-goffrato-ral6005", "doga-goffrato-ral6009", "piano-liscio-noce-chiaro",
    "doga-liscio-noce-chiaro", "piano-liscio-noce-scuro", "doga-liscio-noce-scuro",
    "doga-goffrato-ral8014",
]


# Normal map tuning: blur radius of the high-pass (px; larger keeps broader
# relief) and slope per unit of log-luminance.
RELIEF_RADIUS = 6
RELIEF_STRENGTH = 4.0


def normal_map(tile):
    """Tangent-space normal map (glTF: +X right, +Y up) of a seamless tile."""
    lum = np.asarray(tile.convert("L"), dtype=np.float32) / 255
    height = np.log(lum + 0.05)
    # Gaussian high-pass in the frequency domain, which wraps around the
    # edges like the tile does.
    fy = np.fft.fftfreq(height.shape[0])[:, None]
    fx = np.fft.fftfreq(height.shape[1])[None, :]
    low = np.exp(-2 * (np.pi * RELIEF_RADIUS) ** 2 * (fx**2 + fy**2))
    height = np.real(np.fft.ifft2(np.fft.fft2(height) * (1 - low)))
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / 2
    drow = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / 2
    # Image rows run down, +Y runs up.
    n = np.stack([-dx * RELIEF_STRENGTH, drow * RELIEF_STRENGTH, np.ones_like(dx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return Image.fromarray(np.round((n * 0.5 + 0.5) * 255).astype(np.uint8))


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    src = Path(sys.argv[1]).expanduser() / "assets/img/finiture"
    tex_dir, thumb_dir = Path("assets/textures"), Path("assets/finiture")
    tex_dir.mkdir(parents=True, exist_ok=True)
    thumb_dir.mkdir(parents=True, exist_ok=True)
    total = 0
    for id in IDS:
        tile = Image.open(src / "tex" / f"{id}.webp").convert("RGB")
        w, h = tile.size
        out = Image.new("RGB", (w * 2, h * 2))
        out.paste(tile, (0, 0))
        out.paste(ImageOps.mirror(tile), (w, 0))
        out.paste(ImageOps.flip(tile), (0, h))
        out.paste(ImageOps.flip(ImageOps.mirror(tile)), (w, h))
        path = tex_dir / f"{id}.jpg"
        out.save(path, quality=85, optimize=True, progressive=False)
        normals = tex_dir / f"{id}_n.jpg"
        normal_map(out).save(normals, quality=85, optimize=True, progressive=False)
        total += normals.stat().st_size
        shutil.copyfile(src / f"{id}-160.webp", thumb_dir / f"{id}.webp")
        total += path.stat().st_size
    print(f"{len(IDS)} textures, {total / 1024:.0f} KB -> {tex_dir}/")


if __name__ == "__main__":
    main()
