from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.schedule import ScheduleCrawler


class ScheduleService:
    def __init__(self, schedule_crawler: Optional[ScheduleCrawler] = None) -> None:
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()

    def get_month_schedule(self, month: str) -> dict[str, Any]:
        rows = self.schedule_crawler.get_month_schedule(month)
        days_by_date: dict[str, dict[str, Any]] = {}

        for row in rows:
            date = row["date"]
            if date not in days_by_date:
                days_by_date[date] = {
                    "date": date,
                    "label": None,
                    "games": [],
                }
            days_by_date[date]["games"].append(
                {
                    "gameId": row["gameId"],
                    "time": row["time"],
                    "awayId": row["awayId"],
                    "awayName": row["awayName"],
                    "homeId": row["homeId"],
                    "homeName": row["homeName"],
                    "stadium": row["stadium"],
                    "status": row["status"],
                }
            )

        return {
            "month": month,
            "days": list(days_by_date.values()),
        }
