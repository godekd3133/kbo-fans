from __future__ import annotations

import hashlib
import json
import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Optional

from kbo_fans_backend.schemas.push import LiveActivityContentState, LiveActivityUpdateRequest
from kbo_fans_backend.services.push import KBO_TEAM_NAMES, KBO_TEAM_SHORT_NAMES, PushService
from kbo_fans_backend.services.relay import RelayService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.services.standings import StandingsService

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class _RelayFetch:
    payload: Optional[dict[str, Any]] = None
    error: Optional[Exception] = None


class LiveActivityScoreboardSyncService:
    _KST = timezone(timedelta(hours=9))
    _PREGAME_ALERT_WINDOW = timedelta(minutes=10)
    _STALE_BASELINE_WINDOW = timedelta(minutes=2)
    _TRANSIENT_UPDATE_BACKOFF_RETENTION = timedelta(minutes=15)

    def __init__(
        self,
        scoreboard_service: Optional[ScoreboardService] = None,
        push_service: Optional[PushService] = None,
        relay_service: Optional[RelayService] = None,
        standings_service: Optional[StandingsService] = None,
        now_provider: Optional[Callable[[], datetime]] = None,
    ) -> None:
        self.scoreboard_service = scoreboard_service or ScoreboardService()
        self.push_service = push_service or PushService()
        self.relay_service = relay_service
        self.standings_service = standings_service or StandingsService()
        self.now_provider = now_provider or (lambda: datetime.now(timezone.utc))
        self._transient_update_backoff: dict[str, tuple[str, int, datetime]] = {}

    def _sync_now(self) -> datetime:
        now = self.now_provider()
        if now.tzinfo is None:
            return now.replace(tzinfo=timezone.utc)
        return now.astimezone(timezone.utc)

    def close(self) -> None:
        sender = getattr(self.push_service, "live_activity_sender", None)
        close = getattr(sender, "close", None)
        if callable(close):
            close()

    def sync_date(self, date: str) -> dict[str, Any]:
        self._prune_transient_update_backoff(self._sync_now())
        registered_game_ids = set(self.push_service.registry.live_activity_game_ids())
        has_push_registrations = self.push_service.registry.has_device_registrations()
        has_start_tokens = self.push_service.registry.has_live_activity_start_tokens()
        if not registered_game_ids and not has_push_registrations and not has_start_tokens:
            return self._record_heartbeat(
                {
                    "date": date,
                    "checkedGames": 0,
                    "startedGames": [],
                    "updatedGames": [],
                    "pushedMoments": [],
                    "warmed": False,
                    "idle": True,
                }
            )

        retried_moments = self._retry_pending_game_moments()
        scoreboard = self._warm_scoreboard(date)

        started_games = []
        updated_games = []
        pushed_moments = list(retried_moments)
        relay_fetches: dict[str, _RelayFetch] = {}
        for game in scoreboard.get("games", []):
            game_id = str(game.get("gameId") or "")
            status = _status_value(game)
            accepted, game_moments = self._push_moments_for_game(
                game,
                deliver_moments=has_push_registrations,
                relay_fetches=relay_fetches,
            )
            pushed_moments.extend(game_moments)
            if not accepted:
                continue

            if has_start_tokens:
                start_response = self._start_live_activity_for_game(
                    game,
                    status,
                    relay_fetches=relay_fetches,
                )
                if start_response is not None:
                    started_games.append(start_response)

            if game_id not in registered_game_ids:
                continue

            if status == "SCHEDULED" and not self._should_sync_scheduled_activity(game):
                continue

            update = self._update_request_for_game(
                game,
                status,
                relay_fetches=relay_fetches,
            )
            if update is None:
                continue

            if update.event == "end":
                response = self.push_service.send_live_activity_update(update)
            else:
                response = self._send_changed_live_activity_update(update)
                if response is None:
                    continue
            updated_games.append(response)

        return self._record_heartbeat(
            {
                "date": scoreboard.get("date", date),
                "checkedGames": len(scoreboard.get("games", [])),
                "startedGames": started_games,
                "updatedGames": updated_games,
                "pushedMoments": pushed_moments,
            }
        )

    def _warm_scoreboard(self, date: str) -> dict[str, Any]:
        prime = getattr(self.scoreboard_service, "prime_home_scoreboard", None)
        if callable(prime):
            return prime(date)
        return self.scoreboard_service.get_home_scoreboard(date)

    def _record_heartbeat(self, result: dict[str, Any]) -> dict[str, Any]:
        self.push_service.registry.record_sync_heartbeat(
            {
                "date": result.get("date"),
                "checkedGames": result.get("checkedGames"),
                "startedGames": len(result.get("startedGames") or []),
                "updatedGames": len(result.get("updatedGames") or []),
                "pushedMoments": len(result.get("pushedMoments") or []),
            }
        )
        return result

    def _send_changed_live_activity_update(
        self,
        update: LiveActivityUpdateRequest,
    ) -> Optional[dict[str, Any]]:
        tokens = self.push_service.registry.live_activity_tokens_for_game(update.gameId)
        content_signature = _live_activity_content_signature(update)
        tokens_by_delivery_id = {_live_activity_delivery_id(token): token for token in tokens}
        eligible_delivery_ids = []
        now = self._sync_now()
        self._prune_transient_update_backoff(now)
        for delivery_id in tokens_by_delivery_id:
            backoff = self._transient_update_backoff.get(delivery_id)
            if backoff is None:
                eligible_delivery_ids.append(delivery_id)
                continue
            backoff_signature, _, retry_at = backoff
            if backoff_signature != content_signature or now >= retry_at:
                self._transient_update_backoff.pop(delivery_id, None)
                eligible_delivery_ids.append(delivery_id)
        if not eligible_delivery_ids:
            return None
        claims = self.push_service.registry.claim_live_activity_updates(
            game_id=update.gameId,
            delivery_ids=eligible_delivery_ids,
            content_signature=content_signature,
        )
        if not claims:
            return None

        messages = []
        completed_claims: dict[str, str] = {}
        released_claims: dict[str, str] = {}
        for delivery_id, claim_id in claims.items():
            token = tokens_by_delivery_id[delivery_id]
            if not self.push_service.registry.fence_live_activity_update(
                game_id=update.gameId,
                delivery_id=delivery_id,
                content_signature=content_signature,
                claim_id=claim_id,
            ):
                messages.append(
                    {
                        "activityPushToken": token,
                        "sent": False,
                        "skipped": True,
                        "reason": "stale_delivery_claim",
                    }
                )
                continue
            targeted_update = _targeted_live_activity_update(update, token)
            try:
                response = self.push_service.send_live_activity_update(targeted_update)
            except Exception:
                released_claims.update(
                    {
                        pending_delivery_id: pending_claim_id
                        for pending_delivery_id, pending_claim_id in claims.items()
                        if pending_delivery_id not in completed_claims
                    }
                )
                self.push_service.registry.resolve_live_activity_updates(
                    game_id=update.gameId,
                    content_signature=content_signature,
                    completed_claims=completed_claims,
                    released_claims=released_claims,
                )
                raise

            response_messages = response.get("messages")
            if isinstance(response_messages, list):
                messages.extend(response_messages)
            if _live_activity_delivery_complete(response):
                self._transient_update_backoff.pop(delivery_id, None)
                completed_claims[delivery_id] = claim_id
            else:
                permanent_failure = any(
                    isinstance(message, dict) and bool(message.get("permanentTokenFailure"))
                    for message in response_messages or []
                )
                if permanent_failure:
                    self._transient_update_backoff.pop(delivery_id, None)
                else:
                    previous_attempts = self._transient_update_backoff.get(
                        delivery_id,
                        (content_signature, 0, now),
                    )
                    attempts = (
                        previous_attempts[1] if previous_attempts[0] == content_signature else 0
                    )
                    attempts = min(attempts + 1, 6)
                    delay_seconds = min(60, 5 * (2 ** (attempts - 1)))
                    self._transient_update_backoff[delivery_id] = (
                        content_signature,
                        attempts,
                        now + timedelta(seconds=delay_seconds),
                    )
                released_claims[delivery_id] = claim_id

        self.push_service.registry.resolve_live_activity_updates(
            game_id=update.gameId,
            content_signature=content_signature,
            completed_claims=completed_claims,
            released_claims=released_claims,
        )

        return {
            "sent": any(message.get("sent") for message in messages),
            "gameId": update.gameId,
            "messages": messages,
        }

    def _prune_transient_update_backoff(self, now: datetime) -> None:
        cutoff = now - self._TRANSIENT_UPDATE_BACKOFF_RETENTION
        for delivery_id, (_, _, retry_at) in list(self._transient_update_backoff.items()):
            if retry_at <= cutoff:
                self._transient_update_backoff.pop(delivery_id, None)

    def _start_live_activity_for_game(
        self,
        game: dict[str, Any],
        status: str,
        *,
        relay_fetches: dict[str, _RelayFetch],
    ) -> Optional[dict[str, Any]]:
        is_pregame_start = self._should_start_scheduled_activity(game, status)
        if status != "LIVE" and not is_pregame_start:
            return None
        update = self._update_request_for_game(
            game,
            status,
            relay_fetches=relay_fetches,
        )
        if update is None:
            return None

        away = game.get("away") or {}
        home = game.get("home") or {}
        game_id = str(game.get("gameId") or "")
        try:
            response = self.push_service.send_live_activity_start(
                game_id=game_id,
                away_team_id=str(away.get("teamId") or ""),
                away_team_name=_team_short_display_name(away),
                home_team_id=str(home.get("teamId") or ""),
                home_team_name=_team_short_display_name(home),
                state=update.state,
                stale_date=update.staleDate,
                relevance_score=update.relevanceScore,
                alert_title="경기 곧 시작" if is_pregame_start else None,
                alert_body=(
                    self._game_start_soon_alert_body(game, away=away, home=home)
                    if is_pregame_start
                    else None
                ),
            )
        except Exception as error:
            return {
                "sent": False,
                "gameId": game_id,
                "messages": [],
                "error": str(error),
            }
        if not response.get("messages"):
            return None
        return response

    def _should_start_scheduled_activity(self, game: dict[str, Any], status: str) -> bool:
        if status != "SCHEDULED":
            return False
        return self._scheduled_activity_start_at(game) is not None

    def _should_sync_scheduled_activity(self, game: dict[str, Any]) -> bool:
        return _lineup_opened(game) or self._scheduled_activity_start_at(game) is not None

    def _scheduled_activity_start_at(self, game: dict[str, Any]) -> Optional[datetime]:
        current_state = _scoreboard_state(game)
        start_at = _scheduled_start_at(game, current_state)
        if start_at is None:
            return None

        now = self.now_provider().astimezone(self._KST)
        until_start = start_at - now
        if until_start < timedelta(0) or until_start > self._PREGAME_ALERT_WINDOW:
            return None
        return start_at

    def _game_start_soon_alert_body(
        self,
        game: dict[str, Any],
        *,
        away: dict[str, Any],
        home: dict[str, Any],
    ) -> str:
        matchup = f"{_team_short_display_name(away)} vs {_team_short_display_name(home)}"
        start_at = self._scheduled_activity_start_at(game)
        start_time = start_at.strftime("%H:%M") if start_at is not None else ""
        stadium = str(game.get("stadium") or "").strip()
        suffix = " · ".join(part for part in [start_time, stadium] if part)
        if suffix:
            return f"{matchup} 경기가 곧 시작됩니다. {suffix}"
        return f"{matchup} 경기가 곧 시작됩니다."

    def _push_moments_for_game(
        self,
        game: dict[str, Any],
        *,
        deliver_moments: bool,
        relay_fetches: dict[str, _RelayFetch],
    ) -> tuple[bool, list[dict[str, Any]]]:
        game_id = str(game.get("gameId") or "")
        if not game_id:
            return False, []

        current_state = _scoreboard_state(game)
        previous_state = self.push_service.registry.scoreboard_state(game_id)
        _apply_at_bat_history(current_state, previous_state)
        previous_state_fresh = _is_fresh_baseline(
            previous_state,
            now=self.now_provider(),
            max_age=self._STALE_BASELINE_WINDOW,
        )
        previous_score_state = _last_verified_score_state(previous_state)
        previous_score_state_fresh = _is_fresh_baseline(
            previous_score_state,
            now=self.now_provider(),
            max_age=self._STALE_BASELINE_WINDOW,
        )
        pushed = []
        pregame_events = (
            self._pregame_moment_events_for_game(game, current_state) if deliver_moments else []
        )
        event_specs = [event for event, _ in pregame_events]
        pregame_alert_keys = {event["eventId"]: alert_key for event, alert_key in pregame_events}
        should_compare = previous_state_fresh or _is_terminal_transition(
            previous_state,
            current_state,
        )
        if deliver_moments and should_compare and previous_state is not None:
            for moment in _moments_from_state(
                previous_state,
                current_state,
                previous_score_state=(previous_score_state if previous_score_state_fresh else None),
            ):
                event_specs.append(
                    self._game_moment_outbox_event(
                        moment,
                        game_id,
                        current_state,
                        source=_scoreboard_moment_source(
                            moment,
                            previous_state,
                            current_state,
                        ),
                    )
                )

        if _scores_available(current_state):
            current_state["lastVerifiedScoreState"] = {
                **_event_state(current_state),
                "updatedAt": self.now_provider().astimezone(timezone.utc).isoformat(),
            }
        elif previous_score_state is not None:
            current_state["lastVerifiedScoreState"] = {
                **_event_state(previous_score_state),
                "updatedAt": previous_score_state.get("updatedAt"),
            }

        applied = self.push_service.registry.replace_scoreboard_state_and_enqueue_if_current(
            game_id,
            current_state,
            events=event_specs,
            expected_updated_at=(
                str(previous_state.get("updatedAt") or "") if previous_state is not None else None
            ),
        )
        if not applied:
            return False, pushed

        for event in event_specs:
            response = self._deliver_game_moment_event(event)
            if event["payload"]["moment"] == "lineup_opened" and response.get("sent"):
                self.push_service.registry.mark_pregame_alert_sent(
                    game_id,
                    "lineup_opened",
                )
            alert_key = pregame_alert_keys.get(event["eventId"])
            if alert_key and response.get("sent"):
                self.push_service.registry.mark_pregame_alert_sent(
                    game_id,
                    alert_key,
                )
            pushed.append(response)

        if deliver_moments:
            pushed.extend(
                self._push_relay_moments_for_game(
                    game_id,
                    current_state,
                    relay_fetches=relay_fetches,
                )
            )
        return True, pushed

    def _push_relay_moments_for_game(
        self,
        game_id: str,
        current_state: dict[str, Any],
        *,
        relay_fetches: dict[str, _RelayFetch],
    ) -> list[dict[str, Any]]:
        if self.relay_service is None or current_state["status"] != "LIVE":
            return []

        previous_relay_state = self.push_service.registry.relay_state(game_id)
        last_seq = _int_value(previous_relay_state.get("lastSeq")) if previous_relay_state else 0
        after = last_seq if previous_relay_state is not None else None
        previous_relay_state_fresh = _is_fresh_baseline(
            previous_relay_state,
            now=self.now_provider(),
            max_age=self._STALE_BASELINE_WINDOW,
        )

        try:
            relay = self._relay_for_game_once(
                game_id,
                after=after,
                relay_fetches=relay_fetches,
            )
        except Exception as error:
            return [
                {
                    "sent": False,
                    "moment": "homerun",
                    "gameId": game_id,
                    "error": str(error),
                }
            ]

        relay_items = sorted(
            relay.get("relayItems") or [],
            key=lambda item: _int_value(item.get("seqNo")),
        )
        relay_current_state = _relay_current_state(relay.get("currentAtBat"), current_state)
        max_seq = last_seq
        event_specs = []
        for item in relay_items:
            item_seq = _int_value(item.get("seqNo"))
            if item_seq > max_seq:
                max_seq = item_seq
            if not previous_relay_state_fresh:
                continue
            if _is_homerun_relay_item(item):
                homerun_state = {
                    **current_state,
                    **relay_current_state,
                    "inning": _relay_item_inning_text(item) or relay_current_state["inning"],
                    "batterName": (
                        _relay_item_actor(item)
                        or relay_current_state["batterName"]
                        or current_state["batterName"]
                    ),
                    "playText": str(item.get("text") or "").strip(),
                }
                event_specs.append(
                    self._game_moment_outbox_event(
                        "homerun",
                        game_id,
                        homerun_state,
                        source={
                            "kind": "relay",
                            "seqNo": item_seq,
                        },
                    )
                )
                continue
            if _is_hit_relay_item(item):
                hit_state = {
                    **current_state,
                    **relay_current_state,
                    "inning": _relay_item_inning_text(item) or relay_current_state["inning"],
                    "batterName": (
                        _relay_item_actor(item)
                        or relay_current_state["batterName"]
                        or current_state["batterName"]
                    ),
                    "playText": str(item.get("text") or "").strip(),
                }
                event_specs.append(
                    self._game_moment_outbox_event(
                        "hit",
                        game_id,
                        hit_state,
                        source={
                            "kind": "relay",
                            "seqNo": item_seq,
                        },
                    )
                )

        applied = self.push_service.registry.replace_relay_state_and_enqueue_if_current(
            game_id,
            {"lastSeq": max_seq},
            events=event_specs,
            expected_updated_at=(
                str(previous_relay_state.get("updatedAt") or "")
                if previous_relay_state is not None
                else None
            ),
        )
        if not applied:
            return []
        return [self._deliver_game_moment_event(event) for event in event_specs]

    def _relay_for_game_once(
        self,
        game_id: str,
        *,
        after: Optional[int],
        relay_fetches: dict[str, _RelayFetch],
    ) -> dict[str, Any]:
        cached = relay_fetches.get(game_id)
        if cached is None:
            if self.relay_service is None:
                raise ValueError("relay service is not configured")
            try:
                payload = self.relay_service.get_relay(game_id, after=after)
            except Exception as error:
                cached = _RelayFetch(error=error)
            else:
                cached = _RelayFetch(payload=payload)
            relay_fetches[game_id] = cached

        if cached.error is not None:
            raise cached.error
        return cached.payload or {}

    def _pregame_moment_events_for_game(
        self,
        game: dict[str, Any],
        current_state: dict[str, Any],
    ) -> list[tuple[dict[str, Any], str]]:
        if current_state["status"] != "SCHEDULED":
            return []

        start_at = _scheduled_start_at(game, current_state)
        if start_at is None:
            return []

        now = self.now_provider().astimezone(self._KST)
        until_start = start_at - now
        if until_start < timedelta(0) or until_start > self._PREGAME_ALERT_WINDOW:
            return []

        game_id = str(game.get("gameId") or "")
        alert_key = f"game_start_soon:{start_at.isoformat()}"
        if self.push_service.registry.pregame_alert_sent(game_id, alert_key):
            return []

        state = {
            **current_state,
            "startTime": start_at.strftime("%H:%M"),
            "stadium": str(game.get("stadium") or current_state.get("stadium") or ""),
        }
        event = self._game_moment_outbox_event(
            "game_start_soon",
            game_id,
            state,
            source={
                "kind": "pregame",
                "alertKey": alert_key,
            },
        )
        return [(event, alert_key)]

    def _game_moment_outbox_event(
        self,
        moment: str,
        game_id: str,
        current_state: dict[str, Any],
        *,
        source: dict[str, Any],
    ) -> dict[str, Any]:
        payload = {
            "moment": moment,
            "game_id": game_id,
            "away_team_id": current_state["awayTeamId"],
            "away_team_name": current_state["awayTeam"],
            "home_team_id": current_state["homeTeamId"],
            "home_team_name": current_state["homeTeam"],
            "away_score": current_state["awayScore"],
            "home_score": current_state["homeScore"],
            "inning": current_state["inning"],
            "batter_name": current_state["batterName"],
            "pitcher_name": current_state["pitcherName"],
            "situation_text": current_state.get("situationText", ""),
            "play_text": current_state.get("playText", ""),
            "start_time": current_state.get("startTime", ""),
            "stadium": current_state.get("stadium", ""),
            "game_status": current_state.get("status", ""),
        }
        event_id = _game_moment_event_id(
            game_id=game_id,
            moment=moment,
            source=source,
        )
        return {
            "eventId": event_id,
            "kind": "game_moment",
            "payload": payload,
            "targets": self.push_service.game_moment_targets(
                moment=moment,
                game_id=game_id,
                away_team_id=current_state["awayTeamId"],
                home_team_id=current_state["homeTeamId"],
            ),
        }

    def _retry_pending_game_moments(self) -> list[dict[str, Any]]:
        return [
            self._deliver_game_moment_event(event)
            for event in self.push_service.registry.pending_push_outbox_events(
                kind="game_moment",
            )
        ]

    def _deliver_game_moment_event(
        self,
        event: dict[str, Any],
    ) -> dict[str, Any]:
        event_id = str(event.get("eventId") or "")
        persisted = self.push_service.registry.push_outbox_event(event_id) or event
        payload = persisted.get("payload")
        if not isinstance(payload, dict):
            return {
                "sent": False,
                "eventId": event_id,
                "error": "push outbox payload is missing",
            }
        try:
            response = self.push_service.send_game_moment(
                **payload,
                event_id=event_id,
            )
        except Exception as error:
            return {
                "sent": False,
                "moment": payload.get("moment"),
                "gameId": payload.get("game_id"),
                "eventId": event_id,
                "error": str(error),
            }
        if response.get("sent"):
            self.push_service.registry.mark_push_outbox_event_delivered(event_id)
        return {
            **response,
            "eventId": event_id,
        }

    def _update_request_for_game(
        self,
        game: dict[str, Any],
        status: str,
        *,
        relay_fetches: dict[str, _RelayFetch],
    ) -> Optional[LiveActivityUpdateRequest]:
        game_id = str(game.get("gameId") or "")
        away = game.get("away") or {}
        home = game.get("home") or {}
        if not game_id or not away or not home:
            return None

        now = self.now_provider().astimezone(timezone.utc)
        source_away_score = _optional_int_value(away.get("score"))
        source_home_score = _optional_int_value(home.get("score"))
        score_available = source_away_score is not None and source_home_score is not None
        if status == "LIVE" and not score_available:
            return None
        verified_state = _last_verified_score_state(
            self.push_service.registry.scoreboard_state(game_id)
        )
        if status == "SUSPENDED" and not score_available and verified_state is None:
            return None
        away_score = (
            source_away_score
            if source_away_score is not None
            else (_int_value(verified_state.get("awayScore")) if verified_state is not None else 0)
        )
        home_score = (
            source_home_score
            if source_home_score is not None
            else (_int_value(verified_state.get("homeScore")) if verified_state is not None else 0)
        )

        event = "end" if status in {"FINAL", "CANCELLED"} else "update"
        current = self._live_activity_current_payload(
            game,
            status,
            relay_fetches=relay_fetches,
        )
        is_pregame = status == "SCHEDULED" and self._should_sync_scheduled_activity(game)
        ranks = self._rank_labels_for_game(game) if is_pregame else {}
        state = LiveActivityContentState(
            awayTeamId=str(away.get("teamId") or ""),
            awayTeam=_team_short_display_name(away),
            homeTeamId=str(home.get("teamId") or ""),
            homeTeam=_team_short_display_name(home),
            awayScore=away_score,
            homeScore=home_score,
            scoreAvailable=score_available,
            inning=(
                "경기전" if is_pregame else str(current.get("inning") or _inning_text(game, status))
            ),
            batter=current["batterName"],
            batterAverage=str(current.get("batterAverage") or ""),
            pitcher=current["pitcherName"],
            pitcherEra=str(current.get("pitcherEra") or ""),
            pitchCount=_int_value(current.get("pitchCount")),
            balls=_int_value(current.get("balls")),
            strikes=_int_value(current.get("strikes")),
            outs=_int_value(current.get("outs")),
            stadium=str(game.get("stadium") or "KBO"),
            updatedAt=now.astimezone(self._KST).strftime("%H:%M:%S"),
            situationText=str(current.get("situationText") or ""),
            playText="" if is_pregame else str(current.get("playText") or ""),
            isPregame=is_pregame,
            awayRankText=ranks.get(str(away.get("teamId") or ""), ""),
            homeRankText=ranks.get(str(home.get("teamId") or ""), ""),
        )
        return LiveActivityUpdateRequest(
            gameId=game_id,
            state=state,
            event=event,
            staleDate=int((now + timedelta(minutes=2)).timestamp()) if event == "update" else None,
            dismissalDate=int((now + timedelta(hours=1)).timestamp()) if event == "end" else None,
            relevanceScore=100 if event == "update" else 50,
        )

    def _live_activity_current_payload(
        self,
        game: dict[str, Any],
        status: str,
        *,
        relay_fetches: dict[str, _RelayFetch],
    ) -> dict[str, Any]:
        current = _current_payload(game)
        if status in {"FINAL", "CANCELLED", "SUSPENDED"}:
            return {
                **current,
                "batterName": "",
                "pitcherName": "",
                "batterAverage": "",
                "pitcherEra": "",
                "pitchCount": 0,
                "balls": 0,
                "strikes": 0,
                "outs": 0,
                "situationText": "",
                "playText": "",
            }
        game_id = str(game.get("gameId") or "")
        if self.relay_service is None or status != "LIVE" or not game_id:
            return current

        try:
            relay = self._relay_for_game_once(
                game_id,
                after=None,
                relay_fetches=relay_fetches,
            )
        except Exception:
            return current

        relay_current = _relay_current_state(relay.get("currentAtBat"), current)
        return {**current, **relay_current}

    def _rank_labels_for_game(self, game: dict[str, Any]) -> dict[str, str]:
        season = _season_from_game(game)
        if season is None:
            return {}
        try:
            payload = self.standings_service.get_standings(season)
        except Exception as error:
            logger.warning("live activity standings rank skipped: %s", error)
            return {}

        labels = {}
        for standing in payload.get("standings", []):
            team_id = str(standing.get("teamId") or "")
            rank = _int_value(standing.get("rank"))
            if team_id and rank > 0:
                labels[team_id] = f"{rank}위"
        return labels


def _is_homerun_relay_item(item: dict[str, Any]) -> bool:
    event = str(item.get("event") or "").upper()
    if "HOMERUN" in event:
        return True
    return "홈런" in str(item.get("text") or "")


def _is_hit_relay_item(item: dict[str, Any]) -> bool:
    text = str(item.get("text") or "")
    if _is_homerun_relay_item(item):
        return False
    event = str(item.get("event") or "").upper()
    if event == "HIT":
        return True
    return any(marker in text for marker in ("안타", "1루타", "2루타", "3루타"))


def _relay_item_actor(item: dict[str, Any]) -> str:
    text = str(item.get("text") or "").strip()
    if not text:
        return ""
    actor = re.split(r"\s*[:：]\s*", text, maxsplit=1)[0].strip()
    actor = re.sub(r"^\d+\s*번\s*", "", actor).strip()
    return actor if len(actor) <= 12 else ""


def _relay_item_inning_text(item: dict[str, Any]) -> str:
    inning = _int_value(item.get("inning"))
    if inning <= 0:
        return ""
    half = str(item.get("half") or "").lower()
    suffix = "초" if half == "top" else "말" if half == "bottom" else ""
    return f"{inning}회{suffix}"


def _relay_current_state(
    current_at_bat: Any,
    fallback_state: dict[str, Any],
) -> dict[str, Any]:
    if not isinstance(current_at_bat, dict):
        return {
            "inning": fallback_state["inning"],
            "batterName": fallback_state["batterName"],
            "pitcherName": fallback_state["pitcherName"],
            "batterAverage": fallback_state.get("batterAverage", ""),
            "pitcherEra": fallback_state.get("pitcherEra", ""),
            "pitchCount": fallback_state.get("pitchCount", 0),
            "balls": fallback_state.get("balls", 0),
            "strikes": fallback_state.get("strikes", 0),
            "outs": fallback_state.get("outs", 0),
            "situationText": "",
        }

    batter = current_at_bat.get("batter") or {}
    pitcher = current_at_bat.get("pitcher") or {}
    ball_count = current_at_bat.get("ballCount") or {}
    inning = str(current_at_bat.get("inningText") or fallback_state["inning"])
    base_state = str(current_at_bat.get("baseState") or "")
    pitch_count = _int_value(
        pitcher.get("pitchCount")
        if pitcher.get("pitchCount") is not None
        else fallback_state.get("pitchCount")
    )
    balls = _int_value(
        ball_count.get("balls")
        if ball_count.get("balls") is not None
        else fallback_state.get("balls")
    )
    strikes = _int_value(
        ball_count.get("strikes")
        if ball_count.get("strikes") is not None
        else fallback_state.get("strikes")
    )
    outs = _int_value(
        ball_count.get("outs") if ball_count.get("outs") is not None else fallback_state.get("outs")
    )
    return {
        "inning": inning,
        "batterName": str(batter.get("name") or fallback_state["batterName"]),
        "pitcherName": str(pitcher.get("name") or fallback_state["pitcherName"]),
        "batterAverage": str(batter.get("average") or fallback_state.get("batterAverage", "")),
        "pitcherEra": str(pitcher.get("era") or fallback_state.get("pitcherEra", "")),
        "pitchCount": pitch_count,
        "balls": balls,
        "strikes": strikes,
        "outs": outs,
        "situationText": _situation_text(
            outs=outs,
            base_state=base_state,
        ),
    }


def _situation_text(*, outs: int, base_state: str) -> str:
    outs_label = {0: "무사", 1: "1사", 2: "2사"}.get(outs, "")
    base_label = _base_state_label(base_state)
    if outs_label and base_label:
        return f"{outs_label} {base_label}"
    return outs_label or base_label


def _base_state_label(base_state: str) -> str:
    text = base_state.strip()
    if not text:
        return ""
    if text == "주자없음":
        return "주자 없음"
    if text.startswith("주자"):
        return text.removeprefix("주자")
    return text


def _scheduled_start_at(
    game: dict[str, Any],
    current_state: dict[str, Any],
) -> Optional[datetime]:
    game_id = str(game.get("gameId") or "")
    if len(game_id) < 8:
        return None

    raw_time = str(
        current_state.get("startTime") or game.get("startTime") or game.get("time") or ""
    )
    match = re.search(r"(\d{1,2}):(\d{2})", raw_time)
    if not match:
        return None

    try:
        year = int(game_id[:4])
        month = int(game_id[4:6])
        day = int(game_id[6:8])
        hour = int(match.group(1))
        minute = int(match.group(2))
    except ValueError:
        return None

    return datetime(
        year,
        month,
        day,
        hour,
        minute,
        tzinfo=LiveActivityScoreboardSyncService._KST,
    )


def _int_value(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _optional_int_value(value: Any) -> Optional[int]:
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _status_value(game: dict[str, Any]) -> str:
    return str(game.get("status") or "").upper()


def _lineup_opened(game: dict[str, Any]) -> bool:
    for key in ("lineupOpened", "lineup_opened", "LINEUP_CK"):
        value = game.get(key)
        if value is True:
            return True
        if isinstance(value, str) and value.strip().lower() == "true":
            return True
    text = " ".join(str(value or "") for value in (game.get("statusLabel"), game.get("inning")))
    if "라인업" not in text:
        return False
    return "공개" in text or "발표" in text


def _is_fresh_baseline(
    state: Optional[dict[str, Any]],
    *,
    now: datetime,
    max_age: timedelta,
) -> bool:
    if not isinstance(state, dict):
        return False
    observed_at = _state_updated_at(state)
    if observed_at is None:
        return False
    age = now.astimezone(timezone.utc) - observed_at.astimezone(timezone.utc)
    return age <= max_age


def _state_updated_at(state: dict[str, Any]) -> Optional[datetime]:
    raw_value = str(state.get("updatedAt") or "").strip()
    if not raw_value:
        return None
    try:
        parsed = datetime.fromisoformat(raw_value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def _season_from_game(game: dict[str, Any]) -> Optional[int]:
    game_id = str(game.get("gameId") or "")
    if len(game_id) >= 4:
        try:
            return int(game_id[:4])
        except ValueError:
            return None
    return None


def _inning_text(game: dict[str, Any], status: str) -> str:
    inning = str(game.get("inning") or "").strip()
    if inning:
        return inning
    status_label = str(game.get("statusLabel") or "").strip()
    if status_label:
        return status_label
    if status == "FINAL":
        return "경기종료"
    if status == "CANCELLED":
        return "경기취소"
    if status == "SUSPENDED":
        return "서스펜디드"
    return "진행중"


def _team_short_display_name(team: dict[str, Any]) -> str:
    team_id = str(team.get("teamId") or "").strip()
    if team_id in KBO_TEAM_SHORT_NAMES:
        return KBO_TEAM_SHORT_NAMES[team_id]

    short_name = str(team.get("shortName") or "").strip()
    if short_name in KBO_TEAM_SHORT_NAMES:
        return KBO_TEAM_SHORT_NAMES[short_name]

    team_name = str(team.get("teamName") or team.get("name") or "").strip()
    for known_team_id, known_team_name in KBO_TEAM_NAMES.items():
        if team_name == known_team_name or team_name.replace(" ", "") == known_team_name.replace(
            " ", ""
        ):
            return KBO_TEAM_SHORT_NAMES[known_team_id]

    return short_name or team_name or team_id


def _scoreboard_state(game: dict[str, Any]) -> dict[str, Any]:
    away = game.get("away") or {}
    home = game.get("home") or {}
    status = _status_value(game)
    current = _current_payload(game)
    away_score = _optional_int_value(away.get("score"))
    home_score = _optional_int_value(home.get("score"))
    return {
        "status": status,
        "lineupOpened": _lineup_opened(game),
        "awayTeamId": str(away.get("teamId") or ""),
        "awayTeam": _team_short_display_name(away),
        "homeTeamId": str(home.get("teamId") or ""),
        "homeTeam": _team_short_display_name(home),
        "awayScore": away_score,
        "homeScore": home_score,
        "scoreAvailable": away_score is not None and home_score is not None,
        "inning": _inning_text(game, status),
        "batterName": current["batterName"],
        "pitcherName": current["pitcherName"],
        "situationText": "",
        "playText": "",
        "startTime": str(game.get("startTime") or ""),
        "stadium": str(game.get("stadium") or ""),
    }


def _moments_from_state(
    previous: dict[str, Any],
    current: dict[str, Any],
    *,
    previous_score_state: Optional[dict[str, Any]] = None,
) -> list[str]:
    previous_status = str(previous.get("status") or "").upper()
    current_status = str(current.get("status") or "").upper()
    if previous_status == "SUSPENDED" and current_status == "LIVE":
        return []
    score_baseline = previous_score_state or previous
    scores_comparable = _scores_available(score_baseline) and _scores_available(current)
    previous_total = (
        _int_value(score_baseline.get("awayScore")) + _int_value(score_baseline.get("homeScore"))
        if scores_comparable
        else 0
    )
    current_total = (
        _int_value(current.get("awayScore")) + _int_value(current.get("homeScore"))
        if scores_comparable
        else 0
    )
    previous_leader = _leader(score_baseline) if scores_comparable else ""
    current_leader = _leader(current) if scores_comparable else ""
    moments = []

    if (
        current_status == "SCHEDULED"
        and not bool(previous.get("lineupOpened"))
        and bool(current.get("lineupOpened"))
    ):
        moments.append("lineup_opened")
    if previous_status == "SCHEDULED" and current_status == "LIVE":
        moments.append("game_start")
    if scores_comparable and current_status == "LIVE" and current_total > previous_total:
        moments.append("scoring")
    if (
        current_status == "LIVE"
        and previous_leader
        and current_leader
        and previous_leader != current_leader
    ):
        moments.append("reversal")
    if previous_status not in {"FINAL", "CANCELLED", "SUSPENDED"} and current_status in {
        "FINAL",
        "CANCELLED",
        "SUSPENDED",
    }:
        moments.append("game_end")
    if (
        not moments
        and current_status == "LIVE"
        and _current_batter(current)
        and _current_batter(previous) != _current_batter(current)
    ):
        moments.append("at_bat")
    if (
        not moments
        and current_status == "LIVE"
        and str(previous.get("inning") or "") != str(current.get("inning") or "")
    ):
        moments.append("inning_change")

    return moments


def _scores_available(state: dict[str, Any]) -> bool:
    return (
        _optional_int_value(state.get("awayScore")) is not None
        and _optional_int_value(state.get("homeScore")) is not None
    )


def _last_verified_score_state(
    state: Optional[dict[str, Any]],
) -> Optional[dict[str, Any]]:
    if not isinstance(state, dict):
        return None
    if _scores_available(state):
        return state
    nested = state.get("lastVerifiedScoreState")
    if isinstance(nested, dict) and _scores_available(nested):
        return nested
    return None


def _is_terminal_transition(
    previous: Optional[dict[str, Any]],
    current: dict[str, Any],
) -> bool:
    if not isinstance(previous, dict):
        return False
    previous_status = str(previous.get("status") or "").upper()
    current_status = str(current.get("status") or "").upper()
    return previous_status not in {"FINAL", "CANCELLED", "SUSPENDED"} and current_status in {
        "FINAL",
        "CANCELLED",
        "SUSPENDED",
    }


def _apply_at_bat_history(
    current: dict[str, Any],
    previous: Optional[dict[str, Any]],
) -> None:
    seen = []
    if isinstance(previous, dict):
        previous_seen = previous.get("seenAtBatMilestones")
        if isinstance(previous_seen, list):
            seen.extend(str(item) for item in previous_seen if str(item).strip())
        previous_milestone = _at_bat_milestone(previous)
        if previous_milestone:
            seen.append(previous_milestone)

    current_milestone = _at_bat_milestone(current)
    if current_milestone:
        seen.append(current_milestone)
        current["atBatMilestone"] = current_milestone
    current["seenAtBatMilestones"] = list(dict.fromkeys(seen))[-64:]


def _at_bat_milestone(state: dict[str, Any]) -> str:
    if str(state.get("status") or "").upper() != "LIVE":
        return ""
    batter = _current_batter(state)
    if not batter:
        return ""
    return "|".join(
        (
            str(state.get("inning") or "").strip(),
            str(state.get("awayScore") if state.get("awayScore") is not None else "–"),
            str(state.get("homeScore") if state.get("homeScore") is not None else "–"),
            batter,
            str(state.get("pitcherName") or "").strip(),
        )
    )


def _event_state(state: dict[str, Any]) -> dict[str, Any]:
    return {
        key: state.get(key)
        for key in (
            "status",
            "lineupOpened",
            "awayTeamId",
            "homeTeamId",
            "awayScore",
            "homeScore",
            "scoreAvailable",
            "inning",
            "batterName",
            "pitcherName",
            "situationText",
            "playText",
            "startTime",
            "stadium",
            "updatedAt",
        )
    }


def _scoreboard_moment_source(
    moment: str,
    previous: dict[str, Any],
    current: dict[str, Any],
) -> dict[str, Any]:
    source: dict[str, Any] = {
        "kind": "scoreboard",
        "status": str(current.get("status") or "").upper(),
    }
    if moment in {"scoring", "reversal", "game_end"}:
        source.update(
            {
                "awayScore": current.get("awayScore"),
                "homeScore": current.get("homeScore"),
                "scoreAvailable": bool(current.get("scoreAvailable")),
            }
        )
    if moment in {"inning_change", "at_bat"}:
        source["inning"] = str(current.get("inning") or "")
    if moment == "at_bat":
        source.update(
            {
                "milestone": (
                    str(current.get("atBatMilestone") or "") or _at_bat_milestone(current)
                ),
            }
        )
    if moment == "lineup_opened":
        source["lineupOpened"] = True
    return source


def _game_moment_event_id(
    *,
    game_id: str,
    moment: str,
    source: dict[str, Any],
) -> str:
    canonical = json.dumps(
        {
            "gameId": game_id,
            "moment": moment,
            "source": source,
        },
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:24]
    return f"game-moment:{game_id}:{moment}:{digest}"


def _live_activity_content_signature(update: LiveActivityUpdateRequest) -> str:
    state = (
        update.state.model_dump() if hasattr(update.state, "model_dump") else update.state.dict()
    )
    state.pop("updatedAt", None)
    canonical = json.dumps(
        {
            "event": update.event,
            "state": state,
        },
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _live_activity_delivery_id(activity_push_token: str) -> str:
    return hashlib.sha256(activity_push_token.encode("utf-8")).hexdigest()


def _targeted_live_activity_update(
    update: LiveActivityUpdateRequest,
    activity_push_token: str,
) -> LiveActivityUpdateRequest:
    payload = update.model_dump() if hasattr(update, "model_dump") else update.dict()
    payload["activityPushToken"] = activity_push_token
    return LiveActivityUpdateRequest(**payload)


def _live_activity_delivery_complete(response: dict[str, Any]) -> bool:
    messages = response.get("messages")
    return (
        bool(response.get("sent"))
        and isinstance(messages, list)
        and bool(messages)
        and all(isinstance(message, dict) and bool(message.get("sent")) for message in messages)
    )


def _current_payload(game: dict[str, Any]) -> dict[str, Any]:
    current = game.get("current") or {}
    return {
        "balls": current.get("balls"),
        "strikes": current.get("strikes"),
        "outs": current.get("outs"),
        "pitchCount": current.get("pitchCount"),
        "batterName": str(current.get("batterName") or "").strip(),
        "pitcherName": str(current.get("pitcherName") or "").strip(),
        "batterAverage": str(current.get("batterAverage") or "").strip(),
        "pitcherEra": str(current.get("pitcherEra") or "").strip(),
        "situationText": str(
            current.get("situationText") or current.get("baseState") or ""
        ).strip(),
        "playText": str(current.get("playText") or "").strip(),
    }


def _current_batter(state: dict[str, Any]) -> str:
    return str(state.get("batterName") or "").strip()


def _leader(state: dict[str, Any]) -> str:
    away_score = _int_value(state.get("awayScore"))
    home_score = _int_value(state.get("homeScore"))
    if away_score > home_score:
        return "away"
    if home_score > away_score:
        return "home"
    return ""
