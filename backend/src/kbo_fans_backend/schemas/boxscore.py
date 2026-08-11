from __future__ import annotations

from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class BoxscoreAvailability(str, Enum):
    OFFICIAL = "official"
    LIVE_CONTEXT = "live_context"
    OFFICIAL_UNAVAILABLE = "official_unavailable"


class BoxscoreTeamPayload(BaseModel):
    teamId: str
    batters: List[Dict[str, Any]] = Field(default_factory=list)
    pitchers: List[Dict[str, Any]] = Field(default_factory=list)
    totals: Dict[str, Any] = Field(default_factory=dict)


class BoxscorePayload(BaseModel):
    gameId: str
    availability: BoxscoreAvailability
    officialAvailable: bool
    liveContextAvailable: bool
    away: BoxscoreTeamPayload
    home: BoxscoreTeamPayload
    source: Optional[str] = None
    sourceGameId: Optional[str] = None
    unavailableReason: Optional[str] = None


def empty_boxscore_totals() -> Dict[str, Any]:
    return {
        "batting": {"atBats": 0, "runs": 0, "hits": 0, "rbi": 0},
        "pitching": {
            "innings": "0.0",
            "hits": 0,
            "strikeouts": 0,
            "walks": 0,
            "earnedRuns": 0,
        },
    }


def official_unavailable_boxscore(
    game_id: str,
    away_id: str,
    home_id: str,
    *,
    reason: str,
) -> Dict[str, Any]:
    return {
        "gameId": game_id,
        "availability": BoxscoreAvailability.OFFICIAL_UNAVAILABLE.value,
        "officialAvailable": False,
        "liveContextAvailable": False,
        "source": "official_endpoint",
        "unavailableReason": reason,
        "away": {
            "teamId": away_id,
            "batters": [],
            "pitchers": [],
            "totals": empty_boxscore_totals(),
        },
        "home": {
            "teamId": home_id,
            "batters": [],
            "pitchers": [],
            "totals": empty_boxscore_totals(),
        },
    }
