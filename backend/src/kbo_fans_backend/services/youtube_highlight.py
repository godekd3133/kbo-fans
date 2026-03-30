from __future__ import annotations

import re
from typing import Any
from urllib.parse import quote

import requests


class YoutubeHighlightService:
    _SEARCH_URL = "https://www.youtube.com/results?search_query={query}"
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
        for index, video_id in enumerate(video_ids, start=1):
            video_url = f"https://www.youtube.com/watch?v={video_id}"
            videos.append(
                {
                    "videoId": video_id,
                    "title": f"{away_name} vs {home_name} 하이라이트 {index}",
                    "thumbnailUrl": f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
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
