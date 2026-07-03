#!/usr/bin/env python3
"""
gif_to_sdf_atlas.py -- turn an animated GIF into a full-color SDF sprite atlas.

WHY THIS EXISTS (read before "fixing" it):
  msdfgen/msdf-atlas-gen generate distance fields from flat, monochrome VECTOR
  shapes (font glyph outlines). They cannot preserve full-color raster art and
  have no bitmap input path at all -- wrong tool for animated sprite frames.

  This script uses the OTHER well-established SDF technique instead (the one
  Valve documented in 2007): compute a single-channel signed distance field
  directly from the frame's alpha/silhouette via a distance transform, and
  store it in the OUTPUT alpha channel while leaving the original RGB colors
  untouched. Shader-side, a smoothstep on that alpha channel gives crisp,
  scale-independent edges on full-color art -- exactly what a monochrome MSDF
  cannot do.

USAGE:
  python gif_to_sdf_atlas.py input.gif output_basename [--spread N] [--cols N] [--downscale N]

OUTPUT (end-user-simple, matches the project's existing JSON-authoring convention):
  output_basename.png   -- the packed atlas (RGB = original color, A = SDF)
  output_basename.json  -- layout data: frame size, grid, frame count, spread

REQUIRES: Python 3, Pillow, numpy, scipy (all already present in this environment).
NO COMPILER, NO C++ TOOLCHAIN NEEDED. That is the point.
"""

import sys
import os
import json
import argparse
import math

import numpy as np
from PIL import Image, ImageSequence
from scipy.ndimage import distance_transform_edt


def load_gif_frames(path):
    """Yield each GIF frame as an RGBA numpy array (H, W, 4), uint8."""
    im = Image.open(path)
    frames = []
    for frame in ImageSequence.Iterator(im):
        rgba = frame.convert("RGBA")
        frames.append(np.array(rgba, dtype=np.uint8))
    if not frames:
        raise ValueError(f"No frames decoded from {path}")
    return frames


def alpha_mask(frame_rgba, alpha_threshold=16):
    """Foreground silhouette: alpha channel above the given threshold.
    Falls back to luminance if the source has no real alpha (fully opaque)."""
    a = frame_rgba[:, :, 3]
    if a.min() == a.max():
        # No usable alpha (e.g. flattened GIF) -- fall back to "non-black" as foreground.
        lum = frame_rgba[:, :, :3].astype(np.uint16).sum(axis=2)
        return lum > 24
    return a > alpha_threshold


def signed_distance_field(mask, spread_px):
    """Single-channel SDF: 0..255, 128 == exact edge.
    Positive side (>128) is outside the shape, negative side (<128) is inside.
    `spread_px` is how many source pixels the 0..255 range covers on EACH side
    of the edge -- this is the glow/falloff radius, tune per art style."""
    inside = distance_transform_edt(mask)
    outside = distance_transform_edt(~mask)
    signed = outside - inside  # >0 outside, <0 inside, 0 exactly on the edge
    normalized = signed / max(spread_px, 1e-6)  # roughly -1..1 within the spread band
    clamped = np.clip(normalized, -1.0, 1.0)
    return ((clamped * 0.5 + 0.5) * 255.0).astype(np.uint8)


def build_frame(frame_rgba, spread_px, downscale):
    mask = alpha_mask(frame_rgba)
    sdf = signed_distance_field(mask, spread_px)
    out = frame_rgba.copy()
    out[:, :, 3] = sdf  # keep RGB exactly as-is; alpha becomes the distance field
    if downscale > 1:
        h, w = out.shape[:2]
        img = Image.fromarray(out, mode="RGBA")
        img = img.resize((max(1, w // downscale), max(1, h // downscale)), Image.LANCZOS)
        out = np.array(img, dtype=np.uint8)
    return out


def pack_atlas(frames, cols=None):
    """Pack same-size frames into a grid atlas. Returns (atlas_array, cols, rows)."""
    n = len(frames)
    h, w = frames[0].shape[:2]
    if cols is None:
        cols = max(1, math.ceil(math.sqrt(n)))
    rows = math.ceil(n / cols)

    atlas = np.zeros((h * rows, w * cols, 4), dtype=np.uint8)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        atlas[r * h:(r + 1) * h, c * w:(c + 1) * w] = f
    return atlas, cols, rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input_gif")
    ap.add_argument("output_basename")
    ap.add_argument("--spread", type=int, default=8,
                     help="Distance-field spread in source pixels (glow/falloff radius). Default 8.")
    ap.add_argument("--cols", type=int, default=None,
                     help="Force atlas column count. Default: auto near-square.")
    ap.add_argument("--downscale", type=int, default=1,
                     help="Downscale factor AFTER computing the SDF (render at high-res, ship small). Default 1 (none).")
    args = ap.parse_args()

    raw_frames = load_gif_frames(args.input_gif)
    processed = [build_frame(f, args.spread, args.downscale) for f in raw_frames]

    # after downscale, frame dims may differ slightly frame-to-frame only if source dims already differed;
    # GIFs are constant-canvas so this is safe, but guard anyway.
    h0, w0 = processed[0].shape[:2]
    for i, f in enumerate(processed):
        if f.shape[:2] != (h0, w0):
            raise ValueError(f"Frame {i} size {f.shape[:2]} != frame 0 size {(h0, w0)} -- inconsistent GIF canvas")

    atlas, cols, rows = pack_atlas(processed, cols=args.cols)

    png_path = args.output_basename + ".png"
    json_path = args.output_basename + ".json"

    Image.fromarray(atlas, mode="RGBA").save(png_path)

    layout = {
        "sourceFile": os.path.basename(args.input_gif),
        "technique": "single-channel-sdf-in-alpha",
        "frameWidth": w0,
        "frameHeight": h0,
        "cols": cols,
        "rows": rows,
        "frameCount": len(processed),
        "spreadPixels": args.spread,
        "downscale": args.downscale,
        "note": "RGB channels are original full color; alpha channel is a signed distance "
                "field (128=edge, >128=outside, <128=inside). Shader should smoothstep the "
                "alpha channel around 0.5 for crisp scale-independent edges, NOT treat it as "
                "plain opacity.",
    }
    with open(json_path, "w") as fh:
        json.dump(layout, fh, indent=2)

    print(f"Wrote {png_path} ({atlas.shape[1]}x{atlas.shape[0]}, {cols}x{rows} grid, {len(processed)} frames)")
    print(f"Wrote {json_path}")


if __name__ == "__main__":
    main()
