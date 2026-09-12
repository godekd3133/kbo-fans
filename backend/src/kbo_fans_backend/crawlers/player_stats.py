from __future__ import annotations

import concurrent.futures
import re
from contextlib import contextmanager
from typing import Any, Dict, Iterator, List, Optional, Tuple

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags
from kbo_fans_backend.utils.kbo_time import current_kbo_year
from kbo_fans_backend.utils.player_images import kbo_player_image_url
from kbo_fans_backend.utils.ttl_cache import TtlCache


@contextmanager
def _player_stats_executor(
    max_workers: int,
) -> Iterator[concurrent.futures.ThreadPoolExecutor]:
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
    try:
        yield executor
    except BaseException:
        # A failed detail page should not wait for the sibling total page to
        # hit its crawler timeout before the API can expose the failure.
        executor.shutdown(wait=False, cancel_futures=True)
        raise
    else:
        executor.shutdown(wait=True)


class PlayerStatsCrawler(BaseCrawler):
    """Fetches team roster and player detail records from official KBO pages."""

    _PLAYER_TYPE_CACHE_TTL_SECONDS = 300
    _REGISTER_URL = "/Player/Register.aspx"
    _REGISTER_ALL_URL = "/Player/RegisterAll.aspx"
    _PLAYER_SEARCH_URL = "https://eng.koreabaseball.com/Teams/PlayerSearch.aspx"
    _HITTER_DETAIL_URL = "/Record/Player/HitterDetail/Basic.aspx?playerId={player_id}"
    _PITCHER_DETAIL_URL = "/Record/Player/PitcherDetail/Basic.aspx?playerId={player_id}"
    _HITTER_TOTAL_URL = "/Record/Player/HitterDetail/Total.aspx?playerId={player_id}"
    _PITCHER_TOTAL_URL = "/Record/Player/PitcherDetail/Total.aspx?playerId={player_id}"
    _SEASON_FIELD = (
        "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlSeason$ddlSeason"
    )
    _TEAM_FIELD = "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlTeam$ddlTeam"
    _CURRENT_TEAM_STAT_SOURCES = (
        (
            "hitter_basic",
            "/Record/Player/HitterBasic/BasicOld.aspx?sort=HRA_RT",
            "hitter",
            ("AVG", "G", "H", "HR", "RBI", "SB"),
        ),
        (
            "hitter_ops",
            "/Record/Player/HitterBasic/Basic2.aspx?sort=OPS_RT",
            "hitter",
            ("OPS", "SLG", "OBP"),
        ),
        (
            "pitcher",
            "/Record/Player/PitcherBasic/Basic1.aspx?sort=ERA_RT",
            "pitcher",
            ("ERA", "G", "W", "L", "SV", "HLD", "IP", "SO", "WHIP"),
        ),
    )
    _PLAYER_RECORD_LINK_RE = re.compile(
        r'href=["\']/Record/Player/(Hitter|Pitcher)Detail/Basic\.aspx\?playerId=(\d+)',
        re.I,
    )
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
    _TEAM_NAME_TO_ID = {
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
    }
    _POSITION_GROUPS = ("1", "2", "3,4,5,6", "7,8,9")

    def __init__(self) -> None:
        super().__init__()
        self._player_type_cache: TtlCache[str, str] = TtlCache(
            self._PLAYER_TYPE_CACHE_TTL_SECONDS
        )

    def get_team_players(self, team_id: str, season: int) -> List[Dict[str, Any]]:
        players: List[Dict[str, Any]] = []
        entry_keys: set[Tuple[str, int]] = set()
        register_error: Optional[Exception] = None
        with _player_stats_executor(max_workers=2) as executor:
            # The entry list and Korean roster page are independent official
            # reads. Start them together so the primary roster path has only
            # the slower of the two upstream waits on its critical path.
            entry_future = executor.submit(self._parse_register_all_entries, team_id)
            register_future = executor.submit(self._fetch_register_roster_players, team_id)
            for future in concurrent.futures.as_completed((entry_future, register_future)):
                if future is entry_future:
                    entry_keys = future.result()
                    continue
                try:
                    players = future.result()
                except Exception as error:
                    # Preserve the previous search-first fallback when the
                    # Korean roster endpoint itself is unavailable.
                    register_error = error

        if not players:
            grouped_players: Dict[int, List[Dict[str, Any]]] = {}
            with _player_stats_executor(max_workers=len(self._POSITION_GROUPS)) as executor:
                # The English form remains a compatibility fallback for a
                # roster page that parses empty or changes its markup.
                search_futures = {
                    executor.submit(self._fetch_player_search_rows, team_id, group): index
                    for index, group in enumerate(self._POSITION_GROUPS)
                }
                for future in concurrent.futures.as_completed(search_futures):
                    grouped_players[search_futures[future]] = future.result()

            for index in range(len(self._POSITION_GROUPS)):
                players.extend(grouped_players[index])
            if not players and register_error is not None:
                raise register_error

        # A non-empty Korean roster is authoritative for the current list, so
        # do not spend eight extra requests on the known-empty English form.
        self._remember_player_types(players)
        bulk_stats: Optional[Dict[str, Dict[str, str]]] = None
        if (
            season == current_kbo_year()
            and players
            and entry_keys
            and not any(self._needs_profile_enrichment(player) for player in players)
        ):
            bulk_stats = self._try_fetch_current_team_stats_by_player(team_id, season)

        profile_futures = {}
        total_futures = {}
        with _player_stats_executor(max_workers=6) as executor:
            for index, player in enumerate(players):
                if self._needs_profile_enrichment(player):
                    profile_futures[index] = executor.submit(
                        self._fetch_player_profile_summary,
                        player_id=player["id"],
                        player_type=player["playerType"],
                        season=season,
                    )
                initial_roster_key = (player.get("name", ""), player.get("number", 0))
                if initial_roster_key in entry_keys and (
                    bulk_stats is None or player["id"] not in bulk_stats
                ):
                    # The profile and total pages are independent GETs. Submit
                    # them together while retaining the existing six-request
                    # worker ceiling for the whole player enrichment batch.
                    total_futures[index] = executor.submit(
                        self._fetch_player_total_stats,
                        player_id=player["id"],
                        player_type=player["playerType"],
                        season=season,
                    )

            enriched_players = []
            for index, player in enumerate(players):
                profile_future = profile_futures.get(index)
                if profile_future is not None:
                    try:
                        profile_summary = profile_future.result()
                        player = {**player, **profile_summary}
                    except Exception:
                        pass

                roster_key = (player.get("name", ""), player.get("number", 0))
                is_entry = roster_key in entry_keys
                if not is_entry:
                    enriched_players.append(
                        self._build_player_summary(
                            player=player,
                            season=season,
                            season_stats={},
                            roster_group="reserve",
                            status="inactive",
                            status_note="엔트리 제외",
                        )
                    )
                    continue

                try:
                    if index in total_futures:
                        season_stats = total_futures[index].result()
                    elif bulk_stats is not None:
                        season_stats = bulk_stats.get(player["id"], {})
                    else:
                        # Preserve the old edge-case behavior if profile
                        # parsing changes a reserve row into an entry row.
                        season_stats = self._fetch_player_total_stats(
                            player_id=player["id"],
                            player_type=player["playerType"],
                            season=season,
                        )
                except Exception:
                    season_stats = {}

                enriched_players.append(
                    self._build_player_summary(
                        player=player,
                        season=season,
                        season_stats=season_stats,
                        roster_group="entry",
                        status="available",
                        status_note=None,
                    )
                )
            return enriched_players

    @staticmethod
    def _needs_profile_enrichment(player: Dict[str, Any]) -> bool:
        # The Korean Register page already contains the localized list fields.
        # Profile GETs are still required for English-search fallback rows,
        # which do not carry role/handedness metadata.
        return any(
            not str(player.get(field) or "").strip()
            for field in ("name", "roleLabel", "handedness", "birthDate", "heightWeight")
        )

    def _try_fetch_current_team_stats_by_player(
        self,
        team_id: str,
        season: int,
    ) -> Optional[Dict[str, Dict[str, str]]]:
        try:
            return self._fetch_current_team_stats_by_player(team_id, season)
        except Exception:
            # A bulk page is an optimization, not a new failure mode. Fall
            # back to the established per-player Total.aspx path if its
            # markup, filter, or upstream request is unavailable.
            return None

    def _fetch_current_team_stats_by_player(
        self,
        team_id: str,
        season: int,
    ) -> Dict[str, Dict[str, str]]:
        page_stats: Dict[str, Dict[str, Dict[str, str]]] = {}
        with _player_stats_executor(max_workers=len(self._CURRENT_TEAM_STAT_SOURCES)) as executor:
            futures = {
                executor.submit(
                    self._fetch_current_team_stats_page,
                    source_name,
                    path,
                    player_type,
                    required_fields,
                    team_id,
                    season,
                ): source_name
                for source_name, path, player_type, required_fields in (
                    self._CURRENT_TEAM_STAT_SOURCES
                )
            }
            for future in concurrent.futures.as_completed(futures):
                page_stats[futures[future]] = future.result()

        merged: Dict[str, Dict[str, str]] = {}
        for stats_by_player in page_stats.values():
            for player_id, stats in stats_by_player.items():
                merged.setdefault(player_id, {}).update(stats)
        return merged

    def _fetch_current_team_stats_page(
        self,
        source_name: str,
        path: str,
        player_type: str,
        required_fields: Tuple[str, ...],
        team_id: str,
        season: int,
    ) -> Dict[str, Dict[str, str]]:
        url = f"{self.base_url}{path}"
        html = self._get_text(
            url,
            breaker_key=f"kbo:team_player_stats:{source_name}",
        )
        if self._selected_form_value(html, self._SEASON_FIELD) != str(season):
            html = self._post_text(
                url,
                breaker_key=f"kbo:team_player_stats:{source_name}",
                data=self._build_web_form_payload(
                    html,
                    overrides={self._SEASON_FIELD: str(season)},
                    event_target=self._SEASON_FIELD,
                ),
            )

        if self._selected_form_value(html, self._TEAM_FIELD) != team_id:
            html = self._post_text(
                url,
                breaker_key=f"kbo:team_player_stats:{source_name}",
                data=self._build_web_form_payload(
                    html,
                    overrides={self._TEAM_FIELD: team_id},
                    event_target=self._TEAM_FIELD,
                ),
            )

        selected_team = self._selected_form_value(html, self._TEAM_FIELD)
        if selected_team != team_id:
            raise RuntimeError(
                f"KBO team player stats filter did not select {team_id}: {selected_team}"
            )
        return self._parse_current_team_stats_page(
            html,
            player_type=player_type,
            team_id=team_id,
            required_fields=required_fields,
        )

    @classmethod
    def _selected_form_value(cls, html: str, field: str) -> Optional[str]:
        match = re.search(
            rf'<select\b[^>]*name="{re.escape(field)}"[^>]*>(.*?)</select>',
            html,
            re.S | re.I,
        )
        if match is None:
            return None
        return cls._selected_option_value(match.group(1))

    def _parse_current_team_stats_page(
        self,
        html: str,
        *,
        player_type: str,
        team_id: str,
        required_fields: Tuple[str, ...],
    ) -> Dict[str, Dict[str, str]]:
        header_match = re.search(r"<thead>(.*?)</thead>", html, re.S | re.I)
        body_match = re.search(r"<tbody>(.*?)</tbody>", html, re.S | re.I)
        if header_match is None or body_match is None:
            raise RuntimeError("KBO team player stats page has no table")

        headers = [
            strip_tags(cell).replace("팀명", "TEAM").strip()
            for cell in re.findall(r"<th[^>]*>(.*?)</th>", header_match.group(1), re.S | re.I)
        ]
        if any(field not in headers for field in required_fields) or "TEAM" not in headers:
            raise RuntimeError("KBO team player stats page has an unexpected schema")

        team_index = headers.index("TEAM")
        stats_by_player: Dict[str, Dict[str, str]] = {}
        for row in re.findall(r"<tr[^>]*>(.*?)</tr>", body_match.group(1), re.S | re.I):
            raw_cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S | re.I)
            if len(raw_cells) != len(headers):
                continue
            player_match = self._PLAYER_RECORD_LINK_RE.search(row)
            if player_match is None or player_match.group(1).lower() != player_type:
                continue
            cells = [strip_tags(cell) for cell in raw_cells]
            if self._TEAM_NAME_TO_ID.get(cells[team_index]) != team_id:
                continue
            stats_by_player[player_match.group(2)] = {
                header: value for header, value in zip(headers, cells)
            }
        return stats_by_player

    def _remember_player_types(self, players: List[Dict[str, Any]]) -> None:
        for player in players:
            player_id = player.get("id")
            player_type = player.get("playerType")
            if (
                isinstance(player_id, str)
                and player_id
                and player_type in ("hitter", "pitcher")
            ):
                self._player_type_cache.set(player_id, player_type)

    def _fetch_player_profile_summary(
        self,
        *,
        player_id: str,
        player_type: str,
        season: int,
    ) -> Dict[str, Any]:
        detail_url = self._detail_url(player_id, player_type)
        html = self._get_text(
            f"{self.base_url}{detail_url}",
            breaker_key="kbo_player_detail",
        )
        return self._parse_profile(html, player_id, player_type, season)

    def get_player_detail(
        self,
        player_id: str,
        player_type: Optional[str],
        season: int,
        base_profile: Optional[Dict[str, Any]] = None,
        include_recent: bool = True,
    ) -> Dict[str, Any]:
        detail_html: Optional[str] = None
        if player_type is None:
            player_type = self._player_type_cache.get(player_id)
            if player_type is None:
                player_type, detail_html = self._guess_player_type_with_html(player_id)
        if player_type in ("hitter", "pitcher"):
            self._player_type_cache.set(player_id, player_type)

        detail_url = self._detail_url(player_id, player_type)
        if detail_html is None:
            with _player_stats_executor(max_workers=2) as executor:
                detail_future = executor.submit(
                    self._get_text,
                    f"{self.base_url}{detail_url}",
                    breaker_key="kbo_player_detail",
                )
                total_future = executor.submit(
                    self._get_text,
                    f"{self.base_url}{self._total_url(player_id, player_type)}",
                    breaker_key="kbo_player_total",
                )
                for future in concurrent.futures.as_completed(
                    (detail_future, total_future)
                ):
                    future.result()
                html = detail_future.result()
                total_html = total_future.result()
        else:
            html = detail_html
            total_html = self._get_text(
                f"{self.base_url}{self._total_url(player_id, player_type)}",
                breaker_key="kbo_player_total",
            )

        profile = dict(base_profile or {})
        profile.update(self._parse_profile(html, player_id, player_type, season))

        season_stats = self._parse_season_stats(total_html, season)
        current_season = self._resolve_recent_games_season(html)
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

    def _fetch_player_total_stats(
        self, player_id: str, player_type: str, season: int
    ) -> Dict[str, str]:
        total_html = self._get_text(
            f"{self.base_url}{self._total_url(player_id, player_type)}",
            breaker_key="kbo_player_total",
        )
        return self._parse_season_stats(total_html, season)

    def _fetch_register_page(self, team_id: str) -> str:
        session = self._session_for_current_thread()
        response = session.get(f"{self.base_url}{self._REGISTER_URL}", timeout=self.timeout)
        response.raise_for_status()
        html = response.text

        search_date_field = (
            "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$hfSearchDate"
        )
        payload = {
            "__VIEWSTATE": self._extract_hidden(html, "__VIEWSTATE"),
            "__VIEWSTATEGENERATOR": self._extract_hidden(html, "__VIEWSTATEGENERATOR"),
            "__EVENTVALIDATION": self._extract_hidden(html, "__EVENTVALIDATION"),
            "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$hfSearchTeam": team_id,
            search_date_field: self._extract_hidden(html, search_date_field),
            "__EVENTTARGET": (
                "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$btnCalendarSelect"
            ),
            "__EVENTARGUMENT": "",
        }

        post_response = session.post(
            f"{self.base_url}{self._REGISTER_URL}",
            data=payload,
            timeout=self.timeout,
        )
        post_response.raise_for_status()
        return post_response.text

    def _fetch_player_search_rows(self, team_id: str, position_value: str) -> List[Dict[str, Any]]:
        session = self._session_for_current_thread()
        response = session.get(self._PLAYER_SEARCH_URL, timeout=self.timeout)
        response.raise_for_status()
        html = response.text

        team_field = (
            "ctl00$ctl00$ctl00$ctl00$cphContainer$cphContainer$cphContent$cphContent$hfTeam"
        )
        position_field = (
            "ctl00$ctl00$ctl00$ctl00$cphContainer$cphContainer$cphContent$cphContent$hfPosition"
        )
        payload = {
            "__VIEWSTATE": self._extract_hidden(html, "__VIEWSTATE"),
            "__VIEWSTATEGENERATOR": self._extract_hidden(html, "__VIEWSTATEGENERATOR"),
            "__EVENTVALIDATION": self._extract_hidden(html, "__EVENTVALIDATION"),
            team_field: self._TEAM_SEARCH_CODE_MAP.get(team_id, team_id.lower()),
            position_field: position_value,
            "__EVENTTARGET": (
                "ctl00$ctl00$ctl00$ctl00$cphContainer$cphContainer$cphContent"
                "$cphContent$lbtnSearch"
            ),
            "__EVENTARGUMENT": "",
        }
        html = session.post(self._PLAYER_SEARCH_URL, data=payload, timeout=self.timeout).text
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
                    "name": strip_tags(cells[0]),
                    "number": self._parse_int(strip_tags(cells[1])) or 0,
                    "position": strip_tags(cells[2]),
                    "birthDate": strip_tags(cells[3]),
                    "heightWeight": strip_tags(cells[4]).replace(",", " / "),
                }
            )
        return players

    def _fetch_register_roster_players(self, team_id: str) -> List[Dict[str, Any]]:
        html = self._fetch_register_page(team_id)
        return self._parse_register_roster_players(html, team_id)

    @staticmethod
    def _parse_register_roster_players(html: str, team_id: str) -> List[Dict[str, Any]]:
        players: List[Dict[str, Any]] = []
        seen_ids: set[str] = set()
        position_groups = {"투수", "포수", "내야수", "외야수"}
        tables = re.findall(
            r'<table\b[^>]*class="[^"]*\btNData\b[^"]*"[^>]*>(.*?)</table>',
            html,
            re.S,
        )

        for table in tables:
            header_match = re.search(r"<thead>(.*?)</thead>", table, re.S)
            if not header_match:
                continue
            headers = [
                strip_tags(cell)
                for cell in re.findall(r"<th[^>]*>(.*?)</th>", header_match.group(1), re.S)
            ]
            if len(headers) < 2:
                continue
            position = headers[1].strip()
            if position not in position_groups:
                continue

            body_match = re.search(r"<tbody>(.*?)</tbody>", table, re.S)
            if not body_match:
                continue
            for row in re.findall(r"<tr[^>]*>(.*?)</tr>", body_match.group(1), re.S):
                cells = re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", row, re.S)
                if len(cells) < 5:
                    continue
                href_match = re.search(
                    r'href=["\'][^"\']*/Record/Player/(Pitcher|Hitter)Detail'
                    r'/Basic\.aspx\?playerId=(\d+)["\']',
                    cells[1],
                )
                if not href_match:
                    continue

                player_id = href_match.group(2)
                name = strip_tags(cells[1])
                if not player_id or not name or player_id in seen_ids:
                    continue
                seen_ids.add(player_id)
                players.append(
                    {
                        "id": player_id,
                        "teamId": team_id,
                        "playerType": (
                            "pitcher" if href_match.group(1) == "Pitcher" else "hitter"
                        ),
                        "name": name,
                        "number": PlayerStatsCrawler._parse_int(strip_tags(cells[0])) or 0,
                        "position": position,
                        "roleLabel": position,
                        "handedness": strip_tags(cells[2]),
                        "birthDate": strip_tags(cells[3]),
                        "heightWeight": strip_tags(cells[4]).replace(",", " / "),
                    }
                )
        return players

    def _parse_register_all_entries(self, team_id: str) -> set[Tuple[str, int]]:
        html = self._session_for_current_thread().get(
            f"{self.base_url}{self._REGISTER_ALL_URL}", timeout=self.timeout
        ).text
        team_name = self._REGISTER_TEAM_NAME_MAP.get(team_id, team_id)
        row_html = None
        for row in re.findall(r"<tr\b[^>]*>(.*?)</tr>", html, re.S):
            header_match = re.search(
                r'<th\b[^>]*scope="row"[^>]*>(.*?)</th>',
                row,
                re.S,
            )
            if header_match and strip_tags(header_match.group(1)).startswith(team_name):
                row_html = row
                break
        if row_html is None:
            return set()

        cells = re.findall(r"<td[^>]*>(.*?)</td>", row_html, re.S)
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
        player_type, _ = self._guess_player_type_with_html(player_id)
        return player_type

    def _guess_player_type_with_html(self, player_id: str) -> Tuple[str, Optional[str]]:
        session = self._session_for_current_thread()
        for player_type in ("hitter", "pitcher"):
            detail_url = self._detail_url(player_id, player_type)
            html = session.get(f"{self.base_url}{detail_url}", timeout=self.timeout).text
            resolved_type = self._resolve_player_type_from_detail_html(html, player_type)
            if resolved_type is not None:
                # Reuse only when the page we fetched matches the requested
                # canonical URL. A hitter URL can occasionally reveal that a
                # player is a pitcher; that HTML must not be treated as the
                # pitcher page without fetching the canonical URL.
                return resolved_type, html if resolved_type == player_type else None
        return "hitter", None

    def _resolve_player_type_from_detail_html(
        self, html: str, requested_player_type: str
    ) -> Optional[str]:
        name = self._extract_profile_field(html, "lblName")
        if not name and "선수명" not in html:
            return None

        position = self._extract_profile_field(html, "lblPosition").strip()
        if position.startswith("투수"):
            return "pitcher"
        return requested_player_type

    def _detail_url(self, player_id: str, player_type: str) -> str:
        if player_type == "pitcher":
            return self._PITCHER_DETAIL_URL.format(player_id=player_id)
        return self._HITTER_DETAIL_URL.format(player_id=player_id)

    def _total_url(self, player_id: str, player_type: str) -> str:
        if player_type == "pitcher":
            return self._PITCHER_TOTAL_URL.format(player_id=player_id)
        return self._HITTER_TOTAL_URL.format(player_id=player_id)

    def _parse_profile(
        self,
        html: str,
        player_id: str,
        player_type: str,
        season: int,
    ) -> Dict[str, Any]:
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
            "imageUrl": kbo_player_image_url(season, player_id),
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
            r"<table[^>]*class=\"tbl tt[^\"]*\"[^>]*>.*?<thead>(.*?)</thead>"
            r".*?<tbody>(.*?)</tbody>.*?</table>",
            html,
            re.S,
        )
        if not match:
            return {}

        headers = [
            strip_tags(cell) for cell in re.findall(r"<th[^>]*>(.*?)</th>", match.group(1), re.S)
        ]
        rows = re.findall(r"<tr>(.*?)</tr>", match.group(2), re.S)
        for row in rows:
            values = [strip_tags(cell) for cell in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
            if not values or values[0] != str(season):
                continue
            if len(values) == len(headers):
                return {
                    header.replace("팀명", "TEAM").strip(): value
                    for header, value in zip(headers, values)
                }
        return {}

    @staticmethod
    def _extract_current_season(html: str) -> int:
        match = re.search(r"(\d{4})\s*시즌", html)
        return int(match.group(1)) if match else 0

    def _resolve_recent_games_season(self, html: str) -> int:
        return self._extract_current_season(html) or current_kbo_year()

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

    def _build_sort_metrics(
        self, player_type: str, stats: Dict[str, str]
    ) -> Dict[str, Optional[float]]:
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

    def _build_player_summary(
        self,
        *,
        player: Dict[str, Any],
        season: int,
        season_stats: Dict[str, str],
        roster_group: str,
        status: str,
        status_note: Optional[str],
    ) -> Dict[str, Any]:
        player_type = player["playerType"]
        position = player.get("position", "")
        return {
            "id": player["id"],
            "teamId": player["teamId"],
            "playerType": player_type,
            "imageUrl": kbo_player_image_url(season, player["id"]),
            "name": player.get("name", ""),
            "number": player.get("number", 0),
            "position": position,
            "roleLabel": player.get("roleLabel", position),
            "handedness": player.get("handedness", ""),
            "birthDate": player.get("birthDate", ""),
            "heightWeight": player.get("heightWeight", ""),
            "career": player.get("career", ""),
            "season": season,
            "seasonStats": self._build_season_stat_list(player_type, season_stats),
            "highlights": self._build_highlights(player_type, season_stats),
            "recentGames": [],
            "headlineStat": self._build_headline(player_type, season_stats),
            "secondaryStat": self._build_secondary(player_type, season_stats),
            "sortMetrics": self._build_sort_metrics(player_type, season_stats),
            "rosterGroup": roster_group,
            "status": status,
            "statusNote": status_note,
        }
