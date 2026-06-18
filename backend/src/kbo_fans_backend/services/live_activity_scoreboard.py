from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Optional

from kbo_fans_backend.schemas.push import LiveActivityContentState, LiveActivityUpdateRequest
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.relay import RelayService
from kbo_fans_backend.services.scoreboard import ScoreboardService


class LiveActivityScoreboardSyncService:
    _KST = timezone(timedelta(hours=9))
    _PREGAME_ALERT_WINDOW = timedelta(minutes=10)

    def __init__(
        self,
        scoreboard_service: Optional[ScoreboardService] = None,
        push_service: Optional[PushService] = None,
        relay_service: Optional[RelayService] = None,
        now_provider: Optional[Callable[[], datetime]] = None,
    ) -> None:
        self.scoreboard_service = scoreboard_service or ScoreboardService()
        self.push_service = push_service or PushService()
        self.relay_service = relay_service
        self.now_provider = now_provider or (lambda: datetime.now(timezone.utc))

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

        pushed.extend(self._push_pregame_moments_for_game(game, current_state))

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
        relay_current_state = _relay_current_state(relay.get("currentAtBat"), current_state)
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
                continue
            if _is_hit_relay_item(item):
                hit_state = {
                    **current_state,
                    **relay_current_state,
                    "inning": _relay_item_inning_text(item) or relay_current_state["inning"],
                    "batterName": _relay_item_actor(item) or current_state["batterName"],
                    "playText": str(item.get("text") or "").strip(),
                }
                pushed.append(self._send_game_moment("hit", game_id, hit_state))

        self.push_service.registry.replace_relay_state(game_id, {"lastSeq": max_seq})
        return pushed

    def _push_pregame_moments_for_game(
        self,
        game: dict[str, Any],
        current_state: dict[str, Any],
    ) -> list[dict[str, Any]]:
        if current_state["status"] != "SCHEDULED":
            return []

        start_at = _scheduled_start_at(game, current_state)
        if start_at is None:
            return []

        now = self.now_provider().astimezone(self._KST)
        until_start = start_at - now
        if until_start < timedelta(0) or until_start > self._PREGAME_ALERT_WINDOW:
            return []

        game_id = str(game.get("gameId") or "")
        alert_key = f"game_start_soon:{start_at.isoformat()}"
        if self.push_service.registry.pregame_alert_sent(game_id, alert_key):
            return []

        state = {
            **current_state,
            "startTime": start_at.strftime("%H:%M"),
            "stadium": str(game.get("stadium") or current_state.get("stadium") or ""),
        }
        response = self._send_game_moment("game_start_soon", game_id, state)
        if response.get("sent"):
            self.push_service.registry.mark_pregame_alert_sent(game_id, alert_key)
        return [response]

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
                situation_text=current_state.get("situationText", ""),
                play_text=current_state.get("playText", ""),
                start_time=current_state.get("startTime", ""),
                stadium=current_state.get("stadium", ""),
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


def _is_hit_relay_item(item: dict[str, Any]) -> bool:
    text = str(item.get("text") or "")
    if _is_homerun_relay_item(item):
        return False
    event = str(item.get("event") or "").upper()
    if event == "HIT":
        return True
    return any(marker in text for marker in ("안타", "1루타", "2루타", "3루타"))


def _relay_item_actor(item: dict[str, Any]) -> str:
    text = str(item.get("text") or "").strip()
    if not text:
        return ""
    actor = re.split(r"\s*[:：]\s*", text, maxsplit=1)[0].strip()
    actor = re.sub(r"^\d+\s*번\s*", "", actor).strip()
    return actor if len(actor) <= 12 else ""


def _relay_item_inning_text(item: dict[str, Any]) -> str:
    inning = _int_value(item.get("inning"))
    if inning <= 0:
        return ""
    half = str(item.get("half") or "").lower()
    suffix = "초" if half == "top" else "말" if half == "bottom" else ""
    return f"{inning}회{suffix}"


def _relay_current_state(
    current_at_bat: Any,
    fallback_state: dict[str, Any],
) -> dict[str, Any]:
    if not isinstance(current_at_bat, dict):
        return {
            "inning": fallback_state["inning"],
            "batterName": fallback_state["batterName"],
            "pitcherName": fallback_state["pitcherName"],
            "situationText": "",
        }

    batter = current_at_bat.get("batter") or {}
    pitcher = current_at_bat.get("pitcher") or {}
    ball_count = current_at_bat.get("ballCount") or {}
    inning = str(current_at_bat.get("inningText") or fallback_state["inning"])
    base_state = str(current_at_bat.get("baseState") or "")
    return {
        "inning": inning,
        "batterName": str(batter.get("name") or fallback_state["batterName"]),
        "pitcherName": str(pitcher.get("name") or fallback_state["pitcherName"]),
        "situationText": _situation_text(
            outs=_int_value(ball_count.get("outs")),
            base_state=base_state,
        ),
    }


def _situation_text(*, outs: int, base_state: str) -> str:
    outs_label = {0: "무사", 1: "1사", 2: "2사"}.get(outs, "")
    base_label = _base_state_label(base_state)
    if outs_label and base_label:
        return f"{outs_label} {base_label}"
    return outs_label or base_label


def _base_state_label(base_state: str) -> str:
    text = base_state.strip()
    if not text:
        return ""
    if text == "주자없음":
        return "주자 없음"
    if text.startswith("주자"):
        return text.removeprefix("주자")
    return text


def _scheduled_start_at(
    game: dict[str, Any],
    current_state: dict[str, Any],
) -> Optional[datetime]:
    game_id = str(game.get("gameId") or "")
    if len(game_id) < 8:
        return None

    raw_time = str(
        current_state.get("startTime") or game.get("startTime") or game.get("time") or ""
    )
    match = re.search(r"(\d{1,2}):(\d{2})", raw_time)
    if not match:
        return None

    try:
        year = int(game_id[:4])
        month = int(game_id[4:6])
        day = int(game_id[6:8])
        hour = int(match.group(1))
        minute = int(match.group(2))
    except ValueError:
        return None

    return datetime(
        year,
        month,
        day,
        hour,
        minute,
        tzinfo=LiveActivityScoreboardSyncService._KST,
    )


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
        "situationText": "",
        "playText": "",
        "startTime": str(game.get("startTime") or ""),
        "stadium": str(game.get("stadium") or ""),
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
