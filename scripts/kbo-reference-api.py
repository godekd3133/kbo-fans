#!/usr/bin/env python3
"""Serve deterministic KBO Fans reference data for local web visual QA."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import List, Optional
from urllib.parse import parse_qs, urlparse


DEFAULT_DATE = "2026-06-19"
PLAYER_IMAGE_BASE = "https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle"


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


def _game_by_id(game_id: str) -> Optional[dict]:
    for game in _games():
        if game["gameId"] == game_id:
            return game
    return None


def _batter(
    order: int,
    position: str,
    name: str,
    at_bats: int,
    runs: int,
    hits: int,
    rbi: int,
) -> dict:
    return {
        "order": order,
        "position": position,
        "name": name,
        "atBats": at_bats,
        "runs": runs,
        "hits": hits,
        "rbi": rbi,
    }


def _pitcher(
    name: str,
    innings: str,
    hits: int,
    strikeouts: int,
    walks: int,
    earned_runs: int,
    decision: Optional[str] = None,
) -> dict:
    return {
        "name": name,
        "innings": innings,
        "hits": hits,
        "strikeouts": strikeouts,
        "walks": walks,
        "earnedRuns": earned_runs,
        "decision": decision,
    }


def _boxscore_payload(game_id: str) -> dict:
    return {
        "gameId": game_id,
        "officialAvailable": True,
        "away": {
            "teamId": "SS",
            "batters": [
                _batter(1, "CF", "김지찬", 4, 1, 2, 0),
                _batter(2, "RF", "구자욱", 4, 1, 2, 2),
                _batter(3, "1B", "디아즈", 3, 0, 1, 1),
                _batter(4, "C", "강민호", 3, 0, 1, 0),
                _batter(5, "LF", "이성규", 3, 0, 0, 0),
            ],
            "pitchers": [
                _pitcher("원태인", "6.0", 5, 5, 2, 2, "LIVE"),
                _pitcher("김태훈", "1.0", 1, 1, 0, 0, "H"),
            ],
        },
        "home": {
            "teamId": "LG",
            "batters": [
                _batter(1, "RF", "홍창기", 4, 1, 2, 0),
                _batter(2, "2B", "신민재", 3, 0, 1, 0),
                _batter(3, "3B", "문보경", 3, 1, 2, 1),
                _batter(4, "1B", "오스틴", 3, 0, 1, 1),
                _batter(5, "CF", "박해민", 3, 0, 0, 0),
            ],
            "pitchers": [
                _pitcher("임찬규", "5.2", 6, 4, 2, 3, "LIVE"),
                _pitcher("유영찬", "1.1", 1, 2, 0, 0, None),
            ],
        },
    }


def _player(
    player_id: str,
    team_id: str,
    player_type: str,
    name: str,
    number: int,
    position: str,
    headline_stat: str,
    secondary_stat: str,
) -> dict:
    return {
        "id": player_id,
        "teamId": team_id,
        "playerType": player_type,
        "season": 2026,
        "imageUrl": f"{PLAYER_IMAGE_BASE}/2026/{player_id}.jpg",
        "name": name,
        "number": number,
        "position": position,
        "roleLabel": position,
        "handedness": "",
        "heightWeight": "",
        "birthDate": "",
        "status": "available",
        "rosterGroup": "entry",
        "headlineStat": headline_stat,
        "secondaryStat": secondary_stat,
        "seasonStats": [headline_stat, secondary_stat],
        "highlights": [],
        "recentGames": [],
        "sortMetrics": {},
        "isRetired": False,
    }


def _players(team_id: str) -> List[dict]:
    players_by_team = {
        "SS": [
            _player("50458", "SS", "hitter", "김지찬", 58, "CF", "AVG .312", "최근 5G 8안타"),
            _player("62404", "SS", "hitter", "구자욱", 5, "RF", "OPS .908", "오늘 2타점"),
            _player("54400", "SS", "hitter", "디아즈", 0, "1B", "HR 18", "중심 타선"),
            _player("74540", "SS", "hitter", "강민호", 47, "C", "OPS .801", "안방 리드"),
            _player("66409", "SS", "hitter", "이성규", 13, "LF", "HR 11", "장타 대기"),
            _player("69446", "SS", "pitcher", "원태인", 18, "SP", "ERA 2.89", "6이닝 5K"),
            _player("62360", "SS", "pitcher", "김태훈", 27, "RP", "HLD 9", "무실점"),
        ],
        "LG": [
            _player("66108", "LG", "hitter", "홍창기", 51, "RF", "OBP .421", "멀티히트"),
            _player("65207", "LG", "hitter", "신민재", 4, "2B", "AVG .286", "출루 연결"),
            _player("69102", "LG", "hitter", "문보경", 2, "3B", "AVG .301", "동점권 안타"),
            _player("53123", "LG", "hitter", "오스틴", 23, "1B", "OPS .884", "타점 생산"),
            _player("62415", "LG", "hitter", "박해민", 17, "CF", "SB 12", "수비 범위"),
            _player("61101", "LG", "pitcher", "임찬규", 1, "SP", "ERA 3.41", "5.2이닝"),
            _player("50106", "LG", "pitcher", "유영찬", 54, "RP", "K/9 10.1", "불펜"),
        ],
    }
    return players_by_team.get(team_id.upper(), [])


def _lineup_payload(game_id: str) -> dict:
    boxscore = _boxscore_payload(game_id)
    return {
        "gameId": game_id,
        "away": {
            "teamId": "SS",
            "starter": {
                "id": "69446",
                "name": "원태인",
                "imageUrl": f"{PLAYER_IMAGE_BASE}/2026/69446.jpg",
            },
            "lineup": [
                {
                    "order": batter["order"],
                    "position": batter["position"],
                    "positionKo": batter["position"],
                    "name": batter["name"],
                    "statValue": f"{batter['hits']}-{batter['atBats']}",
                }
                for batter in boxscore["away"]["batters"]
            ],
        },
        "home": {
            "teamId": "LG",
            "starter": {
                "id": "61101",
                "name": "임찬규",
                "imageUrl": f"{PLAYER_IMAGE_BASE}/2026/61101.jpg",
            },
            "lineup": [
                {
                    "order": batter["order"],
                    "position": batter["position"],
                    "positionKo": batter["position"],
                    "name": batter["name"],
                    "statValue": f"{batter['hits']}-{batter['atBats']}",
                }
                for batter in boxscore["home"]["batters"]
            ],
        },
    }


def _relay_payload() -> dict:
    return {
        "currentAtBat": {
            "batter": {"name": "문보경", "number": 35, "hand": "L", "recent": "3타수 2안타"},
            "pitcher": {"name": "원태인", "number": 18, "hand": "R", "pitchCount": 91},
            "inningText": "7회말",
            "baseState": "1루",
            "ballCount": {"balls": 1, "strikes": 2, "outs": 1},
        },
        "relayItems": [
            {
                "seqNo": 3,
                "inning": 7,
                "half": "bottom",
                "event": "안타",
                "isScoring": False,
                "text": "문보경 우전 안타, 1사 1루.",
            },
            {
                "seqNo": 2,
                "inning": 6,
                "half": "top",
                "event": "득점",
                "isScoring": True,
                "text": "구자욱 우중간 2루타로 삼성 2득점.",
            },
            {
                "seqNo": 1,
                "inning": 2,
                "half": "bottom",
                "event": "득점",
                "isScoring": True,
                "text": "오스틴 희생플라이, LG 1득점.",
            },
        ],
    }


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
            "title": "오늘의 KBO 소식",
            "subtitle": "지금 볼 장면 7개",
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
                    "route": "/records/player/66710?season=2026",
                    "gameId": None,
                    "teamIds": ["HH"],
                    "fallbackLabel": "노시환",
                },
                {
                    "type": "player_performance",
                    "eyebrow": "승부처",
                    "title": "7회 이후 득점력",
                    "subtitle": "삼성 .318 · LG .250",
                    "route": "/game/20260619SSLG0",
                    "gameId": "20260619SSLG0",
                    "teamIds": ["SS", "LG"],
                    "fallbackLabel": "삼성 LG",
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
                    "fallbackLabel": "선발",
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
                "route": "/records/player/68525?season=2026",
                "teamId": "LT",
                "imageUrl": f"{PLAYER_IMAGE_BASE}/2026/68525.jpg",
                "fallbackLabel": "빅터 레이예스",
            },
            {
                "eyebrow": "선수 집중",
                "title": "구자욱 장타율 상승",
                "subtitle": "최근 7경기 장타 5개 · 삼성 중심 타선",
                "route": "/records/player/62415?season=2026",
                "teamId": "SS",
                "imageUrl": f"{PLAYER_IMAGE_BASE}/2026/62415.jpg",
                "fallbackLabel": "구자욱",
            },
            {
                "eyebrow": "불펜 체크",
                "title": "LG 필승조 3연투 없음",
                "subtitle": "오늘 후반 승부 여유 구간",
                "route": "/records/team/LG",
                "teamId": "LG",
                "fallbackLabel": "LG",
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

        path_parts = [part for part in parsed.path.split("/") if part]
        if len(path_parts) == 3 and path_parts[:2] == ["api", "game"]:
            game = _game_by_id(path_parts[2])
            if game is None:
                self._send_json(
                    {
                        "success": False,
                        "error": {
                            "code": "NOT_FOUND",
                            "message": f"Unsupported reference game: {path_parts[2]}",
                        },
                    },
                    status=404,
                )
                return
            self._send_json({"success": True, "data": {"game": game}})
            return

        if len(path_parts) == 4 and path_parts[:2] == ["api", "game"]:
            game_id = path_parts[2]
            resource = path_parts[3]
            if resource == "boxscore":
                self._send_json({"success": True, "data": _boxscore_payload(game_id)})
                return
            if resource == "lineup":
                self._send_json({"success": True, "data": _lineup_payload(game_id)})
                return
            if resource == "relay":
                self._send_json({"success": True, "data": _relay_payload()})
                return
            if resource == "highlights":
                self._send_json(
                    {"success": True, "data": {"highlightInfo": None}}
                )
                return

        if (
            len(path_parts) == 4
            and path_parts[0] == "api"
            and path_parts[1] == "team"
            and path_parts[3] == "players"
        ):
            self._send_json(
                {"success": True, "data": {"players": _players(path_parts[2])}}
            )
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
