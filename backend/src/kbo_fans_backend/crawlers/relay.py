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
        pitcher_box = soup.select_one(".playerBox.awayBox .player-info-wrap")
        batter_box = soup.select_one(".playerBox.homeBox .player-info-wrap")
        if present is None or players is None:
            return None

        count_texts = [strong.get_text(" ", strip=True) for strong in present.select("strong")]
        inning_text = count_texts[0] if len(count_texts) > 0 else ""
        count_text = count_texts[1] if len(count_texts) > 1 else ""
        runner_names = self._parse_runner_names(soup)
        base_state = self._parse_base_state(
            present.select_one("img")
        ) or self._base_state_from_runner_names(runner_names)

        pitcher = self._player_text(players.select_one("li.pitcher"))
        batter = self._player_text(players.select_one("li.supervision"))
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
            },
            "pitcher": {
                "name": pitcher or pitcher_meta["name"],
                "number": pitcher_meta["number"],
                "hand": pitcher_meta["hand"],
                "pitchCount": pitcher_meta["pitch_count"],
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
            }

        number_text = RelayCrawler._player_text(element.select_one(".no"))
        hand_text = ""
        who = element.select_one(".who")
        if who is not None:
            spans = who.select("span")
            if spans:
                hand_text = RelayCrawler._normalize_text(
                    spans[-1].get_text(" ", strip=True)
                ).strip("()")

        today_text = RelayCrawler._player_text(element.select_one(".today span"))
        pitch_count_match = re.search(r"(\d+)투구", today_text)

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
            "recent": today_text if not pitch_count_match else "",
        }

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
