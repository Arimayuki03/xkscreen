# XkScreen app icon generator (Pillow).
# Design: dark rounded plate + two gauge rings (CPU amber / GPU sky)
# + a centre emerald clock pill - matching the console's hero preview.
# Outputs: appicon.png (256), appicon.ico (multi-size for the exe),
# and a copy as the web favicon (frontend/src/app/icon.png).

from PIL import Image, ImageDraw

S = 1024  # supersampled canvas for smooth edges
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)


def rr(box, radius, fill, outline=None, width=0):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


# background plate
rr([16, 16, S - 16, S - 16], 210, (11, 15, 20, 255), (30, 41, 59, 255), 20)


def ring(cx, cy, r, w, color, frac):
    d.arc([cx - r, cy - r, cx + r, cy + r], 0, 360, fill=(30, 41, 59, 255), width=w)
    d.arc([cx - r, cy - r, cx + r, cy + r], -90, -90 + int(360 * frac), fill=color, width=w)


# CPU ring (amber, 62%) / GPU ring (sky, 40%)
ring(316, 512, 168, 68, (251, 191, 36, 255), 0.62)
ring(708, 512, 168, 68, (56, 189, 248, 255), 0.40)
# centre clock pill (emerald)
rr([470, 380, 554, 644], 42, (52, 211, 153, 255))

img512 = img.resize((512, 512), Image.LANCZOS)
img256 = img512.resize((256, 256), Image.LANCZOS)

png_path = r"D:\Code\Xingcan-Xiaolan-Drive\product\XkScreen.Gui\appicon.png"
ico_path = r"D:\Code\Xingcan-Xiaolan-Drive\product\XkScreen.Gui\appicon.ico"
fav_path = r"D:\Code\Xingcan-Xiaolan-Drive\product\frontend\src\app\icon.png"

img256.save(png_path)
img512.save(ico_path, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
img256.save(fav_path)

print("icon files written:")
print(" ", png_path)
print(" ", ico_path)
print(" ", fav_path)
