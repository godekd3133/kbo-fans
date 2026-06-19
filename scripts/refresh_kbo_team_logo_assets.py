#!/usr/bin/env python3
"""Refresh bundled KBO team logo reference assets.

The Flutter app can load KBO CDN logos at runtime, but native widgets and
small repeated Flutter surfaces need stable local transparent PNGs.
"""

from __future__ import annotations

import argparse
import urllib.request
from pathlib import Path
from typing import Dict

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_DIR = ROOT / "app/assets/visuals/reference_team_logos"
IOS_ASSET_ROOT = ROOT / "app/ios/Runner/Assets.xcassets"
TEAM_IDS = ("LG", "KT", "SK", "SS", "NC", "HH", "LT", "HT", "OB", "WO")
CDN_BASE = "https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/emblem/regular/fixed"

# Lotte's _L CDN image is opaque white; keep the transparent base emblem there.
REFERENCE_URLS: Dict[str, str] = {
    "HH": f"{CDN_BASE}/emblem_HH_L.png",
    "LT": f"{CDN_BASE}/emblem_LT.png",
    "WO": f"{CDN_BASE}/emblem_WO_L.png",
}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "Referer": "https://www.koreabaseball.com/",
            "User-Agent": "kbo-fans-logo-refresh/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read()


def ensure_reference_assets(overwrite: bool) -> None:
    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)
    for team_id in TEAM_IDS:
        destination = REFERENCE_DIR / f"{team_id}.png"
        if destination.exists() and not overwrite:
            continue
        url = REFERENCE_URLS.get(team_id, f"{CDN_BASE}/emblem_{team_id}.png")
        destination.write_bytes(fetch(url))
        Image.open(destination).convert("RGBA").save(destination)


def normalized_logo(source_path: Path, size: int = 256, max_content: int = 214) -> Image.Image:
    source = Image.open(source_path).convert("RGBA")
    alpha_bbox = source.getchannel("A").getbbox()
    if alpha_bbox is not None:
        source = source.crop(alpha_bbox)

    scale = min(max_content / source.width, max_content / source.height)
    resized = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = ((size - resized.width) // 2, (size - resized.height) // 2)
    canvas.alpha_composite(resized, offset)
    return canvas


def write_ios_team_assets() -> None:
    for team_id in TEAM_IDS:
        source = REFERENCE_DIR / f"{team_id}.png"
        asset_dir = IOS_ASSET_ROOT / f"TeamLogo_{team_id}.imageset"
        asset_dir.mkdir(parents=True, exist_ok=True)
        normalized_logo(source).save(asset_dir / "logo.png", format="PNG")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--overwrite-reference",
        action="store_true",
        help="Replace existing Flutter reference PNGs with KBO CDN assets.",
    )
    args = parser.parse_args()

    ensure_reference_assets(overwrite=args.overwrite_reference)
    write_ios_team_assets()


if __name__ == "__main__":
    main()
