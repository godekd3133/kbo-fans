from __future__ import annotations

import json
from typing import Annotated, Literal, Optional

from pydantic import BaseModel, Field, StringConstraints, model_validator

NotificationDelivery = Literal["immediate", "summary", "live_only", "off"]
NotificationSummaryDetailLevel = Literal["essential", "standard", "detailed"]
NotificationLiveDetailLevel = Literal["essential", "standard", "detailed"]
BoundedGameId = Annotated[str, Field(min_length=1, max_length=32)]
BoundedDeviceToken = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=2048),
]
BoundedOwnerId = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=128),
]
OptionalOwnerId = Annotated[
    str,
    StringConstraints(strip_whitespace=True, max_length=128),
]
BoundedPlatform = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=16),
]
BoundedLiveActivityToken = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=512),
]
OptionalLiveActivityToken = Annotated[
    str,
    StringConstraints(strip_whitespace=True, max_length=512),
]
ReceiptDataKey = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=64),
]
ReceiptDataValue = Annotated[
    str,
    StringConstraints(strip_whitespace=True, max_length=1024),
]


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
    summaryDetailLevel: NotificationSummaryDetailLevel = "detailed"
    liveDetailLevel: NotificationLiveDetailLevel = "detailed"
    deliveryModes: Optional[NotificationDeliveryModes] = None


class PushRegisterRequest(BaseModel):
    deviceToken: BoundedDeviceToken
    platform: BoundedPlatform
    installationId: Optional[OptionalOwnerId] = None
    myTeam: Optional[str] = Field(default=None, max_length=8)
    notifications: NotificationSettings
    followedGameIds: list[BoundedGameId] = Field(default_factory=list, max_length=16)
    notificationsAllowed: Optional[bool] = None
    authorizationStatus: Optional[str] = Field(default=None, max_length=32)
    apnsTokenReady: Optional[bool] = None


class PushTestRequest(BaseModel):
    title: str
    body: str
    topic: Optional[str] = None
    token: Optional[str] = None


class PushDeviceTestRequest(BaseModel):
    deviceToken: BoundedDeviceToken
    installationId: Optional[BoundedOwnerId] = None


class PushReceiptRequest(BaseModel):
    deviceToken: BoundedDeviceToken
    installationId: Optional[BoundedOwnerId] = None
    messageId: Optional[str] = Field(default=None, max_length=256)
    source: str = Field(min_length=1, max_length=32)
    type: Optional[str] = Field(default=None, max_length=64)
    gameId: Optional[str] = Field(default=None, max_length=32)
    route: Optional[str] = Field(default=None, max_length=512)
    receivedAt: Optional[str] = Field(default=None, max_length=64)
    data: dict[ReceiptDataKey, ReceiptDataValue] = Field(
        default_factory=dict,
        max_length=8,
    )

    @model_validator(mode="after")
    def validate_data_byte_size(self) -> PushReceiptRequest:
        serialized = json.dumps(
            self.data,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        if len(serialized) > 4096:
            raise ValueError("receipt data exceeds 4096 bytes")
        return self


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
    gameId: Optional[str] = None
    matchup: Optional[str] = None
    startTime: Optional[str] = None
    stadium: Optional[str] = None
    dryRun: bool = False


class LiveActivityContentState(BaseModel):
    awayTeamId: str
    awayTeam: str
    homeTeamId: str
    homeTeam: str
    awayScore: int
    homeScore: int
    scoreAvailable: bool = True
    inning: str
    batter: str = ""
    batterAverage: str = ""
    pitcher: str = ""
    pitcherEra: str = ""
    pitchCount: int = 0
    balls: int = 0
    strikes: int = 0
    outs: int = 0
    stadium: str
    updatedAt: str
    situationText: str = ""
    playText: str = ""
    isPregame: bool = False
    awayRankText: str = ""
    homeRankText: str = ""


class LiveActivityRegisterRequest(BaseModel):
    gameId: BoundedGameId
    activityPushToken: BoundedLiveActivityToken
    activityId: Optional[OptionalOwnerId] = None
    previousActivityPushToken: Optional[OptionalLiveActivityToken] = None
    installationId: Optional[OptionalOwnerId] = None
    platform: BoundedPlatform = "ios"


class LiveActivityStartTokenRegisterRequest(BaseModel):
    pushToStartToken: BoundedLiveActivityToken
    previousPushToStartToken: Optional[OptionalLiveActivityToken] = None
    installationId: BoundedOwnerId
    platform: BoundedPlatform = "ios"


class LiveActivityUnregisterRequest(BaseModel):
    gameId: BoundedGameId
    activityPushToken: Optional[OptionalLiveActivityToken] = None
    activityId: Optional[OptionalOwnerId] = None
    installationId: Optional[BoundedOwnerId] = None


class LiveActivityUpdateRequest(BaseModel):
    gameId: str
    state: LiveActivityContentState
    event: Literal["update", "end"] = "update"
    activityPushToken: Optional[str] = None
    staleDate: Optional[int] = None
    dismissalDate: Optional[int] = None
    relevanceScore: Optional[float] = None
