KBO_PLAYER_IMAGE_BASE = "https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle"
KBO_PLAYER_IMAGE_MIN_SEASON = 2022


def kbo_player_image_season(season: int) -> int:
    return max(season, KBO_PLAYER_IMAGE_MIN_SEASON)


def kbo_player_image_url(season: int, player_id: str) -> str:
    return f"{KBO_PLAYER_IMAGE_BASE}/{kbo_player_image_season(season)}/{player_id}.jpg"
