from __future__ import annotations

from typing import Any

from kbo_fans_backend.crawlers.base import BaseCrawler


class MainCrawler(BaseCrawler):
    """Fetches core game-center metadata from Main.asmx endpoints."""

    def get_kbo_game_list(self, date: str) -> list[dict[str, Any]]:
        return self._post_json(
            f"{self.base_url}/ws/Main.asmx/GetKboGameList",
            breaker_key="kbo:main_game_list",
            data={
                "leId": "1",
                "srId": self._series_for_date(date),
                "date": date.replace("-", ""),
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
            },
        ).get("game", [])

    @staticmethod
    def _series_for_date(date: str) -> str:
        compact = date.replace("-", "")
        if compact[:4] >= "2021":
            series = "0,1,3,4,5,6,7,9"
        else:
            series = "0,1,3,4,5,7,9"
        if compact >= "20241026":
            series = "0,1,3,4,5,6,7,8,9"
        return series
