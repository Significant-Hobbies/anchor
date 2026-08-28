#!/usr/bin/env python3
"""Render Anchor's app icon into the shared asset catalogue.

The icon is the two-eyed Anchor face already used in the Mac navigation rail,
drawn in the product's warm paper and charcoal palette. Generating it rather
than maintaining twelve hand-resized files keeps the small-size silhouette and
the in-app mark aligned.

    python3 scripts/make-icon.py

Requires Pillow. Writes every macOS size plus a full-bleed 1024 for iOS and
watchOS, which is what `AppIcon.appiconset/Contents.json` expects.
"""

from __future__ import annotations

import math
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - developer tooling only
    sys.exit("Pillow is required: pip install Pillow")

MASTER = 4096  # every size is downscaled from one master, so edges stay clean

# Straight from AnchorTheme.light and DESIGN.md.
PAPER = (0xFB, 0xFA, 0xF7)
PAPER_SHADE = (0xE9, 0xE6, 0xDF)
INK = (0x17, 0x17, 0x17)

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Apps/Shared/Assets.xcassets/AppIcon.appiconset",
)

MAC_SIZES = [
    (16, "16x16", "1x"), (32, "16x16", "2x"),
    (32, "32x32", "1x"), (64, "32x32", "2x"),
    (128, "128x128", "1x"), (256, "128x128", "2x"),
    (256, "256x256", "1x"), (512, "256x256", "2x"),
    (512, "512x512", "1x"), (1024, "512x512", "2x"),
]


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_icon(full_bleed: bool) -> Image.Image:
    """`full_bleed` for iOS/watchOS, which mask the icon themselves; the inset
    squircle is for macOS, which draws icons free-standing."""
    size = MASTER
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    inset = 0 if full_bleed else int(size * 0.085)
    box = (inset, inset, size - inset - 1, size - inset - 1)
    side = box[2] - box[0]
    radius = 0 if full_bleed else int(side * 0.2237)  # Apple's squircle ratio

    plate = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pd = ImageDraw.Draw(plate)
    if radius:
        pd.rounded_rectangle(box, radius=radius, fill=(255, 255, 255, 255))
    else:
        pd.rectangle(box, fill=(255, 255, 255, 255))

    gradient = Image.new("RGBA", (size, size), PAPER + (255,))
    gd = ImageDraw.Draw(gradient)
    for y in range(size):
        gd.line([(0, y), (size, y)], fill=lerp(PAPER, PAPER_SHADE, y / size) + (255,))
    img.paste(gradient, (0, 0), plate)

    cx = size / 2
    cy = size * 0.47

    # Match AnchorFaceMark, but let the app icon's silhouette feel hand-drawn
    # rather than like a perfect UI primitive.
    # Oversize the mark optically so it still reads as the Anchor face in the
    # 16 pt Dock and Settings treatments, not as a dark fleck on pale paper.
    face_width = side * 0.62
    face_height = side * 0.54
    face_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    fd = ImageDraw.Draw(face_layer)
    points = []
    for index in range(180):
        angle = 2 * math.pi * index / 180
        wobble = 1 + 0.035 * math.sin(3 * angle + 0.6) + 0.018 * math.sin(5 * angle)
        points.append(
            (
                cx + math.cos(angle) * face_width / 2 * wobble,
                cy + math.sin(angle) * face_height / 2 * wobble,
            )
        )
    fd.polygon(points, fill=INK + (255,))
    face_layer = face_layer.rotate(-4, resample=Image.Resampling.BICUBIC, center=(cx, cy))
    img.alpha_composite(face_layer)

    eye_radius = side * 0.039
    eye_y = cy - side * 0.018
    eye_offset = side * 0.062
    draw = ImageDraw.Draw(img)
    for eye_x in (cx - eye_offset, cx + eye_offset):
        draw.ellipse(
            [eye_x - eye_radius, eye_y - eye_radius, eye_x + eye_radius, eye_y + eye_radius],
            fill=PAPER + (255,),
        )

    return img


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    mac = draw_icon(full_bleed=False)
    bleed = draw_icon(full_bleed=True)

    for px, base, scale in MAC_SIZES:
        name = f"mac_{base}{'' if scale == '1x' else '@2x'}.png"
        mac.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))

    for platform in ("ios", "watchos"):
        bleed.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, f"{platform}_1024.png"))

    print(f"wrote {len(MAC_SIZES) + 2} icon files to {OUT}")


if __name__ == "__main__":
    main()
