from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 630
img = Image.new("RGB", (W, H), "#10141a")
d = ImageDraw.Draw(img)

def font(size):
    for path in ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()

d.rectangle([0, 0, W, 6], fill="#3ddc84")
d.text((80, 240), "Angus Dawson", font=font(76), fill="#e6e9ee")
d.text((80, 350), "Active Directory  ·  Homelab  ·  Detection",
       font=font(34), fill="#3ddc84")
d.text((80, 430), "basil9099.github.io", font=font(26), fill="#8792a3")

img.save("static/images/og-default.png")
print("wrote static/images/og-default.png")
