#!/usr/bin/env python3
"""Serve deterministic KBO Fans reference data for local web visual QA."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import List, Optional
from urllib.parse import parse_qs, urlparse


DEFAULT_DATE = "2026-06-19"


def _team_score(
    team_id: str,
    team_name: str,
    short_name: str,
    score: int,
    scores: List[Optional[int]],
    hits: int,
    errors: int,
    balls: int,
) -> dict:
    return {
        "teamId": team_id,
        "teamName": team_name,
        "shortName": short_name,
        "score": score,
        "scores": scores,
        "hits": hits,
        "errors": errors,
        "balls": balls,
    }


def _games() -> List[dict]:
    return [
        {
            "gameId": "20260619SSLG0",
            "status": "LIVE",
            "inning": "7회말",
            "statusLabel": "7회말",
            "stadium": "잠실",
            "startTime": "18:30",
            "away": _team_score(
                "SS",
                "삼성 라이온즈",
                "삼성",
                3,
                [0, 0, 1, 0, 0, 2, 0, None, None],
                7,
                0,
                3,
            ),
            "home": _team_score(
                "LG",
                "LG 트윈스",
                "LG",
                2,
                [0, 1, 0, 0, 1, 0, 0, None, None],
                6,
                1,
                4,
            ),
        },
        {
            "gameId": "20260619OBSK0",
            "status": "SCHEDULED",
            "inning": "",
            "statusLabel": "18:30",
            "stadium": "문학",
            "startTime": "18:30",
            "away": _team_score(
                "OB",
                "두산 베어스",
                "두산",
                0,
                [None] * 9,
                0,
                0,
                0,
            ),
            "home": _team_score(
                "SK",
                "SSG 랜더스",
                "SSG",
                0,
                [None] * 9,
                0,
                0,
                0,
            ),
        },
        {
            "gameId": "20260619KTNC0",
            "status": "SCHEDULED",
            "inning": "",
            "statusLabel": "18:30",
            "stadium": "수원",
            "startTime": "18:30",
            "away": _team_score(
                "KT",
                "KT 위즈",
                "KT",
                0,
                [None] * 9,
                0,
                0,
                0,
            ),
            "home": _team_score(
                "NC",
                "NC 다이노스",
                "NC",
                0,
                [None] * 9,
                0,
                0,
                0,
            ),
        },
    ]


def _standing(
    rank: int,
    team_id: str,
    team_name: str,
    wins: int,
    losses: int,
    draws: int,
    pct: str,
    gb: str,
    streak: str,
) -> dict:
    return {
        "rank": rank,
        "teamId": team_id,
        "teamName": team_name,
        "wins": wins,
        "losses": losses,
        "draws": draws,
        "pct": pct,
        "gb": gb,
        "streak": streak,
    }


def _standings() -> List[dict]:
    return [
        _standing(1, "HT", "KIA 타이거즈", 30, 15, 3, ".667", "-", "W2"),
        _standing(2, "LG", "LG 트윈스", 28, 17, 2, ".622", "2.0", "W4"),
        _standing(3, "SS", "삼성 라이온즈", 24, 21, 1, ".533", "6.0", "2연승"),
        _standing(4, "SK", "SSG 랜더스", 25, 19, 1, ".568", "5.0", "W1"),
        _standing(5, "OB", "두산 베어스", 20, 24, 1, ".455", "9.5", "1승 1패"),
        _standing(6, "KT", "KT 위즈", 22, 22, 2, ".500", "7.5", "L1"),
        _standing(7, "NC", "NC 다이노스", 21, 23, 1, ".477", "8.5", "W1"),
    ]


def _home_payload(date: str, my_team: Optional[str]) -> dict:
    selected_team = my_team or "LG"
    return {
        "date": date,
        "myTeam": selected_team,
        "myTeamBrief": {
            "teamId": selected_team,
            "teamLabel": "LG 트윈스",
            "standing": _standings()[1],
            "todayGameId": "20260619SSLG0",
            "nextGame": None,
            "recentWins": 4,
            "recentLosses": 1,
            "recentDraws": 0,
            "recentGamesCount": 5,
            "recentSummaries": [
                {
                    "gameId": "20260618LGLT0",
                    "result": "승",
                    "opponentName": "롯데",
                    "score": "5:2",
                },
                {
                    "gameId": "20260617LGLT0",
                    "result": "승",
                    "opponentName": "롯데",
                    "score": "6:3",
                },
                {
                    "gameId": "20260616LGLT0",
                    "result": "패",
                    "opponentName": "롯데",
                    "score": "2:4",
                },
                {
                    "gameId": "20260615LGNC0",
                    "result": "승",
                    "opponentName": "NC",
                    "score": "7:1",
                },
                {
                    "gameId": "20260614LGNC0",
                    "result": "승",
                    "opponentName": "NC",
                    "score": "4:3",
                },
            ],
        },
        "kboBrief": {
            "title": "오늘의 KBO 인사이트 팩",
            "subtitle": "지금 볼 장면 8개",
            "items": [
                {
                    "type": "game_flow",
                    "eyebrow": "접전",
                    "title": "삼성 3 : 2 LG",
                    "subtitle": "7회말 · 잠실 · 한 점 승부 구간",
                    "route": "/game/20260619SSLG0",
                    "gameId": "20260619SSLG0",
                    "teamIds": ["SS", "LG"],
                },
                {
                    "type": "standings",
                    "eyebrow": "순위",
                    "title": "2~5위 0.5G 혼전",
                    "subtitle": "LG 4연승 · 상위권 추격 구도",
                    "route": "/standings",
                    "gameId": None,
                    "teamIds": ["HT", "LG"],
                },
                {
                    "type": "record_radar",
                    "eyebrow": "기록",
                    "title": "홈런 레이스",
                    "subtitle": "노시환 17개 · 상위 3명 격차 3개",
                    "route": "/records",
                    "gameId": None,
                    "teamIds": ["HH"],
                },
                {
                    "type": "player_performance",
                    "eyebrow": "승부처",
                    "title": "7회 이후 득점력",
                    "subtitle": "삼성 .318 · LG .250",
                    "route": "/game/20260619SSLG0",
                    "gameId": "20260619SSLG0",
                    "teamIds": ["SS", "LG"],
                },
                {
                    "type": "team_trend",
                    "eyebrow": "상위권",
                    "title": "2~5위 혼전",
                    "subtitle": "2위 한화 · 5위 KT 0.5G 차이",
                    "route": "/standings",
                    "gameId": None,
                    "teamIds": ["HH", "KT"],
                },
                {
                    "type": "pitcher_check",
                    "eyebrow": "선발 체크",
                    "title": "오늘 선발 평균자책",
                    "subtitle": "2.89 · 리그 평균 4.35",
                    "route": "/records",
                    "gameId": None,
                    "teamIds": ["LG"],
                },
                {
                    "type": "big_match",
                    "eyebrow": "오늘 일정",
                    "title": "두산 vs SSG",
                    "subtitle": "18:30 · 문학 · 오늘 2경기 예정",
                    "route": "/game/20260619OBSK0",
                    "gameId": "20260619OBSK0",
                    "teamIds": ["OB", "SK"],
                },
                {
                    "type": "schedule_remaining",
                    "eyebrow": "남은 경기",
                    "title": "SSG vs 두산 외 1경기",
                    "subtitle": "18:30 시작 · 중계 바로가기",
                    "route": "/schedule",
                    "gameId": None,
                    "teamIds": ["SK", "OB"],
                },
            ],
        },
        "quickItems": [
            {
                "eyebrow": "마이팀 경기",
                "title": "LG vs 삼성",
                "subtitle": "잠실 · 7회말 · 승부처 진행 중",
                "route": "/game/20260619SSLG0",
                "teamId": "LG",
                "fallbackLabel": "LG 트윈스",
            },
            {
                "eyebrow": "오늘 일정",
                "title": "오늘 3경기",
                "subtitle": "남은 경기 2 · 18:30 시작",
                "route": "/schedule",
                "teamId": "SK",
                "fallbackLabel": "SSG 랜더스",
            },
            {
                "eyebrow": "순위 변화",
                "title": "2~5위 0.5G",
                "subtitle": "상위권 혼전 · LG 추격권",
                "route": "/standings",
                "teamId": "LG",
                "fallbackLabel": "LG 트윈스",
            },
            {
                "eyebrow": "기록 리더",
                "title": "타율 1위 .354",
                "subtitle": "빅터 레이예스 · 롯데",
                "route": "/records",
                "teamId": "LT",
                "fallbackLabel": "빅터 레이예스",
            },
        ],
        "standingsPreview": _standings(),
    }


class ReferenceApiHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self) -> None:
        self._send_headers(204)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/metrics/client":
            self._send_headers(204)
            return

        self._send_json(
            {
                "success": False,
                "error": {
                    "code": "NOT_FOUND",
                    "message": f"Unsupported reference path: {parsed.path}",
                },
            },
            status=404,
        )

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        date = params.get("date", [DEFAULT_DATE])[0]

        if parsed.path in {"/api/health", "/health"}:
            self._send_json({"success": True, "data": {"status": "ok"}})
            return

        if parsed.path == "/api/scoreboard/home":
            self._send_json(
                {"success": True, "data": {"date": date, "games": _games()}}
            )
            return

        if parsed.path == "/api/scoreboard/compact":
            self._send_json(
                {"success": True, "data": {"date": date, "games": _games()}}
            )
            return

        if parsed.path == "/api/home":
            my_team = params.get("myTeam", [None])[0]
            self._send_json({"success": True, "data": _home_payload(date, my_team)})
            return

        self._send_json(
            {
                "success": False,
                "error": {
                    "code": "NOT_FOUND",
                    "message": f"Unsupported reference path: {parsed.path}",
                },
            },
            status=404,
        )

    def log_message(self, format: str, *args: object) -> None:
        return

    def _send_headers(self, status: int) -> None:
        self.send_response(status)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "content-type")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def _send_json(self, payload: dict, status: int = 200) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "content-type")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8001)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), ReferenceApiHandler)
    print(f"KBO reference API listening on http://{args.host}:{args.port}/api")
    server.serve_forever()


if __name__ == "__main__":
    main()
