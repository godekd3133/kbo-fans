from fastapi import APIRouter

from kbo_fans_backend.api.routes import (
    games,
    health,
    players,
    push,
    schedule,
    scoreboard,
    standings,
    teams,
)

api_router = APIRouter()
api_router.include_router(health.router, tags=["health"])
api_router.include_router(scoreboard.router, tags=["scoreboard"])
api_router.include_router(games.router, tags=["games"])
api_router.include_router(schedule.router, tags=["schedule"])
api_router.include_router(standings.router, tags=["standings"])
api_router.include_router(teams.router, tags=["teams"])
api_router.include_router(players.router, tags=["players"])
api_router.include_router(push.router, tags=["push"])
