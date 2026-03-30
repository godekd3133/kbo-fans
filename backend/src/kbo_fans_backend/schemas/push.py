from __future__ import annotations

from typing import Optional

from pydantic import BaseModel


class NotificationSettings(BaseModel):
    gameStart: bool
    scoring: bool
    homerun: bool
    reversal: bool
    gameEnd: bool
    allGames: bool


class PushRegisterRequest(BaseModel):
    deviceToken: str
    platform: str
    myTeam: Optional[str] = None
    notifications: NotificationSettings
