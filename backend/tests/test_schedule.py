from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.services.ticketing import TicketingService


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
