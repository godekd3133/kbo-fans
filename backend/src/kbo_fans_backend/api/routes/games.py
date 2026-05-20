from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException, Query, status

from kbo_fans_backend.api.runtime_services import (
    boxscore_service,
    relay_service,
    schedule_service,
    scoreboard_service,
)
from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.lineup import LineupService
from kbo_fans_backend.services.youtube_highlight import YoutubeHighlightService

router = APIRouter(prefix="/game/{game_id}")
lineup_service = LineupService()
youtube_highlight_service = YoutubeHighlightService()


@router.get("", response_model=ApiEnvelope[dict])
def get_game(game_id: str) -> ApiEnvelope[dict]:
    game = scoreboard_service.get_game(game_id)
    scheduled_game = None
    if game is None:
        scheduled_game = schedule_service.get_schedule_game(game_id)

    if game is None and scheduled_game is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="해당 경기를 찾을 수 없습니다",
        )

    if game is None and scheduled_game is not None:
        game = {
            "gameId": scheduled_game["gameId"],
            "status": scheduled_game["status"],
            "inning": f'{scheduled_game["time"]} 예정',
            "stadium": scheduled_game["stadium"],
            "startTime": scheduled_game["time"],
            "crowd": None,
            "away": {
                "teamId": scheduled_game["awayId"],
                "teamName": scheduled_game["awayName"],
                "shortName": scheduled_game["awayName"],
                "score": 0,
                "scores": [None] * 9,
                "hits": 0,
                "errors": 0,
                "balls": 0,
            },
            "home": {
                "teamId": scheduled_game["homeId"],
                "teamName": scheduled_game["homeName"],
                "shortName": scheduled_game["homeName"],
                "score": 0,
                "scores": [None] * 9,
                "hits": 0,
                "errors": 0,
                "balls": 0,
            },
        }

    if scheduled_game is not None and game is not None:
        game["ticketInfo"] = scheduled_game.get("ticketInfo")
        game["highlightInfo"] = {
            "officialUrl": (
                "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx"
                f'?gameDate={scheduled_game["gameId"][:8]}'
                f'&gameId={scheduled_game["gameId"]}&section=HIGHLIGHT'
            ),
            "youtubeVideos": [],
        }

    return ApiEnvelope.success_response({"game": game})


@router.get("/highlights", response_model=ApiEnvelope[dict])
def get_highlights(game_id: str) -> ApiEnvelope[dict]:
    scheduled_game = schedule_service.get_schedule_game(game_id)
    if scheduled_game is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="해당 경기의 하이라이트 정보를 찾을 수 없습니다",
        )

    highlight_info = {
        "officialUrl": (
            "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx"
            f'?gameDate={scheduled_game["gameId"][:8]}'
            f'&gameId={scheduled_game["gameId"]}&section=HIGHLIGHT'
        ),
        "youtubeVideos": []
        if scheduled_game.get("status") == "SCHEDULED"
        else youtube_highlight_service.fetch_highlights(
            game_id=scheduled_game["gameId"],
            away_name=scheduled_game["awayName"],
            home_name=scheduled_game["homeName"],
        ),
    }
    return ApiEnvelope.success_response({"highlightInfo": highlight_info})


@router.get("/relay", response_model=ApiEnvelope[dict])
def get_relay(game_id: str, after: Optional[int] = Query(default=None)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(relay_service.get_relay(game_id, after=after))


@router.get("/boxscore", response_model=ApiEnvelope[dict])
def get_boxscore(game_id: str) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(boxscore_service.get_boxscore(game_id))


@router.get("/lineup", response_model=ApiEnvelope[dict])
def get_lineup(game_id: str) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(lineup_service.get_lineup(game_id))
