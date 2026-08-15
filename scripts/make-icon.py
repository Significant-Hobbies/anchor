#!/usr/bin/env python3
"""Render Anchor's app icon into the shared asset catalogue.

The icon is the app's own focus ring: a cobalt arc, most of the way round, with
the lit head at its leading edge. Generating it rather than hand-drawing it means
the icon and the interface cannot drift apart — the colours below are the same
tokens as `AnchorTheme.dark`.

    python3 scripts/make-icon.py

Requires Pillow. Writes every macOS size plus a full-bleed 1024 for iOS and
watchOS, which is what `AppIcon.appiconset/Contents.json` expects.
"""

from __future__ import annotations

import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover - developer tooling only
    sys.exit("Pillow is required: pip install Pillow")

MASTER = 4096  # every size is downscaled from one master, so edges stay clean

# Straight from AnchorTheme.dark.
DEEP = (0x1D, 0x4E, 0xD8)
MID = (0x3B, 0x82, 0xF6)
LIGHT = (0x7D, 0xD3, 0xFC)
BG_TOP = (0x1A, 0x22, 0x30)
BG_BOTTOM = (0x06, 0x08, 0x0C)

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


def ring_color(t: float):
    """Deep -> mid -> light, matching the ring's angular gradient in the app."""
    return lerp(DEEP, MID, t / 0.55) if t < 0.55 else lerp(MID, LIGHT, (t - 0.55) / 0.45)


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

    gradient = Image.new("RGBA", (size, size))
    gd = ImageDraw.Draw(gradient)
    for y in range(size):
        gd.line([(0, y), (size, y)], fill=lerp(BG_TOP, BG_BOTTOM, y / size) + (255,))
    img.paste(gradient, (0, 0), plate)

    draw = ImageDraw.Draw(img)
    cx = cy = size / 2
    r = side * 0.295
    w = side * 0.10

    # Unfilled track, as in the app.
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 24), width=int(w))

    # Progress arc, drawn in short overlapping segments so the gradient sweeps.
    start, sweep, steps = -90.0, 288.0, 900
    for i in range(steps):
        t = i / steps
        draw.arc(
            [cx - r, cy - r, cx + r, cy + r],
            start + sweep * t,
            start + sweep * ((i + 1.5) / steps),
            fill=ring_color(t) + (255,),
            width=int(w),
        )

    # Rounded caps, each matching the gradient where it sits.
    for t in (0.0, 1.0):
        angle = math.radians(start + sweep * t)
        px, py = cx + r * math.cos(angle), cy + r * math.sin(angle)
        draw.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=ring_color(t) + (255,))

    # The lit head. Blurred on its own layer rather than stacked rings, which
    # otherwise reads as a milky blob at small sizes.
    head_angle = math.radians(start + sweep)
    hx, hy = cx + r * math.cos(head_angle), cy + r * math.sin(head_angle)
    hr = w * 0.60
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [hx - hr * 1.7, hy - hr * 1.7, hx + hr * 1.7, hy + hr * 1.7], fill=LIGHT + (150,)
    )
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(int(w * 0.55))))
    ImageDraw.Draw(img).ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(0xEB, 0xF7, 0xFF, 255))
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
