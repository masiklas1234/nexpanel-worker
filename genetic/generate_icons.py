import os
import shutil
try:
    from PIL import Image, ImageDraw
except ImportError:
    os.system("pip install Pillow")
    from PIL import Image, ImageDraw

ICON_SIZES = {
    "mdpi":    48,
    "hdpi":    72,
    "xhdpi":   96,
    "xxhdpi":  144,
    "xxxhdpi": 192
}

# 1. Clean up existing mipmap folders first
res_dir = "app/src/main/res"
for density in ICON_SIZES.keys():
    mipmap_dir = os.path.join(res_dir, f"mipmap-{density}")
    if os.path.exists(mipmap_dir):
        print(f"Deleting: {mipmap_dir}")
        shutil.rmtree(mipmap_dir)

def load_img(path):
    img = Image.open(path)
    if img.mode == "RGBA":
        bg = Image.new("RGB", img.size, (0, 0, 0))
        bg.paste(img, mask=img.split()[3])
        return bg
    elif img.mode != "RGB":
        return img.convert("RGB")
    return img

def make_placeholder(size):
    icon = Image.new("RGB", (size, size), (8, 12, 16))
    draw = ImageDraw.Draw(icon)
    draw.ellipse([size//4, size//4, 3*size//4, 3*size//4], fill=(0, 212, 255))
    return icon

# Load default icon
use_default = os.path.isfile("sync.jpg")
img_default = load_img("sync.jpg") if use_default else None

# Generate icons
for density, size in ICON_SIZES.items():
    out_dir = os.path.join(res_dir, f"mipmap-{density}")
    os.makedirs(out_dir, exist_ok=True)

    # 1. Default Launcher Icons
    icon = img_default.resize((size, size), Image.LANCZOS) if use_default else make_placeholder(size)
    icon.save(os.path.join(out_dir, "ic_launcher.png"), "PNG")
    icon.save(os.path.join(out_dir, "ic_launcher_round.png"), "PNG")
    print(f"Generated launcher icons ({density}): {size}x{size}")

print("All default launcher icons successfully generated!")
