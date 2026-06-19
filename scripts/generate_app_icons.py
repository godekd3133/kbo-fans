#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "app"
BRANDING_DIR = APP_DIR / "assets/branding"
VISUALS_DIR = APP_DIR / "assets/visuals"
FONT_PATH = APP_DIR / "assets/fonts/PretendardVariable.ttf"


def load_font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_PATH), size=size)


def write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def resize_png(path: Path, size: int, source: Image.Image) -> None:
    write_png(path, source.resize((size, size), Image.Resampling.LANCZOS))


def lerp(start: int, end: int, t: float) -> int:
    return round(start + (end - start) * t)


def build_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    pixels = image.load()
    top = (7, 12, 21)
    bottom = (17, 24, 39)
    for y in range(size):
        t = y / max(1, size - 1)
        color = tuple(lerp(top[i], bottom[i], t) for i in range(3)) + (255,)
        for x in range(size):
            pixels[x, y] = color

    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    scale = size / 1024
    draw.polygon(
        [
            (130 * scale, 820 * scale),
            (814 * scale, 136 * scale),
            (916 * scale, 136 * scale),
            (232 * scale, 820 * scale),
        ],
        fill=(46, 92, 170, 72),
    )
    draw.polygon(
        [
            (130 * scale, 820 * scale),
            (462 * scale, 488 * scale),
            (532 * scale, 488 * scale),
            (232 * scale, 820 * scale),
        ],
        fill=(231, 57, 77, 58),
    )
    return Image.alpha_composite(image, overlay)


def draw_baseball(draw: ImageDraw.ImageDraw, center: tuple[int, int], radius: int) -> None:
    cx, cy = center
    bbox = (cx - radius, cy - radius, cx + radius, cy + radius)
    shadow = Image.new("RGBA", draw.im.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse(
        (bbox[0] + 12, bbox[1] + 22, bbox[2] + 12, bbox[3] + 22),
        fill=(0, 0, 0, 72),
    )
    draw.bitmap((0, 0), shadow)

    draw.ellipse(bbox, fill=(250, 248, 242, 255))
    draw.arc(
        (cx - radius * 0.94, cy - radius * 0.98, cx - radius * 0.1, cy + radius * 0.98),
        104,
        256,
        fill=(216, 58, 72, 255),
        width=max(7, radius // 12),
    )
    draw.arc(
        (cx + radius * 0.1, cy - radius * 0.98, cx + radius * 0.94, cy + radius * 0.98),
        -76,
        76,
        fill=(48, 108, 245, 255),
        width=max(7, radius // 12),
    )

    red_stitches = [
        ((-0.58, -0.48), (-0.41, -0.34)),
        ((-0.66, -0.21), (-0.46, -0.07)),
        ((-0.69, 0.08), (-0.47, 0.23)),
        ((-0.65, 0.36), (-0.45, 0.51)),
        ((-0.54, 0.62), (-0.36, 0.78)),
    ]
    blue_stitches = [((-a[0], a[1]), (-b[0], b[1])) for a, b in red_stitches]
    for stitches, color in ((red_stitches, (216, 58, 72, 255)), (blue_stitches, (48, 108, 245, 255))):
        for start, end in stitches:
            draw.line(
                (
                    cx + start[0] * radius,
                    cy + start[1] * radius,
                    cx + end[0] * radius,
                    cy + end[1] * radius,
                ),
                fill=color,
                width=max(6, radius // 16),
                joint="curve",
            )


def text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, tracking: int) -> tuple[int, int]:
    width = 0
    height = 0
    for index, char in enumerate(text):
        bbox = draw.textbbox((0, 0), char, font=font, stroke_width=0)
        width += bbox[2] - bbox[0]
        height = max(height, bbox[3] - bbox[1])
        if index < len(text) - 1:
            width += tracking
    return width, height


def draw_tracked_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    center_x: int,
    top: int,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    tracking: int,
    stroke_width: int = 0,
    stroke_fill: tuple[int, int, int, int] = (0, 0, 0, 0),
) -> None:
    width, _ = text_size(draw, text, font, tracking)
    x = center_x - width / 2
    for index, char in enumerate(text):
        draw.text(
            (x, top),
            char,
            font=font,
            fill=fill,
            stroke_width=stroke_width,
            stroke_fill=stroke_fill,
        )
        char_width = draw.textlength(char, font=font)
        x += char_width + (tracking if index < len(text) - 1 else 0)


def build_icon(size: int = 1024) -> Image.Image:
    icon = build_background(size)
    draw = ImageDraw.Draw(icon)
    scale = size / 1024
    draw_baseball(draw, (round(512 * scale), round(356 * scale)), round(176 * scale))

    kbo_font = load_font(round(170 * scale))
    fans_font = load_font(round(86 * scale))
    draw_tracked_text(
        draw,
        "KBO",
        round(512 * scale),
        round(610 * scale),
        kbo_font,
        (255, 255, 255, 255),
        round(6 * scale),
        stroke_width=round(2 * scale),
        stroke_fill=(4, 8, 14, 210),
    )
    draw_tracked_text(
        draw,
        "FANS",
        round(512 * scale),
        round(772 * scale),
        fans_font,
        (226, 232, 240, 255),
        round(10 * scale),
        stroke_width=round(1 * scale),
        stroke_fill=(4, 8, 14, 180),
    )
    opaque = Image.new("RGBA", icon.size, (7, 12, 21, 255))
    opaque.alpha_composite(icon)
    return opaque


def build_header_logo() -> Image.Image:
    image = Image.new("RGBA", (292, 110), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw_baseball(draw, (42, 54), 30)
    kbo_font = load_font(44)
    fans_font = load_font(28)
    draw.text((86, 20), "KBO", font=kbo_font, fill=(255, 255, 255, 255))
    draw.text((88, 64), "FANS", font=fans_font, fill=(226, 232, 240, 255))
    draw.line((84, 58, 226, 58), fill=(255, 68, 68, 210), width=3)
    draw.line((226, 58, 262, 58), fill=(41, 121, 255, 210), width=3)
    return image


def write_ios_icons(icon: Image.Image) -> None:
    ios_dir = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
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
    for name, size in ios_icons.items():
        resize_png(ios_dir / name, size, icon)


def write_android_icons(icon: Image.Image) -> None:
    android_dir = ROOT / "app/android/app/src/main/res"
    android_icons = {
        "mipmap-mdpi/ic_launcher.png": 48,
        "mipmap-hdpi/ic_launcher.png": 72,
        "mipmap-xhdpi/ic_launcher.png": 96,
        "mipmap-xxhdpi/ic_launcher.png": 144,
        "mipmap-xxxhdpi/ic_launcher.png": 192,
    }
    launch_icons = {
        "mipmap-mdpi/launch_logo.png": 96,
        "mipmap-hdpi/launch_logo.png": 144,
        "mipmap-xhdpi/launch_logo.png": 192,
        "mipmap-xxhdpi/launch_logo.png": 288,
        "mipmap-xxxhdpi/launch_logo.png": 384,
    }
    for rel_path, size in android_icons.items():
        resize_png(android_dir / rel_path, size, icon)
    for rel_path, size in launch_icons.items():
        resize_png(android_dir / rel_path, size, icon)


def write_web_icons(icon: Image.Image) -> None:
    web_dir = ROOT / "app/web/icons"
    web_icons = {
        "Icon-192.png": 192,
        "Icon-512.png": 512,
        "Icon-maskable-192.png": 192,
        "Icon-maskable-512.png": 512,
    }
    for name, size in web_icons.items():
        resize_png(web_dir / name, size, icon)
    resize_png(ROOT / "app/web/favicon.png", 32, icon)


def write_launch_images(icon: Image.Image) -> None:
    launch_dir = ROOT / "app/ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for name, size in {
        "LaunchImage.png": 128,
        "LaunchImage@2x.png": 256,
        "LaunchImage@3x.png": 384,
    }.items():
        resize_png(launch_dir / name, size, icon)


def main() -> None:
    icon = build_icon()
    write_png(BRANDING_DIR / "app_icon_source_1024.png", icon)
    write_png(BRANDING_DIR / "app_icon_variant_sport.png", icon)
    write_png(VISUALS_DIR / "kbo_header_logo.png", build_header_logo())
    write_ios_icons(icon)
    write_android_icons(icon)
    write_web_icons(icon)
    write_launch_images(icon)


if __name__ == "__main__":
    main()
