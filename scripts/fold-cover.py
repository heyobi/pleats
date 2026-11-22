"""App Store cover for the iPhone Duo inner-display slot (2853x2007): the real simulator screenshot drawn on a
half-open iPhone Duo, like an open book seen from the front, so the fold is obvious at a glance.

Usage: python -X utf8 scripts/fold-cover.py <raw inner screenshot.png> <out.png> [angle]
angle = opening angle in degrees between the two halves (default 125).
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 2853, 2007
BOLD = 'C:/Windows/Fonts/georgiab.ttf'
SEMI = 'C:/Windows/Fonts/georgia.ttf'


def coeffs(src, dst):
    """Perspective coefficients mapping dst quad -> src quad (PIL wants the inverse)."""
    import numpy as np
    A, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return np.linalg.solve(np.array(A, float), np.array(b, float)).tolist()


def warp(img, quad, size):
    w, h = img.size
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    out = img.convert('RGBA').transform(size, Image.PERSPECTIVE, coeffs(src, quad), Image.BICUBIC)
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).polygon(quad, fill=255)
    out.putalpha(mask)
    return out


def main():
    raw = Image.open(sys.argv[1]).convert('RGB')
    out_path = sys.argv[2]
    opening = float(sys.argv[3]) if len(sys.argv) > 3 else 125
    tilt = math.radians((180 - opening) / 2)   # each half turns away from the viewer by this much

    # Background and caption, matching the other screenshots.
    bg = Image.new('RGB', (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(70 - 52 * t), int(12 - 8 * t), int(20 - 14 * t)))
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W * 0.18, H * 0.30, W * 0.82, H * 1.05], fill=(220, 160, 80, 60))
    bg.paste(glow.filter(ImageFilter.GaussianBlur(220)), (0, 0), glow.filter(ImageFilter.GaussianBlur(220)))
    d = ImageDraw.Draw(bg)
    f1 = ImageFont.truetype(BOLD, 112)
    f2 = ImageFont.truetype(SEMI, 60)
    for text, font, fill, y in (("The hinge is the bellows", f1, (248, 236, 214), 120),
                                ("Open and close iPhone Duo to play", f2, (220, 179, 102), 270)):
        tw = d.textlength(text, font=font)
        d.text(((W - tw) / 2, y), text, font=font, fill=fill)

    # Device halves: the screenshot split at the fold, each with a dark bezel.
    sw, sh = raw.size
    half_w = sw // 2
    bezel = 34
    halves = []
    for i in range(2):
        part = raw.crop((i * half_w, 0, (i + 1) * half_w, sh))
        framed = Image.new('RGB', (half_w + 2 * bezel, sh + 2 * bezel), (14, 12, 14))
        framed.paste(part, (bezel, bezel))
        r = Image.new('L', framed.size, 0)
        ImageDraw.Draw(r).rounded_rectangle([0, 0, framed.size[0] - 1, framed.size[1] - 1], 90, fill=255)
        halves.append((framed, r))

    # Geometry: the hinge is a vertical line at the centre; each half recedes, so its outer edge is shorter
    # (perspective) and its width shrinks by cos(tilt).
    scale = 0.62
    ph = halves[0][0].size[1] * scale          # height at the hinge
    pw = halves[0][0].size[0] * scale * math.cos(tilt)
    persp = 1 - 0.18 * math.sin(tilt) / math.sin(math.radians(27.5))   # outer edge height factor
    cx, cy = W / 2, H * 0.60
    # Open book seen from the front: the hinge is farthest away (shorter), the outer edges come towards the viewer
    # (taller) and sit a little lower, as seen from slightly above.
    hh = ph * persp
    top, bot = cy - hh / 2 - ph * 0.03, cy + hh / 2 - ph * 0.03
    otop, obot = cy - ph / 2 + ph * 0.02, cy + ph / 2 + ph * 0.02

    # Soft shadow on the "table" under the open device.
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([cx - pw * 1.15, obot - 60, cx + pw * 1.15, obot + 110], fill=(0, 0, 0, 170))
    bg.paste(shadow.filter(ImageFilter.GaussianBlur(60)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(60)))

    quads = [
        [(cx - pw, otop), (cx, top), (cx, bot), (cx - pw, obot)],   # left half
        [(cx, top), (cx + pw, otop), (cx + pw, obot), (cx, bot)],   # right half
    ]
    for (framed, rmask), quad, shade in zip(halves, quads, (0.82, 1.0)):
        rgba = framed.convert('RGBA')
        rgba.putalpha(rmask)
        w = warp(rgba, quad, (W, H))
        # The left half faces a little away from the light.
        if shade < 1:
            dark = Image.new('RGBA', (W, H), (0, 0, 0, int(255 * (1 - shade))))
            dark.putalpha(Image.eval(w.getchannel('A'), lambda a: int(a * (1 - shade))))
            w = Image.alpha_composite(w, dark)
        bg.paste(w, (0, 0), w)

    # Hinge spine.
    spine = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(spine)
    for k in range(24):
        a = int(200 - abs(k - 12) * 14)
        sd.line([(cx - 12 + k, top + 6), (cx - 12 + k, bot - 6)], fill=(a // 3, a // 3, a // 3, 255))
    bg.paste(spine, (0, 0), spine)

    # A gentle highlight along the right half's edge.
    hl = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(hl).line([(cx + pw - 2, otop + 40), (cx + pw - 2, obot - 40)], fill=(255, 240, 220, 70), width=4)
    bg.paste(hl, (0, 0), hl)

    bg.save(out_path, optimize=True)
    print('saved', out_path)


if __name__ == '__main__':
    main()
