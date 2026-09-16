#!/usr/bin/env python3
"""
generate_icons.py
-----------------
Generates custom application icons for Antigravity IDE and Antigravity 2.0
from the base Antigravity logo PNG.

Requirements:
- Antigravity IDE: Dark background (#181825)
- Antigravity 2.0: Light background (#FFFFFF)
"""

import os
import sys
from PIL import Image, ImageDraw

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SRC = os.path.join(SCRIPT_DIR, "antigravity.png")

def make_icon(src_img_path, bg_color, radius_ratio=0.22, padding_ratio=0.15, size=(512, 512)):
    if not os.path.isfile(src_img_path):
        raise FileNotFoundError(f"Source icon not found at {src_img_path}")

    logo = Image.open(src_img_path).convert("RGBA")
    icon = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)

    # Draw rounded squircle background
    r = int(size[0] * radius_ratio)
    draw.rounded_rectangle([(0, 0), size], radius=r, fill=bg_color)

    # Scale logo maintaining aspect ratio with padding
    pad = int(size[0] * padding_ratio)
    target_w = size[0] - 2 * pad
    target_h = size[1] - 2 * pad

    # Scale maintaining aspect ratio
    logo_w, logo_h = logo.size
    ratio = min(target_w / logo_w, target_h / logo_h)
    new_w = int(logo_w * ratio)
    new_h = int(logo_h * ratio)
    resized_logo = logo.resize((new_w, new_h), Image.Resampling.LANCZOS)

    # Center placement
    offset_x = pad + (target_w - new_w) // 2
    offset_y = pad + (target_h - new_h) // 2

    icon.alpha_composite(resized_logo, (offset_x, offset_y))
    return icon

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    out_dir = sys.argv[2] if len(sys.argv) > 2 else SCRIPT_DIR

    os.makedirs(out_dir, exist_ok=True)
    ide_path = os.path.join(out_dir, "antigravity-ide.png")
    app_path = os.path.join(out_dir, "antigravity-2.0.png")

    # Dark background for Antigravity IDE (#181825)
    ide_icon = make_icon(src, (24, 24, 37, 255))
    ide_icon.save(ide_path, "PNG")
    print(f"Generated Antigravity IDE icon: {ide_path}")

    # Light background for Antigravity 2.0 (#FFFFFF)
    app_icon = make_icon(src, (255, 255, 255, 255))
    app_icon.save(app_path, "PNG")
    print(f"Generated Antigravity 2.0 icon: {app_path}")

if __name__ == "__main__":
    main()
