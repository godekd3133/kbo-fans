from __future__ import annotations

import re
from datetime import date, datetime
from typing import Any

from kbo_fans_backend.crawlers.base import BaseCrawler


class StandingsCrawler(BaseCrawler):
    """Fetches season standings from KBO's annual WebForms page."""

    _STANDINGS_PATH = "/Record/TeamRank/TeamRank.aspx"
    _SEASON_FIELD = "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlYear"
    _SOURCE_SEASON_FIELD = "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$hfSearchYear"
    _SOURCE_DATE_FIELD = "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$hfSearchDate"

    def get_standings(self, season: int) -> dict[str, Any]:
        url = f"{self.base_url}{self._STANDINGS_PATH}"
        initial_html = self._get_text(
            url,
            breaker_key="kbo:standings_annual",
        )
        self._require_available_season(initial_html, season)
        html = self._post_text(
            url,
            breaker_key="kbo:standings_annual",
            data=self._build_web_form_payload(
                initial_html,
                overrides={self._SEASON_FIELD: str(season)},
                event_target=self._SEASON_FIELD,
            ),
        )

        source_season = self._source_season(html)
        source_date = self._source_date(html)
        if source_season != season:
            raise ValueError(
                f"KBO standings season mismatch: requested={season}, source={source_season}"
            )
        if source_date.year != season:
            raise ValueError(
                "KBO standings source date mismatch: "
                f"requested={season}, source={source_date.isoformat()}"
            )

        row_matches = re.findall(
            (
                r"<tr>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*"
                r"<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*"
                r"<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*"
                r"<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*</tr>"
            ),
            html,
        )

        standings = []
        for row in row_matches:
            rank, team_name, games, wins, losses, draws, pct, gb, last10, streak, home, away = row
            standings.append(
                {
                    "rank": int(rank),
                    "teamId": self._team_name_to_id(team_name),
                    "teamName": self._team_name_to_full_name(team_name),
                    "wins": int(wins),
                    "losses": int(losses),
                    "draws": int(draws),
                    "pct": pct,
                    "gb": gb,
                    "last10": last10,
                    "streak": streak,
                    "games": int(games),
                    "home": home,
                    "away": away,
                }
            )

        if not standings:
            raise ValueError(f"KBO standings response is empty for season {season}")

        source_date_iso = source_date.isoformat()

        return {
            "season": source_season,
            "sourceSeason": source_season,
            "sourceDate": source_date_iso,
            "standings": standings,
            "updatedAt": source_date_iso,
        }

    @classmethod
    def _require_available_season(cls, html: str, season: int) -> None:
        select_body = cls._season_select_body(html)
        option_values = {
            value
            for option_tag in re.findall(r"<option\b[^>]*>", select_body, re.S | re.I)
            if (value := cls._extract_attr(option_tag, "value")) is not None
        }
        if str(season) not in option_values:
            raise ValueError(f"KBO standings season is unavailable: {season}")

    @classmethod
    def _source_season(cls, html: str) -> int:
        select_body = cls._season_select_body(html)
        selected_value = None
        for option_tag in re.findall(r"<option\b[^>]*>", select_body, re.S | re.I):
            if re.search(r"\bselected(?:\s*=|\s|>)", option_tag, re.I):
                selected_value = cls._extract_attr(option_tag, "value")
                break
        if selected_value is None:
            raise ValueError("KBO standings response has no selected season")

        hidden_value = cls._hidden_field_value(html, cls._SOURCE_SEASON_FIELD)
        if hidden_value != selected_value:
            raise ValueError(
                "KBO standings source season fields disagree: "
                f"selected={selected_value}, hidden={hidden_value}"
            )
        try:
            return int(selected_value)
        except ValueError as error:
            raise ValueError(f"KBO standings source season is invalid: {selected_value}") from error

    @classmethod
    def _source_date(cls, html: str) -> date:
        raw_value = cls._hidden_field_value(html, cls._SOURCE_DATE_FIELD)
        try:
            return datetime.strptime(raw_value.strip(), "%Y%m%d").date()
        except ValueError as error:
            raise ValueError(f"KBO standings source date is invalid: {raw_value}") from error

    @classmethod
    def _season_select_body(cls, html: str) -> str:
        match = re.search(
            r'<select\b[^>]*\bname="%s"[^>]*>(.*?)</select>' % re.escape(cls._SEASON_FIELD),
            html,
            re.S | re.I,
        )
        if match is None:
            raise ValueError("KBO standings response is missing the season selector")
        return match.group(1)

    @classmethod
    def _hidden_field_value(cls, html: str, field_name: str) -> str:
        match = re.search(
            r'<input\b[^>]*\bname="%s"[^>]*>' % re.escape(field_name),
            html,
            re.S | re.I,
        )
        if match is None:
            raise ValueError(f"KBO standings response is missing source field: {field_name}")
        value = cls._extract_attr(match.group(0), "value")
        if value is None:
            raise ValueError(f"KBO standings source field has no value: {field_name}")
        return value

    @staticmethod
    def _team_name_to_id(team_name: str) -> str:
        return {
            "LG": "LG",
            "KT": "KT",
            "SSG": "SK",
            "삼성": "SS",
            "NC": "NC",
            "한화": "HH",
            "롯데": "LT",
            "KIA": "HT",
            "두산": "OB",
            "키움": "WO",
        }.get(team_name, team_name)

    @staticmethod
    def _team_name_to_full_name(team_name: str) -> str:
        return {
            "LG": "LG 트윈스",
            "KT": "KT 위즈",
            "SSG": "SSG 랜더스",
            "삼성": "삼성 라이온즈",
            "NC": "NC 다이노스",
            "한화": "한화 이글스",
            "롯데": "롯데 자이언츠",
            "KIA": "KIA 타이거즈",
            "두산": "두산 베어스",
            "키움": "키움 히어로즈",
        }.get(team_name, team_name)
