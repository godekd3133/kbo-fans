import threading

from kbo_fans_backend.crawlers.team_stats import TeamStatsCrawler
from kbo_fans_backend.utils.kbo_time import current_kbo_year


def _team_stats_html(crawler: TeamStatsCrawler, selected_season: int) -> str:
    return f'''
    <select name="{crawler._SEASON_FIELD}">
      <option value="{selected_season - 1}">{selected_season - 1}</option>
      <option selected="selected" value="{selected_season}">{selected_season}</option>
    </select>
    <table>
      <thead><tr><th>순위</th><th>팀명</th><th>AVG</th></tr></thead>
      <tbody><tr><td>1</td><td>LG</td><td>.280</td></tr></tbody>
    </table>
    '''


def test_current_team_stats_uses_get_without_season_post(monkeypatch) -> None:
    crawler = TeamStatsCrawler()
    season = current_kbo_year()
    html = _team_stats_html(crawler, season)
    monkeypatch.setattr(crawler, "_get_text", lambda *args, **kwargs: html)

    def fail_post(*args, **kwargs):
        raise AssertionError("current team stats should not issue a season POST")

    monkeypatch.setattr(crawler, "_post_text", fail_post)

    stats = crawler._fetch_table_stats(crawler._HITTER_URL, season, "LG")

    assert stats["팀명"] == "LG"
    assert stats["AVG"] == ".280"


def test_historical_team_stats_still_posts_selected_season(monkeypatch) -> None:
    crawler = TeamStatsCrawler()
    season = current_kbo_year() - 1
    initial_html = _team_stats_html(crawler, current_kbo_year())
    post_seasons = []
    monkeypatch.setattr(crawler, "_get_text", lambda *args, **kwargs: initial_html)

    def post_page(*args, **kwargs):
        post_seasons.append(kwargs["data"][crawler._SEASON_FIELD])
        return _team_stats_html(crawler, season)

    monkeypatch.setattr(crawler, "_post_text", post_page)

    stats = crawler._fetch_table_stats(crawler._HITTER_URL, season, "LG")

    assert post_seasons == [str(season)]
    assert stats["팀명"] == "LG"


def test_current_team_stats_fetches_hitter_and_pitcher_without_post(monkeypatch) -> None:
    crawler = TeamStatsCrawler()
    season = current_kbo_year()
    html = _team_stats_html(crawler, season)
    get_calls = []
    monkeypatch.setattr(
        crawler,
        "_get_text",
        lambda *args, **kwargs: get_calls.append(args[0]) or html,
    )

    def fail_post(*args, **kwargs):
        raise AssertionError("current team stats should not issue a season POST")

    monkeypatch.setattr(crawler, "_post_text", fail_post)

    payload = crawler.get_team_stats("LG", season)

    assert len(get_calls) == 2
    assert payload["teamId"] == "LG"
    assert payload["hitting"]["AVG"] == ".280"
    assert payload["pitching"]["AVG"] == ".280"


def test_team_stats_failure_does_not_wait_for_sibling_table() -> None:
    class _FailFastTeamStatsCrawler(TeamStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.start_barrier = threading.Barrier(2)
            self.sibling_started = threading.Event()
            self.sibling_release = threading.Event()

        def _fetch_table_stats(self, path: str, season: int, team_name: str):
            self.start_barrier.wait(timeout=1)
            if path == self._HITTER_URL:
                raise RuntimeError("hitter table unavailable")
            self.sibling_started.set()
            assert self.sibling_release.wait(timeout=2)
            return {}

    crawler = _FailFastTeamStatsCrawler()
    errors = []

    def load() -> None:
        try:
            crawler.get_team_stats("LG", 2026)
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=load)
    thread.start()
    assert crawler.sibling_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        crawler.sibling_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "hitter table unavailable"


def test_pitcher_stats_failure_does_not_wait_for_hitter_table() -> None:
    class _LateFailureTeamStatsCrawler(TeamStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.start_barrier = threading.Barrier(2)
            self.sibling_started = threading.Event()
            self.sibling_release = threading.Event()

        def _fetch_table_stats(self, path: str, season: int, team_name: str):
            self.start_barrier.wait(timeout=1)
            if path == self._PITCHER_URL:
                raise RuntimeError("pitcher table unavailable")
            self.sibling_started.set()
            assert self.sibling_release.wait(timeout=2)
            return {}

    crawler = _LateFailureTeamStatsCrawler()
    errors = []

    def load() -> None:
        try:
            crawler.get_team_stats("LG", 2026)
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=load)
    thread.start()
    assert crawler.sibling_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        crawler.sibling_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "pitcher table unavailable"
