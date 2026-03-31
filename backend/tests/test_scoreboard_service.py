from kbo_fans_backend.services.scoreboard import ScoreboardService


def test_normalize_date_accepts_compact_format() -> None:
    normalized = ScoreboardService._normalize_date("20260330")

    assert normalized == "2026-03-30"


def test_normalize_date_keeps_iso_format() -> None:
    normalized = ScoreboardService._normalize_date("2026-03-30")

    assert normalized == "2026-03-30"
