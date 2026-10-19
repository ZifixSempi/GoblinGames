#!/usr/bin/env python3
"""
tools/art/make_art.py  (developer tool, not shipped in the addon zip)

Generates every texture GoblinGames ships in GoblinGames/Media, plus the
CurseForge logo. All art is original: drawn here with Pillow, or rendered from
SVG with cairosvg. None of it is Blizzard art.

WoW texture rules this script follows:
  - .tga, 32-bit RGBA, uncompressed, with origin at the top-left (works on
    every client, Retail and Classic)
  - width and height are powers of two (64, 128, 256 ...)
  - most UI pieces are drawn in neutral light colours, so the addon can tint
    them per faction with Texture:SetVertexColor()

Run from the repo root:
    pip install pillow cairosvg
    python3 tools/art/make_art.py
"""
import io
import math
import os
import random
import re

import cairosvg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MEDIA = os.path.join(ROOT, "GoblinGames", "Media")
ART = os.path.join(ROOT, "tools", "art")
random.seed(7)


def save_tga(img, name):
    img = img.convert("RGBA")
    w, h = img.size
    assert w & (w - 1) == 0 and h & (h - 1) == 0, f"{name}: size must be a power of two"
    img.save(os.path.join(MEDIA, name + ".tga"), compression=None, orientation=-1)


def svg_to_image(svg_text, size):
    png = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


# ---------------------------------------------------------------------------
# Logo, goblin head, coin (from SVG)
# ---------------------------------------------------------------------------
def make_logo():
    svg = open(os.path.join(ART, "logo.svg")).read()
    # CurseForge project logo (upload this one on the website).
    svg_to_image(svg, 512).save(os.path.join(ART, "curseforge-logo.png"))
    # In-game copy for the window header.
    save_tga(svg_to_image(svg, 256), "Logo")

    # The goblin's head alone: the mascot and the minimap icon.
    defs = re.search(r"<defs>.*?</defs>", svg, re.S).group(0)
    face = re.search(r"<!-- Ears -->.*?(?=<!-- Die)", svg, re.S).group(0)
    # Wide crop with the ear tips (256x128), and a square face crop for icons.
    wide = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-28 52 568 284">' + defs + face + "</svg>")
    png = cairosvg.svg2png(bytestring=wide.encode(), output_width=256, output_height=128)
    save_tga(Image.open(io.BytesIO(png)).convert("RGBA"), "GoblinHead")
    square = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="112 52 288 288">' + defs + face + "</svg>")
    save_tga(svg_to_image(square, 64), "GoblinFace")

    coin = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-40 -40 80 80">' + defs +
            '<circle r="36" fill="url(#gold)" stroke="#7a4f0c" stroke-width="5"/>'
            '<circle r="25" fill="none" stroke="#9c6a12" stroke-width="3"/>'
            '<path d="M-14 -20 Q-4 -26 4 -20" stroke="#fff6c0" stroke-width="5" fill="none" stroke-linecap="round"/>'
            '<text x="0" y="13" text-anchor="middle" font-family="Luckiest Guy" font-size="38" fill="#7a4f0c">G</text>'
            "</svg>")
    save_tga(svg_to_image(coin, 64), "Coin")


# ---------------------------------------------------------------------------
# Wood
# ---------------------------------------------------------------------------
def wood_strip(w, h, base, horizontal=True, seed=0):
    """A strip of wood with grain running along it."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), base + (255,))
    d = ImageDraw.Draw(img)
    length, across = (w, h) if horizontal else (h, w)
    for _ in range(across // 2):
        pos = rnd.uniform(0, across)
        shade = rnd.uniform(-28, 18)
        col = tuple(max(0, min(255, int(c + shade))) for c in base) + (255,)
        wav = rnd.uniform(0.5, 2.5)
        pts = []
        for x in range(0, length + 8, 8):
            y = pos + math.sin(x / (length / (2 + rnd.random() * 3)) + rnd.random()) * wav
            pts.append((x, y) if horizontal else (y, x))
        d.line(pts, fill=col, width=rnd.choice([1, 1, 2]))
    return img


def make_planks():
    """Tileable dark plank background (vertical seams line up when tiled)."""
    size = 256
    img = Image.new("RGBA", (size, size))
    plank_h = 64
    for i in range(size // plank_h):
        base = lerp((74, 46, 28), (92, 58, 34), random.random())
        strip = wood_strip(size, plank_h, base, True, seed=i * 13)
        d = ImageDraw.Draw(strip)
        d.line([(0, 0), (size, 0)], fill=(40, 22, 12, 255), width=3)        # seam
        d.line([(0, 3), (size, 3)], fill=(120, 80, 50, 255), width=1)       # highlight
        # a knot here and there
        if i % 2 == 0:
            kx, ky = random.randint(30, 220), random.randint(20, 44)
            d.ellipse([kx - 9, ky - 5, kx + 9, ky + 5], outline=(48, 28, 14, 255), width=2)
            d.ellipse([kx - 3, ky - 2, kx + 3, ky + 2], fill=(48, 28, 14, 255))
        img.paste(strip, (0, i * plank_h))
    # nails at both ends of each plank (half-nails wrap across the tile edge)
    d = ImageDraw.Draw(img)
    for i in range(size // plank_h):
        y = i * plank_h + 32
        for x in (10, 246):
            d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(150, 150, 140, 255), outline=(50, 40, 30, 255))
    save_tga(img, "Planks")


def make_frame():
    """9-slice window frame: 64px corners, wood band, gold corner brackets.
    The centre is transparent; the planks go behind it."""
    size, band, corner = 256, 40, 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    base = (176, 132, 92)   # light wood, tinted per faction in game
    top = wood_strip(size, band, base, True, 1)
    left = wood_strip(band, size, base, False, 2)
    img.paste(top, (0, 4))
    img.paste(top.transpose(Image.FLIP_TOP_BOTTOM), (0, size - band - 4))
    img.paste(left, (4, 0))
    img.paste(left.transpose(Image.FLIP_LEFT_RIGHT), (size - band - 4, 0))
    # cut the centre back out and round everything with outlines
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([4, 4, size - 5, size - 5], radius=18, fill=255)
    md.rounded_rectangle([4 + band, 4 + band, size - 5 - band, size - 5 - band], radius=6, fill=0)
    img.putalpha(mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([4, 4, size - 5, size - 5], radius=18, outline=(40, 22, 10, 255), width=4)
    d.rounded_rectangle([4 + band, 4 + band, size - 5 - band, size - 5 - band], radius=6, outline=(40, 22, 10, 255), width=3)
    d.rounded_rectangle([8, 8, size - 9, size - 9], radius=15, outline=(220, 180, 130, 160), width=1)

    # gold corner brackets with rivets
    gold, dark = (240, 196, 80, 255), (110, 70, 15, 255)
    for cx, cy, sx, sy in [(0, 0, 1, 1), (size, 0, -1, 1), (0, size, 1, -1), (size, size, -1, -1)]:
        pts = [(cx + sx * 2, cy + sy * 2), (cx + sx * 58, cy + sy * 2), (cx + sx * 58, cy + sy * 18),
               (cx + sx * 18, cy + sy * 18), (cx + sx * 18, cy + sy * 58), (cx + sx * 2, cy + sy * 58)]
        d.polygon(pts, fill=gold, outline=dark)
        d.line(pts + [pts[0]], fill=dark, width=3)
        for rx, ry in [(10, 10), (44, 10), (10, 44)]:
            x, y = cx + sx * rx, cy + sy * ry
            d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 235, 150, 255), outline=dark, width=2)
    save_tga(img, "Frame")


# ---------------------------------------------------------------------------
# Parchment, buttons, ribbons, tabs, bubbles
# ---------------------------------------------------------------------------
def make_parchment():
    """9-slice parchment card (24px corners)."""
    size = 128
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    paper = Image.new("RGBA", (size, size), (238, 218, 172, 255))
    pd = ImageDraw.Draw(paper)
    for _ in range(900):
        x, y = random.randrange(size), random.randrange(size)
        s = random.randint(-14, 8)
        pd.point((x, y), fill=(238 + s, 218 + s, 172 + s, 255))
    paper = paper.filter(ImageFilter.GaussianBlur(0.6))
    # darker, burnt-looking rim
    rim = Image.new("L", (size, size), 0)
    rd = ImageDraw.Draw(rim)
    for i in range(14):
        rd.rounded_rectangle([i, i, size - 1 - i, size - 1 - i], radius=14, outline=int(120 * (1 - i / 14)))
    brown = Image.new("RGBA", (size, size), (140, 96, 50, 255))
    paper = Image.composite(brown, paper, rim)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([2, 2, size - 3, size - 3], radius=14, fill=255)
    img.paste(paper, (0, 0), mask)
    ImageDraw.Draw(img).rounded_rectangle([2, 2, size - 3, size - 3], radius=14, outline=(90, 58, 26, 255), width=3)
    save_tga(img, "Parchment")


def make_button():
    """3-slice chunky button, 256x64 (left cap 32px). Light grey so it tints well."""
    w, h = 256, 64
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # dark base (the "3D" bottom edge)
    d.rounded_rectangle([2, 8, w - 3, h - 3], radius=22, fill=(60, 60, 60, 255))
    # body with vertical gradient
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y in range(h):
        t = y / h
        col = lerp((255, 255, 255), (170, 170, 170), t)
        ImageDraw.Draw(body).line([(0, y), (w, y)], fill=col + (255,))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([2, 2, w - 3, h - 10], radius=22, fill=255)
    img.paste(body, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2, 2, w - 3, h - 3], radius=22, outline=(30, 30, 30, 255), width=3)
    d.line([(26, 9), (w - 26, 9)], fill=(255, 255, 255, 200), width=3)   # shine
    save_tga(img, "Button")

    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle([6, 6, w - 7, h - 12], radius=20, fill=(255, 255, 220, 110))
    save_tga(glow.filter(ImageFilter.GaussianBlur(4)), "ButtonGlow")


def make_ribbon():
    """Banner ribbon, 512x128, white-ish so it can be tinted any colour."""
    w, h = 512, 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark = (40, 40, 40, 255)
    # tails
    for side in (0, 1):
        x0 = 6 if side == 0 else w - 86
        pts = [(x0, 34), (x0 + 80, 34), (x0 + 80, 114), (x0, 114)]
        notch = (x0 + 26, 74) if side == 0 else (x0 + 54, 74)
        poly = [pts[0], pts[1], pts[2], pts[3], notch] if side == 0 else [pts[1], pts[0], pts[3], pts[2], notch]
        d.polygon(poly, fill=(150, 150, 150, 255))
        d.line(poly + [poly[0]], fill=dark, width=4)
    # main band with a gentle curve
    top = [(56 + x, 18 + 10 * math.sin(math.pi * x / (w - 112))) for x in range(0, w - 111, 8)]
    bottom = [(x, y + 76) for x, y in reversed(top)]
    d.polygon(top + bottom, fill=(232, 232, 232, 255))
    d.line(top + bottom + [top[0]], fill=dark, width=5)
    d.line([(x, y + 8) for x, y in top], fill=(255, 255, 255, 255), width=3)
    save_tga(img, "Ribbon")


def make_tab():
    """Top tab, 128x64. Drawn light so it can be tinted."""
    w, h = 128, 64
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([4, 4, w - 5, h + 20], radius=18, fill=(225, 225, 225, 255), outline=(35, 35, 35, 255), width=4)
    d.line([(20, 10), (w - 20, 10)], fill=(255, 255, 255, 255), width=3)
    save_tga(img, "Tab")


def make_bubble():
    """Speech bubble body (9-slice, 32px corners) and its tail."""
    size = 128
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([3, 3, size - 4, size - 4], radius=26, fill=(255, 250, 235, 255), outline=(60, 40, 20, 255), width=4)
    save_tga(img, "Bubble")
    tail = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    td = ImageDraw.Draw(tail)
    td.polygon([(31, 4), (31, 26), (2, 30)], fill=(255, 250, 235, 255))
    td.line([(31, 26), (2, 30), (31, 4)], fill=(60, 40, 20, 255), width=3)
    save_tga(tail, "BubbleTail")


def make_ring():
    """Gold ring to frame square game icons (64x64 icon area inside 128)."""
    size = 128
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([6, 6, size - 7, size - 7], outline=(110, 70, 15, 255), width=16)
    d.ellipse([9, 9, size - 10, size - 10], outline=(240, 196, 80, 255), width=10)
    d.arc([14, 14, size - 15, size - 15], 200, 300, fill=(255, 240, 170, 255), width=4)
    save_tga(img, "Ring")
    # Round mask so icons look like coins: white circle, used with SetMask on Retail
    # and as a plain overlay on clients without masks.
    m = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ImageDraw.Draw(m).ellipse([0, 0, 63, 63], fill=(255, 255, 255, 255))
    save_tga(m, "CircleMask")


def make_spark():
    """A little white star for confetti (tinted at runtime)."""
    size = 32
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    pts = []
    for i in range(10):
        r = 15 if i % 2 == 0 else 6
        a = math.pi / 2 + i * math.pi / 5
        pts.append((c + r * math.cos(a), c - r * math.sin(a)))
    d.polygon(pts, fill=(255, 255, 255, 255))
    save_tga(img.filter(ImageFilter.GaussianBlur(0.5)), "Spark")


def make_slot():
    """Board cell: a carved, slightly sunken wooden slot (128x128)."""
    size = 128
    img = wood_strip(size, size, (150, 108, 70), True, 5)
    d = ImageDraw.Draw(img)
    for i in range(10):
        shade = int(90 * (1 - i / 10))
        d.rounded_rectangle([i, i, size - 1 - i, size - 1 - i], radius=16, outline=(30, 16, 6, shade))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=16, fill=255)
    img.putalpha(mask)
    d.rounded_rectangle([1, 1, size - 2, size - 2], radius=16, outline=(40, 22, 10, 255), width=3)
    save_tga(img, "Slot")


def make_connect6():
    """Connect 6 (vertical rack, like the classic box game).
    RackHole: one 64x64 tile of the rack's front panel with a round hole in it
    (transparent), tiled in game; the checkers sit BEHIND the panel, so they
    show through the holes. Checker: a ridged disc, light grey so it can be
    tinted per faction. StoneRim: a ring drawn on top of a checker."""
    size = 64
    # Rack tile: golden plastic/brass panel with a bevelled hole.
    tile = Image.new("RGBA", (size, size), (238, 190, 52, 255))
    d = ImageDraw.Draw(tile)
    d.line([(0, 0), (size, 0)], fill=(255, 226, 120, 255), width=2)          # top light
    d.line([(0, size - 1), (size, size - 1)], fill=(170, 120, 20, 255), width=2)
    c, r = size / 2, 24
    # bevel ring around the hole: dark at the top (inner shadow), light at the bottom
    for i in range(6):
        t = i / 6
        d.ellipse([c - r - 6 + i, c - r - 6 + i, c + r + 6 - i, c + r + 6 - i],
                  outline=lerp((150, 104, 12), (255, 228, 130), t) + (255,), width=1)
    mask = Image.new("L", (size, size), 255)
    ImageDraw.Draw(mask).ellipse([c - r, c - r, c + r, c + r], fill=0)
    tile.putalpha(mask)
    save_tga(tile, "RackHole")

    # Chip: a poker chip, light grey so it can be tinted (red for Horde, blue
    # for Alliance). The white edge notches are a separate, untinted texture
    # (ChipNotches) laid on top, and the faction crest goes in the middle.
    chip = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(chip)
    d.ellipse([2, 2, size - 3, size - 3], fill=(225, 225, 225, 255), outline=(40, 40, 40, 255), width=3)
    d.ellipse([12, 12, size - 13, size - 13], fill=(200, 200, 200, 255), outline=(150, 150, 150, 255), width=2)
    d.ellipse([16, 16, size - 17, size - 17], outline=(245, 245, 245, 255), width=2)   # inlay ring
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse([12, 8, 34, 20], fill=(255, 255, 255, 120))
    chip.alpha_composite(hl.filter(ImageFilter.GaussianBlur(3)))
    save_tga(chip, "Chip")

    notches = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    nd = ImageDraw.Draw(notches)
    c0 = size / 2 - 0.5
    for k in range(8):
        a0 = math.radians(k * 45 - 9)
        a1 = math.radians(k * 45 + 9)
        pts = []
        for a in (a0, (a0 + a1) / 2, a1):
            pts.append((c0 + 28.5 * math.cos(a), c0 + 28.5 * math.sin(a)))
        for a in (a1, (a0 + a1) / 2, a0):
            pts.append((c0 + 21 * math.cos(a), c0 + 21 * math.sin(a)))
        nd.polygon(pts, fill=(250, 248, 240, 255))
    save_tga(notches, "ChipNotches")

    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(rim).ellipse([2, 2, size - 3, size - 3], outline=(255, 255, 255, 255), width=6)
    save_tga(rim, "StoneRim")


def make_bingo():
    """Guild Bingo: card cells and lottery balls.
    BingoCell: a cream square with a rounded, inked border.
    Ball: a glossy sphere drawn light (tinted by column colour in game).
    BallFace: the white disc on the ball where the number goes (not tinted)."""
    size = 64
    cell = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(cell)
    d.rounded_rectangle([2, 2, size - 3, size - 3], radius=10, fill=(250, 241, 214, 255), outline=(120, 82, 40, 255), width=3)
    d.rounded_rectangle([6, 6, size - 7, size - 7], radius=8, outline=(255, 252, 240, 255), width=1)
    save_tga(cell, "BingoCell")

    ball = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = ball.load()
    c, r = size / 2 - 0.5, size / 2 - 2
    for y in range(size):
        for x in range(size):
            dx, dy = (x - c) / r, (y - c) / r
            d2 = dx * dx + dy * dy
            if d2 <= 1:
                nz = math.sqrt(1 - d2)
                light = max(0.0, (-dx * 0.4 - dy * 0.5 + nz * 0.75))
                v = int(120 + 135 * min(1.0, light))
                edge = 1 if d2 < 0.93 else max(0.0, (1 - d2) / 0.07)
                px[x, y] = (v, v, v, int(255 * edge))
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse([14, 9, 30, 19], fill=(255, 255, 255, 190))
    ball.alpha_composite(hl.filter(ImageFilter.GaussianBlur(2.5)))
    save_tga(ball, "Ball")

    face = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(face).ellipse([15, 15, size - 16, size - 16], fill=(255, 253, 245, 255), outline=(200, 195, 185, 255), width=2)
    save_tga(face, "BallFace")


def make_cards():
    """Playing cards (original art).
    CardFace / CardBack: a 128x183 card drawn in the top of a 128x256
    texture (WoW wants power-of-two sizes; the game crops it with
    SetTexCoord(0, 1, 0, 183/256)). Suits: four suit symbols in a row,
    already coloured (black spades/clubs, red hearts/diamonds)."""
    W, H = 128, 183

    face = Image.new("RGBA", (128, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(face)
    d.rounded_rectangle([1, 1, W - 2, H - 2], radius=12, fill=(253, 250, 240, 255), outline=(70, 60, 50, 255), width=3)
    d.rounded_rectangle([6, 6, W - 7, H - 7], radius=9, outline=(225, 215, 195, 255), width=1)
    save_tga(face, "CardFace")

    back = Image.new("RGBA", (128, 256), (0, 0, 0, 0))
    card = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle([1, 1, W - 2, H - 2], radius=12, fill=(120, 26, 22, 255), outline=(40, 10, 8, 255), width=3)
    # gold inner frame and a lattice of little diamonds
    cd.rounded_rectangle([8, 8, W - 9, H - 9], radius=8, outline=(222, 176, 70, 255), width=3)
    for yy in range(18, H - 14, 14):
        for xx in range(18, W - 14, 14):
            off = 7 if (yy // 14) % 2 else 0
            x = xx + off
            if x < W - 16:
                cd.polygon([(x, yy - 4), (x + 4, yy), (x, yy + 4), (x - 4, yy)], fill=(160, 44, 34, 255))
    # goblin badge in the middle
    head = Image.open(os.path.join(MEDIA, "GoblinFace.tga")).convert("RGBA").resize((70, 70), Image.LANCZOS)
    cd.ellipse([W / 2 - 40, H / 2 - 40, W / 2 + 40, H / 2 + 40], fill=(60, 14, 10, 255), outline=(222, 176, 70, 255), width=4)
    card.alpha_composite(head, (int(W / 2 - 35), int(H / 2 - 37)))
    back.paste(card, (0, 0))
    save_tga(back, "CardBack")

    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    suits = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    sd = ImageDraw.Draw(suits)
    font = ImageFont.truetype(font_path, 58)
    for i, (glyph, col) in enumerate([("\u2660", (28, 28, 36)), ("\u2665", (205, 30, 34)),
                                      ("\u2666", (205, 30, 34)), ("\u2663", (28, 28, 36))]):
        sd.text((i * 64 + 32, 34), glyph, font=font, fill=col + (255,), anchor="mm")
    save_tga(suits, "Suits")


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    make_logo()
    make_planks()
    make_frame()
    make_parchment()
    make_button()
    make_ribbon()
    make_tab()
    make_bubble()
    make_ring()
    make_spark()
    make_slot()
    make_connect6()
    make_bingo()
    make_cards()
    print("Wrote textures to", MEDIA)
