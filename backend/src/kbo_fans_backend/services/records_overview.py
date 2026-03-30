from __future__ import annotations

from typing import Any, Dict, Optional

from kbo_fans_backend.crawlers.records_overview import RecordsOverviewCrawler


class RecordsOverviewService:
    def __init__(self, crawler: Optional[RecordsOverviewCrawler] = None) -> None:
        self.crawler = crawler or RecordsOverviewCrawler()

    def get_overview(self, season: int) -> Dict[str, Any]:
        return self.crawler.get_overview(season)
