# Draws the Pleats icon (1024x1024, no alpha) and writes the asset catalog (AppIcon, AccentColor, LaunchColor).
# An accordion seen from the front, opened like a book: two lacquered boards with pearl buttons and pleated bellows
# between them, on a deep oxblood ground with a brass glow. Original artwork, drawn here.
# Usage: python scripts/icon.py
from PIL import Image, ImageDraw, ImageFilter
import json, os, math

S = 1024
SS = 2  # supersample
W = S * SS
img = Image.new('RGB', (W, W))
d = ImageDraw.Draw(img)
for y in range(W):
    t = y / W
    d.line([(0, y), (W, y)], fill=(int(70 - 40 * t), int(14 - 8 * t), int(24 - 12 * t)))

glow = Image.new('RGBA', (W, W), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([W * 0.12, W * 0.10, W * 0.88, W * 0.86], fill=(230, 170, 80, 70))
glow = glow.filter(ImageFilter.GaussianBlur(W * 0.11))
img.paste(glow, (0, 0), glow)

layer = Image.new('RGBA', (W, W), (0, 0, 0, 0))
L = ImageDraw.Draw(layer)

top, bottom = W * 0.20, W * 0.80
left_board = (W * 0.13, top, W * 0.40, bottom)
right_board = (W * 0.60, top, W * 0.87, bottom)
r = W * 0.045

# Shadow
sh = Image.new('RGBA', (W, W), (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle([W * 0.13, top + W * 0.03, W * 0.87, bottom + W * 0.04], r, fill=(0, 0, 0, 150))
sh = sh.filter(ImageFilter.GaussianBlur(W * 0.025))
img.paste(sh, (0, 0), sh)

# Bellows: pleats as alternating vertical bands with a zigzag top and bottom edge.
bx0, bx1 = W * 0.40, W * 0.60
n = 7
fw = (bx1 - bx0) / n
for i in range(n):
    x = bx0 + i * fw
    light = (150, 30, 44) if i % 2 == 0 else (60, 10, 18)
    L.polygon([(x, top + W * 0.025), (x + fw, top + (W * 0.0 if i % 2 == 0 else W * 0.025)),
               (x + fw, bottom - (W * 0.0 if i % 2 == 0 else W * 0.025)), (x, bottom - W * 0.025)], fill=light)
    L.line([(x, top + W * 0.02), (x, bottom - W * 0.02)], fill=(20, 4, 8), width=SS * 2)
# Tape edges
L.rectangle([bx0, top - W * 0.005, bx1, top + W * 0.03], fill=(246, 238, 222))
L.rectangle([bx0, bottom - W * 0.03, bx1, bottom + W * 0.005], fill=(246, 238, 222))
for i in range(n):
    x = bx0 + i * fw
    for (y0, y1) in [(top + W * 0.03, top + W * 0.065), (bottom - W * 0.03, bottom - W * 0.065)]:
        L.polygon([(x + fw * 0.15, y0), (x + fw * 0.85, y0), (x + fw * 0.5, y1)], fill=(214, 172, 92))

# Boards
for (x0, y0, x1, y1) in [left_board, right_board]:
    L.rounded_rectangle([x0, y0, x1, y1], r, fill=(20, 8, 12))
    L.rounded_rectangle([x0 + W * 0.012, y0 + W * 0.012, x1 - W * 0.012, y1 - W * 0.012], r * 0.7, outline=(214, 172, 92), width=SS * 3)


def pearl(cx, cy, rad, ebony=False):
    L.ellipse([cx - rad * 1.12, cy - rad * 1.12, cx + rad * 1.12, cy + rad * 1.12], fill=(190, 148, 70))
    steps = 18
    for k in range(steps):
        t = k / steps
        rr = rad * (1 - t * 0.85)
        if ebony:
            c = int(14 + 70 * t)
            col = (c, c, c)
        else:
            col = (int(205 + 50 * t), int(198 + 55 * t), int(190 + 60 * t))
        off = rad * 0.25 * t
        L.ellipse([cx - rr - off, cy - rr - off, cx + rr - off, cy + rr - off], fill=col)


# Treble buttons on the right board: a 3-row lattice.
rows = 3
for row in range(rows):
    for k in range(5):
        cx = W * 0.665 + row * W * 0.07
        cy = top + W * 0.10 + k * W * 0.105 + (W * 0.05 if row % 2 else 0)
        if cy > bottom - W * 0.07:
            continue
        pearl(cx, cy, W * 0.026, ebony=(row == 1 and k % 2 == 1))
# Bass buttons on the left board: a slanted 3-row grid, smaller.
for row in range(3):
    for k in range(6):
        cx = W * 0.20 + row * W * 0.07
        cy = top + W * 0.085 + k * W * 0.085 + row * W * 0.028
        if cy > bottom - W * 0.06:
            continue
        pearl(cx, cy, W * 0.021)

img.paste(layer, (0, 0), layer)
img = img.resize((S, S), Image.LANCZOS)

root = os.path.join(os.path.dirname(__file__), '..', 'Pleats', 'Assets.xcassets')
icon_dir = os.path.join(root, 'AppIcon.appiconset')
os.makedirs(icon_dir, exist_ok=True)
img.save(os.path.join(icon_dir, 'icon-1024.png'))
json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(icon_dir, 'Contents.json'), 'w'), indent=2)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(root, 'Contents.json'), 'w'), indent=2)


def colorset(name, light, dark):
    p = os.path.join(root, name + '.colorset')
    os.makedirs(p, exist_ok=True)
    def comp(c):
        return {"color-space": "srgb", "components": {"red": f"{c[0]:.3f}", "green": f"{c[1]:.3f}", "blue": f"{c[2]:.3f}", "alpha": "1.000"}}
    json.dump({"colors": [{"idiom": "universal", "color": comp(light)},
                          {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "color": comp(dark)}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(p, 'Contents.json'), 'w'), indent=2)


colorset('AccentColor', (0.62, 0.45, 0.16), (0.86, 0.70, 0.40))
colorset('LaunchColor', (0.88, 0.83, 0.74), (0.04, 0.02, 0.03))
os.makedirs(os.path.join(os.path.dirname(__file__), '..', 'docs'), exist_ok=True)
img.resize((256, 256), Image.LANCZOS).save(os.path.join(os.path.dirname(__file__), '..', 'docs', 'icon.png'))
print('icon written')
