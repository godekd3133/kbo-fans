#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
BRANDING_DIR = ROOT / "app/assets/branding"
BASE_ICON = BRANDING_DIR / "app_icon_variant_sport.png"


def build_tighter_icon(scale: float = 1.18) -> Image.Image:
    base = Image.open(BASE_ICON).convert("RGBA")

    content_mask = Image.new("L", base.size, 0)
    src = base.load()
    mask_px = content_mask.load()
    for y in range(base.height):
        for x in range(base.width):
            r, g, b, a = src[x, y]
            # Keep bright foreground elements: baseball, logotype, highlights.
            if a and (r + g + b) / 3 >= 70:
                mask_px[x, y] = 255

    content_bbox = content_mask.getbbox()
    if content_bbox is None:
        return base

    foreground = Image.new("RGBA", base.size, (0, 0, 0, 0))
    foreground.paste(base, (0, 0), content_mask)

    scaled_foreground = foreground.resize(
        (
            int(base.width * scale),
            int(base.height * scale),
        ),
        Image.Resampling.LANCZOS,
    )

    background = base.copy()
    background.paste((0, 0, 0, 0), (0, 0), content_mask)

    canvas = Image.new("RGBA", base.size, (0, 0, 0, 0))
    canvas.alpha_composite(background)
    offset = (
        (base.width - scaled_foreground.width) // 2,
        (base.height - scaled_foreground.height) // 2,
    )
    canvas.alpha_composite(scaled_foreground, offset)
    return canvas


def write_png(path: Path, size: int, source: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    source.resize((size, size), Image.Resampling.LANCZOS).save(path, format="PNG")


def main() -> None:
    ios_dir = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    android_dir = ROOT / "app/android/app/src/main/res"
    web_dir = ROOT / "app/web/icons"

    icon = build_tighter_icon()

    ios_icons = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    android_icons = {
        "mipmap-mdpi/ic_launcher.png": 48,
        "mipmap-hdpi/ic_launcher.png": 72,
        "mipmap-xhdpi/ic_launcher.png": 96,
        "mipmap-xxhdpi/ic_launcher.png": 144,
        "mipmap-xxxhdpi/ic_launcher.png": 192,
    }
    web_icons = {
        "Icon-192.png": 192,
        "Icon-512.png": 512,
        "Icon-maskable-192.png": 192,
        "Icon-maskable-512.png": 512,
    }

    for name, size in ios_icons.items():
        write_png(ios_dir / name, size, icon)

    for rel_path, size in android_icons.items():
        write_png(android_dir / rel_path, size, icon)

    for name, size in web_icons.items():
        write_png(web_dir / name, size, icon)

    write_png(ROOT / "app/web/favicon.png", 32, icon)
    write_png(BRANDING_DIR / "app_icon_source_1024.png", 1024, icon)


if __name__ == "__main__":
    main()
