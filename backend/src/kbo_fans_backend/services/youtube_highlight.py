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
    _TEAM_ALIASES = (
        ("LG 트윈스", "LG", "엘지", "트윈스"),
        ("KT 위즈", "KT", "케이티", "위즈"),
        ("SSG 랜더스", "SSG", "SK", "랜더스"),
        ("삼성 라이온즈", "삼성", "라이온즈"),
        ("NC 다이노스", "NC", "다이노스"),
        ("한화 이글스", "한화", "이글스"),
        ("롯데 자이언츠", "롯데", "자이언츠"),
        ("KIA 타이거즈", "KIA", "기아", "타이거즈"),
        ("두산 베어스", "두산", "베어스"),
        ("키움 히어로즈", "키움", "히어로즈"),
    )
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
        self._cache: TtlCache[str, list[dict[str, Any]]] = TtlCache(self._CACHE_TTL_SECONDS)

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

    def build_search_fallback(
        self,
        *,
        game_id: str,
        away_name: str,
        home_name: str,
    ) -> dict[str, Any]:
        query = self._build_query(
            game_id=game_id,
            away_name=away_name,
            home_name=home_name,
        )
        return {
            "videoId": "",
            "title": f"{away_name} vs {home_name} 하이라이트 검색",
            "thumbnailUrl": "",
            "videoUrl": self._SEARCH_URL.format(query=quote(query)),
            "source": "youtube_search_fallback",
        }

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
        normalized = self._normalize_for_match(title)
        month = str(int(game_id[4:6]))
        day = str(int(game_id[6:8]))
        full_date = f"{month}/{day}"
        compact_kor_date = f"{month}/{day}경기"
        compact_dot_date = f"{month}.{day}"
        spaced_kor_date = f"{month}월{day}일"

        if "하이라이트" not in title and "highlights" not in normalized:
            return False
        if not self._title_mentions_team(normalized, away_name):
            return False
        if not self._title_mentions_team(normalized, home_name):
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

    def _title_mentions_team(self, normalized_title: str, team_name: str) -> bool:
        return any(
            alias and alias in normalized_title for alias in self._team_aliases_for_name(team_name)
        )

    @classmethod
    def _team_aliases_for_name(cls, team_name: str) -> tuple[str, ...]:
        normalized_name = cls._normalize_for_match(team_name)
        aliases = {normalized_name}
        for alias_group in cls._TEAM_ALIASES:
            normalized_group = {
                cls._normalize_for_match(alias) for alias in alias_group if alias.strip()
            }
            if normalized_name in normalized_group:
                aliases.update(normalized_group)
                continue
            if any(
                alias in normalized_name or normalized_name in alias for alias in normalized_group
            ):
                aliases.update(normalized_group)
        return tuple(sorted(aliases, key=len, reverse=True))

    @staticmethod
    def _normalize_for_match(value: str) -> str:
        return value.lower().replace(" ", "")
