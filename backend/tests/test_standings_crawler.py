from kbo_fans_backend.crawlers.standings import StandingsCrawler


class _HtmlStandingsCrawler(StandingsCrawler):
    def __init__(self, html: str) -> None:
        super().__init__()
        self._html = html

    def _get_text(self, url: str, *, breaker_key=None, **kwargs) -> str:
        return self._html


def test_standings_crawler_preserves_streak() -> None:
    crawler = _HtmlStandingsCrawler(
        """
        <span class="exp2">(2026.05.20 16:30 기준)</span>
        <table>
          <tbody>
            <tr>
              <td>1</td><td>LG</td><td>43</td><td>25</td><td>17</td><td>1</td>
              <td>0.595</td><td>0</td><td>7승0무3패</td><td>3승</td>
              <td>13-1-9</td><td>12-0-8</td>
            </tr>
          </tbody>
        </table>
        """
    )

    payload = crawler.get_standings(2026)
    standing = payload["standings"][0]

    assert standing["teamId"] == "LG"
    assert standing["last10"] == "7승0무3패"
    assert standing["streak"] == "3승"
    assert payload["updatedAt"] == "2026.05.20 16:30"
