from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from kbo_fans_backend.schemas.push import LiveActivityContentState, LiveActivityUpdateRequest
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.relay import RelayService
from kbo_fans_backend.services.scoreboard import ScoreboardService


class LiveActivityScoreboardSyncService:
    def __init__(
        self,
        scoreboard_service: Optional[ScoreboardService] = None,
        push_service: Optional[PushService] = None,
        relay_service: Optional[RelayService] = None,
    ) -> None:
        self.scoreboard_service = scoreboard_service or ScoreboardService()
        self.push_service = push_service or PushService()
        self.relay_service = relay_service

    def sync_date(self, date: str) -> dict[str, Any]:
        registered_game_ids = set(self.push_service.registry.live_activity_game_ids())
        has_push_registrations = self.push_service.registry.has_device_registrations()
        if not registered_game_ids and not has_push_registrations:
            return self._record_heartbeat(
                {"date": date, "checkedGames": 0, "updatedGames": [], "pushedMoments": []}
            )

        scoreboard = self.scoreboard_service.get_home_scoreboard(date)
        updated_games = []
        pushed_moments = []
        for game in scoreboard.get("games", []):
            game_id = str(game.get("gameId") or "")
            if has_push_registrations:
                pushed_moments.extend(self._push_moments_for_game(game))

            if game_id not in registered_game_ids:
                continue

            status = _status_value(game)
            if status == "SCHEDULED":
                continue

            update = self._update_request_for_game(game, status)
            if update is None:
                continue
            response = self.push_service.send_live_activity_update(update)
            updated_games.append(response)

        return self._record_heartbeat(
            {
                "date": scoreboard.get("date", date),
                "checkedGames": len(scoreboard.get("games", [])),
                "updatedGames": updated_games,
                "pushedMoments": pushed_moments,
            }
        )

    def _record_heartbeat(self, result: dict[str, Any]) -> dict[str, Any]:
        self.push_service.registry.record_sync_heartbeat(
            {
                "date": result.get("date"),
                "checkedGames": result.get("checkedGames"),
                "updatedGames": len(result.get("updatedGames") or []),
                "pushedMoments": len(result.get("pushedMoments") or []),
            }
        )
        return result

    def _push_moments_for_game(self, game: dict[str, Any]) -> list[dict[str, Any]]:
        game_id = str(game.get("gameId") or "")
        if not game_id:
            return []

        current_state = _scoreboard_state(game)
        previous_state = self.push_service.registry.replace_scoreboard_state(game_id, current_state)
        pushed = []

        if previous_state is not None:
            for moment in _moments_from_state(previous_state, current_state):
                pushed.append(self._send_game_moment(moment, game_id, current_state))

        pushed.extend(self._push_relay_moments_for_game(game_id, current_state))
        return pushed

    def _push_relay_moments_for_game(
        self,
        game_id: str,
        current_state: dict[str, Any],
    ) -> list[dict[str, Any]]:
        if self.relay_service is None or current_state["status"] != "LIVE":
            return []

        previous_relay_state = self.push_service.registry.relay_state(game_id)
        last_seq = _int_value(previous_relay_state.get("lastSeq")) if previous_relay_state else 0
        after = last_seq if previous_relay_state is not None else None

        try:
            relay = self.relay_service.get_relay(game_id, after=after)
        except Exception as error:
            return [
                {
                    "sent": False,
                    "moment": "homerun",
                    "gameId": game_id,
                    "error": str(error),
                }
            ]

        relay_items = sorted(
            relay.get("relayItems") or [],
            key=lambda item: _int_value(item.get("seqNo")),
        )
        max_seq = last_seq
        pushed = []
        for item in relay_items:
            item_seq = _int_value(item.get("seqNo"))
            if item_seq > max_seq:
                max_seq = item_seq
            if previous_relay_state is None:
                continue
            if _is_homerun_relay_item(item):
                pushed.append(self._send_game_moment("homerun", game_id, current_state))

        self.push_service.registry.replace_relay_state(game_id, {"lastSeq": max_seq})
        return pushed

    def _send_game_moment(
        self,
        moment: str,
        game_id: str,
        current_state: dict[str, Any],
    ) -> dict[str, Any]:
        try:
            return self.push_service.send_game_moment(
                moment=moment,
                game_id=game_id,
                away_team_id=current_state["awayTeamId"],
                away_team_name=current_state["awayTeam"],
                home_team_id=current_state["homeTeamId"],
                home_team_name=current_state["homeTeam"],
                away_score=current_state["awayScore"],
                home_score=current_state["homeScore"],
                inning=current_state["inning"],
                batter_name=current_state["batterName"],
                pitcher_name=current_state["pitcherName"],
            )
        except Exception as error:
            return {
                "sent": False,
                "moment": moment,
                "gameId": game_id,
                "error": str(error),
            }

    def _update_request_for_game(
        self,
        game: dict[str, Any],
        status: str,
    ) -> Optional[LiveActivityUpdateRequest]:
        game_id = str(game.get("gameId") or "")
        away = game.get("away") or {}
        home = game.get("home") or {}
        if not game_id or not away or not home:
            return None

        now = datetime.now(timezone.utc)
        event = "end" if status in {"FINAL", "CANCELLED", "SUSPENDED"} else "update"
        current = _current_payload(game)
        state = LiveActivityContentState(
            awayTeamId=str(away.get("teamId") or ""),
            awayTeam=str(away.get("shortName") or away.get("name") or ""),
            homeTeamId=str(home.get("teamId") or ""),
            homeTeam=str(home.get("shortName") or home.get("name") or ""),
            awayScore=_int_value(away.get("score")),
            homeScore=_int_value(home.get("score")),
            inning=_inning_text(game, status),
            batter=current["batterName"],
            pitcher=current["pitcherName"],
            pitchCount=_int_value(current.get("pitchCount")),
            balls=_int_value(current.get("balls")),
            strikes=_int_value(current.get("strikes")),
            outs=_int_value(current.get("outs")),
            stadium=str(game.get("stadium") or "KBO"),
            updatedAt=now.astimezone().strftime("%H:%M:%S"),
        )
        return LiveActivityUpdateRequest(
            gameId=game_id,
            state=state,
            event=event,
            staleDate=int((now + timedelta(minutes=2)).timestamp()) if event == "update" else None,
            dismissalDate=int((now + timedelta(hours=1)).timestamp()) if event == "end" else None,
            relevanceScore=100 if event == "update" else 50,
        )


def _is_homerun_relay_item(item: dict[str, Any]) -> bool:
    event = str(item.get("event") or "").upper()
    if "HOMERUN" in event:
        return True
    return "홈런" in str(item.get("text") or "")


def _int_value(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _status_value(game: dict[str, Any]) -> str:
    return str(game.get("status") or "").upper()


def _inning_text(game: dict[str, Any], status: str) -> str:
    inning = str(game.get("inning") or "").strip()
    if inning:
        return inning
    status_label = str(game.get("statusLabel") or "").strip()
    if status_label:
        return status_label
    if status == "FINAL":
        return "경기종료"
    if status == "CANCELLED":
        return "경기취소"
    if status == "SUSPENDED":
        return "서스펜디드"
    return "진행중"


def _scoreboard_state(game: dict[str, Any]) -> dict[str, Any]:
    away = game.get("away") or {}
    home = game.get("home") or {}
    status = _status_value(game)
    current = _current_payload(game)
    return {
        "status": status,
        "awayTeamId": str(away.get("teamId") or ""),
        "awayTeam": str(away.get("shortName") or away.get("name") or ""),
        "homeTeamId": str(home.get("teamId") or ""),
        "homeTeam": str(home.get("shortName") or home.get("name") or ""),
        "awayScore": _int_value(away.get("score")),
        "homeScore": _int_value(home.get("score")),
        "inning": _inning_text(game, status),
        "batterName": current["batterName"],
        "pitcherName": current["pitcherName"],
    }


def _moments_from_state(
    previous: dict[str, Any],
    current: dict[str, Any],
) -> list[str]:
    previous_status = str(previous.get("status") or "").upper()
    current_status = str(current.get("status") or "").upper()
    previous_total = _int_value(previous.get("awayScore")) + _int_value(previous.get("homeScore"))
    current_total = _int_value(current.get("awayScore")) + _int_value(current.get("homeScore"))
    moments = []

    if previous_status == "SCHEDULED" and current_status == "LIVE":
        moments.append("game_start")
    if current_status == "LIVE" and current_total > previous_total:
        moments.append("scoring")
    if current_status == "LIVE" and _leader(previous) != _leader(current) and _leader(current):
        moments.append("reversal")
    if previous_status not in {"FINAL", "CANCELLED", "SUSPENDED"} and current_status in {
        "FINAL",
        "CANCELLED",
        "SUSPENDED",
    }:
        moments.append("game_end")
    if (
        not moments
        and current_status == "LIVE"
        and _current_batter(current)
        and _current_batter(previous) != _current_batter(current)
    ):
        moments.append("at_bat")
    if (
        not moments
        and current_status == "LIVE"
        and str(previous.get("inning") or "") != str(current.get("inning") or "")
    ):
        moments.append("inning_change")

    return moments


def _current_payload(game: dict[str, Any]) -> dict[str, Any]:
    current = game.get("current") or {}
    return {
        "balls": current.get("balls"),
        "strikes": current.get("strikes"),
        "outs": current.get("outs"),
        "pitchCount": current.get("pitchCount"),
        "batterName": str(current.get("batterName") or "").strip(),
        "pitcherName": str(current.get("pitcherName") or "").strip(),
    }


def _current_batter(state: dict[str, Any]) -> str:
    return str(state.get("batterName") or "").strip()


def _leader(state: dict[str, Any]) -> str:
    away_score = _int_value(state.get("awayScore"))
    home_score = _int_value(state.get("homeScore"))
    if away_score > home_score:
        return "away"
    if home_score > away_score:
        return "home"
    return ""
