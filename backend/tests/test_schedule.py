from datetime import date as date_type

from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.services.ticketing import TicketingService
from kbo_fans_backend.storage import JsonSnapshotStore


class _StubScheduleCrawler:
    def get_month_schedule(self, month: str):
        today = date_type.today().isoformat()
        return [
            {
                "date": today,
                "gameId": f"{today.replace('-', '')}LGOB0",
                "time": "18:30",
                "awayId": "LG",
                "awayName": "LG",
                "awayScore": None,
                "homeId": "OB",
                "homeName": "두산",
                "homeScore": None,
                "stadium": "잠실",
                "status": "SCHEDULED",
            }
        ]


class _StubMainCrawler:
    def get_kbo_game_list(self, date: str):
        return [
            {
                "G_ID": f"{date.replace('-', '')}LGOB0",
                "G_TM": "18:30",
                "GAME_STATE_SC": "2",
                "T_SCORE_CN": "4",
                "B_SCORE_CN": "2",
                "S_NM": "잠실",
            }
        ]


def test_derive_status_marks_start_pit_as_scheduled() -> None:
    html = (
        "<a href='/Schedule/GameCenter/Main.aspx?"
        "gameDate=20260331&gameId=20260331HTLG0&section=START_PIT'"
        " class='btn2' id='btnPreView'>프리뷰</a>"
    )

    status = ScheduleCrawler._derive_status(html)

    assert status == "SCHEDULED"


def test_parse_play_score_extracts_final_score() -> None:
    play_html = (
        "<span>KT</span><em><span class=\"win\">11</span>"
        "<span>vs</span><span class=\"lose\">7</span></em><span>LG</span>"
    )

    away_score, home_score = ScheduleCrawler._parse_play_score(play_html)

    assert away_score == 11
    assert home_score == 7


def test_ticket_info_is_omitted_for_terminal_schedule_status() -> None:
    service = TicketingService()

    ticket_info = service.build_ticket_info(
        home_team_id="LG",
        game_id="20260328KTLG0",
        start_time="14:00",
        status="FINAL",
    )

    assert ticket_info is None


def test_current_day_schedule_status_is_enriched_from_main_game(tmp_path) -> None:
    today = date_type.today().isoformat()
    service = ScheduleService(
        schedule_crawler=_StubScheduleCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_month_schedule(today[:7])
    game = payload["days"][0]["games"][0]

    assert game["status"] == "LIVE"
    assert game["awayScore"] == 4
    assert game["homeScore"] == 2


def test_schedule_saves_non_terminal_month_snapshot(tmp_path) -> None:
    today = date_type.today().isoformat()
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    service = ScheduleService(
        schedule_crawler=_StubScheduleCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=store,
    )

    payload = service.get_month_schedule(today[:7])

    assert store.load_payload("schedule", today[:7]) == payload
