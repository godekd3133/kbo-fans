from kbo_fans_backend.crawlers.relay import RelayCrawler


def test_parse_current_at_bat_from_live_text_view() -> None:
    html = """
    <p class="present">
      <span class="date">2026-03-29 [경기종료]</span>
      <span class="base">
        <strong>9회 말</strong>
        <strong>1-1 3out</strong>
      </span>
    </p>
    <div class="playerName">
      <ul>
        <li class="pitcher">김원중</li>
        <li class="supervision">김지찬</li>
        <li class="typing2">박세혁</li>
      </ul>
    </div>
    """

    current_at_bat = RelayCrawler()._parse_current_at_bat(html)

    assert current_at_bat == {
        "batter": {"name": "김지찬", "number": 0, "hand": ""},
        "pitcher": {"name": "김원중", "number": 0, "hand": "", "pitchCount": 0},
        "ballCount": {"balls": 1, "strikes": 1, "outs": 3},
        "inningText": "9회 말",
    }
