from __future__ import annotations

import re
from html import unescape
from typing import Optional


TAG_RE = re.compile(r"<[^>]+>")


def strip_tags(value: str) -> str:
    return re.sub(TAG_RE, "", unescape(value or "")).strip()


def extract_href(value: str) -> Optional[str]:
    match = re.search(r"href=['\"]([^'\"]+)['\"]", value or "")
    return match.group(1) if match else None


def extract_game_id(value: str) -> Optional[str]:
    match = re.search(r"gameId=([A-Z0-9]+)", value or "")
    return match.group(1) if match else None
