from __future__ import annotations

import re
from typing import Any
from urllib.parse import quote

import requests

from kbo_fans_backend.utils.ttl_cache import TtlCache


class YoutubeHighlightService:
    _CACHE_TTL_SECONDS = 600
    _SEARCH_URL = "https://www.youtube.com/results?search_query={query}"
    _OEMBED_URL = "https://www.youtube.com/oembed?url={video_url}&format=json"
    _VIDEO_ID_PATTERN = re.compile(r'"videoId":"([A-Za-z0-9_-]{11})"')
    _NEGATIVE_KEYWORDS = (
        "직캠",
        "브이로그",
        "한줄평",
        "개막전",
        "응원",
        "직관",
        "예측",
        "분석",
        "요약",
        "사건",
        "결말",
        "먹방",
        "인터넷tv",
        "결과 요약",
    )

    def __init__(self, timeout_seconds: int = 10) -> None:
        self.timeout_seconds = timeout_seconds
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": "Mozilla/5.0"})
        self._cache: TtlCache[str, list[dict[str, Any]]] = TtlCache(
            self._CACHE_TTL_SECONDS
        )

    def fetch_highlights(
        self,
        *,
        game_id: str,
        away_name: str,
        home_name: str,
        limit: int = 6,
    ) -> list[dict[str, Any]]:
        cache_key = f"{game_id}:{away_name}:{home_name}:{limit}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        query = self._build_query(game_id=game_id, away_name=away_name, home_name=home_name)
        video_ids = self._search_video_ids(query, limit=limit)
        videos = []
        for video_id in video_ids:
            video_url = f"https://www.youtube.com/watch?v={video_id}"
            title = self._fetch_title(video_url) or f"{away_name} vs {home_name} 하이라이트"
            if not self._is_relevant_title(
                title=title,
                away_name=away_name,
                home_name=home_name,
                game_id=game_id,
            ):
                continue
            videos.append(
                {
                    "videoId": video_id,
                    "title": title,
                    "thumbnailUrl": f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg",
                    "videoUrl": video_url,
                    "source": "youtube_search",
                }
            )
            if len(videos) >= limit:
                break
        self._cache.set(cache_key, videos)
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

    def _fetch_title(self, video_url: str) -> str:
        response = self.session.get(
            self._OEMBED_URL.format(video_url=quote(video_url, safe="")),
            timeout=self.timeout_seconds,
        )
        if not response.ok:
            return ""
        return str(response.json().get("title") or "")

    def _is_relevant_title(
        self,
        *,
        title: str,
        away_name: str,
        home_name: str,
        game_id: str,
    ) -> bool:
        normalized = title.lower().replace(" ", "")
        away = away_name.lower().replace(" ", "")
        home = home_name.lower().replace(" ", "")
        month = str(int(game_id[4:6]))
        day = str(int(game_id[6:8]))
        full_date = f"{month}/{day}"
        compact_kor_date = f"{month}/{day}경기"
        compact_dot_date = f"{month}.{day}"
        spaced_kor_date = f"{month}월{day}일"

        if "하이라이트" not in title and "highlights" not in normalized:
            return False
        if away not in normalized or home not in normalized:
            return False
        if (
            full_date not in normalized
            and compact_kor_date not in normalized
            and compact_dot_date not in normalized
            and spaced_kor_date not in normalized
        ):
            return False
        if any(keyword in normalized for keyword in self._NEGATIVE_KEYWORDS):
            return False
        return True
