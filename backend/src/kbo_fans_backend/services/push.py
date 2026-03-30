from __future__ import annotations

from typing import Any

from kbo_fans_backend.schemas.push import PushRegisterRequest


class PushService:
    def register(self, payload: PushRegisterRequest) -> dict[str, Any]:
        topics = self._build_topics(payload)
        return {
            "registered": True,
            "subscribedTopics": topics,
        }

    def _build_topics(self, payload: PushRegisterRequest) -> list[str]:
        team_key = payload.myTeam or "ALL"
        topics: list[str] = []

        topic_flags = {
            "game_start": payload.notifications.gameStart,
            "scoring": payload.notifications.scoring,
            "homerun": payload.notifications.homerun,
            "reversal": payload.notifications.reversal,
            "game_end": payload.notifications.gameEnd,
        }

        for topic_name, enabled in topic_flags.items():
            if not enabled:
                continue

            if payload.notifications.allGames:
                topics.append(f"{topic_name}_ALL")
            else:
                topics.append(f"{topic_name}_{team_key}")

        if payload.notifications.allGames:
            topics.append("all_games_enabled")

        return topics
