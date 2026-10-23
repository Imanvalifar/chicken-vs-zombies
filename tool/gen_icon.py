"""Launcher icon from the asset pack's Mother Hen concept art."""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(ROOT, "assets", "images", "concept_art")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

S = 1024

src = Image.open(os.path.join(IMG, "concept_boss_mother_hen_hd.png")).convert("RGB")
# crop on the mother hen's cockpit so the face sits dead centre
box = (275, 105, 755, 585)
art = src.crop(box).resize((S, S), Image.LANCZOS)

# gentle vignette so the edges sink into the icon shape
vignette = Image.new("L", (S, S), 0)
vd = ImageDraw.Draw(vignette)
vd.ellipse((-S * 0.12, -S * 0.12, S * 1.12, S * 1.12), fill=255)
vignette = vignette.filter(ImageFilter.GaussianBlur(S * 0.06))
dark = Image.new("RGB", (S, S), (4, 6, 10))
art = Image.composite(art, dark, vignette)

img = art.convert("RGBA")
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22), fill=255)
img.putalpha(mask)

for name, size in SIZES.items():
    folder = os.path.join(RES, f"mipmap-{name}")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "ic_launcher.png")
    img.resize((size, size), Image.LANCZOS).save(path)
    print("wrote", path, f"{size}x{size}")

preview = os.path.join(ROOT, "tool", "icon_preview.png")
img.resize((256, 256), Image.LANCZOS).save(preview)

small = img.resize((48, 48), Image.LANCZOS)
sheet = Image.new("RGBA", (400, 260), (24, 24, 28, 255))
sheet.paste(img.resize((200, 200), Image.LANCZOS), (10, 30))
sheet.paste(small.resize((200, 200), Image.NEAREST), (225, 30))
sheet.save(os.path.join(ROOT, "tool", "icon_check.png"))
print("preview:", preview)
