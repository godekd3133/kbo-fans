from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel


class NotificationSettings(BaseModel):
    gameStart: bool
    scoring: bool
    homerun: bool
    reversal: bool
    gameEnd: bool
    lineupOpened: bool = True
    inningChange: bool = False
    allGames: bool


class PushRegisterRequest(BaseModel):
    deviceToken: str
    platform: str
    myTeam: Optional[str] = None
    notifications: NotificationSettings


class PushTestRequest(BaseModel):
    title: str
    body: str
    topic: Optional[str] = None
    token: Optional[str] = None


class LiveActivityContentState(BaseModel):
    awayTeamId: str
    awayTeam: str
    homeTeamId: str
    homeTeam: str
    awayScore: int
    homeScore: int
    inning: str
    batter: str = ""
    pitcher: str = ""
    pitchCount: int = 0
    balls: int = 0
    strikes: int = 0
    outs: int = 0
    stadium: str
    updatedAt: str


class LiveActivityRegisterRequest(BaseModel):
    gameId: str
    activityPushToken: str
    activityId: Optional[str] = None
    previousActivityPushToken: Optional[str] = None
    platform: str = "ios"


class LiveActivityUnregisterRequest(BaseModel):
    gameId: str
    activityPushToken: Optional[str] = None
    activityId: Optional[str] = None


class LiveActivityUpdateRequest(BaseModel):
    gameId: str
    state: LiveActivityContentState
    event: Literal["update", "end"] = "update"
    activityPushToken: Optional[str] = None
    staleDate: Optional[int] = None
    dismissalDate: Optional[int] = None
    relevanceScore: Optional[float] = None
