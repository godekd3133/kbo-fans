from __future__ import annotations

import json
import re
from html import unescape
from typing import Any, Optional, Union

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags


class BoxscoreCrawler(BaseCrawler):
    """Fetches boxscore data."""

    def __init__(self, relay_crawler: Optional[Any] = None) -> None:
        super().__init__()
        self.relay_crawler = relay_crawler

    def get_boxscore(self, game_id: str) -> dict[str, Any]:
        payload = self._post_json(
            f"{self.base_url}/ws/Schedule.asmx/GetBoxScoreScroll",
            data={
                "leId": 1,
                "srId": 0,
                "seasonId": int(game_id[:4]),
                "gameId": game_id,
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
            },
            breaker_key="kbo_boxscore",
        )
        away_id, home_id = self._derive_team_ids(game_id)

        hitters_payload = payload.get("arrHitter")
        pitchers_payload = payload.get("arrPitcher")
        if not hitters_payload or not pitchers_payload:
            return self._live_context_boxscore(game_id) or self._empty_boxscore(
                game_id, away_id, home_id
            )

        away_hitters = self._parse_hitter_team(hitters_payload[0])
        home_hitters = self._parse_hitter_team(hitters_payload[1])
        away_pitchers = self._parse_pitcher_team(pitchers_payload[0])
        home_pitchers = self._parse_pitcher_team(pitchers_payload[1])
        if not self._has_displayable_records(
            away_hitters["batters"],
            away_pitchers["pitchers"],
        ) and not self._has_displayable_records(
            home_hitters["batters"],
            home_pitchers["pitchers"],
        ):
            return self._live_context_boxscore(game_id) or self._empty_boxscore(
                game_id, away_id, home_id
            )

        return {
            "gameId": game_id,
            "officialAvailable": True,
            "liveContextAvailable": False,
            "away": {
                "teamId": away_id,
                "batters": away_hitters["batters"],
                "pitchers": away_pitchers["pitchers"],
                "totals": {
                    "batting": away_hitters["totals"],
                    "pitching": away_pitchers["totals"],
                },
            },
            "home": {
                "teamId": home_id,
                "batters": home_hitters["batters"],
                "pitchers": home_pitchers["pitchers"],
                "totals": {
                    "batting": home_hitters["totals"],
                    "pitching": home_pitchers["totals"],
                },
            },
        }

    @staticmethod
    def _empty_boxscore(game_id: str, away_id: str, home_id: str) -> dict[str, Any]:
        empty_totals = {
            "batting": {"atBats": 0, "runs": 0, "hits": 0, "rbi": 0},
            "pitching": {
                "innings": "0.0",
                "hits": 0,
                "strikeouts": 0,
                "walks": 0,
                "earnedRuns": 0,
            },
        }
        return {
            "gameId": game_id,
            "officialAvailable": False,
            "liveContextAvailable": False,
            "away": {
                "teamId": away_id,
                "batters": [],
                "pitchers": [],
                "totals": empty_totals,
            },
            "home": {
                "teamId": home_id,
                "batters": [],
                "pitchers": [],
                "totals": empty_totals,
            },
        }

    def _live_context_boxscore(self, game_id: str) -> Optional[dict[str, Any]]:
        main_game = self._main_game_for_game(game_id)
        if not main_game or str(main_game.get("GAME_STATE_SC") or "") != "2":
            return None

        away_id, home_id = self._derive_team_ids(game_id)
        inning_text = self._format_inning(main_game)
        is_top = self._is_top_inning(main_game, inning_text)
        relay_current_at_bat = self._relay_current_at_bat(game_id)
        away_batters: list[dict[str, Any]] = []
        home_batters: list[dict[str, Any]] = []
        away_pitchers: list[dict[str, Any]] = []
        home_pitchers: list[dict[str, Any]] = []

        current_batter = self._clean_name(
            main_game.get("T_P_NM") if is_top else main_game.get("B_P_NM")
        )
        relay_batter = (
            relay_current_at_bat.get("batter", {})
            if isinstance(relay_current_at_bat, dict)
            else {}
        )
        relay_batter_name = self._clean_name(relay_batter.get("name"))
        if not current_batter and relay_batter_name:
            current_batter = relay_batter_name
        current_pitcher = self._clean_name(
            main_game.get("B_P_NM") if is_top else main_game.get("T_P_NM")
        )
        batter_label = f"{inning_text} 현재 타자" if inning_text else "현재 타자"
        pitcher_label = f"{inning_text} 현재 투수" if inning_text else "현재 투수"

        if current_batter:
            at_bats, hits = self._relay_today_batter_stats(
                relay_batter,
                current_batter,
            )
            batter = self._live_batter(
                current_batter,
                batter_label,
                at_bats=at_bats,
                hits=hits,
            )
            if is_top:
                away_batters.append(batter)
            else:
                home_batters.append(batter)

        self._add_live_pitcher(
            away_pitchers,
            self._clean_name(main_game.get("T_PIT_P_NM")),
            "선발 투수",
        )
        self._add_live_pitcher(
            home_pitchers,
            self._clean_name(main_game.get("B_PIT_P_NM")),
            "선발 투수",
        )
        if is_top:
            self._add_live_pitcher(
                home_pitchers, current_pitcher, pitcher_label, decision="LIVE"
            )
        else:
            self._add_live_pitcher(
                away_pitchers, current_pitcher, pitcher_label, decision="LIVE"
            )

        if not self._has_displayable_records(away_batters, away_pitchers) and not (
            self._has_displayable_records(home_batters, home_pitchers)
        ):
            return None

        return {
            "gameId": game_id,
            "officialAvailable": False,
            "liveContextAvailable": True,
            "source": "live_context",
            "away": {
                "teamId": away_id,
                "batters": away_batters,
                "pitchers": away_pitchers,
                "totals": self._empty_totals(),
            },
            "home": {
                "teamId": home_id,
                "batters": home_batters,
                "pitchers": home_pitchers,
                "totals": self._empty_totals(),
            },
        }

    def _relay_current_at_bat(self, game_id: str) -> Optional[dict[str, Any]]:
        relay_crawler = self.relay_crawler
        if relay_crawler is None:
            try:
                from kbo_fans_backend.crawlers.relay import RelayCrawler

                relay_crawler = RelayCrawler()
                self.relay_crawler = relay_crawler
            except Exception:
                return None
        try:
            relay = relay_crawler.get_relay(game_id)
        except Exception:
            return None
        current_at_bat = relay.get("currentAtBat") if isinstance(relay, dict) else None
        return current_at_bat if isinstance(current_at_bat, dict) else None

    @classmethod
    def _relay_today_batter_stats(
        cls,
        relay_batter: dict[str, Any],
        current_batter: str,
    ) -> tuple[int, int]:
        relay_batter_name = cls._clean_name(relay_batter.get("name"))
        if relay_batter_name != cls._clean_name(current_batter):
            return 0, 0
        at_bats = cls._safe_int(relay_batter.get("todayAtBats"))
        hits = cls._safe_int(relay_batter.get("todayHits"))
        return at_bats, hits

    def _main_game_for_game(self, game_id: str) -> Optional[dict[str, Any]]:
        if len(game_id) < 8:
            return None
        date = game_id[:8]
        try:
            payload = self._post_json(
                f"{self.base_url}/ws/Main.asmx/GetKboGameList",
                breaker_key="kbo:main_game_list",
                data={
                    "leId": "1",
                    "srId": self._series_for_date(date),
                    "date": date,
                },
                headers={
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "X-Requested-With": "XMLHttpRequest",
                },
            )
        except Exception:
            return None
        games = payload.get("game") or []
        return next((game for game in games if game.get("G_ID") == game_id), None)

    @staticmethod
    def _empty_totals() -> dict[str, Any]:
        return {
            "batting": {"atBats": 0, "runs": 0, "hits": 0, "rbi": 0},
            "pitching": {
                "innings": "0.0",
                "hits": 0,
                "strikeouts": 0,
                "walks": 0,
                "earnedRuns": 0,
            },
        }

    @staticmethod
    def _live_batter(
        name: str,
        context_label: str,
        *,
        at_bats: int = 0,
        hits: int = 0,
    ) -> dict[str, Any]:
        return {
            "order": 0,
            "position": "타자",
            "name": name,
            "atBats": at_bats,
            "runs": 0,
            "hits": hits,
            "rbi": 0,
            "liveContext": True,
            "liveStatsAvailable": at_bats > 0 or hits > 0,
            "contextLabel": context_label,
        }

    @classmethod
    def _add_live_pitcher(
        cls,
        pitchers: list[dict[str, Any]],
        name: Optional[str],
        context_label: str,
        *,
        decision: Optional[str] = None,
    ) -> None:
        if not name:
            return
        for pitcher in pitchers:
            if cls._clean_name(pitcher.get("name")) != name:
                continue
            if decision:
                pitcher["decision"] = decision
                pitcher["contextLabel"] = context_label
            return
        pitchers.append(
            {
                "name": name,
                "innings": "",
                "hits": 0,
                "strikeouts": 0,
                "walks": 0,
                "earnedRuns": 0,
                "decision": decision,
                "liveContext": True,
                "contextLabel": context_label,
            }
        )

    @staticmethod
    def _clean_name(value: Any) -> Optional[str]:
        text = str(value or "").replace("\xa0", " ").strip()
        return text or None

    @staticmethod
    def _safe_int(value: Any) -> int:
        if value in (None, "", "-", "&nbsp;"):
            return 0
        try:
            return int(str(value).replace(",", ""))
        except (TypeError, ValueError):
            return 0

    @staticmethod
    def _format_inning(main_game: dict[str, Any]) -> str:
        inning = main_game.get("GAME_INN_NO")
        half = main_game.get("GAME_TB_SC_NM")
        if inning and half:
            return f"{inning}회{half}"
        return ""

    @staticmethod
    def _is_top_inning(main_game: dict[str, Any], inning_text: str) -> bool:
        return "회초" in inning_text or str(main_game.get("GAME_TB_SC") or "") == "T"

    @staticmethod
    def _series_for_date(date: str) -> str:
        compact = date.replace("-", "")
        if compact >= "20241026":
            return "0,1,3,4,5,6,7,8,9"
        if compact[:4] >= "2021":
            return "0,1,3,4,5,6,7,9"
        return "0,1,3,4,5,7,9"

    def _parse_hitter_team(self, team_payload: dict[str, Any]) -> dict[str, Any]:
        table1 = json.loads(team_payload["table1"])
        table3 = json.loads(team_payload["table3"])
        stat_tables = [
            json.loads(team_payload[key])
            for key in ("table2", "table3")
            if key in team_payload
        ]

        batters = []
        totals = {"atBats": 0, "runs": 0, "hits": 0, "rbi": 0}
        for row1, row3 in zip(table1["rows"], table3["rows"]):
            left = self._row_values(row1)
            right = self._row_values(row3)
            stat_rows = self._stat_rows_for_index(stat_tables, len(batters))

            at_bats = self._stat_int(
                stat_rows,
                ("타수", "AB"),
                fallback_values=right,
                fallback_index=0,
            )
            hits = self._stat_int(
                stat_rows,
                ("안타", "H"),
                fallback_values=right,
                fallback_index=1,
            )
            rbi = self._stat_int(
                stat_rows,
                ("타점", "RBI"),
                fallback_values=right,
                fallback_index=2,
            )
            runs = self._stat_int(
                stat_rows,
                ("득점", "R"),
                fallback_values=right,
                fallback_index=3,
            )
            batter = {
                "order": self._parse_int(left[0]),
                "position": left[1],
                "name": left[2],
                "atBats": at_bats,
                "hits": hits,
                "rbi": rbi,
                "runs": runs,
            }
            self._put_optional_int(
                batter,
                "plateAppearances",
                self._stat_int(stat_rows, ("타석", "PA")),
            )
            self._put_optional_int(
                batter,
                "doubles",
                self._stat_int(stat_rows, ("2루타", "2B")),
            )
            self._put_optional_int(
                batter,
                "triples",
                self._stat_int(stat_rows, ("3루타", "3B")),
            )
            self._put_optional_int(
                batter,
                "homeRuns",
                self._stat_int(stat_rows, ("홈런", "HR")),
            )
            self._put_optional_int(
                batter,
                "walks",
                self._stat_int(stat_rows, ("볼넷", "BB")),
            )
            self._put_optional_int(
                batter,
                "hitByPitch",
                self._stat_int(stat_rows, ("사구", "HBP")),
            )
            self._put_optional_int(
                batter,
                "strikeouts",
                self._stat_int(stat_rows, ("삼진", "SO", "K")),
            )
            self._put_optional_int(
                batter,
                "stolenBases",
                self._stat_int(stat_rows, ("도루", "SB")),
            )
            batters.append(batter)
            totals["atBats"] += batter["atBats"] or 0
            totals["runs"] += batter["runs"] or 0
            totals["hits"] += batter["hits"] or 0
            totals["rbi"] += batter["rbi"] or 0

        return {"batters": batters, "totals": totals}

    def _parse_pitcher_team(self, team_payload: dict[str, Any]) -> dict[str, Any]:
        table = json.loads(team_payload["table"])
        header_map = self._header_index_map(table)
        pitchers = []
        totals = {
            "innings": "0.0",
            "hits": 0,
            "strikeouts": 0,
            "walks": 0,
            "earnedRuns": 0,
        }
        innings_outs = 0

        for row in table["rows"]:
            cells = self._row_values(row)

            def value(
                headers: tuple[str, ...],
                fallback_index: int,
                row_cells: list[str] = cells,
            ) -> str:
                return self._value_by_headers(
                    row_cells,
                    header_map,
                    headers,
                    fallback_index,
                )

            pitcher = {
                "name": value(("선수명", "선수"), 0),
                "innings": value(("이닝", "IP"), 6),
                "hits": self._parse_int(value(("피안타", "H"), 10)),
                "strikeouts": self._parse_int(value(("삼진", "SO", "K"), 13)),
                "walks": self._parse_int(value(("4사구", "볼넷", "BB"), 12)),
                "earnedRuns": self._parse_int(value(("자책", "ER"), 15)),
                "decision": None
                if value(("결과",), 2) in {"", "-"}
                else unescape(value(("결과",), 2)),
            }
            self._put_optional_int(
                pitcher,
                "pitchCount",
                self._parse_int(value(("투구수", "투구", "NP"), 8)),
            )
            self._put_optional_int(
                pitcher,
                "runs",
                self._parse_int(value(("실점", "R"), 14)),
            )
            if not self._is_displayable_pitcher(pitcher):
                continue
            pitchers.append(pitcher)
            totals["hits"] += pitcher["hits"] or 0
            totals["strikeouts"] += pitcher["strikeouts"] or 0
            totals["walks"] += pitcher["walks"] or 0
            totals["earnedRuns"] += pitcher["earnedRuns"] or 0
            innings_outs += self._innings_to_outs(pitcher["innings"])

        totals["innings"] = self._outs_to_innings(innings_outs)
        return {"pitchers": pitchers, "totals": totals}

    @classmethod
    def _has_displayable_records(
        cls,
        batters: list[dict[str, Any]],
        pitchers: list[dict[str, Any]],
    ) -> bool:
        return any((batter.get("name") or "").strip() for batter in batters) or bool(
            pitchers
        )

    @staticmethod
    def _is_displayable_pitcher(pitcher: dict[str, Any]) -> bool:
        name = (pitcher.get("name") or "").strip()
        if not name:
            return False
        if pitcher.get("liveContext") is True:
            return True
        innings = str(pitcher.get("innings") or "").strip()
        decision = str(pitcher.get("decision") or "").strip().upper()
        return (
            innings not in {"", "0", "0.0"}
            or (pitcher.get("hits") or 0) > 0
            or (pitcher.get("strikeouts") or 0) > 0
            or (pitcher.get("walks") or 0) > 0
            or (pitcher.get("earnedRuns") or 0) > 0
            or decision not in {"", "-", "LIVE", "NONE"}
        )

    @staticmethod
    def _derive_team_ids(game_id: str) -> tuple[str, str]:
        return game_id[8:10], game_id[10:12]

    @staticmethod
    def _parse_int(value: Union[str, int, None]) -> Optional[int]:
        if value in (None, "", "-", "&nbsp;"):
            return None
        if isinstance(value, int):
            return value
        return int(str(value))

    @staticmethod
    def _innings_to_outs(value: str) -> int:
        value = value.strip()
        if not value:
            return 0
        if " " in value:
            whole, frac = value.split(" ", 1)
            return int(whole) * 3 + (2 if "2/3" in frac else 1 if "1/3" in frac else 0)
        if re.fullmatch(r"\d+\.[012]", value):
            whole, remainder = value.split(".", 1)
            return int(whole) * 3 + int(remainder)
        if value.isdigit():
            return int(value) * 3
        return 0

    @staticmethod
    def _outs_to_innings(outs: int) -> str:
        whole = outs // 3
        remainder = outs % 3
        return f"{whole}.{remainder}"

    @staticmethod
    def _row_values(row: dict[str, Any]) -> list[str]:
        return [
            strip_tags(cell["Text"]).replace("\xa0", "").strip()
            for cell in row.get("row", [])
        ]

    def _stat_rows_for_index(
        self,
        tables: list[dict[str, Any]],
        index: int,
    ) -> list[tuple[dict[str, int], list[str]]]:
        rows = []
        for table in tables:
            table_rows = table.get("rows") or []
            if index >= len(table_rows):
                continue
            rows.append((self._header_index_map(table), self._row_values(table_rows[index])))
        return rows

    def _stat_int(
        self,
        stat_rows: list[tuple[dict[str, int], list[str]]],
        headers: tuple[str, ...],
        fallback_values: Optional[list[str]] = None,
        fallback_index: Optional[int] = None,
    ) -> Optional[int]:
        for header_map, values in stat_rows:
            raw = self._value_by_headers(values, header_map, headers)
            parsed = self._parse_int(raw)
            if parsed is not None:
                return parsed
        if fallback_values is not None and fallback_index is not None:
            if 0 <= fallback_index < len(fallback_values):
                return self._parse_int(fallback_values[fallback_index])
        return None

    @staticmethod
    def _put_optional_int(payload: dict[str, Any], key: str, value: Optional[int]) -> None:
        if value is not None:
            payload[key] = value

    @staticmethod
    def _header_index_map(table: dict[str, Any]) -> dict[str, int]:
        headers = table.get("headers") or []
        if not headers:
            return {}
        header_cells = headers[0].get("row", [])
        result = {}
        for index, cell in enumerate(header_cells):
            text = strip_tags(cell["Text"]).replace("\xa0", "").strip()
            if text:
                result[text] = index
        return result

    @staticmethod
    def _value_by_headers(
        values: list[str],
        header_map: dict[str, int],
        headers: tuple[str, ...],
        fallback_index: Optional[int] = None,
    ) -> str:
        for header in headers:
            index = header_map.get(header)
            if index is not None and 0 <= index < len(values):
                return values[index]
        if fallback_index is not None and 0 <= fallback_index < len(values):
            return values[fallback_index]
        return ""
