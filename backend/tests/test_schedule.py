from kbo_fans_backend.crawlers.schedule import ScheduleCrawler


def test_derive_status_marks_start_pit_as_scheduled() -> None:
    html = (
        "<a href='/Schedule/GameCenter/Main.aspx?"
        "gameDate=20260331&gameId=20260331HTLG0&section=START_PIT'"
        " class='btn2' id='btnPreView'>프리뷰</a>"
    )

    status = ScheduleCrawler._derive_status(html)

    assert status == "SCHEDULED"
