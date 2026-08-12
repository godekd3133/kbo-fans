import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import pytest

from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.services.ticketing import TicketingService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date


class _StubScheduleCrawler:
    def get_month_schedule(self, month: str):
        today = current_kbo_date().isoformat()
        return [
            {
                "date": today,
                "gameId": f"{today.replace('-', '')}LGOB0",
                "time": "18:30",
                "awayId": "LG",
                "awayName": "LG",
                "awayScore": None,
                "homeId": "OB",
                "homeName": "두산",
                "homeScore": None,
                "stadium": "잠실",
                "status": "SCHEDULED",
            }
        ]


class _StubMainCrawler:
    def get_kbo_game_list(self, date: str):
        return [
            {
                "G_ID": f"{date.replace('-', '')}LGOB0",
                "G_TM": "18:30",
                "GAME_STATE_SC": "2",
                "T_SCORE_CN": "4",
                "B_SCORE_CN": "2",
                "S_NM": "잠실",
            }
        ]


class _ScheduledZeroMainCrawler:
    def get_kbo_game_list(self, date: str):
        return [
            {
                "G_ID": f"{date.replace('-', '')}LGOB0",
                "G_TM": "18:30",
                "GAME_STATE_SC": "1",
                "T_SCORE_CN": "0",
                "B_SCORE_CN": "0",
                "S_NM": "잠실",
            }
        ]


class _CancelledMainCrawler:
    def get_kbo_game_list(self, date: str):
        return [
            {
                "G_ID": f"{date.replace('-', '')}LGOB0",
                "G_TM": "18:30",
                "GAME_STATE_SC": "4",
                "CANCEL_SC_NM": "우천취소",
                "T_SCORE_CN": "0",
                "B_SCORE_CN": "0",
                "S_NM": "잠실",
            }
        ]


class _FailingScheduleCrawler:
    def get_month_schedule(self, month: str):
        raise RuntimeError("schedule unavailable")


class _FailingMainCrawler:
    def get_kbo_game_list(self, date: str):
        raise RuntimeError("main unavailable")


class _BlockingScheduleCrawler:
    def __init__(self) -> None:
        self.calls = 0
        self.first_started = threading.Event()
        self.release = threading.Event()
        self._lock = threading.Lock()

    def get_month_schedule(self, month: str):
        with self._lock:
            self.calls += 1
            call_number = self.calls
        if call_number == 1:
            self.first_started.set()
            assert self.release.wait(timeout=2)
        return [
            {
                "date": f"{month}-01",
                "gameId": f"{month.replace('-', '')}LGOB0",
                "time": "18:30",
                "awayId": "LG",
                "awayName": "LG",
                "awayScore": None,
                "homeId": "OB",
                "homeName": "두산",
                "homeScore": None,
                "stadium": "잠실",
                "status": "SCHEDULED",
            }
        ]


def test_derive_status_marks_start_pit_as_scheduled() -> None:
    html = (
        "<a href='/Schedule/GameCenter/Main.aspx?"
        "gameDate=20260331&gameId=20260331HTLG0&section=START_PIT'"
        " class='btn2' id='btnPreView'>프리뷰</a>"
    )

    status = ScheduleCrawler._derive_status(html)

    assert status == "SCHEDULED"


def test_derive_lineup_opened_marks_start_pit() -> None:
    html = (
        "<a href='/Schedule/GameCenter/Main.aspx?"
        "gameDate=20260331&gameId=20260331HTLG0&section=START_PIT'"
        " class='btn2' id='btnPreView'>프리뷰</a>"
    )

    assert ScheduleCrawler._derive_lineup_opened(html) is True


def test_derive_status_marks_rain_cancelled() -> None:
    status = ScheduleCrawler._derive_status("", "우천취소")
    label = ScheduleCrawler._derive_status_label(status, "우천취소")

    assert status == "CANCELLED"
    assert label == "우천취소"


def test_parse_play_score_extracts_final_score() -> None:
    play_html = (
        '<span>KT</span><em><span class="win">11</span>'
        '<span>vs</span><span class="lose">7</span></em><span>LG</span>'
    )

    away_score, home_score = ScheduleCrawler._parse_play_score(play_html)

    assert away_score == 11
    assert home_score == 7


def test_ticket_info_is_omitted_for_terminal_schedule_status() -> None:
    service = TicketingService()

    ticket_info = service.build_ticket_info(
        home_team_id="LG",
        game_id="20260328KTLG0",
        start_time="14:00",
        status="FINAL",
    )

    assert ticket_info is None


def test_ticket_info_open_at_is_timezone_aware_kbo_time() -> None:
    service = TicketingService()

    ticket_info = service.build_ticket_info(
        home_team_id="LG",
        game_id="20260720KTLG0",
        start_time="18:30",
        status="SCHEDULED",
    )

    assert ticket_info is not None
    assert ticket_info["openAt"] == "2026-07-13T11:00:00+09:00"


def test_ticket_info_keeps_schedule_available_when_datetime_is_malformed() -> None:
    service = TicketingService()

    ticket_info = service.build_ticket_info(
        home_team_id="LG",
        game_id="invalid-date-LG",
        start_time="18:30",
        status="SCHEDULED",
    )

    assert ticket_info is not None
    assert ticket_info["openAt"] is None


def test_current_day_schedule_status_is_enriched_from_main_game(tmp_path) -> None:
    today = current_kbo_date().isoformat()
    service = ScheduleService(
        schedule_crawler=_StubScheduleCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_month_schedule(today[:7])
    game = payload["days"][0]["games"][0]

    assert game["status"] == "LIVE"
    assert game["awayScore"] == 4
    assert game["homeScore"] == 2


def test_current_day_scheduled_game_keeps_scores_empty_even_when_main_has_zero(
    tmp_path,
) -> None:
    today = current_kbo_date().isoformat()
    service = ScheduleService(
        schedule_crawler=_StubScheduleCrawler(),
        main_crawler=_ScheduledZeroMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_month_schedule(today[:7])
    game = payload["days"][0]["games"][0]

    assert game["status"] == "SCHEDULED"
    assert game["awayScore"] is None
    assert game["homeScore"] is None


def test_current_day_cancelled_game_uses_cancel_label_and_keeps_scores_empty(
    tmp_path,
) -> None:
    today = current_kbo_date().isoformat()
    service = ScheduleService(
        schedule_crawler=_StubScheduleCrawler(),
        main_crawler=_CancelledMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_month_schedule(today[:7])
    game = payload["days"][0]["games"][0]

    assert game["status"] == "CANCELLED"
    assert game["statusLabel"] == "우천취소"
    assert game["awayScore"] is None
    assert game["homeScore"] is None


def test_concurrent_month_schedule_requests_share_one_crawler_call(tmp_path) -> None:
    crawler = _BlockingScheduleCrawler()
    service = ScheduleService(
        schedule_crawler=crawler,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(service.get_month_schedule, "2099-01")
        assert crawler.first_started.wait(timeout=2)
        second = executor.submit(service.get_month_schedule, "2099-01")

        deadline = time.monotonic() + 1
        while crawler.calls < 2 and time.monotonic() < deadline:
            time.sleep(0.01)
        assert crawler.calls == 1

        crawler.release.set()
        assert first.result(timeout=2) == second.result(timeout=2)

    assert crawler.calls == 1


def test_schedule_saves_non_terminal_month_snapshot(tmp_path) -> None:
    today = current_kbo_date().isoformat()
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    service = ScheduleService(
        schedule_crawler=_StubScheduleCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=store,
    )

    payload = service.get_month_schedule(today[:7])

    assert store.load_payload("schedule", today[:7]) == payload


def test_historical_schedule_rejects_snapshot_for_another_month(tmp_path) -> None:
    season = current_kbo_date().year - 1
    month = f"{season}-06"
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save("schedule", month, {"month": f"{season}-05", "days": []})

    service = ScheduleService(
        schedule_crawler=_FailingScheduleCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="schedule unavailable"):
        service.get_month_schedule(month)


def test_current_month_schedule_rejects_old_snapshot_on_failure(tmp_path) -> None:
    today = current_kbo_date().isoformat()
    month = today[:7]
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    _write_snapshot_record(
        tmp_path,
        "schedule",
        month,
        {
            "month": month,
            "days": [
                {
                    "date": today,
                    "games": [
                        {
                            "gameId": f"{today.replace('-', '')}LGOB0",
                            "status": "SCHEDULED",
                            "awayScore": 0,
                            "homeScore": 0,
                        }
                    ],
                }
            ],
        },
    )
    service = ScheduleService(
        schedule_crawler=_FailingScheduleCrawler(),
        main_crawler=_FailingMainCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_month_schedule(month)


def test_current_month_schedule_rejects_fresh_snapshot_on_failure(tmp_path) -> None:
    today = current_kbo_date().isoformat()
    month = today[:7]
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = {
        "month": month,
        "days": [
            {
                "date": today,
                "games": [
                    {
                        "gameId": f"{today.replace('-', '')}LGOB0",
                        "status": "SCHEDULED",
                        "awayScore": None,
                        "homeScore": None,
                    }
                ],
            }
        ],
    }
    store.save("schedule", month, expected)
    service = ScheduleService(
        schedule_crawler=_FailingScheduleCrawler(),
        main_crawler=_FailingMainCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_month_schedule(month)


def _write_snapshot_record(tmp_path, namespace: str, key: str, payload: dict) -> None:
    path = tmp_path / namespace / f"{key}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "savedAt": "2000-01-01T00:00:00+00:00",
                "payload": payload,
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
