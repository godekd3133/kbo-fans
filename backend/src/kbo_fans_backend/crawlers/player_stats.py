from __future__ import annotations

import concurrent.futures
import re
from html import unescape
from typing import Any, Dict, List, Optional, Sequence, Tuple

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags


class PlayerStatsCrawler(BaseCrawler):
    """Fetches team roster and player detail records from official KBO pages."""

    _REGISTER_URL = "/Player/Register.aspx"
    _REGISTER_ALL_URL = "/Player/RegisterAll.aspx"
    _PLAYER_SEARCH_URL = "https://eng.koreabaseball.com/Teams/PlayerSearch.aspx"
    _HITTER_DETAIL_URL = "/Record/Player/HitterDetail/Basic.aspx?playerId={player_id}"
    _PITCHER_DETAIL_URL = "/Record/Player/PitcherDetail/Basic.aspx?playerId={player_id}"
    _HITTER_TOTAL_URL = "/Record/Player/HitterDetail/Total.aspx?playerId={player_id}"
    _PITCHER_TOTAL_URL = "/Record/Player/PitcherDetail/Total.aspx?playerId={player_id}"
    _PLAYER_IMAGE_URL = "https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle/2026/{player_id}.jpg"
    _TEAM_SEARCH_CODE_MAP = {
        "LG": "lg",
        "KT": "kt",
        "SK": "sk",
        "SS": "ss",
        "NC": "nc",
        "HH": "hh",
        "LT": "lt",
        "HT": "ht",
        "OB": "ob",
        "WO": "wo",
    }
    _REGISTER_TEAM_NAME_MAP = {
        "LG": "LG",
        "KT": "KT",
        "SK": "SSG",
        "SS": "삼성",
        "NC": "NC",
        "HH": "한화",
        "LT": "롯데",
        "HT": "KIA",
        "OB": "두산",
        "WO": "키움",
    }
    _POSITION_GROUPS = ("1", "2", "3,4,5,6", "7,8,9")

    def get_team_players(self, team_id: str, season: int) -> List[Dict[str, Any]]:
        entry_keys = self._parse_register_all_entries(team_id)
        players = []
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=len(self._POSITION_GROUPS)
        ) as executor:
            grouped_players = executor.map(
                lambda group: self._fetch_player_search_rows(team_id, group),
                self._POSITION_GROUPS,
            )
            for group_players in grouped_players:
                players.extend(group_players)

        def enrich(player: Dict[str, Any]) -> Dict[str, Any]:
            detail = self.get_player_detail(
                player_id=player["id"],
                player_type=player["playerType"],
                season=season,
                base_profile=player,
                include_recent=False,
            )
            roster_key = (detail.get("name", ""), detail.get("number", 0))
            if roster_key in entry_keys:
                detail["rosterGroup"] = "entry"
                detail["status"] = "available"
                detail["statusNote"] = None
            else:
                detail["rosterGroup"] = "reserve"
                detail["status"] = "inactive"
                detail["statusNote"] = "엔트리 제외"
            return detail

        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
            return list(executor.map(enrich, players))

    def get_player_detail(
        self,
        player_id: str,
        player_type: Optional[str],
        season: int,
        base_profile: Optional[Dict[str, Any]] = None,
        include_recent: bool = True,
    ) -> Dict[str, Any]:
        if player_type is None:
            player_type = self._guess_player_type(player_id)

        detail_url = self._detail_url(player_id, player_type)
        response = self.session.get(f"{self.base_url}{detail_url}", timeout=self.timeout)
        response.raise_for_status()
        html = response.text
        total_html = self.session.get(
            f"{self.base_url}{self._total_url(player_id, player_type)}", timeout=self.timeout
        ).text

        profile = dict(base_profile or {})
        profile.update(self._parse_profile(html, player_id, player_type))

        season_stats = self._parse_season_stats(total_html, season)
        current_season = self._extract_current_season(html)
        recent_games = self._parse_recent_games(
            html,
            include_recent=include_recent and season == current_season,
            player_type=player_type,
        )

        profile["season"] = season
        profile["seasonStats"] = self._build_season_stat_list(player_type, season_stats)
        profile["highlights"] = self._build_highlights(player_type, season_stats)
        profile["recentGames"] = recent_games
        profile["headlineStat"] = self._build_headline(player_type, season_stats)
        profile["secondaryStat"] = self._build_secondary(player_type, season_stats)
        profile["sortMetrics"] = self._build_sort_metrics(player_type, season_stats)
        return profile

    def _fetch_register_page(self, team_id: str) -> str:
        response = self.session.get(f"{self.base_url}{self._REGISTER_URL}", timeout=self.timeout)
        response.raise_for_status()
        html = response.text

        payload = {
            "__VIEWSTATE": self._extract_hidden(html, "__VIEWSTATE"),
            "__VIEWSTATEGENERATOR": self._extract_hidden(html, "__VIEWSTATEGENERATOR"),
            "__EVENTVALIDATION": self._extract_hidden(html, "__EVENTVALIDATION"),
            "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$hfSearchTeam": team_id,
            "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$hfSearchDate": self._extract_hidden(
                html, "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$hfSearchDate"
            ),
            "__EVENTTARGET": "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$btnCalendarSelect",
            "__EVENTARGUMENT": "",
        }

        post_response = self.session.post(
            f"{self.base_url}{self._REGISTER_URL}",
            data=payload,
            timeout=self.timeout,
        )
        post_response.raise_for_status()
        return post_response.text

    def _fetch_player_search_rows(self, team_id: str, position_value: str) -> List[Dict[str, Any]]:
        response = self.session.get(self._PLAYER_SEARCH_URL, timeout=self.timeout)
        response.raise_for_status()
        html = response.text

        payload = {
            "__VIEWSTATE": self._extract_hidden(html, "__VIEWSTATE"),
            "__VIEWSTATEGENERATOR": self._extract_hidden(html, "__VIEWSTATEGENERATOR"),
            "__EVENTVALIDATION": self._extract_hidden(html, "__EVENTVALIDATION"),
            "ctl00$ctl00$ctl00$ctl00$cphContainer$cphContainer$cphContent$cphContent$hfTeam": self._TEAM_SEARCH_CODE_MAP.get(
                team_id, team_id.lower()
            ),
            "ctl00$ctl00$ctl00$ctl00$cphContainer$cphContainer$cphContent$cphContent$hfPosition": position_value,
            "__EVENTTARGET": "ctl00$ctl00$ctl00$ctl00$cphContainer$cphContainer$cphContent$cphContent$lbtnSearch",
            "__EVENTARGUMENT": "",
        }
        html = self.session.post(self._PLAYER_SEARCH_URL, data=payload, timeout=self.timeout).text
        rows = re.findall(r"<tr>\s*<th scope=\"row\" title=\"player\">.*?</tr>", html, re.S)
        players: List[Dict[str, Any]] = []
        for row in rows:
            cells = re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", row, re.S)
            if len(cells) < 5:
                continue
            href_match = re.search(
                r'href="/Teams/PlayerInfo(Pitcher|Hitter)/Summary\.aspx\?pcode=(\d+)"',
                cells[0],
            )
            if not href_match:
                continue
            players.append(
                {
                    "id": href_match.group(2),
                    "teamId": team_id,
                    "playerType": "pitcher" if href_match.group(1) == "Pitcher" else "hitter",
                    "nameEn": strip_tags(cells[0]),
                    "number": self._parse_int(strip_tags(cells[1])) or 0,
                    "positionEn": strip_tags(cells[2]),
                    "birthDate": strip_tags(cells[3]),
                    "heightWeight": strip_tags(cells[4]).replace(",", " / "),
                }
            )
        return players

    def _parse_register_all_entries(self, team_id: str) -> set[Tuple[str, int]]:
        html = self.session.get(f"{self.base_url}{self._REGISTER_ALL_URL}", timeout=self.timeout).text
        team_name = self._REGISTER_TEAM_NAME_MAP.get(team_id, team_id)
        row_match = re.search(
            r'<tr>\s*<th scope="row" class="fir">%s</th>(.*?)</tr>' % re.escape(team_name),
            html,
            re.S,
        )
        if not row_match:
            return set()

        cells = re.findall(r"<td[^>]*>(.*?)</td>", row_match.group(1), re.S)
        entry_keys: set[Tuple[str, int]] = set()
        for cell in cells[2:]:
            for item in re.findall(r"<li>(.*?)</li>", cell, re.S):
                match = re.search(r"(.+?)\((\d+)\)", strip_tags(item))
                if match:
                    entry_keys.add((match.group(1).strip(), int(match.group(2))))
        return entry_keys

    @staticmethod
    def _extract_hidden(html: str, name: str) -> str:
        pattern = r'name="%s"[^>]*value="([^"]*)"' % re.escape(name)
        match = re.search(pattern, html)
        return match.group(1) if match else ""

    def _guess_player_type(self, player_id: str) -> str:
        for player_type in ("hitter", "pitcher"):
            detail_url = self._detail_url(player_id, player_type)
            html = self.session.get(f"{self.base_url}{detail_url}", timeout=self.timeout).text
            if "선수명:" in html:
                return player_type
        return "hitter"

    def _detail_url(self, player_id: str, player_type: str) -> str:
        if player_type == "pitcher":
            return self._PITCHER_DETAIL_URL.format(player_id=player_id)
        return self._HITTER_DETAIL_URL.format(player_id=player_id)

    def _total_url(self, player_id: str, player_type: str) -> str:
        if player_type == "pitcher":
            return self._PITCHER_TOTAL_URL.format(player_id=player_id)
        return self._HITTER_TOTAL_URL.format(player_id=player_id)

    def _parse_profile(self, html: str, player_id: str, player_type: str) -> Dict[str, Any]:
        name = self._extract_profile_field(html, "lblName")
        number = self._parse_int(self._extract_profile_field(html, "lblBackNo")) or 0
        birth_date = self._extract_profile_field(html, "lblBirthday")
        position_field = self._extract_profile_field(html, "lblPosition")
        height_weight = self._extract_profile_field(html, "lblHeightWeight").replace("/", " / ")
        career = self._extract_profile_field(html, "lblCareer")

        position = position_field
        handedness = ""
        pos_match = re.match(r"(.+?)\((.+)\)", position_field)
        if pos_match:
            position = pos_match.group(1)
            handedness = pos_match.group(2)

        return {
            "id": player_id,
            "playerType": player_type,
            "imageUrl": self._PLAYER_IMAGE_URL.format(player_id=player_id),
            "name": name,
            "number": number,
            "position": position,
            "roleLabel": position,
            "handedness": handedness,
            "birthDate": birth_date,
            "heightWeight": height_weight,
            "career": career,
        }

    @staticmethod
    def _extract_profile_field(html: str, suffix: str) -> str:
        pattern = r'id="[^"]*%s"[^>]*>(.*?)</span>' % re.escape(suffix)
        match = re.search(pattern, html, re.S)
        return strip_tags(match.group(1)) if match else ""

    def _parse_season_stats(self, html: str, season: int) -> Dict[str, str]:
        match = re.search(
            r"<table[^>]*class=\"tbl tt[^\"]*\"[^>]*>.*?<thead>(.*?)</thead>.*?<tbody>(.*?)</tbody>.*?</table>",
            html,
            re.S,
        )
        if not match:
            return {}

        headers = [strip_tags(cell) for cell in re.findall(r"<th[^>]*>(.*?)</th>", match.group(1), re.S)]
        rows = re.findall(r"<tr>(.*?)</tr>", match.group(2), re.S)
        for row in rows:
            values = [strip_tags(cell) for cell in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
            if not values or values[0] != str(season):
                continue
            if len(values) == len(headers):
                return {header.replace("팀명", "TEAM").strip(): value for header, value in zip(headers, values)}
        return {}

    @staticmethod
    def _extract_current_season(html: str) -> int:
        match = re.search(r"(\d{4})\s*시즌", html)
        return int(match.group(1)) if match else 0

    def _parse_recent_games(
        self, html: str, include_recent: bool, player_type: str
    ) -> List[Dict[str, Any]]:
        if not include_recent:
            return []

        match = re.search(
            r"최근 10경기</h6>.*?<tbody>(.*?)</tbody>",
            html,
            re.S,
        )
        if not match:
            return []

        games: List[Dict[str, Any]] = []
        rows = re.findall(r"<tr>(.*?)</tr>", match.group(1), re.S)
        for row in rows[:5]:
            cells = [strip_tags(cell) for cell in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
            if len(cells) < 3:
                continue
            if player_type == "pitcher":
                summary = "결과 %s · IP %s · SO %s · ER %s" % (
                    cells[2] if len(cells) > 2 else "-",
                    cells[5] if len(cells) > 5 else "-",
                    cells[10] if len(cells) > 10 else "-",
                    cells[12] if len(cells) > 12 else "-",
                )
                score = self._score_pitcher_recent_game(cells)
            else:
                summary = "AVG %s · H %s · HR %s · RBI %s" % (
                    cells[2] if len(cells) > 2 else "-",
                    cells[6] if len(cells) > 6 else "-",
                    cells[9] if len(cells) > 9 else "-",
                    cells[10] if len(cells) > 10 else "-",
                )
                score = self._score_hitter_recent_game(cells)

            games.append(
                {
                    "date": cells[0],
                    "opponent": cells[1],
                    "summary": summary,
                    "score": score,
                }
            )
        return games

    def _score_hitter_recent_game(self, cells: List[str]) -> float:
        avg = self._parse_float(cells[2] if len(cells) > 2 else None) or 0.0
        hits = self._parse_int(cells[6] if len(cells) > 6 else None) or 0
        hr = self._parse_int(cells[9] if len(cells) > 9 else None) or 0
        rbi = self._parse_int(cells[10] if len(cells) > 10 else None) or 0
        return hits * 3 + hr * 6 + rbi * 2 + avg

    def _score_pitcher_recent_game(self, cells: List[str]) -> float:
        result = cells[2] if len(cells) > 2 else ""
        ip = cells[5] if len(cells) > 5 else "0"
        strikeouts = self._parse_int(cells[10] if len(cells) > 10 else None) or 0
        earned_runs = self._parse_int(cells[12] if len(cells) > 12 else None) or 0
        score = self._innings_to_outs(ip) * 0.6 + strikeouts * 1.5 - earned_runs * 3
        if "승" in result or result.upper() == "W":
            score += 3
        if "세" in result or result.upper() == "S":
            score += 2
        if "홀" in result or result.upper() == "H":
            score += 1
        return score

    @staticmethod
    def _innings_to_outs(value: str) -> int:
        try:
            if " " in value:
                whole, frac = value.split(" ", 1)
                return int(whole) * 3 + (2 if "2/3" in frac else 1 if "1/3" in frac else 0)
            if "." in value:
                whole, frac = value.split(".", 1)
                return int(whole) * 3 + int(frac)
            return int(value) * 3
        except Exception:
            return 0

    @staticmethod
    def _build_season_stat_list(player_type: str, stats: Dict[str, str]) -> List[str]:
        if player_type == "pitcher":
            keys = ["ERA", "G", "W", "L", "SV", "HLD", "IP", "SO", "WHIP"]
        else:
            keys = ["AVG", "G", "H", "HR", "RBI", "SB", "OBP", "SLG", "OPS"]
        result = []
        for key in keys:
            value = stats.get(key)
            if value and value != "-":
                result.append(f"{key} {value}")
        return result

    @staticmethod
    def _build_highlights(player_type: str, stats: Dict[str, str]) -> List[str]:
        if player_type == "pitcher":
            highlights = [
                f"ERA {stats['ERA']}" if stats.get("ERA") else None,
                f"WHIP {stats['WHIP']}" if stats.get("WHIP") else None,
                f"{stats['W']}승 {stats['L']}패" if stats.get("W") and stats.get("L") else None,
            ]
        else:
            highlights = [
                f"타율 {stats['AVG']}" if stats.get("AVG") else None,
                f"OPS {stats['OPS']}" if stats.get("OPS") else None,
                f"{stats['HR']}홈런" if stats.get("HR") else None,
            ]
        return [item for item in highlights if item]

    @staticmethod
    def _build_headline(player_type: str, stats: Dict[str, str]) -> str:
        if player_type == "pitcher":
            return "ERA %s" % stats.get("ERA", "-")
        return "타율 %s" % stats.get("AVG", "-")

    @staticmethod
    def _build_secondary(player_type: str, stats: Dict[str, str]) -> str:
        if player_type == "pitcher":
            if stats.get("WHIP"):
                return "WHIP %s" % stats["WHIP"]
            return "%s승 %s패" % (stats.get("W", "0"), stats.get("L", "0"))
        if stats.get("OPS"):
            return "OPS %s" % stats["OPS"]
        return "%s홈런" % stats.get("HR", "0")

    def _build_sort_metrics(self, player_type: str, stats: Dict[str, str]) -> Dict[str, Optional[float]]:
        if player_type == "pitcher":
            return {
                "era": self._parse_float(stats.get("ERA")),
                "whip": self._parse_float(stats.get("WHIP")),
            }
        return {
            "avg": self._parse_float(stats.get("AVG")),
            "ops": self._parse_float(stats.get("OPS")),
        }

    @staticmethod
    def _parse_int(value: Optional[str]) -> Optional[int]:
        if value in (None, "", "-"):
            return None
        return int(str(value).replace(",", ""))

    @staticmethod
    def _parse_float(value: Optional[str]) -> Optional[float]:
        if value in (None, "", "-"):
            return None
        try:
            return float(str(value).replace(",", ""))
        except ValueError:
            return None
