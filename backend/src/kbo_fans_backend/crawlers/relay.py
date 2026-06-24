from __future__ import annotations

import logging
import re
from typing import Any, Optional

from bs4 import BeautifulSoup

from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.crawlers.base import BaseCrawler

logger = logging.getLogger(__name__)


class RelayCrawler(BaseCrawler):
    """Fetches play-by-play relay data from KBO live text pages."""

    _KBO_BASE_URL = "https://www.koreabaseball.com"

    def __init__(self) -> None:
        super().__init__()
        settings = get_settings()
        self.user_id = settings.kbo_relay_user_id
        self.password = settings.kbo_relay_password
        self._logged_in = False
        self._login_attempts = 0

    def get_relay(self, game_id: str) -> dict[str, Any]:
        last_error: Optional[Exception] = None
        for attempt in range(2):
            try:
                self._ensure_logged_in(force=attempt > 0)
                self._fetch_live_text_page(game_id)
                view2_html = self._post_live_text_view("LiveTextView2.aspx", game_id)
                self._assert_valid_relay_response(view2_html, "LiveTextView2")

                return {
                    "gameId": game_id,
                    "currentAtBat": self._parse_current_at_bat(view2_html),
                    "relayItems": self._parse_relay_items(view2_html),
                }
            except Exception as exc:
                last_error = exc
                logger.warning(
                    "Relay fetch failed for %s on attempt %s: %s",
                    game_id,
                    attempt + 1,
                    exc,
                )
                self._reset_login_state()

        assert last_error is not None
        raise last_error

    def _ensure_logged_in(self, force: bool = False) -> None:
        if self._logged_in and not force:
            return
        if not self.user_id or not self.password:
            raise RuntimeError("KBO relay credentials are not configured.")

        if force:
            self._reset_login_state()

        login_page = self.session.get(f"{self.base_url}/Member/Login.aspx", timeout=self.timeout)
        login_page.raise_for_status()

        def _field(name: str) -> str:
            match = re.search(r'name="%s"[^>]*value="([^"]*)"' % re.escape(name), login_page.text)
            return match.group(1) if match else ""

        response = self.session.post(
            f"{self.base_url}/Member/Login.aspx",
            data={
                "__EVENTTARGET": "",
                "__EVENTARGUMENT": "",
                "__LASTFOCUS": "",
                "__VIEWSTATE": _field("__VIEWSTATE"),
                "__VIEWSTATEGENERATOR": _field("__VIEWSTATEGENERATOR"),
                "__EVENTVALIDATION": _field("__EVENTVALIDATION"),
                "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$txtUserId": self.user_id,
                "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$txtPassWord": self.password,
                "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$btnLogin.x": "42",
                "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$btnLogin.y": "16",
                "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$hdUrl": "",
            },
            timeout=self.timeout,
            allow_redirects=True,
        )
        response.raise_for_status()

        if "로그아웃" not in response.text and "LogOut.aspx" not in response.text:
            raise RuntimeError("KBO relay login failed.")

        self._logged_in = True
        self._login_attempts += 1
        logger.info("KBO relay login succeeded (attempt %s).", self._login_attempts)

    def _fetch_live_text_page(self, game_id: str) -> None:
        response = self.session.get(
            f"{self.base_url}/Game/LiveText.aspx",
            params={
                "leagueId": 1,
                "seriesId": 0,
                "gameId": game_id,
                "gyear": game_id[:4],
            },
            timeout=self.timeout,
        )
        response.raise_for_status()

    def _post_live_text_view(self, view_name: str, game_id: str) -> str:
        response = self.session.post(
            f"{self.base_url}/Game/{view_name}",
            data={
                "leagueId": 1,
                "seriesId": 0,
                "gameId": game_id,
                "gyear": game_id[:4],
            },
            headers={"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"},
            timeout=self.timeout,
        )
        response.raise_for_status()
        return response.text

    def _reset_login_state(self) -> None:
        self.session.cookies.clear()
        self._logged_in = False

    @staticmethod
    def _assert_valid_relay_response(html: str, source: str) -> None:
        if "에러 | KBO" in html or "Error/Error.html" in html:
            raise RuntimeError(f"{source} returned KBO error page.")
        if 'id="numCont1"' not in html and 'class="playerBox' not in html:
            raise RuntimeError(f"{source} did not contain expected relay markup.")

    def _parse_relay_items(self, html: str) -> list[dict[str, Any]]:
        soup = BeautifulSoup(html, "html.parser")
        items = []
        seq_no = 1

        for inning in range(1, 11):
            container = soup.select_one(f"#numCont{inning}")
            if container is None:
                continue

            texts = [span.get_text(" ", strip=True) for span in container.select("span")]
            texts = [self._normalize_text(text) for text in texts if self._normalize_text(text)]
            texts.reverse()

            half = "top"
            for text in texts:
                if "회초" in text and "공격" in text:
                    half = "top"
                    items.append(
                        self._build_item(
                            seq_no=seq_no,
                            inning=inning,
                            half=half,
                            text=text,
                            event="INNING_CHANGE",
                            is_scoring=False,
                        )
                    )
                    seq_no += 1
                    continue

                if "회말" in text and "공격" in text:
                    half = "bottom"
                    items.append(
                        self._build_item(
                            seq_no=seq_no,
                            inning=inning,
                            half=half,
                            text=text,
                            event="INNING_CHANGE",
                            is_scoring=False,
                        )
                    )
                    seq_no += 1
                    continue

                event, is_scoring = self._classify_event(text)
                items.append(
                    self._build_item(
                        seq_no=seq_no,
                        inning=inning,
                        half=half,
                        text=text,
                        event=event,
                        is_scoring=is_scoring,
                    )
                )
                seq_no += 1

        return items

    def _parse_current_at_bat(self, html: str) -> Optional[dict[str, Any]]:
        soup = BeautifulSoup(html, "html.parser")
        present = soup.select_one("p.present")
        players = soup.select_one("div.playerName")
        away_box = soup.select_one(".playerBox.awayBox")
        home_box = soup.select_one(".playerBox.homeBox")
        if present is None or players is None:
            return None

        count_texts = [strong.get_text(" ", strip=True) for strong in present.select("strong")]
        inning_text = count_texts[0] if len(count_texts) > 0 else ""
        count_text = count_texts[1] if len(count_texts) > 1 else ""
        runner_names = self._parse_runner_names(soup)
        base_state = self._parse_base_state(
            present.select_one("img")
        ) or self._base_state_from_runner_names(runner_names)

        if "초" in inning_text:
            batter_box = away_box
            pitcher_box = home_box
        else:
            batter_box = home_box
            pitcher_box = away_box

        pitcher = self._player_text(players.select_one("li.pitcher"))
        batter = self._current_batter_name(players)
        balls, strikes, outs = self._parse_count_text(count_text)
        pitcher_meta = self._parse_player_info_box(pitcher_box)
        batter_meta = self._parse_player_info_box(batter_box)

        if not pitcher and not batter and not count_text and not inning_text:
            return None

        return {
            "batter": {
                "name": batter or batter_meta["name"],
                "number": batter_meta["number"],
                "hand": batter_meta["hand"],
                "recent": batter_meta["recent"],
                "average": batter_meta["average"],
                "imageUrl": batter_meta["image_url"],
            },
            "pitcher": {
                "name": pitcher or pitcher_meta["name"],
                "number": pitcher_meta["number"],
                "hand": pitcher_meta["hand"],
                "pitchCount": pitcher_meta["pitch_count"],
                "era": pitcher_meta["era"],
                "imageUrl": pitcher_meta["image_url"],
            },
            "ballCount": {
                "balls": balls,
                "strikes": strikes,
                "outs": outs,
            },
            "inningText": inning_text,
            "baseState": base_state,
        }

    @staticmethod
    def _normalize_text(text: str) -> str:
        text = re.sub(r"\s+", " ", text).strip()
        return text

    @staticmethod
    def _classify_event(text: str) -> tuple[str, bool]:
        if "경기종료" in text:
            return "GAME_END", False
        if "포일" in text:
            return "PASSED_BALL", "득점" in text or "홈인" in text
        if "득점" in text or "홈인" in text:
            return "RUNS", True
        if "홈런" in text:
            return "HOMERUN", True
        if "볼넷" in text:
            return "WALK", False
        if "삼진" in text:
            return "STRIKEOUT", False
        if "플라이 아웃" in text or "땅볼 아웃" in text or "아웃" in text:
            return "OUT", False
        if "교체" in text:
            return "SUBSTITUTION", False
        if "안타" in text or "1루타" in text or "2루타" in text or "3루타" in text:
            return "HIT", False
        return "PLAY", False

    @staticmethod
    def _build_item(
        *,
        seq_no: int,
        inning: int,
        half: str,
        text: str,
        event: str,
        is_scoring: bool,
    ) -> dict[str, Any]:
        return {
            "seqNo": seq_no,
            "inning": inning,
            "half": half,
            "event": event,
            "isScoring": is_scoring,
            "text": text,
            "pitchSequence": None,
        }

    @staticmethod
    def _player_text(element: Optional[Any]) -> str:
        if element is None:
            return ""
        return RelayCrawler._normalize_text(element.get_text(" ", strip=True))

    @staticmethod
    def _current_batter_name(players: Any) -> str:
        for item in players.select("li"):
            classes = item.get("class") or []
            if any(str(class_name).startswith("supervision") for class_name in classes):
                return RelayCrawler._player_text(item)
        return ""

    @staticmethod
    def _parse_count_text(text: str) -> tuple[int, int, int]:
        match = re.search(r"(\d+)-(\d+)\s+(\d+)out", text)
        if not match:
            return 0, 0, 0
        balls = int(match.group(1))
        strikes = int(match.group(2))
        outs = int(match.group(3))
        return balls, strikes, outs

    @staticmethod
    def _parse_player_info_box(element: Optional[Any]) -> dict[str, Any]:
        if element is None:
            return {
                "name": "",
                "number": 0,
                "hand": "",
                "pitch_count": 0,
                "recent": "",
                "average": "",
                "era": "",
                "image_url": "",
            }

        player_wrap = element.select_one(".player-info-wrap") or element
        number_text = RelayCrawler._player_text(player_wrap.select_one(".no"))
        hand_text = ""
        who = player_wrap.select_one(".who")
        if who is not None:
            spans = who.select("span")
            if spans:
                hand_text = RelayCrawler._normalize_text(spans[-1].get_text(" ", strip=True)).strip(
                    "()"
                )

        today_text = RelayCrawler._player_text(player_wrap.select_one(".today span"))
        pitch_count_match = re.search(r"(\d+)투구", today_text)
        image = player_wrap.select_one(".player-img img.pic") or player_wrap.select_one(
            "img.pic"
        )
        image_src = str(image.get("src") or "") if image is not None else ""

        name = number_text
        number = 0
        if number_text.startswith("No."):
            match = re.match(r"No\.(\d+)\s+(.+)", number_text)
            if match:
                number = int(match.group(1))
                name = match.group(2).strip()

        return {
            "name": name,
            "number": number,
            "hand": hand_text,
            "pitch_count": int(pitch_count_match.group(1)) if pitch_count_match else 0,
            "recent": "" if pitch_count_match or today_text == "-" else today_text,
            "average": RelayCrawler._parse_live_batting_average(element, today_text),
            "era": RelayCrawler._parse_season_stat(element, ("ERA", "평균자책", "평균자책점")),
            "image_url": RelayCrawler._normalize_player_image_url(image_src),
        }

    @staticmethod
    def _normalize_player_image_url(src: str) -> str:
        value = src.strip()
        if not value:
            return ""
        lower = value.lower()
        if any(
            marker in lower
            for marker in (
                "noimage",
                "no_img",
                "noimg",
                "no_photo",
                "player_no",
                "playernone",
            )
        ):
            return ""
        if value.startswith("//"):
            return f"https:{value}"
        if value.startswith("/"):
            return f"{RelayCrawler._KBO_BASE_URL}{value}"
        return value

    @staticmethod
    def _parse_live_batting_average(element: Any, today_text: str) -> str:
        season_average = RelayCrawler._parse_season_stat(element, ("타율", "AVG"))
        season_at_bats = RelayCrawler._parse_season_stat_int(element, ("타수", "AB"))
        season_hits = RelayCrawler._parse_season_stat_int(element, ("안타", "H"))
        today_at_bats, today_hits = RelayCrawler._parse_today_batting_line(today_text)

        if (
            season_at_bats is None
            or season_hits is None
            or today_at_bats <= 0
            or season_at_bats + today_at_bats <= 0
        ):
            return season_average

        average = (season_hits + today_hits) / (season_at_bats + today_at_bats)
        return f"{average:.3f}"

    @staticmethod
    def _parse_season_stat(element: Any, header_candidates: tuple[str, ...]) -> str:
        for table in element.select("table"):
            headers = [
                RelayCrawler._normalize_text(header.get_text(" ", strip=True))
                for header in table.select("thead th")
            ]
            stat_index = next(
                (index for index, header in enumerate(headers) if header in header_candidates),
                -1,
            )
            if stat_index < 0:
                continue

            for row in table.select("tbody tr"):
                cells = row.find_all(["th", "td"])
                if not cells:
                    continue
                label = RelayCrawler._normalize_text(cells[0].get_text(" ", strip=True))
                if label != "시즌" or stat_index >= len(cells):
                    continue
                value = RelayCrawler._normalize_text(cells[stat_index].get_text(" ", strip=True))
                if value and value != "-":
                    return value
        return ""

    @staticmethod
    def _parse_season_stat_int(element: Any, header_candidates: tuple[str, ...]) -> Optional[int]:
        value = RelayCrawler._parse_season_stat(element, header_candidates)
        if not value:
            return None
        match = re.search(r"\d+", value.replace(",", ""))
        if not match:
            return None
        return int(match.group(0))

    @staticmethod
    def _parse_today_batting_line(today_text: str) -> tuple[int, int]:
        at_bats = 0
        hits = 0
        for raw_result in today_text.split("|"):
            result = RelayCrawler._normalize_text(raw_result)
            if not result or result == "-":
                continue
            if RelayCrawler._is_non_at_bat_result(result):
                continue
            if RelayCrawler._is_hit_result(result):
                at_bats += 1
                hits += 1
                continue
            if RelayCrawler._is_at_bat_result(result):
                at_bats += 1
        return at_bats, hits

    @staticmethod
    def _is_non_at_bat_result(result: str) -> bool:
        return any(
            keyword in result
            for keyword in (
                "4구",
                "볼넷",
                "고의",
                "사구",
                "몸에 맞",
                "희생",
                "희비",
                "희번",
                "타격방해",
                "포수방해",
            )
        )

    @staticmethod
    def _is_hit_result(result: str) -> bool:
        if any(keyword in result for keyword in ("안타", "1루타", "2루타", "3루타", "홈런")):
            return True
        return bool(re.search(r"(좌|중|우|내야|번트).*(안|홈)$", result))

    @staticmethod
    def _is_at_bat_result(result: str) -> bool:
        if any(
            keyword in result
            for keyword in (
                "삼진",
                "땅볼",
                "플라이",
                "파울플라이",
                "직선타",
                "라인드라이브",
                "병살",
                "실책",
                "야수선택",
                "야선",
                "아웃",
            )
        ):
            return True
        return result.endswith(("땅", "비", "직"))

    @staticmethod
    def _parse_base_state(element: Optional[Any]) -> str:
        if element is None:
            return ""

        src = element.get("src", "")
        match = re.search(r"ground_base(\d+)\.png", src)
        if not match:
            alt = RelayCrawler._normalize_text(element.get("alt", ""))
            return alt if alt != "주자" else ""

        return {
            "0": "주자없음",
            "1": "주자1루",
            "2": "주자2루",
            "3": "주자1,2루",
            "4": "주자3루",
            "5": "주자1,3루",
            "6": "주자2,3루",
            "7": "만루",
        }.get(match.group(1), "")

    @staticmethod
    def _parse_runner_names(soup: BeautifulSoup) -> tuple[str, str, str]:
        def text_from_selectors(selectors: list[str]) -> str:
            for selector in selectors:
                node = soup.select_one(selector)
                if node is None:
                    continue
                text = RelayCrawler._normalize_text(node.get_text(" ", strip=True))
                if text:
                    return text
            return ""

        first = text_from_selectors(
            [
                "#txtBase1",
                "#base1Player",
                ".base1 .name",
                ".runner-first .name",
                ".baseRunner.first",
            ]
        )
        second = text_from_selectors(
            [
                "#txtBase2",
                "#base2Player",
                ".base2 .name",
                ".runner-second .name",
                ".baseRunner.second",
            ]
        )
        third = text_from_selectors(
            [
                "#txtBase3",
                "#base3Player",
                ".base3 .name",
                ".runner-third .name",
                ".baseRunner.third",
            ]
        )
        return first, second, third

    @staticmethod
    def _base_state_from_runner_names(runners: tuple[str, str, str]) -> str:
        first = bool(runners[0])
        second = bool(runners[1])
        third = bool(runners[2])
        if not first and not second and not third:
            return ""
        if first and not second and not third:
            return "주자1루"
        if not first and second and not third:
            return "주자2루"
        if not first and not second and third:
            return "주자3루"
        if first and second and not third:
            return "주자1,2루"
        if first and not second and third:
            return "주자1,3루"
        if not first and second and third:
            return "주자2,3루"
        return "만루"
