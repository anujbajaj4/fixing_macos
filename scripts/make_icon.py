"""Draws the app icon once and writes assets/AppIcon.iconset (run: python3 scripts/make_icon.py)."""
import os
from PIL import Image, ImageDraw

S = 1024
def draw():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Background tile (macOS icon grid: ~824px tile centred in 1024)
    m = 100
    top, bottom = (58, 72, 104), (24, 30, 46)
    tile = Image.new("RGBA", (S, S))
    td = ImageDraw.Draw(tile)
    for y in range(S):
        t = y / S
        td.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([m, m, S - m, S - m], radius=185, fill=255)
    img.paste(tile, (0, 0), mask)
    # Three window thumbnails, as in Mission Control
    def win(x0, y0, x1, y1, a):
        d.rounded_rectangle([x0, y0, x1, y1], radius=28, fill=(235, 240, 250, a), outline=(255, 255, 255, 255), width=10)
        d.rounded_rectangle([x0, y0, x1, y0 + 46], radius=28, fill=(200, 210, 228, a))
    win(190, 360, 470, 560, 150)
    win(560, 360, 840, 560, 150)
    win(330, 560, 760, 820, 255)
    # Red close button on the front window's top-left corner
    cx, cy, r = 330, 560, 118
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(236, 74, 66, 255), outline=(255, 255, 255, 255), width=14)
    k = 50
    d.line([cx - k, cy - k, cx + k, cy + k], fill=(255, 255, 255, 255), width=30)
    d.line([cx - k, cy + k, cx + k, cy - k], fill=(255, 255, 255, 255), width=30)
    return img

out = os.path.join(os.path.dirname(__file__), "..", "assets", "AppIcon.iconset")
os.makedirs(out, exist_ok=True)
big = draw()
big.save(os.path.join(os.path.dirname(__file__), "..", "assets", "icon-1024.png"))
for base in (16, 32, 128, 256, 512):
    big.resize((base, base), Image.LANCZOS).save(os.path.join(out, f"icon_{base}x{base}.png"))
    big.resize((base * 2, base * 2), Image.LANCZOS).save(os.path.join(out, f"icon_{base}x{base}@2x.png"))
print("wrote", os.path.normpath(out))
