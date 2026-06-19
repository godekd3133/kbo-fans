from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field

NotificationDelivery = Literal["immediate", "summary", "live_only", "off"]


class NotificationDeliveryModes(BaseModel):
    gameStart: Optional[NotificationDelivery] = None
    scoring: Optional[NotificationDelivery] = None
    hit: Optional[NotificationDelivery] = None
    homerun: Optional[NotificationDelivery] = None
    reversal: Optional[NotificationDelivery] = None
    gameEnd: Optional[NotificationDelivery] = None
    lineupOpened: Optional[NotificationDelivery] = None
    inningChange: Optional[NotificationDelivery] = None
    atBat: Optional[NotificationDelivery] = None
    baseballInfo: Optional[NotificationDelivery] = None


class NotificationSettings(BaseModel):
    gameStart: bool
    scoring: bool
    hit: bool = True
    homerun: bool
    reversal: bool
    gameEnd: bool
    lineupOpened: bool = True
    inningChange: bool = False
    atBat: bool = True
    baseballInfo: bool = True
    allGames: bool
    deliveryModes: Optional[NotificationDeliveryModes] = None


class PushRegisterRequest(BaseModel):
    deviceToken: str
    platform: str
    myTeam: Optional[str] = None
    notifications: NotificationSettings
    followedGameIds: list[str] = Field(default_factory=list)


class PushTestRequest(BaseModel):
    title: str
    body: str
    topic: Optional[str] = None
    token: Optional[str] = None


class PushBaseballInfoRequest(BaseModel):
    kind: Literal[
        "weekly_check",
        "off_day",
        "game_day",
        "records_check",
        "lineup_day",
        "rival_watch",
    ] = "weekly_check"
    date: str = ""
    topic: Optional[str] = None
    token: Optional[str] = None
    teamId: Optional[str] = None
    dryRun: bool = False


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
    situationText: str = ""
    playText: str = ""


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
