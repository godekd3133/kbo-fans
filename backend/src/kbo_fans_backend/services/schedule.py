from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.services.ticketing import TicketingService


class ScheduleService:
    def __init__(
        self,
        schedule_crawler: Optional[ScheduleCrawler] = None,
        ticketing_service: Optional[TicketingService] = None,
    ) -> None:
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()
        self.ticketing_service = ticketing_service or TicketingService()

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
                    "ticketInfo": self.ticketing_service.build_ticket_info(
                        home_team_id=row["homeId"],
                        game_id=row["gameId"],
                        start_time=row["time"],
                    ),
                }
            )

        return {
            "month": month,
            "days": list(days_by_date.values()),
        }

    def get_schedule_game(self, game_id: str) -> Optional[dict[str, Any]]:
        month = f"{game_id[:4]}-{game_id[4:6]}"
        rows = self.schedule_crawler.get_month_schedule(month)
        for row in rows:
            if row["gameId"] != game_id:
                continue

            return {
                **row,
                "ticketInfo": self.ticketing_service.build_ticket_info(
                    home_team_id=row["homeId"],
                    game_id=row["gameId"],
                    start_time=row["time"],
                ),
            }

        return None
