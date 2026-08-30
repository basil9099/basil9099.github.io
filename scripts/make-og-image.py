"""Generate the Open Graph share card at static/images/og-default.png.

LinkedIn renders the card around 520px wide in-feed, a 0.43x reduction from
1200px. Two consequences drive the design here:

  * Type is sized so it survives that reduction. Anything under ~30px at
    1200px wide lands under 13px in the feed and stops being readable.
  * The card is rendered at 2x and downsampled with LANCZOS. Rasterising
    large and shrinking gives noticeably crisper glyph edges than drawing
    at final size, which is what made the first version look soft.

The site URL is deliberately absent: LinkedIn prints the domain beneath the
card already, so repeating it inside the image wastes space and adds a line
too small to read.
"""

from PIL import Image, ImageDraw, ImageFont

SCALE = 2  # supersample, then downsample for crisper text
W, H = 1200 * SCALE, 630 * SCALE

BG = "#10141a"
ACCENT = "#3ddc84"
PRIMARY = "#e6e9ee"

BOLD = ("C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf")
REGULAR = ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf")


def font(paths, size):
    for path in paths:
        try:
            return ImageFont.truetype(path, size * SCALE)
        except OSError:
            continue
    return ImageFont.load_default()


img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

d.rectangle([0, 0, W, 8 * SCALE], fill=ACCENT)

d.text((80 * SCALE, 236 * SCALE), "Angus Dawson",
       font=font(BOLD, 104), fill=PRIMARY)
d.text((80 * SCALE, 372 * SCALE), "Active Directory  ·  Homelab  ·  Detection",
       font=font(REGULAR, 46), fill=ACCENT)

img = img.resize((1200, 630), Image.LANCZOS)
img.save("static/images/og-default.png", optimize=True)
print("wrote static/images/og-default.png")
