# Renders Art/Icon/AppIcon-1024.png from the app's own paper textures, then
# builds Assets/AppIcon.icns.  Usage: python3 Art/Icon/make_icon.py
import pathlib, shutil, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = pathlib.Path(__file__).resolve().parents[2]
S = 1024
INK = (48, 56, 48, 240)

def paper(name, width, angle):
    im = Image.open(root / f"Sources/DoveSonoArrivato/Resources/paper-{name}.png").convert("RGBA")
    im = im.crop(im.getchannel("A").getbbox())
    im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
    return im.rotate(angle, resample=Image.BICUBIC, expand=True)

def shadowed(base, layer, xy, blur=18, alpha=0.28, dy=14):
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    shadow.paste((20, 30, 40, 255), (xy[0], xy[1] + dy), layer.getchannel("A").point(lambda v: int(v * alpha)))
    base = Image.alpha_composite(base, shadow.filter(ImageFilter.GaussianBlur(blur)))
    base.alpha_composite(layer, xy)
    return base

def handwriting(size):
    for index in range(6):
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Noteworthy.ttc", size, index=index)
        if "Bold" in " ".join(font.getname()):
            return font
    return ImageFont.truetype("/System/Library/Fonts/Supplemental/Noteworthy.ttc", size)

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# macOS icon grid: an 824 pt rounded square, centred, with a soft drop shadow.
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((100, 100, 924, 924), radius=185, fill=255)
gradient = Image.new("RGBA", (S, S))
draw = ImageDraw.Draw(gradient)
top, bottom = (241, 245, 249), (198, 211, 225)
for y in range(S):
    t = max(0, min(1, (y - 100) / 824))
    draw.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
plate = Image.new("RGBA", (S, S), (0, 0, 0, 0))
plate.paste(gradient, (0, 0), mask)
drop = Image.new("RGBA", (S, S), (0, 0, 0, 0))
drop.paste((10, 20, 30, 90), (0, 10), mask)
canvas = Image.alpha_composite(canvas, drop.filter(ImageFilter.GaussianBlur(16)))
canvas = Image.alpha_composite(canvas, plate)

back = paper("mint", 560, 9)
canvas = shadowed(canvas, back, (S // 2 - back.width // 2 + 60, S // 2 - back.height // 2 - 40))
front = paper("yellow", 580, -5)
fx, fy = S // 2 - front.width // 2 - 30, S // 2 - front.height // 2 + 40
canvas = shadowed(canvas, front, (fx, fy))

ink = Image.new("RGBA", (S, S), (0, 0, 0, 0))
font = handwriting(470)
cx, cy = fx + front.width // 2, fy + front.height // 2
box = ImageDraw.Draw(ink).textbbox((0, 0), "?", font=font)
ImageDraw.Draw(ink).text((cx - (box[0] + box[2]) // 2, cy - (box[1] + box[3]) // 2 + 10), "?", font=font, fill=INK)
canvas = Image.alpha_composite(canvas, ink.rotate(-5, resample=Image.BICUBIC, center=(cx, cy)))
canvas.save(root / "Art/Icon/AppIcon-1024.png")

with tempfile.TemporaryDirectory() as tmp:
    iconset = pathlib.Path(tmp) / "AppIcon.iconset"
    iconset.mkdir()
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            suffix = "" if scale == 1 else "@2x"
            canvas.resize((pixels, pixels), Image.LANCZOS).save(iconset / f"icon_{points}x{points}{suffix}.png")
    (root / "Assets").mkdir(exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(root / "Assets/AppIcon.icns")], check=True)
print("Assets/AppIcon.icns")
