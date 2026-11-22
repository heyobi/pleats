"""App Store screenshots for Pleats: headline, subline and the simulator screenshot on a gradient.

Usage: python scripts/compose-screens.py <raw-dir> <out-dir> <iphone|ipad|duo-outer|duo-inner>
Raw screenshots come from .github/workflows/screenshots.yml; output has the same size as the raw image.

"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# (raw name, title, subtitle on iPhone Duo, subtitle elsewhere)
ORDER = [
    ('1-play', 'The hinge is the bellows', 'Open and close iPhone Duo to play', 'Drag the bellows, press the buttons'),
    ('2-lesson', 'Learn songs, button by button', 'The next button lights up and waits', 'The next button lights up and waits'),
    ('3-registers', 'Real reeds, real registers', 'Musette, Bandoneon, Clarinet and more', 'Musette, Bandoneon, Clarinet and more'),
    ('4-songs', 'Folk tunes and classics', 'From Ode to Joy to a sea shanty', 'From Ode to Joy to a sea shanty'),
    ('5-done', 'Three stars to earn', 'Free songs, no ads, no account', 'Free songs, no ads, no account'),
]

BOLD = 'C:/Windows/Fonts/georgiab.ttf'
SEMI = 'C:/Windows/Fonts/georgia.ttf'


def gradient(top, bottom, w, h):
    g = Image.new('RGB', (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h))


def rounded(img, r):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), r, fill=255)
    out = Image.new('RGBA', img.size)
    out.paste(img, (0, 0), mask)
    return out


def mark_fold(shot, fold: float, label: str):
    """A dashed line where the iPhone Duo folds, with a small label, to show the layout splits at the fold."""
    w, h = shot.size
    x = int(w * fold)
    layer = Image.new('RGBA', shot.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    dash, gap, lw = int(h * 0.022), int(h * 0.014), max(4, int(w * 0.0022))
    y = int(h * 0.10)
    while y < h:
        d.rectangle((x - lw // 2 - 2, y - 2, x + lw // 2 + 2, min(y + dash, h) + 2), fill=(0, 0, 0, 90))
        d.rectangle((x - lw // 2, y, x + lw // 2, min(y + dash, h)), fill=(255, 255, 255, 200))
        y += dash + gap
    f = ImageFont.truetype(SEMI, int(h * 0.024))
    tw = d.textlength(label, font=f)
    px, py = int(h * 0.014), int(h * 0.007)
    top = int(h * 0.045)
    box = (x - tw / 2 - px, top, x + tw / 2 + px, top + f.size + 2 * py)
    d.rounded_rectangle(box, radius=(box[3] - box[1]) / 2, fill=(255, 255, 255, 235))
    d.text((x - tw / 2, top + py - int(f.size * 0.12)), label, font=f, fill=(40, 40, 60, 255))
    out = shot.convert('RGBA')
    out.alpha_composite(layer)
    return out.convert('RGB')


def compose(raw: Path, title: str, sub: str, out: Path, dark: bool, fold: float | None = None, fold_label: str = 'iPhone Duo'):
    """Same size as the raw screenshot (iPhone, iPad or iPhone Duo); type and margins scale with the width."""
    shot = Image.open(raw).convert('RGB')
    if fold:
        shot = mark_fold(shot, fold, fold_label)
    w, h = shot.size
    k = min(w, h) / 1206 * (1 if h >= w else 0.8)  # landscape (iPhone Duo inner display): scale by height
    bg = gradient((46, 10, 16), (14, 4, 6), w, h) if dark else gradient((92, 18, 30), (40, 8, 12), w, h)
    canvas = bg.convert('RGBA')
    d = ImageDraw.Draw(canvas)
    f1 = ImageFont.truetype(BOLD, int(96 * k))
    f2 = ImageFont.truetype(SEMI, int(52 * k))
    y = int(170 * k) if h / w > 1.6 else int(110 * k)
    while d.textlength(title, font=f1) > w - 140 * k and f1.size > 40:
        f1 = ImageFont.truetype(BOLD, f1.size - 4)
    for text, font, fill, gap in ((title, f1, (248, 236, 214), 26 * k), (sub, f2, (220, 179, 102), 0)):
        tw = d.textlength(text, font=font)
        d.text(((w - tw) / 2, y), text, font=font, fill=fill)
        y += font.size + gap + 14 * k
    top = int(y + 80 * k)
    sh = min(int(h * 0.80), h - top - int(50 * k))
    sw = int(sh * w / h)
    r = int(70 * k * sw / (w * 0.8))
    img = rounded(shot.resize((sw, sh), Image.LANCZOS), r)
    x = (w - sw) // 2
    pad = int(60 * k)
    shadow = Image.new('RGBA', (sw + 2 * pad, sh + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((pad, pad + 10, sw + pad, sh + pad + 10), r + 10, fill=(10, 10, 40, 150))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(int(36 * k))), (x - pad, top - pad))
    b = max(6, int(8 * k))
    border = Image.new('RGBA', (sw + 2 * b, sh + 2 * b), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((0, 0, sw + 2 * b - 1, sh + 2 * b - 1), r + b, fill=(18, 18, 24, 255))
    canvas.alpha_composite(border, (x - b, top - b))
    canvas.alpha_composite(img, (x, top))
    canvas.convert('RGB').save(out, optimize=True)


def main():
    raw, out, kind = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    duo = kind.startswith('duo')
    out.mkdir(parents=True, exist_ok=True)
    i = 0
    for name, title, sub_duo, sub in ORDER:
        src = raw / f'{name}.png'
        if not src.exists():
            print('missing', name)
            continue
        i += 1
        fold = None  # the bellows strip already shows the fold
        label = 'iPhone Duo hinge'
        compose(src, title, sub_duo if duo else sub, out / f'{i}-{name[2:]}.png', i % 2 == 1, fold, label)
        print('saved', i, name)


if __name__ == '__main__':
    main()
