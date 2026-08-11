import pytest

from kbo_fans_backend.crawlers.standings import StandingsCrawler


class _HtmlStandingsCrawler(StandingsCrawler):
    def __init__(self, initial_html: str, response_html: str) -> None:
        super().__init__()
        self._initial_html = initial_html
        self._response_html = response_html
        self.post_data = None

    def _get_text(self, url: str, *, breaker_key=None, **kwargs) -> str:
        return self._initial_html

    def _post_text(self, url: str, *, breaker_key=None, **kwargs) -> str:
        self.post_data = kwargs["data"]
        return self._response_html


def _standings_html(
    *,
    selected_season: int,
    source_season: int,
    source_date: str,
    include_rows: bool = True,
) -> str:
    season_field = StandingsCrawler._SEASON_FIELD
    source_season_field = StandingsCrawler._SOURCE_SEASON_FIELD
    source_date_field = StandingsCrawler._SOURCE_DATE_FIELD
    selected_2026 = ' selected="selected"' if selected_season == 2026 else ""
    selected_2025 = ' selected="selected"' if selected_season == 2025 else ""
    row = ""
    if include_rows:
        row = """
          <tr>
            <td>1</td><td>LG</td><td>43</td><td>25</td><td>17</td><td>1</td>
            <td>0.595</td><td>0</td><td>7승0무3패</td><td>3승</td>
            <td>13-1-9</td><td>12-0-8</td>
          </tr>
        """
    return f"""
      <input type="hidden" name="__VIEWSTATE" value="fixture-state" />
      <select name="{season_field}">
        <option{selected_2026} value="2026">2026</option>
        <option{selected_2025} value="2025">2025</option>
      </select>
      <input type="hidden" name="{source_season_field}" value="{source_season}" />
      <input type="hidden" name="{source_date_field}" value="{source_date}" />
      <table><tbody>{row}</tbody></table>
    """


def test_standings_crawler_posts_requested_season_and_preserves_streak() -> None:
    crawler = _HtmlStandingsCrawler(
        _standings_html(
            selected_season=2026,
            source_season=2026,
            source_date="20261231",
        ),
        _standings_html(
            selected_season=2025,
            source_season=2025,
            source_date="20251231",
        ),
    )

    payload = crawler.get_standings(2025)
    standing = payload["standings"][0]

    assert crawler.post_data is not None
    assert crawler.post_data[StandingsCrawler._SEASON_FIELD] == "2025"
    assert crawler.post_data["__EVENTTARGET"] == StandingsCrawler._SEASON_FIELD
    assert crawler.post_data["__VIEWSTATE"] == "fixture-state"
    assert standing["teamId"] == "LG"
    assert standing["last10"] == "7승0무3패"
    assert standing["streak"] == "3승"
    assert payload["season"] == 2025
    assert payload["sourceSeason"] == 2025
    assert payload["sourceDate"] == "2025-12-31"
    assert payload["updatedAt"] == "2025-12-31"


def test_standings_crawler_rejects_source_season_mismatch() -> None:
    crawler = _HtmlStandingsCrawler(
        _standings_html(
            selected_season=2026,
            source_season=2026,
            source_date="20261231",
        ),
        _standings_html(
            selected_season=2026,
            source_season=2026,
            source_date="20261231",
        ),
    )

    with pytest.raises(ValueError, match="season mismatch"):
        crawler.get_standings(2025)


def test_standings_crawler_rejects_source_date_from_another_season() -> None:
    crawler = _HtmlStandingsCrawler(
        _standings_html(
            selected_season=2026,
            source_season=2026,
            source_date="20261231",
        ),
        _standings_html(
            selected_season=2025,
            source_season=2025,
            source_date="20261231",
        ),
    )

    with pytest.raises(ValueError, match="source date mismatch"):
        crawler.get_standings(2025)


def test_standings_crawler_rejects_empty_table() -> None:
    crawler = _HtmlStandingsCrawler(
        _standings_html(
            selected_season=2026,
            source_season=2026,
            source_date="20261231",
        ),
        _standings_html(
            selected_season=2025,
            source_season=2025,
            source_date="20251231",
            include_rows=False,
        ),
    )

    with pytest.raises(ValueError, match="response is empty"):
        crawler.get_standings(2025)
