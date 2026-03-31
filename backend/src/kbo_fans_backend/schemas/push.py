from __future__ import annotations

from typing import Optional

from pydantic import BaseModel


class NotificationSettings(BaseModel):
    gameStart: bool
    scoring: bool
    homerun: bool
    reversal: bool
    gameEnd: bool
    lineupOpened: bool = True
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
