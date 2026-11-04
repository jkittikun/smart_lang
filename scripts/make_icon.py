#!/usr/bin/env python3
"""Draws the SmartLang app icon and writes Resources/AppIcon.icns (+ a PNG).

Two keycaps, ก and A, with swap arrows, on a macOS-style rounded square.

Needs Pillow. The .icns file is written directly (PNG entries), so this
runs anywhere, not just on macOS:

    python3 scripts/make_icon.py [--thai-font PATH] [--latin-font PATH]
"""
import argparse
import io
import math
import os
import struct

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Resources")

SS = 2            # supersampling factor
S = 1024 * SS     # working canvas size

THAI_FONTS = [
    "/System/Library/Fonts/Supplemental/Thonburi.ttc",
    "/System/Library/Fonts/Thonburi.ttc",
    "/usr/share/fonts/opentype/tlwg/Loma-Bold.otf",
]
LATIN_FONTS = [
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def first_existing(paths):
    for p in paths:
        if p and os.path.exists(p):
            return p
    raise SystemExit(f"No font found; tried: {paths}")


def squircle_mask(size, box, n=5.0):
    """Superellipse (|x|^n + |y|^n = 1) mask, close to the macOS icon shape."""
    x0, y0, x1, y1 = box
    cx, cy, a, b = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + a * math.copysign(abs(c) ** (2 / n), c),
                    cy + b * math.copysign(abs(s) ** (2 / n), s)))
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def gradient(size, top_left, bottom_right):
    """Diagonal linear gradient."""
    g = Image.new("RGB", (size, size))
    px = g.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(int(top_left[i] + (bottom_right[i] - top_left[i]) * t) for i in range(3))
    return g


def gradient_fast(size, c0, c1):
    small = gradient(256, c0, c1)
    return small.resize((size, size), Image.BICUBIC)


def rounded_rect_mask(size, box, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def shadow(mask, offset, blur, opacity):
    sh = Image.new("L", mask.size, 0)
    sh.paste(mask, offset)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    return sh.point(lambda v: int(v * opacity))


def draw_centered(draw, box, text, font, fill):
    x0, y0, x1, y1 = box
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    w, h = r - l, b - t
    draw.text((x0 + (x1 - x0 - w) / 2 - l, y0 + (y1 - y0 - h) / 2 - t), text, font=font, fill=fill)


def arrow_arc(draw, center, radius, start_deg, end_deg, width, fill):
    """Arc with an arrowhead at end_deg (degrees, clockwise from +x, PIL style)."""
    cx, cy = center
    box = (cx - radius, cy - radius, cx + radius, cy + radius)
    draw.arc(box, start_deg, end_deg, fill=fill, width=width)
    # Arrowhead: a triangle tangent to the circle at end_deg, pointing clockwise.
    t = math.radians(end_deg)
    px, py = cx + radius * math.cos(t), cy + radius * math.sin(t)
    tx, ty = -math.sin(t), math.cos(t)          # clockwise tangent
    nx, ny = math.cos(t), math.sin(t)           # outward normal
    L, W = width * 2.4, width * 1.7
    tip = (px + tx * L * 0.85, py + ty * L * 0.85)
    base1 = (px + nx * W - tx * L * 0.15, py + ny * W - ty * L * 0.15)
    base2 = (px - nx * W - tx * L * 0.15, py - ny * W - ty * L * 0.15)
    draw.polygon([tip, base1, base2], fill=fill)


def render(thai_font_path, latin_font_path):
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Background tile (macOS grid: 824/1024 with ~100px margin).
    m = 100 * SS
    tile_box = (m, m, S - m, S - m)
    tile_mask = squircle_mask(S, tile_box)
    drop = shadow(tile_mask, (0, 14 * SS), 22 * SS, 0.35)
    canvas.paste((0, 0, 0, 255), (0, 0), drop)
    bg = gradient_fast(S, (79, 70, 229), (13, 148, 136)).convert("RGBA")   # indigo -> teal
    canvas.paste(bg, (0, 0), tile_mask)

    # Soft top highlight: a vertical fade, strongest at the top edge.
    fade = Image.new("L", (1, 256))
    for y in range(256):
        fade.putpixel((0, y), int(55 * max(0.0, 1 - y / 120) ** 1.6))
    hl = ImageChops.multiply(fade.resize((S, S), Image.BICUBIC), tile_mask)
    canvas.paste((255, 255, 255, 255), (0, 0), hl)

    thai_font = ImageFont.truetype(thai_font_path, 330 * SS)
    latin_font = ImageFont.truetype(latin_font_path, 280 * SS)

    key = 360 * SS
    radius = 78 * SS
    back_box = (230 * SS, 214 * SS, 230 * SS + key, 214 * SS + key)    # ก, upper left
    front_box = (434 * SS, 450 * SS, 434 * SS + key, 450 * SS + key)   # A, lower right

    def keycap(box, face, text, font, text_fill, nudge=(0, 0)):
        km = rounded_rect_mask(S, box, radius)
        canvas.paste((0, 0, 0, 255), (0, 0), shadow(km, (0, 18 * SS), 18 * SS, 0.30))
        # Keycap base (slightly darker rim at the bottom).
        rim = rounded_rect_mask(S, (box[0], box[1] + 14 * SS, box[2], box[3] + 14 * SS), radius)
        canvas.paste(tuple(max(0, c - 40) for c in face) + (255,), (0, 0), rim)
        canvas.paste(face + (255,), (0, 0), km)
        d = ImageDraw.Draw(canvas)
        dx, dy = nudge[0] * SS, nudge[1] * SS
        draw_centered(d, (box[0] + dx, box[1] - 8 * SS + dy, box[2] + dx, box[3] - 8 * SS + dy), text, font, text_fill)

    # ก sits up-left so the front key doesn't cover it.
    keycap(back_box, (255, 255, 255), "ก", thai_font, (49, 46, 129), nudge=(-38, -40))
    keycap(front_box, (30, 27, 75), "A", latin_font, (255, 255, 255))

    # Swap arrows around the pair.
    d = ImageDraw.Draw(canvas)
    center = (S / 2 + 10 * SS, S / 2 + 18 * SS)
    r = 330 * SS
    w = 30 * SS
    white = (255, 255, 255, 235)
    arrow_arc(d, center, r, 290, 352, w, white)   # top-right, pointing down to A
    arrow_arc(d, center, r, 110, 172, w, white)   # bottom-left, pointing up to ก

    return canvas.resize((1024, 1024), Image.LANCZOS)


ICNS_TYPES = [  # (OSType, pixel size)
    (b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128), (b"ic08", 256),
    (b"ic09", 512), (b"ic10", 1024), (b"ic11", 32), (b"ic12", 64), (b"ic13", 256), (b"ic14", 512),
]


def write_icns(master, path):
    chunks = []
    for ostype, px in ICNS_TYPES:
        buf = io.BytesIO()
        master.resize((px, px), Image.LANCZOS).save(buf, "PNG", optimize=True)
        data = buf.getvalue()
        chunks.append(ostype + struct.pack(">I", len(data) + 8) + data)
    body = b"".join(chunks)
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--thai-font")
    ap.add_argument("--latin-font")
    args = ap.parse_args()
    icon = render(first_existing([args.thai_font] + THAI_FONTS),
                  first_existing([args.latin_font] + LATIN_FONTS))
    os.makedirs(OUT_DIR, exist_ok=True)
    icon.save(os.path.join(OUT_DIR, "AppIcon.png"))
    write_icns(icon, os.path.join(OUT_DIR, "AppIcon.icns"))
    print("Wrote", os.path.join(OUT_DIR, "AppIcon.icns"))


if __name__ == "__main__":
    main()
