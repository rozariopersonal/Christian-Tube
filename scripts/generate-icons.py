import os
import sys
from PIL import Image, ImageDraw, ImageFont

def main():
    if len(sys.argv) < 5:
        print("Usage: python generate-icons.py <src_icon> <res_dir> <logo_dst> <is_beta>")
        sys.exit(1)

    src = sys.argv[1]
    res_dir = sys.argv[2]
    logo_dst = sys.argv[3]
    is_beta = sys.argv[4].lower() == 'true'

    img = Image.open(src).convert('RGBA')

    if is_beta:
        w, h = img.size
        overlay = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)

        # Bottom badge pill
        pill_w = int(w * 0.62)
        pill_h = int(h * 0.15)
        pill_x0 = (w - pill_w) // 2
        pill_y0 = int(h * 0.81)
        pill_x1 = pill_x0 + pill_w
        pill_y1 = pill_y0 + pill_h
        radius = pill_h // 2

        # Shadow
        shadow_offset = max(2, int(pill_h * 0.08))
        draw.rounded_rectangle(
            [pill_x0, pill_y0 + shadow_offset, pill_x1, pill_y1 + shadow_offset],
            radius=radius,
            fill=(0, 0, 0, 140)
        )

        # High-contrast Pill (Rose / Crimson)
        draw.rounded_rectangle(
            [pill_x0, pill_y0, pill_x1, pill_y1],
            radius=radius,
            fill=(225, 29, 72, 250),
            outline=(255, 255, 255, 240),
            width=max(2, int(w * 0.008))
        )

        font_size = int(pill_h * 0.60)
        font = None
        for fn in ['arialbd.ttf', 'DejaVuSans-Bold.ttf', 'seguiui.ttf', 'arial.ttf']:
            try:
                font = ImageFont.truetype(fn, font_size)
                break
            except Exception:
                pass
        if not font:
            font = ImageFont.load_default()

        text = 'BETA'
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        tx = pill_x0 + (pill_w - tw) // 2 - bbox[0]
        ty = pill_y0 + (pill_h - th) // 2 - bbox[1]
        draw.text((tx, ty), text, font=font, fill=(255, 255, 255, 255))

        img = Image.alpha_composite(img, overlay)

    # Save to mobile assets logo.png
    os.makedirs(os.path.dirname(logo_dst), exist_ok=True)
    img.save(logo_dst, 'PNG')

    # Generate Android mipmaps
    sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192
    }
    for folder, sz in sizes.items():
        target_dir = os.path.join(res_dir, folder)
        os.makedirs(target_dir, exist_ok=True)
        scale = sz * 0.84 / max(img.width, img.height)
        nw, nh = max(1, int(img.width * scale)), max(1, int(img.height * scale))
        resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (sz, sz), (0, 0, 0, 0))
        canvas.paste(resized, ((sz - nw) // 2, (sz - nh) // 2), resized)
        canvas.save(os.path.join(target_dir, 'ic_launcher.png'), 'PNG')

if __name__ == '__main__':
    main()
