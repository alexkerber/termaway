#!/usr/bin/env python3
"""Render the DMG background that release.sh drops into the disk image.

    cd apps/macos && python3 dmg-background.py
    tiffutil -cathidpicheck dmg-background.png dmg-background@2x.png \
      -out dmg-background.tiff

The TIFF carries both scales so the window is crisp on Retina. CARD and the
icon centres below must stay in step with the AppleScript in release.sh, which
positions the real icons on top of what this draws.
"""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H, S = 640, 420, 2          # window points, and the supersample factor
CARD = (40, 178, 600, 378)     # glass panel, in points
APP_C, DEST_C = (176, 270), (464, 270)   # icon centres, in points

SLATE_TOP, SLATE_BOT = (32, 37, 45), (13, 17, 23)
CREAM, ORANGE, AMBER = (245, 237, 224), (255, 107, 53), (255, 182, 39)


def font(size, weight="Regular"):
    for path, idx in (("/System/Library/Fonts/SFNS.ttf", 0),
                      ("/System/Library/Fonts/HelveticaNeue.ttc", 0)):
        try:
            f = ImageFont.truetype(path, size * S, index=idx)
            try:
                f.set_variation_by_name(weight)
            except Exception:
                pass
            return f
        except OSError:
            continue
    return ImageFont.load_default()


def sparkle(draw, cx, cy, r, fill):
    """The app icon's four-point star: a superellipse with p<1 is concave."""
    pts = []
    for i in range(240):
        t = 2 * math.pi * i / 240
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + r * math.copysign(abs(c) ** 4, c),
                    cy + r * math.copysign(abs(s) ** 4, s)))
    draw.polygon(pts, fill=fill)


img = Image.new("RGB", (W * S, H * S))
d = ImageDraw.Draw(img)

# Vertical slate gradient, the icon's own backdrop.
for y in range(H * S):
    t = y / (H * S - 1)
    d.line([(0, y), (W * S, y)],
           fill=tuple(round(a + (b - a) * t) for a, b in zip(SLATE_TOP, SLATE_BOT)))

# A warm glow behind the wordmark, drawn small and blurred up.
glow = Image.new("L", (W * S // 4, H * S // 4), 0)
gw, gh = W * S // 4, H * S // 4
ImageDraw.Draw(glow).ellipse([gw * 0.18, -gh * 0.10, gw * 0.82, gh * 0.42], fill=95)
glow = glow.resize((W * S, H * S)).filter(ImageFilter.GaussianBlur(60 * S))
img.paste(Image.new("RGB", img.size, ORANGE), (0, 0), glow)

# Wordmark and tagline.
d = ImageDraw.Draw(img)
d.text((W * S / 2, 74 * S), "TermAway", font=font(44, "Bold"),
       fill=CREAM, anchor="mm")
d.text((W * S / 2, 124 * S), "Your Mac terminal, on your iPad.",
       font=font(16), fill=(168, 172, 180), anchor="mm")

# Glass card behind the two icons, on the site's own surface values.
card = Image.new("RGBA", img.size, (0, 0, 0, 0))
cd = ImageDraw.Draw(card)
box = [c * S for c in CARD]
cd.rounded_rectangle(box, radius=22 * S, fill=(255, 255, 255, 12),
                     outline=(255, 255, 255, 30), width=max(1, S))
img.paste(Image.alpha_composite(img.convert("RGBA"), card).convert("RGB"))

# Sparkles marching from the app towards Applications, sized in an arc so the
# eye reads a direction rather than a row of dots.
d = ImageDraw.Draw(img, "RGBA")
x0, x1 = APP_C[0] + 62, DEST_C[0] - 62
for i in range(5):
    f = i / 4
    x = x0 + (x1 - x0) * f
    y = APP_C[1] - 20 * math.sin(math.pi * f)
    r = 5 + 5 * math.sin(math.pi * f)
    tint = tuple(round(a + (b - a) * f) for a, b in zip(AMBER, ORANGE))
    sparkle(d, x * S, y * S, r * S, tint + (200,))

img.resize((W * S, H * S)).save("dmg-background@2x.png")
img.resize((W, H), Image.LANCZOS).save("dmg-background.png")
print(f"wrote {W*S}x{H*S} and {W}x{H}")
