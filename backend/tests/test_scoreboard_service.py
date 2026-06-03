from kbo_fans_backend.services.scoreboard import ScoreboardService


def test_normalize_date_accepts_compact_format() -> None:
    normalized = ScoreboardService._normalize_date("20260330")

    assert normalized == "2026-03-30"


def test_normalize_date_keeps_iso_format() -> None:
    normalized = ScoreboardService._normalize_date("2026-03-30")

    assert normalized == "2026-03-30"


def test_score_from_innings_fills_missing_live_total() -> None:
    score = ScoreboardService._score_from_innings(None, [1, 0, 0, 3, None])

    assert score == 4


def test_score_from_innings_keeps_existing_total() -> None:
    score = ScoreboardService._score_from_innings(7, [1, 0, 0, 3, None])

    assert score == 7


def test_cancelled_main_game_uses_cancel_label_for_inning() -> None:
    service = ScoreboardService()
    main_game = {
        "GAME_STATE_SC": "4",
        "CANCEL_SC_NM": "우천취소",
        "G_TM": "18:30",
        "GAME_INN_NO": 0,
        "GAME_TB_SC_NM": "초",
    }

    assert service._format_inning(main_game) == "우천취소"
    assert service._status_label_for_main_game("CANCELLED", main_game) == "우천취소"
