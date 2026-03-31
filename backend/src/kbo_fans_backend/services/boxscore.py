from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.storage import JsonSnapshotStore


class BoxscoreService:
    def __init__(
        self,
        crawler: Optional[BoxscoreCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.crawler = crawler or BoxscoreCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()

    def get_boxscore(self, game_id: str) -> dict[str, Any]:
        snapshot = self.snapshot_store.load_payload("boxscore", game_id)
        try:
            payload = self.crawler.get_boxscore(game_id)
        except Exception:
            if snapshot is not None:
                return snapshot
            raise

        self.snapshot_store.save("boxscore", game_id, payload)
        return payload
