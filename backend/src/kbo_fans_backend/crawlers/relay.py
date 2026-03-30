from __future__ import annotations

import re
from typing import Any, Optional

from bs4 import BeautifulSoup

from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.crawlers.base import BaseCrawler


class RelayCrawler(BaseCrawler):
    """Fetches play-by-play relay data from KBO live text pages."""

    def __init__(self) -> None:
        super().__init__()
        settings = get_settings()
        self.user_id = settings.kbo_relay_user_id
        self.password = settings.kbo_relay_password
        self._logged_in = False

    def get_relay(self, game_id: str) -> dict[str, Any]:
        self._ensure_logged_in()
        self._fetch_live_text_page(game_id)
        view2_html = self._post_live_text_view("LiveTextView2.aspx", game_id)

        return {
            "gameId": game_id,
            "currentAtBat": None,
            "relayItems": self._parse_relay_items(view2_html),
        }

    def _ensure_logged_in(self) -> None:
        if self._logged_in:
            return
        if not self.user_id or not self.password:
            raise RuntimeError("KBO relay credentials are not configured.")

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

    @staticmethod
    def _normalize_text(text: str) -> str:
        text = re.sub(r"\s+", " ", text).strip()
        return text

    @staticmethod
    def _classify_event(text: str) -> tuple[str, bool]:
        if "경기종료" in text:
            return "GAME_END", False
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
