#!/usr/bin/env python3
"""Audit KBO team logo source candidates.

The script downloads official/high-resolution candidates discovered during
manual Google/Pinterest research, records dimensions, and compares them with
the currently bundled iOS TeamLogo assets.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import json
import re
import shutil
import struct
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional


TEAM_IDS = ("LG", "KT", "SK", "SS", "NC", "HH", "LT", "HT", "OB", "WO")


@dataclass(frozen=True)
class Candidate:
    team: str
    label: str
    url: str
    source: str
    priority: str
    fetch: bool = True
    notes: str = ""


OFFICIAL_CANDIDATES = (
    Candidate(
        "SK",
        "official_ssg_emblem_ai_zip",
        "https://ssg-new-prod.s3.ap-northeast-2.amazonaws.com/homepage/emblem/"
        "ssg_baseballclub_landers_emblem.zip",
        "official",
        "primary",
        notes="Official SSG BI page exposes the ZIP; page states personal use only.",
    ),
    Candidate(
        "KT",
        "official_kt_emblem_ai_zip",
        "https://www.ktwiz.co.kr/static/media/Emblem_ai.6d7ad674.zip",
        "official",
        "primary",
    ),
    Candidate(
        "KT",
        "official_kt_emblem_jpg",
        "https://www.ktwiz.co.kr/static/media/Emblem_jpg.692b85eb.jpg",
        "official",
        "primary",
    ),
    Candidate(
        "NC",
        "official_nc_emblem_zip",
        "https://ncdinos-common-bucket.s3.ap-northeast-2.amazonaws.com/v1/etc/vi/"
        "NC_Dinos_Emblem.zip",
        "official",
        "primary",
    ),
    Candidate(
        "HT",
        "official_kia_wordmark_jpg",
        "https://tigers.co.kr/img/download/bi/wordmark.jpg",
        "official",
        "primary",
    ),
    Candidate(
        "HT",
        "official_kia_initial_logo_jpg",
        "https://tigers.co.kr/img/download/bi/initial-logo.jpg",
        "official",
        "primary",
    ),
    Candidate(
        "HT",
        "official_kia_emblem_jpg",
        "https://tigers.co.kr/img/download/emblem/emblem.jpg",
        "official",
        "primary",
    ),
    Candidate(
        "SS",
        "official_samsung_emblem_ai_zip",
        "https://www.samsunglions.com/img/intro/emblem/ai_1_2.zip",
        "official",
        "primary",
    ),
    Candidate(
        "SS",
        "official_samsung_emblem_jpg_zip",
        "https://www.samsunglions.com/img/intro/emblem/jpg_1_2.zip",
        "official",
        "primary",
    ),
    Candidate(
        "WO",
        "official_kiwoom_bi_ai",
        "https://heroesbaseball.co.kr/heroes/bi-download.do?name=Kiwoom_heroes_BI.ai",
        "official",
        "primary",
    ),
    Candidate(
        "WO",
        "official_kiwoom_bi_pdf",
        "https://heroesbaseball.co.kr/heroes/bi-download.do?name=Kiwoom_heroes_BI.pdf",
        "official",
        "primary",
    ),
    Candidate(
        "OB",
        "official_doosan_meta_svg",
        "https://www.doosanbears.com/images/meta_img.svg",
        "official",
        "primary",
        notes="Large official meta/social SVG. Requires crop check before bundling.",
    ),
    Candidate(
        "LG",
        "official_lg_header_logo_png",
        "https://www.lgtwins.com/images/common/logo.png",
        "official",
        "secondary",
    ),
    Candidate(
        "HH",
        "official_hanwha_main_ci_png",
        "https://www.hanwhaeagles.co.kr/images/pages/eagles/ci_logo_main.png",
        "official",
        "secondary",
    ),
    Candidate(
        "HH",
        "official_hanwha_sub_ci_png",
        "https://www.hanwhaeagles.co.kr/images/pages/eagles/ci_logo_sub.png",
        "official",
        "secondary",
    ),
)


REFERENCE_CANDIDATES = (
    Candidate(
        "ALL",
        "pinterest_foxcg_kbo_logos_pin",
        "https://cz.pinterest.com/pin/151503974963218866/",
        "pinterest",
        "discovery",
        fetch=False,
        notes="Pinterest discovery route; do not bundle from Pinterest directly.",
    ),
    Candidate(
        "ALL",
        "seeklogo_kbo_vector_index",
        "https://seeklogo.com/free-vector-logos/kbo",
        "third_party_vector_index",
        "reference_only",
        fetch=False,
        notes="Useful fallback discovery for AI/SVG/PNG; requires rights/source review.",
    ),
    Candidate(
        "LT",
        "wikimedia_lotte_recent_png",
        "https://ko.m.wikipedia.org/wiki/파일:롯데자이언츠_최신_엠블럼.png",
        "third_party_reference",
        "reference_only",
        fetch=False,
    ),
    Candidate(
        "HH",
        "hanwha_2025_bi_news",
        "https://www.hanwhaeagles.co.kr/FA/CN/PCFACN02.do?id=1699",
        "official_news",
        "reference_only",
        fetch=False,
        notes="Confirms 2025 BI but not a high-resolution downloadable asset.",
    ),
)


def kbo_cdn_candidates() -> Iterable[Candidate]:
    for team in TEAM_IDS:
        for suffix, label in (("", "base"), ("_L", "large")):
            yield Candidate(
                team,
                f"kbo_cdn_{label}_{team}",
                "https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/emblem/regular/"
                f"fixed/emblem_{team}{suffix}.png",
                "kbo_cdn",
                "fallback",
                notes="Small but consistent official CDN fallback.",
            )


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("_")[:120]


def fetch_bytes(url: str, timeout: int) -> tuple[Optional[bytes], Optional[str]]:
    request = urllib.request.Request(url, headers={"User-Agent": "kbo-fans-logo-audit/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read(), None
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        if not shutil.which("curl"):
            return None, str(exc)
        result = subprocess.run(
            ["curl", "-L", "-fsS", "--max-time", str(timeout), url],
            check=False,
            capture_output=True,
        )
        if result.returncode == 0:
            return result.stdout, None
        fallback_error = result.stderr.decode("utf-8", errors="replace").strip()
        return None, f"{exc}; curl fallback: {fallback_error}"


def detect_kind(data: bytes, path: Optional[Path] = None) -> str:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data.startswith(b"\xff\xd8"):
        return "jpg"
    if data.startswith(b"PK\x03\x04"):
        return "zip"
    if data.startswith(b"%PDF"):
        return "pdf_or_ai"
    if data[:512].lstrip().startswith(b"<svg") or b"<svg" in data[:512].lower():
        return "svg"
    if path and shutil.which("file"):
        result = subprocess.run(
            ["file", "-b", str(path)],
            check=False,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()
    return "unknown"


def png_dimensions(data: bytes) -> Optional[tuple[int, int]]:
    if not data.startswith(b"\x89PNG\r\n\x1a\n") or len(data) < 24:
        return None
    return struct.unpack(">II", data[16:24])


def jpg_dimensions(data: bytes) -> Optional[tuple[int, int]]:
    if not data.startswith(b"\xff\xd8"):
        return None
    index = 2
    while index + 9 < len(data):
        if data[index] != 0xFF:
            index += 1
            continue
        marker = data[index + 1]
        index += 2
        if marker in (0xD8, 0xD9):
            continue
        if index + 2 > len(data):
            return None
        segment_length = struct.unpack(">H", data[index : index + 2])[0]
        if segment_length < 2 or index + segment_length > len(data):
            return None
        if marker in range(0xC0, 0xC4) or marker in range(0xC5, 0xC8) or marker in range(0xC9, 0xCC) or marker in range(0xCD, 0xD0):
            if index + 7 <= len(data):
                height = struct.unpack(">H", data[index + 3 : index + 5])[0]
                width = struct.unpack(">H", data[index + 5 : index + 7])[0]
                return width, height
        index += segment_length
    return None


def svg_dimensions(data: bytes) -> Optional[tuple[int, int]]:
    text = data[:4096].decode("utf-8", errors="ignore")
    match = re.search(r"viewBox=[\"']\s*[-0-9.]+\s+[-0-9.]+\s+([0-9.]+)\s+([0-9.]+)", text)
    if match:
        return int(float(match.group(1))), int(float(match.group(2)))
    width = re.search(r"\bwidth=[\"']([0-9.]+)", text)
    height = re.search(r"\bheight=[\"']([0-9.]+)", text)
    if width and height:
        return int(float(width.group(1))), int(float(height.group(1)))
    return None


def image_dimensions(kind: str, data: bytes) -> Optional[tuple[int, int]]:
    if kind == "png":
        return png_dimensions(data)
    if kind == "jpg":
        return jpg_dimensions(data)
    if kind == "svg":
        return svg_dimensions(data)
    return None


def inspect_zip(data: bytes) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            entry = {
                "name": info.filename,
                "size": info.file_size,
                "kind": "",
                "width": "",
                "height": "",
            }
            lower = info.filename.lower()
            if lower.endswith((".png", ".jpg", ".jpeg", ".svg")):
                payload = archive.read(info)
                kind = detect_kind(payload)
                dims = image_dimensions(kind, payload)
                entry["kind"] = kind
                if dims:
                    entry["width"], entry["height"] = dims
            elif lower.endswith((".ai", ".pdf")):
                entry["kind"] = "pdf_or_ai"
            entries.append(entry)
    return entries

def current_ios_logo_dimensions(repo: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    assets_dir = repo / "app/ios/Runner/Assets.xcassets"
    for team in TEAM_IDS:
        logo_path = assets_dir / f"TeamLogo_{team}.imageset/logo.png"
        row = {"team": team, "path": str(logo_path), "width": "", "height": "", "exists": logo_path.exists()}
        if logo_path.exists():
            data = logo_path.read_bytes()
            dims = png_dimensions(data) or jpg_dimensions(data)
            if dims:
                row["width"], row["height"] = dims
        rows.append(row)
    return rows


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def build_markdown(rows: list[dict[str, object]], ios_rows: list[dict[str, object]]) -> str:
    lines = [
        "# KBO Team Logo Source Audit Run",
        "",
        f"Generated: {dt.datetime.now().isoformat(timespec='seconds')}",
        "",
        "## Current iOS Bundle",
        "",
        "| Team | Width | Height | Exists |",
        "| --- | ---: | ---: | --- |",
    ]
    for row in ios_rows:
        lines.append(f"| {row['team']} | {row['width']} | {row['height']} | {row['exists']} |")

    lines.extend(
        [
            "",
            "## Candidate Summary",
            "",
            "| Team | Label | Source | Priority | Status | Kind | Size | Dimensions | Notes |",
            "| --- | --- | --- | --- | --- | --- | ---: | --- | --- |",
        ]
    )
    for row in rows:
        dims = ""
        if row.get("width") and row.get("height"):
            dims = f"{row['width']}x{row['height']}"
        lines.append(
            "| {team} | {label} | {source} | {priority} | {status} | {kind} | {bytes} | {dims} | {notes} |".format(
                team=row.get("team", ""),
                label=row.get("label", ""),
                source=row.get("source", ""),
                priority=row.get("priority", ""),
                status=row.get("status", ""),
                kind=row.get("kind", ""),
                bytes=row.get("bytes", ""),
                dims=dims,
                notes=str(row.get("notes", "")).replace("|", "/"),
            )
        )
    return "\n".join(lines) + "\n"


def run(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve()
    output = Path(args.output).resolve()
    sources_dir = output / "sources"
    output.mkdir(parents=True, exist_ok=True)
    sources_dir.mkdir(parents=True, exist_ok=True)

    candidates = list(OFFICIAL_CANDIDATES) + list(kbo_cdn_candidates()) + list(REFERENCE_CANDIDATES)
    rows: list[dict[str, object]] = []
    zip_rows: list[dict[str, object]] = []

    for candidate in candidates:
        row: dict[str, object] = {
            "team": candidate.team,
            "label": candidate.label,
            "source": candidate.source,
            "priority": candidate.priority,
            "url": candidate.url,
            "status": "reference_only" if not candidate.fetch else "",
            "kind": "",
            "bytes": "",
            "width": "",
            "height": "",
            "path": "",
            "error": "",
            "notes": candidate.notes,
        }
        if not candidate.fetch or args.metadata_only:
            if args.metadata_only and candidate.fetch:
                row["status"] = "metadata_only"
            rows.append(row)
            continue

        data, error = fetch_bytes(candidate.url, args.timeout)
        if error or data is None:
            row["status"] = "error"
            row["error"] = error or "unknown"
            rows.append(row)
            continue

        file_path = sources_dir / candidate.team / f"{safe_name(candidate.label)}"
        file_path.parent.mkdir(parents=True, exist_ok=True)
        suffix = Path(urllib.parse.urlparse(candidate.url).path).suffix
        if suffix and not file_path.name.endswith(suffix):
            file_path = file_path.with_suffix(suffix)
        file_path.write_bytes(data)

        kind = detect_kind(data, file_path)
        dims = image_dimensions(kind, data)
        row.update(
            {
                "status": "ok",
                "kind": kind,
                "bytes": len(data),
                "path": str(file_path),
            }
        )
        if dims:
            row["width"], row["height"] = dims
        if kind == "zip":
            for entry in inspect_zip(data):
                zip_rows.append(
                    {
                        "team": candidate.team,
                        "label": candidate.label,
                        "entry": entry["name"],
                        "kind": entry["kind"],
                        "bytes": entry["size"],
                        "width": entry["width"],
                        "height": entry["height"],
                    }
                )
        rows.append(row)

    ios_rows = current_ios_logo_dimensions(repo)

    write_csv(
        output / "candidate-summary.csv",
        rows,
        ["team", "label", "source", "priority", "url", "status", "kind", "bytes", "width", "height", "path", "error", "notes"],
    )
    write_csv(
        output / "zip-entries.csv",
        zip_rows,
        ["team", "label", "entry", "kind", "bytes", "width", "height"],
    )
    write_csv(
        output / "current-ios-team-logo-sizes.csv",
        ios_rows,
        ["team", "path", "width", "height", "exists"],
    )
    (output / "candidate-summary.json").write_text(
        json.dumps({"candidates": rows, "zipEntries": zip_rows, "currentIos": ios_rows}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (output / "README.md").write_text(build_markdown(rows, ios_rows), encoding="utf-8")

    print(f"Wrote audit to {output}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="Repository root")
    parser.add_argument(
        "--output",
        default="artifacts/team-logo-source-audit",
        help="Output folder for downloaded candidates and reports",
    )
    parser.add_argument("--timeout", type=int, default=20, help="Per-request timeout in seconds")
    parser.add_argument(
        "--metadata-only",
        action="store_true",
        help="Write candidate/reference metadata without downloading files",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(run(parse_args(sys.argv[1:])))
