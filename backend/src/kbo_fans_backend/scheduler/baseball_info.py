from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from kbo_fans_backend.services.push import (
    KBO_TEAM_IDS,
    KBO_TEAM_NAMES,
    KBO_TEAM_SHORT_NAMES,
    PushService,
)

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - Python 3.9+ expected
    ZoneInfo = None

_KST = timezone(timedelta(hours=9))
_LINEUP_WINDOW_MINUTES = 180


def current_kbo_date() -> str:
    tz = ZoneInfo("Asia/Seoul") if ZoneInfo is not None else _KST
    return datetime.now(tz).date().isoformat()


def send_once(
    *,
    date: Optional[str] = None,
    kind: Optional[str] = None,
    topic: Optional[str] = None,
    token: Optional[str] = None,
    team_id: Optional[str] = None,
    now_time: Optional[str] = None,
    dry_run: bool = False,
) -> dict:
    target_date = date or current_kbo_date()
    resolved_kind = kind or _scheduled_kind_for_date(target_date)
    if resolved_kind is None:
        return {
            "sent": False,
            "date": target_date,
            "reason": "no scheduled baseball info prompt",
        }

    response = PushService().send_baseball_info(
        kind=resolved_kind,
        date=target_date,
        topic=topic,
        token=token,
        team_id=team_id,
        dry_run=dry_run,
    )
    return {"date": target_date, **response}


def send_smart_daily(
    *,
    date: Optional[str] = None,
    team_id: Optional[str] = None,
    now_time: Optional[str] = None,
    dry_run: bool = False,
    scoreboard_service: Optional[Any] = None,
    push_service: Optional[Any] = None,
) -> dict:
    target_date = date or current_kbo_date()
    if scoreboard_service is None:
        from kbo_fans_backend.services.scoreboard import ScoreboardService

        scoreboard = ScoreboardService()
    else:
        scoreboard = scoreboard_service
    payload = scoreboard.get_home_scoreboard(target_date)
    games = payload.get("games", [])
    plan = build_smart_daily_plan(games=games, team_id=team_id, now_time=now_time)
    push = push_service or PushService()
    deliveries = []

    for item in plan:
        response = push.send_baseball_info(
            kind=item["kind"],
            date=target_date,
            topic=item.get("topic"),
            team_id=item.get("teamId"),
            game_id=item.get("gameId"),
            matchup=item.get("matchup"),
            start_time=item.get("startTime"),
            stadium=item.get("stadium"),
            dry_run=dry_run,
        )
        deliveries.append({**item, "response": response})

    return {
        "sent": any(delivery["response"].get("sent") for delivery in deliveries),
        "dryRun": dry_run,
        "date": target_date,
        "mode": "smart_daily",
        "scoreboardGameCount": len(games) if isinstance(games, list) else 0,
        "planned": deliveries,
    }


def build_smart_daily_plan(
    *,
    games: Any,
    team_id: Optional[str] = None,
    now_time: Optional[str] = None,
) -> list[dict[str, str]]:
    game_list = games if isinstance(games, list) else []
    team_items = _team_plan_items_for_games(game_list, now_time=now_time)
    idle_kind = _idle_kind_for_games(game_list, now_time=now_time)
    teams = [team_id] if team_id else list(KBO_TEAM_IDS)
    plan = []
    for team in teams:
        if team not in KBO_TEAM_IDS:
            continue
        item = team_items.get(team)
        if item is None:
            item = {"teamId": team, "kind": idle_kind}
        plan.append(dict(item))
    if team_id is None:
        plan.append({"topic": "baseball_info_ALL", "kind": _league_kind(plan)})
    return plan


def _scheduled_kind_for_date(date_text: str) -> Optional[str]:
    try:
        parsed = datetime.strptime(date_text, "%Y-%m-%d").date()
    except ValueError:
        return None
    if parsed.weekday() == 0:
        return "weekly_check"
    return None


def _team_plan_items_for_games(
    games: list[dict[str, Any]],
    *,
    now_time: Optional[str],
) -> dict[str, dict[str, str]]:
    now_minutes = _time_to_minutes(now_time)
    team_items: dict[str, dict[str, str]] = {}
    for game in games:
        kind = _kind_for_game(game, now_minutes=now_minutes)
        context = _game_context(game) if kind in {"game_day", "lineup_day"} else {}
        for team_id in [_game_team_id(game, "away"), _game_team_id(game, "home")]:
            if team_id not in KBO_TEAM_IDS:
                continue
            previous = team_items.get(team_id)
            if previous is None or _kind_priority(kind) > _kind_priority(previous["kind"]):
                team_items[team_id] = {"teamId": team_id, "kind": kind, **context}
    return team_items


def _game_context(game: dict[str, Any]) -> dict[str, str]:
    context: dict[str, str] = {}
    game_id = str(game.get("gameId") or "").strip()
    if game_id:
        context["gameId"] = game_id

    away_label = _game_team_label(game, "away")
    home_label = _game_team_label(game, "home")
    if away_label and home_label:
        context["matchup"] = f"{away_label} vs {home_label}"

    start_time = str(game.get("startTime") or game.get("time") or "").strip()
    if start_time:
        context["startTime"] = start_time

    stadium = str(game.get("stadium") or "").strip()
    if stadium:
        context["stadium"] = stadium

    return context


def _game_team_label(game: dict[str, Any], side: str) -> str:
    nested = game.get(side)
    team_id = _game_team_id(game, side)
    if team_id in KBO_TEAM_SHORT_NAMES:
        return KBO_TEAM_SHORT_NAMES[team_id]
    if isinstance(nested, dict):
        for key in ("shortName", "teamName", "name"):
            label = _short_team_name(nested.get(key))
            if label:
                return label
    return _short_team_name(game.get(f"{side}Name")) or team_id


def _short_team_name(value: Any) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    if text in KBO_TEAM_SHORT_NAMES:
        return KBO_TEAM_SHORT_NAMES[text]
    for team_id, full_name in KBO_TEAM_NAMES.items():
        if text == full_name or text.replace(" ", "") == full_name.replace(" ", ""):
            return KBO_TEAM_SHORT_NAMES[team_id]
    return text


def _game_team_id(game: dict[str, Any], side: str) -> str:
    nested = game.get(side)
    if isinstance(nested, dict):
        value = nested.get("teamId")
        if value:
            return str(value)
    return str(game.get(f"{side}Id") or "")


def _kind_for_game(
    game: dict[str, Any],
    *,
    now_minutes: Optional[int],
) -> str:
    status = str(game.get("status") or "").upper()
    if status == "FINAL":
        return "records_check"
    if status in {"CANCELLED", "SUSPENDED"}:
        return "off_day"
    if status == "SCHEDULED" and _is_lineup_window(game, now_minutes=now_minutes):
        return "lineup_day"
    return "game_day"


def _idle_kind_for_games(
    games: list[dict[str, Any]],
    *,
    now_time: Optional[str],
) -> str:
    now_minutes = _time_to_minutes(now_time)
    kinds = [_kind_for_game(game, now_minutes=now_minutes) for game in games]
    if any(kind in {"lineup_day", "game_day", "records_check"} for kind in kinds):
        return "rival_watch"
    return "off_day"


def _is_lineup_window(game: dict[str, Any], *, now_minutes: Optional[int]) -> bool:
    if now_minutes is None:
        return False
    start_minutes = _time_to_minutes(game.get("startTime") or game.get("time"))
    if start_minutes is None:
        return False
    minutes_until_start = start_minutes - now_minutes
    return 0 <= minutes_until_start <= _LINEUP_WINDOW_MINUTES


def _time_to_minutes(value: Any) -> Optional[int]:
    if value is None:
        return None
    match = re.search(r"(\d{1,2}):(\d{2})", str(value))
    if match is None:
        return None
    hour = int(match.group(1))
    minute = int(match.group(2))
    if hour > 23 or minute > 59:
        return None
    return hour * 60 + minute


def _kind_priority(kind: str) -> int:
    return {
        "lineup_day": 4,
        "game_day": 3,
        "records_check": 2,
        "rival_watch": 2,
        "off_day": 1,
    }.get(kind, 0)


def _league_kind(plan: list[dict[str, str]]) -> str:
    kinds = [item["kind"] for item in plan]
    if "lineup_day" in kinds:
        return "lineup_day"
    if "game_day" in kinds:
        return "game_day"
    if "records_check" in kinds:
        return "records_check"
    if "rival_watch" in kinds:
        return "rival_watch"
    return "off_day"


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Send scheduled KBO baseball info push prompts."
    )
    parser.add_argument("--date", default=None)
    parser.add_argument(
        "--kind",
        choices=[
            "weekly_check",
            "off_day",
            "game_day",
            "records_check",
            "lineup_day",
            "rival_watch",
        ],
        default=None,
    )
    parser.add_argument("--topic", default=None)
    parser.add_argument("--token", default=None)
    parser.add_argument("--team-id", default=None)
    parser.add_argument("--now-time", default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--smart-daily", action="store_true")
    args = parser.parse_args(argv)

    if args.smart_daily:
        if args.kind or args.topic or args.token:
            parser.error("--smart-daily cannot be combined with --kind, --topic, or --token")
        result = send_smart_daily(
            date=args.date,
            team_id=args.team_id,
            now_time=args.now_time,
            dry_run=args.dry_run,
        )
    else:
        result = send_once(
            date=args.date,
            kind=args.kind,
            topic=args.topic,
            token=args.token,
            team_id=args.team_id,
            dry_run=args.dry_run,
        )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
