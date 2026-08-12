from __future__ import annotations

import re
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Path, Query, status

from kbo_fans_backend.api.routes.scoreboard import trusted_force_refresh
from kbo_fans_backend.api.runtime_services import (
    boxscore_service,
    lineup_service,
    relay_service,
    schedule_service,
    scoreboard_service,
)
from kbo_fans_backend.schemas.boxscore import BoxscorePayload
from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.youtube_highlight import YoutubeHighlightService

router = APIRouter(prefix="/game/{game_id}")
youtube_highlight_service = YoutubeHighlightService()
_KBO_TEAM_IDS = frozenset(("LG", "KT", "SK", "SS", "NC", "HH", "LT", "HT", "OB", "WO"))
_GAME_ID_RE = re.compile(r"^20\d{6}([A-Z]{2})([A-Z]{2})([A-Za-z0-9_-]{1,20})$")


def _validate_game_id(game_id: str) -> str:
    match = _GAME_ID_RE.fullmatch(game_id)
    if match is None:
        raise HTTPException(status_code=422, detail="유효하지 않은 경기 ID입니다")
    try:
        datetime.strptime(game_id[:8], "%Y%m%d")
    except ValueError as error:
        raise HTTPException(status_code=422, detail="유효하지 않은 경기 날짜입니다") from error
    if match.group(1) not in _KBO_TEAM_IDS or match.group(2) not in _KBO_TEAM_IDS:
        raise HTTPException(status_code=422, detail="유효하지 않은 경기 팀 코드입니다")
    return game_id


@router.get("", response_model=ApiEnvelope[dict])
def get_game(
    game_id: str = Path(..., min_length=8, max_length=32, pattern=r"^[A-Za-z0-9_-]+$"),
    forceRefresh: bool = Query(default=False),
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _validate_game_id(game_id)
    game = scoreboard_service.get_game(
        game_id,
        force_refresh=trusted_force_refresh(
            forceRefresh,
            x_kbo_push_sync_secret,
        ),
    )
    scheduled_game = None
    if game is None:
        scheduled_game = schedule_service.get_schedule_game(game_id)

    if game is None and scheduled_game is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="해당 경기를 찾을 수 없습니다",
        )

    if game is None and scheduled_game is not None:
        schedule_status = str(scheduled_game.get("status") or "SCHEDULED").upper()
        schedule_status_label = str(scheduled_game.get("statusLabel") or "").strip()
        if not schedule_status_label:
            schedule_status_label = {
                "FINAL": "경기종료",
                "CANCELLED": "경기 취소",
                "SUSPENDED": "경기 중단",
                "LIVE": "경기 진행 중",
            }.get(schedule_status, "")
        inning_label = schedule_status_label or (
            f"{scheduled_game.get('time') or ''} 예정"
            if schedule_status == "SCHEDULED"
            else schedule_status
        )
        away_score = scheduled_game.get("awayScore")
        home_score = scheduled_game.get("homeScore")
        if not isinstance(away_score, int) or isinstance(away_score, bool):
            away_score = None
        if not isinstance(home_score, int) or isinstance(home_score, bool):
            home_score = None
        game = {
            "gameId": scheduled_game["gameId"],
            "status": schedule_status,
            "statusLabel": schedule_status_label or None,
            "inning": inning_label,
            "stadium": scheduled_game["stadium"],
            "startTime": scheduled_game["time"],
            "crowd": None,
            "away": {
                "teamId": scheduled_game["awayId"],
                "teamName": scheduled_game["awayName"],
                "shortName": scheduled_game["awayName"],
                "score": away_score,
                "scores": [None] * 9,
                "hits": None,
                "errors": None,
                "balls": None,
            },
            "home": {
                "teamId": scheduled_game["homeId"],
                "teamName": scheduled_game["homeName"],
                "shortName": scheduled_game["homeName"],
                "score": home_score,
                "scores": [None] * 9,
                "hits": None,
                "errors": None,
                "balls": None,
            },
        }

    if scheduled_game is not None and game is not None:
        game["ticketInfo"] = scheduled_game.get("ticketInfo")
        game["highlightInfo"] = {
            "officialUrl": (
                "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx"
                f"?gameDate={scheduled_game['gameId'][:8]}"
                f"&gameId={scheduled_game['gameId']}&section=HIGHLIGHT"
            ),
            "youtubeVideos": [],
        }

    return ApiEnvelope.success_response({"game": game})


@router.get("/highlights", response_model=ApiEnvelope[dict])
def get_highlights(
    game_id: str = Path(..., min_length=8, max_length=32, pattern=r"^[A-Za-z0-9_-]+$"),
) -> ApiEnvelope[dict]:
    _validate_game_id(game_id)
    scheduled_game = schedule_service.get_schedule_game(game_id)
    if scheduled_game is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="해당 경기의 하이라이트 정보를 찾을 수 없습니다",
        )

    youtube_videos = []
    if scheduled_game.get("status") != "SCHEDULED":
        youtube_videos = youtube_highlight_service.fetch_highlights(
            game_id=scheduled_game["gameId"],
            away_name=scheduled_game["awayName"],
            home_name=scheduled_game["homeName"],
        )
        if not youtube_videos:
            youtube_videos = [
                youtube_highlight_service.build_search_fallback(
                    game_id=scheduled_game["gameId"],
                    away_name=scheduled_game["awayName"],
                    home_name=scheduled_game["homeName"],
                )
            ]

    highlight_info = {
        "officialUrl": (
            "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx"
            f"?gameDate={scheduled_game['gameId'][:8]}"
            f"&gameId={scheduled_game['gameId']}&section=HIGHLIGHT"
        ),
        "youtubeVideos": youtube_videos,
    }
    return ApiEnvelope.success_response({"highlightInfo": highlight_info})


@router.get("/relay", response_model=ApiEnvelope[dict])
def get_relay(
    game_id: str = Path(..., min_length=8, max_length=32, pattern=r"^[A-Za-z0-9_-]+$"),
    after: Optional[int] = Query(default=None),
    forceRefresh: bool = Query(default=False),
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _validate_game_id(game_id)
    return ApiEnvelope.success_response(
        relay_service.get_relay(
            game_id,
            after=after,
            force_refresh=trusted_force_refresh(
                forceRefresh,
                x_kbo_push_sync_secret,
            ),
        )
    )


@router.get("/boxscore", response_model=ApiEnvelope[BoxscorePayload])
def get_boxscore(
    game_id: str = Path(..., min_length=8, max_length=32, pattern=r"^[A-Za-z0-9_-]+$"),
) -> ApiEnvelope[BoxscorePayload]:
    _validate_game_id(game_id)
    return ApiEnvelope.success_response(boxscore_service.get_boxscore(game_id))


@router.get("/lineup", response_model=ApiEnvelope[dict])
def get_lineup(
    game_id: str = Path(..., min_length=8, max_length=32, pattern=r"^[A-Za-z0-9_-]+$"),
) -> ApiEnvelope[dict]:
    _validate_game_id(game_id)
    return ApiEnvelope.success_response(lineup_service.get_lineup(game_id))
