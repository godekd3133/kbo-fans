#!/usr/bin/env python3

from __future__ import annotations

import math
import os
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def clamp(value: float) -> int:
    return max(0, min(255, int(round(value))))


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        clamp(a[0] + (b[0] - a[0]) * t),
        clamp(a[1] + (b[1] - a[1]) * t),
        clamp(a[2] + (b[2] - a[2]) * t),
    )


def draw_icon(size: int) -> bytes:
    bg_dark = (9, 11, 17)
    bg_mid = (18, 20, 28)
    red = (247, 78, 68)
    blue = (61, 123, 255)
    cream = (250, 247, 239)
    stitch = (195, 44, 44)
    stitch_blue = (46, 92, 220)
    seam_shadow = (160, 160, 170)

    cx = size / 2
    cy = size / 2
    radius = size * 0.34
    shadow_offset = size * 0.04

    rows: list[bytes] = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            split = (x - cx) + (y - cy) * 0.38
            if split < 0:
                t = max(0.0, min(1.0, (x + y * 0.45) / (size * 0.9)))
                r, g, b = mix(bg_dark, red, t * 0.58)
            else:
                t = max(0.0, min(1.0, ((size - x) + (size - y) * 0.45) / (size * 0.9)))
                r, g, b = mix(bg_dark, blue, t * 0.58)

            center_glow = max(0.0, 1.0 - math.hypot((x - cx) / size, (y - cy) / size) / 0.55)
            r, g, b = mix((r, g, b), bg_mid, center_glow * 0.18)

            glow_red = max(0.0, 1.0 - math.hypot((x - size * 0.22) / size, (y - size * 0.22) / size) / 0.32)
            glow_blue = max(0.0, 1.0 - math.hypot((x - size * 0.80) / size, (y - size * 0.78) / size) / 0.34)
            r = clamp(r + glow_red * 22)
            g = clamp(g + glow_red * 4 + glow_blue * 6)
            b = clamp(b + glow_blue * 26)

            # baseball drop shadow
            shadow_dx = x - cx
            shadow_dy = y - (cy + shadow_offset)
            shadow_dist = math.hypot(shadow_dx, shadow_dy)
            if shadow_dist < radius * 1.03:
                alpha = max(0.0, 1.0 - shadow_dist / (radius * 1.03)) * 0.18
                r = clamp(r * (1 - alpha))
                g = clamp(g * (1 - alpha))
                b = clamp(b * (1 - alpha))

            dx = x - cx
            dy = y - cy
            dist = math.hypot(dx, dy)

            if dist <= radius:
                ball_t = max(0.0, min(1.0, (dy + radius) / (radius * 2)))
                br, bgc, bb = mix((255, 252, 247), cream, ball_t * 0.9)
                highlight = max(0.0, 1.0 - math.hypot((x - cx + radius * 0.28), (y - cy + radius * 0.34)) / (radius * 0.9))
                shade = max(0.0, 1.0 - math.hypot((x - cx - radius * 0.36), (y - cy - radius * 0.22)) / (radius * 1.1))
                br = clamp(br + highlight * 18 - shade * 28)
                bgc = clamp(bgc + highlight * 16 - shade * 25)
                bb = clamp(bb + highlight * 12 - shade * 20)
                r, g, b = br, bgc, bb

                rim = radius - dist
                if rim < size * 0.015:
                    edge_alpha = max(0.0, 1.0 - rim / (size * 0.015))
                    r, g, b = mix((r, g, b), seam_shadow, edge_alpha * 0.45)

                # left seam
                left_curve = ((dx + radius * 0.42) / (radius * 0.46)) ** 2 + (dy / (radius * 1.08)) ** 2
                left_dist = abs(left_curve - 1.0)
                if left_dist < 0.028 and dx < 0:
                    alpha = max(0.0, 1.0 - left_dist / 0.028)
                    r, g, b = mix((r, g, b), stitch, alpha)
                # right seam
                right_curve = ((dx - radius * 0.42) / (radius * 0.46)) ** 2 + (dy / (radius * 1.08)) ** 2
                right_dist = abs(right_curve - 1.0)
                if right_dist < 0.028 and dx > 0:
                    alpha = max(0.0, 1.0 - right_dist / 0.028)
                    r, g, b = mix((r, g, b), stitch_blue, alpha)

                # stitches
                stitch_r = size * 0.012
                for i in range(-4, 5):
                    py = cy + i * radius * 0.18
                    lx = cx - radius * 0.46 + (i * i) * radius * 0.013
                    rx = cx + radius * 0.46 - (i * i) * radius * 0.013
                    ld = math.hypot(x - lx, y - py)
                    rd = math.hypot(x - rx, y - py)
                    if ld < stitch_r:
                        alpha = max(0.0, 1.0 - ld / stitch_r)
                        r, g, b = mix((r, g, b), stitch, alpha)
                    if rd < stitch_r:
                        alpha = max(0.0, 1.0 - rd / stitch_r)
                        r, g, b = mix((r, g, b), stitch_blue, alpha)

                # centered KF monogram
                mono = (22, 26, 36)
                mono_glow = (255, 255, 255)
                stroke = size * 0.014

                # K
                k_stem = abs(dx + radius * 0.12) < stroke and abs(dy) < radius * 0.28
                k_diag_top = abs((dy + dx * 0.95) + radius * 0.02) < stroke and dx > -radius * 0.10 and dx < radius * 0.08
                k_diag_bottom = abs((dy - dx * 0.95) - radius * 0.02) < stroke and dx > -radius * 0.10 and dx < radius * 0.08

                # F
                f_stem = abs(dx - radius * 0.08) < stroke and abs(dy) < radius * 0.28
                f_top = abs(dy + radius * 0.18) < stroke and dx > radius * 0.02 and dx < radius * 0.19
                f_mid = abs(dy) < stroke and dx > radius * 0.02 and dx < radius * 0.15

                if k_stem or k_diag_top or k_diag_bottom or f_stem or f_top or f_mid:
                    center_dist = math.hypot(dx / radius, dy / radius)
                    glow_alpha = max(0.0, 1.0 - center_dist / 0.72) * 0.35
                    r, g, b = mix((r, g, b), mono_glow, glow_alpha)
                    r, g, b = mix((r, g, b), mono, 0.88)

            row.extend((r, g, b, 255))
        rows.append(b"\x00" + bytes(row))

    raw = b"".join(rows)
    compressed = zlib.compress(raw, 9)
    return png_chunk(b"IHDR", struct.pack("!2I5B", size, size, 8, 6, 0, 0, 0)) + png_chunk(b"IDAT", compressed) + png_chunk(b"IEND", b"")


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    return (
        struct.pack("!I", len(data))
        + chunk_type
        + data
        + struct.pack("!I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    )


def write_png(path: Path, size: int) -> None:
    png = b"\x89PNG\r\n\x1a\n" + draw_icon(size)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def main() -> None:
    ios_dir = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    android_dir = ROOT / "app/android/app/src/main/res"

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

    for name, size in ios_icons.items():
        write_png(ios_dir / name, size)

    for rel_path, size in android_icons.items():
        write_png(android_dir / rel_path, size)

    source_dir = ROOT / "app/assets/branding"
    write_png(source_dir / "app_icon_source_1024.png", 1024)


if __name__ == "__main__":
    main()
