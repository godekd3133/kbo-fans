from __future__ import annotations

import re
from typing import Any, Optional
from urllib.parse import quote

import requests


class YoutubeHighlightService:
    _SEARCH_URL = "https://www.youtube.com/results?search_query={query}"
    _OEMBED_URL = "https://www.youtube.com/oembed?url={video_url}&format=json"
    _VIDEO_ID_PATTERN = re.compile(r'"videoId":"([A-Za-z0-9_-]{11})"')

    def __init__(self, timeout_seconds: int = 10) -> None:
        self.timeout_seconds = timeout_seconds
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": "Mozilla/5.0"})

    def fetch_highlights(
        self,
        *,
        game_id: str,
        away_name: str,
        home_name: str,
        limit: int = 6,
    ) -> list[dict[str, Any]]:
        query = self._build_query(game_id=game_id, away_name=away_name, home_name=home_name)
        video_ids = self._search_video_ids(query, limit=limit)
        videos = []
        for video_id in video_ids:
            video_url = f"https://www.youtube.com/watch?v={video_id}"
            oembed = self._fetch_oembed(video_url)
            videos.append(
                {
                    "videoId": video_id,
                    "title": (oembed or {}).get("title") or f"{away_name} vs {home_name} 하이라이트",
                    "thumbnailUrl": (oembed or {}).get("thumbnail_url")
                    or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
                    "videoUrl": video_url,
                    "source": "youtube_search",
                }
            )
        return videos

    def _build_query(self, *, game_id: str, away_name: str, home_name: str) -> str:
        month = game_id[4:6]
        day = game_id[6:8]
        return f"{month}월 {day}일 {away_name} {home_name} 하이라이트"

    def _search_video_ids(self, query: str, *, limit: int) -> list[str]:
        response = self.session.get(
            self._SEARCH_URL.format(query=quote(query)),
            timeout=self.timeout_seconds,
        )
        response.raise_for_status()

        seen = []
        for match in self._VIDEO_ID_PATTERN.finditer(response.text):
            video_id = match.group(1)
            if video_id in seen:
                continue
            seen.append(video_id)
            if len(seen) >= limit:
                break
        return seen

    def _fetch_oembed(self, video_url: str) -> Optional[dict[str, Any]]:
        response = self.session.get(
            self._OEMBED_URL.format(video_url=quote(video_url, safe="")),
            timeout=self.timeout_seconds,
        )
        if not response.ok:
            return None
        return response.json()
