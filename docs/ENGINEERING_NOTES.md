# Engineering Notes

## Purpose

이 문서는 구현 중 얻은 반복적인 인사이트와 운영/검증 메모를 모은다.
기획 문서보다는 구현 판단 기준에 가깝고, `AGENTS.md` / `CLAUDE.md` 를 보완하는 용도로 사용한다.

## 2026-09-11 Post-deploy public smoke boundary

- 기존 Lightsail deploy SSH handle과 AWS login PTY가 종료된 뒤, remote release symlink·systemd 상태를 읽을 수 있는 인증이 없어 public API만 순차적으로 확인했다. 이 smoke는 새 bundle이 실제로 반영됐다는 증거가 아니다.
- 공개 API 결과: `/api/health` HTTP 200 `2.841s`, `/api/scoreboard/home?date=2026-09-10` HTTP 200 `4.275s`, `/api/home?date=2026-09-10&myTeam=LG` 첫 요청 HTTP 200 `12.786s`, 즉시 반복 HTTP 200 `0.422s`, `/api/records/overview?season=2026` HTTP 200 `0.742s`.
- 추가 분리 측정에서는 `/api/schedule?month=2026-09`가 `0.290s`, `/api/standings?season=2026`가 `1.128s`, 미래 날짜 `/api/home?date=2026-09-11&myTeam=LG`가 `0.964s`, 다른 과거 날짜 `/api/home?date=2026-09-09&myTeam=LG`가 `3.625s`였다. 따라서 12초대 cold Home 한 표본만으로 전체 Home fan-out의 고정 병목이라고 결론내리지 않고, 날짜/cache 상태와 scoreboard cold path를 별도 계측 대상으로 둔다.
- timing을 보강한 `scripts/release-api-health-check.sh`를 public API에 실행해 DNS/TLS와 health, scoreboard, relay, Home, schedule, standings, records를 모두 통과시켰다. 첫 순차 run은 health `3.357s`, scoreboard `2.768s`, relay `429 items/미세 cache 상태`, Home `3.784s`, schedule `2.333s`, standings `0.393s`, records `5.349s`였고, 즉시 warm run은 각각 health `0.051s`, scoreboard `0.428s`, relay `0.071s`, Home `0.057s`, schedule `0.054s`, standings `0.049s`, records `0.048s`였다. 이는 현재 public cache가 warm일 때의 단일 readback이며 cold p50/p95나 새 release 반영 증거는 아니다.
- `RELEASE_API_HEALTH_PERFORMANCE=true`를 사용하면 같은 public endpoint 묶음을 `performance_phase=cold`와 `performance_phase=warm`으로 순차 실행한다. 실제 실행에서는 cold health `0.361s`, scoreboard `1.369s`, relay `1.325s`, Home `9.276s`, schedule `3.205s`, standings `0.136s`, records `2.095s`, warm health `0.043s`, scoreboard `0.584s`, relay `0.083s`, Home `0.078s`, schedule `0.069s`, standings `0.043s`, records `0.186s`로 모두 통과했다. 이 표본은 cold/warm 차이를 보여주지만 production p50/p95나 새 bundle 반영 증거는 아니다.
- Home 응답은 `success=true`와 `date`, `quickItems`, `kboBrief`, `standingsPreview`, `myTeam`, `myTeamBrief`, `meta`를 포함했고, records overview도 `success=true`로 `season`, `leaders`, `featured`를 반환했다. cold Home이 여전히 12초대이므로 장기 p50/p95나 새 release 성능 개선으로 일반화하지 않는다.
- 다음 production 판단에는 AWS 재인증 후 `/opt/kbo-fans/current` release, 두 systemd unit의 `active`/`NRestarts`, 메모리·swap·OOM journal을 먼저 읽는 순서가 필요하다. 그 readback 전에는 deploy/restart를 반복하지 않는다.
- `HomeService`는 section future를 제출한 시점부터 scoreboard/schedule/standings/records가 준비된 상대 시각과 `complete`/historical 여부를 `home_upstream_timing`으로 기록하고, payload 조립·recent-context까지 포함한 `home_total_timing`도 별도로 기록한다. 로그에는 payload·query·credential을 넣지 않으며, Home cold 표본의 날짜/cache 차이와 upstream 대기/서버 조립 비용을 원격에서 분리할 수 있게 하는 진단 계층이다. `test_home_logs_upstream_section_timing_without_payload_data`와 전체 backend 회귀가 이 계약을 고정한다.
- 새 계측을 붙인 local real-KBO cold smoke에서 `2026-09-10/LG`는 scoreboard `750.0ms`, schedule `754.5ms`, standings `754.6ms`, records `821.0ms`, total `821.6ms`로 `success` payload를 만들었다. 이는 local single-run evidence일 뿐 p50/p95나 production 증거는 아니지만, public에서 관찰한 12초대 Home 표본이 Home payload 조립 자체의 고정 비용이라고 보기는 어렵다는 inference를 만든다. 원격 원인은 새 release journal/readback으로 확인해야 한다.
- `ScoreboardService.get_home_scoreboard`도 `home_scoreboard_timing`으로 schedule/Main source가 준비된 상대 시각과 source readiness를 기록하고, lightweight game payload 생성·runtime save까지 포함한 `home_scoreboard_total_timing`을 별도로 기록한다. Home aggregate의 scoreboard component가 느릴 때 Home 로그와 같은 기준으로 schedule/Main 대기와 scoreboard 내부 조립 비용을 비교할 수 있다. payload·query·credential은 기록하지 않는다.
- schedule source가 실패해도 `home_scoreboard_timing ready=false`를 남긴다. 성공 timing만 남기면 production에서 503/504의 원천 실패와 단순 지연을 구분할 수 없으므로, 실패 경로도 payload 없이 관측 가능해야 한다. 해당 회귀는 `test_home_scoreboard_logs_timing_when_schedule_fails`로 고정한다.
- `RecordsOverviewCrawler`도 `records_overview_timing`으로 full/home mode의 지표 page별 준비 시각, 완료 여부, page count, 전체 fan-out 시간을 기록한다. records 첫 요청이 느릴 때 7개 원천 중 특정 page가 critical path인지 확인할 수 있고, 실패 시에도 page payload를 남기지 않고 `complete=false`를 기록한다. 성공·실패 계측은 records crawler 회귀 테스트로 고정한다.
- local real-KBO full records cold smoke에서 2026 season은 7 page 모두 성공하고 `avg 570.3ms`, `hr 428.4ms`, `ops 569.7ms`, `era 530.9ms`, `wins 530.4ms`, `saves 570.8ms`, `strikeouts 551.4ms`, total `574.4ms`였다. 이는 단일 local sample이며 production 분포는 아니지만, 지표 fan-out이 병렬로 수렴하는지 확인하는 기준값이다.
- Home seed를 보완하는 `get_overview_from_home`도 `mode=home_seed`로 OPS/wins/saves/strikeouts 4개 page의 준비 시각과 전체 시간을 기록한다. full overview와 lightweight Home overview의 cache seed 경계를 같은 로그 계층으로 관찰하되, 기존 OPS/OPS+ 파싱과 정상 응답 순서는 유지한다.
- local real-KBO cold scoreboard smoke에서 `2026-09-10`은 schedule `439.3ms`, Main `439.3ms`, source total `443.3ms`, 4 games였고 두 source가 같은 critical path에 수렴했다. 이는 local single-run evidence이며 production p50/p95가 아니지만, 원격에서 schedule/Main 중 한쪽만 비정상적으로 느린지 비교할 기준을 제공한다.
- 같은 날짜를 독립 Python process에서 세 번 cold 호출한 local sample은 `458.1ms`, `613.4ms`, `471.5ms`였고 Home total timing은 각각 `451.0ms`, `607.3ms`, `459.0ms`였다. 이 세 표본의 중앙값은 약 `471.5ms`이며, 두 번은 scoreboard가 critical path였고 한 번은 schedule이 약간 늦었다. 이는 local 변동성의 기준일 뿐 production latency 분포로 일반화하지 않는다.

## 2026-09-11 Lightsail release readback after timing bundle

- 최신 current release는 `/opt/kbo-fans/releases/20260911040207`이며 local `home.py`, `scoreboard.py`, `records_overview.py`, worker systemd unit SHA-256이 remote와 각각 일치했다.
- API/worker는 `active`, `NRestarts=0`; API MemoryPeak 약 `60.6MiB`, worker MemoryPeak 약 `68.6MiB`, available memory 약 `148MiB`, swap 사용 약 `221MiB`였다. 최근 kernel journal 샘플에는 OOM match가 없었다. 이는 해당 readback 시점의 snapshot이며 장기 안정성 증거는 아니다.
- remote API file log에서 Home total `2.120s`가 scoreboard `12.7ms`, schedule `12.8ms`, standings `1.799s`, records `2.045s`로 분해됐다. Home records page는 avg `750ms`, hr `1.950s`, era `1.228s`였고, full records home-seed 보완은 OPS `3.431s`, wins `3.749s`, saves `3.431s`, strikeouts `3.991s`, total `4.149s`였다. 원격 Home 지연은 payload 조립이 아니라 standings/records KBO 원천 대기라는 직접 증거가 확보됐다.
- scoreboard schedule/Main은 대부분 `0.17~0.35s`였지만 일부 `1.7~3.9s` 동시 spike가 관찰됐다. 두 source가 함께 느려지는 패턴은 KBO/instance network 변동성 후보로 남기며, source별 추가 병렬화는 적용하지 않는다.

## 2026-09-11 Lightsail sync-worker shutdown bound

- 승인된 Lightsail 배포에서 API는 새 프로세스로 health 응답을 시작했지만, 배포 SSH 세션이 sync worker 재시작 단계에서 장시간 반환되지 않았다. worker의 `sync_once`는 동기 KBO/APNs 요청 중 SIGTERM을 받을 수 있으므로, API readiness 성공만으로 배포 전체가 끝났다고 판단하면 안 된다.
- Lightsail sync-worker systemd unit은 `TimeoutStopSec=30s`와 `KillMode=mixed`를 명시한다. 정상적인 SIGTERM 정리 시간을 주되, 남은 worker process가 배포 SSH 세션을 무기한 붙잡지 않도록 systemd가 bounded kill을 수행한다. worker의 upstream/APNs 요청 자체는 기존 bounded timeout을 유지하며, 이 설정은 current/live 데이터나 push retry semantics를 바꾸지 않는다.
- `scripts/lightsail-deploy.sh`도 원격 명령 전체에 기본 600초 상한과 SSH keepalive/연결 timeout을 적용한다. systemd가 예상대로 종료되지 않거나 네트워크가 끊긴 경우 local deploy command가 무기한 대기하지 않으며, timeout 값은 `--remote-timeout-seconds`로 명시적으로 조정할 수 있다.
- `test_lightsail_sync_worker_shutdown_is_bounded`는 release bundle에 이 운영 계약이 포함되는지 검사한다. 배포 세션이 실제 반환되고 나서만 새 release readback과 cold/warm API 성능을 별도로 판정한다.

## 2026-09-10 Backend home cold fan-out

- `/home`의 scoreboard, schedule, standings, records overview는 모두 응답에 필요한 독립 upstream이므로 scoreboard 완료 뒤에 secondary를 제출하지 않는다. Future를 먼저 제출하고 기존 deadline 안에서 scoreboard를 우선 수집한 뒤 secondary 결과를 수집하면 cold aggregate의 직렬 대기를 제거할 수 있다.
- `/scoreboard/home`의 schedule과 main game list도 서로 독립된 source다. 두 요청을 bounded two-worker scope에서 동시에 시작하되, current schedule 실패 전파, main list 실패 시 기존 lightweight fallback, same-date serialization, per-game detail crawler 비호출을 유지한다.
- 이 병렬화는 API process-local cache와 worker/API runtime state를 분산 cache로 바꾸지 않는다. current/future 실패를 오래된 snapshot으로 숨기지 않으며, 실제 운영 개선은 새 bundle 배포 뒤 같은 날짜의 cold/warm p50/p95와 KBO source별 로그로 재확인한다.
- `/home`의 기록 카드에는 전체 records overview의 8개 지표가 필요하지 않다. current/future는 실제 aggregate가 소비하는 `avg`, `hr`, `era`만 병렬 조회하는 `get_home_overview`를 사용하고, `/records/overview`는 기존 전체 지표 fan-out을 유지한다. lightweight 조회도 current 실패를 빈 기록으로 바꾸지 않으며, historical season은 canonical full overview/snapshot 경로를 유지한다.
- `/home` aggregate의 일정 Future는 `ScheduleService.get_month_schedule_for_home`을 사용한다. 현재/미래 월은 일정 원천만 읽은 raw month cache를 사용하고, aggregate가 이미 받은 current scoreboard game을 해당 날짜에 합친다. 일반 `/schedule` 경로는 이 raw cache를 Main 목록으로 다시 보정해 기존 현재일 status/score 계약을 유지하며, historical month는 기존 snapshot-first 경로를 그대로 탄다.
- `/home`의 마이팀 recent context가 현재 월 completed result 5개를 채우지 못할 때만 이전 월 schedule Future를 current schedule 결과 직후 제출한다. 이 Future는 standings/records 결과를 기다리는 동안 실행되고, 5개 이상이면 추가 원천 호출을 만들지 않는다. deadline·historical partial fallback·previous-month failure 시 current schedule 유지 semantics는 그대로다.
- `api/runtime_services.py`는 `ScoreboardService`와 `ScheduleService`에 같은 `KboSourceCache`를 주입한다. schedule month와 Main 목록의 raw source 결과는 8초 동안만 process-local로 공유하고, normal/force 호출은 같은 key의 singleflight를 사용해 겹친 원천 요청을 만들지 않는다. 이 cache는 분산 cache가 아니며, 실패 시 current snapshot fallback으로 바뀌지 않는다.
- Lightsail deploy 직후 API가 이전 프로세스를 graceful shutdown하고 새 uvicorn을 listen하기까지 시간이 걸릴 수 있다. `scripts/lightsail-deploy.sh`의 내부 health probe는 connection-refused를 포함한 3초 요청을 최대 90초 동안 bounded retry하여 startup race를 실패로 오판하지 않지만, readiness가 끝내 안 되면 명시적으로 실패한다.
- `/records/overview`는 `ops`와 호환용 `opsPlus`가 같은 OPS page를 요구하므로, 두 결과를 한 번의 season page fetch에서 각각 파싱한다. wire key와 OPS-relative semantics는 유지하고, 현재 시즌 GET의 selected season이 맞지 않을 때만 기존 season POST를 수행한다. historical season의 POST/full metric fan-out은 변경하지 않는다.
- `RecordsOverviewCrawler`는 `path + season`별 HTML을 8초 동안 process-local로 보관하고 `get_overview`와 `get_leaderboard` 전환을 singleflight로 합친다. 이 cache는 화면 전환의 짧은 중복만 줄이며, service의 5분 normalized result cache나 historical snapshot의 immutable 규칙을 대체하지 않는다.
- 현재 Home overview cache가 identity와 rank-one shape를 통과하고 `avg/hr/era` 세 그룹 모두 완전하면 full overview는 그 seed를 보존하고 `OPS/OPS+`, `wins`, `saves`, `strikeouts`만 추가로 조회한다. 세 그룹 중 하나라도 비어 있거나 결과가 완전하지 않으면 canonical full crawler로 돌아가며, current 실패를 숨기는 fallback으로 사용하지 않는다.
- OPS/OPS+ 통합 후 full records overview의 고유 page는 7개이므로 crawler executor도 7 worker로 맞춘다. 이 범위는 한 records operation 안의 source fan-out이며, 외부 screen GET bulkhead나 historical snapshot 정책을 대체하지 않는다.
- records overview의 하나의 page가 실패하면 `_records_executor`가 `shutdown(wait=False, cancel_futures=True)`로 오류를 빠르게 반환한다. 이미 시작된 sibling page는 `BaseCrawler`의 bounded timeout으로 정리되며, 성공 시에는 기존처럼 모든 page를 기다린다.
- records overview의 결과 수집은 제출 순서만 기다리지 않는다. `FIRST_EXCEPTION`과 같은 aggregate deadline으로 먼저 실패한 page를 즉시 전파하고, deadline에 도달해 실패가 없으면 아직 끝나지 않은 첫 operation에 기존 operation-specific `UpstreamDeadlineExceeded`를 부여한다. 성공 시 payload 조립 순서와 historical fallback 경계는 그대로다.
- `BoxscoreService`는 current/future cache miss에서 `_game_status`의 schedule 조회와 공식 boxscore crawler를 2-worker로 함께 시작한다. 두 결과가 성공한 뒤 기존 status별 official/live-context 판단을 수행하고, historical game은 snapshot-first를 위해 기존 schedule 확인 후 crawl 순서를 유지한다.
- `LineupService`의 snapshot miss 경로는 lineup 원천과 boxscore 원천을 독립 Future로 동시에 읽고, 둘이 끝난 뒤에만 Main 목록 기반 선발 정보를 합친다. 과거 verified snapshot-first, current failure-visible, optional player metadata budget은 유지한다.
- `LineupService`의 snapshot miss 경로는 lineup·boxscore와 Main 목록 선발 lookup을 함께 시작한다. lineup/boxscore가 실패하면 Main Future를 기다리지 않고 기존 fail-fast 경계를 따르며, 정상 응답은 세 결과 중 Main 실패를 기존 optional `None`으로 처리하고 lineup/boxscore 결과를 기존 순서로 조립한다.
- `LineupService`가 shared `BoxscoreService`를 사용할 때 `_get_lineup_uncached`에도 caller의 `force_refresh`를 전달한다. LiveGameDataWarmService의 직접 boxscore Future와 lineup 내부 boxscore Future가 같은 `boxscore:{gameId}:force` SingleFlight key를 사용해 crawler 중복을 만들지 않으며, standalone `boxscore_crawler` fallback은 기존 인자를 유지한다.
- lineup/boxscore 병렬 fetch 중 하나가 실패하면 `_lineup_executor`가 non-blocking shutdown으로 실패를 전파한다. 이미 실행된 sibling crawler는 자체 bounded timeout으로 끝나며, 정상 응답에서는 두 결과를 모두 기다린다.
- lineup/boxscore 병렬 fetch는 완료 순서로 먼저 오류를 확인한 뒤 성공 결과를 기존 이름 순서로 조립한다. 따라서 boxscore가 먼저 실패하고 lineup이 느린 경우에도 lineup timeout을 기다리지 않으며, 정상 응답·snapshot fallback·current failure-visible 계약은 유지한다.
- runtime의 lineup starter metadata도 scoreboard/schedule과 같은 Main source cache를 사용한다. cache가 없는 경우에만 기존 Main crawler를 fallback으로 호출하며, force/current/historical 데이터 계약을 바꾸지 않는다.
- `BoxscoreCrawler`의 official boxscore 실패 시 live-context fallback도 runtime의 shared Main source를 우선 사용한다. fallback이 아닌 정상 official boxscore, relay 보강, current score availability 판단은 기존 흐름을 유지한다.
- `BoxscoreCrawler`의 live-context fallback은 연결된 `RelayService.get_cached_relay()`를 먼저 확인한다. 완전한 process/runtime relay가 있으면 currentAtBat을 재사용하고, cache miss에서만 직접 인증 relay crawler를 호출한다. 이 peek는 crawl하지 않으므로 relay session 경계를 새로 병렬화하지 않는다.
- full `ScoreboardService.get_scoreboard`도 schedule과 Main 목록 Future를 동시에 시작한 뒤 결과를 조립한다. schedule 실패의 historical fallback/current failure-visible, Main 실패 시 lightweight empty enrichment, same-date lock와 per-game detail fan-out 순서는 기존 계약을 유지한다.
- compact `ScoreboardService.get_compact_scoreboard`도 schedule과 Main 목록을 동시에 시작한다. schedule 실패의 current fail-visible/historical fallback과 Main 실패 시 빈 map 보강은 유지해, 위젯 경로의 cold latency만 두 원천의 최대 대기 시간에 가깝게 줄인다.
- 병렬 source 중 schedule이 먼저 실패하면 `ThreadPoolExecutor`의 기본 `shutdown(wait=True)`가 아직 실행 중인 Main 요청을 기다려 실패 응답을 늦출 수 있다. 세 scoreboard surface는 실패 분기에서 `shutdown(wait=False, cancel_futures=True)`를 사용하고, 이미 실행된 crawler thread는 자체 bounded timeout으로 끝나게 둔다. 이는 오류를 숨기지 않으면서 response path만 fail-fast하게 하는 경계다.
- `ScoreboardService.get_game`도 schedule과 Main 목록을 동시에 시작한다. schedule 실패 또는 요청 game 미존재 시 Main future를 취소하고 response path를 기다리지 않으며, Main 실패는 기존처럼 빈 summary 보강으로 처리한다. 상세 scoreboard crawler는 선택된 game에만 계속 적용한다.
- `ScoreboardService.get_game`에서 schedule future 예외는 `GameScheduleUnavailableError`로 구분해 전파한다. game route는 이를 schedule 재조회 없이 503으로 반환하고, RelayService 등 다른 소비자는 공통 `UpstreamUnavailableError` handler를 탄다. schedule이 성공했지만 game ID가 없을 때의 `None`과 route 404/scheduled fallback은 유지한다.
- current/future scoreboard와 game 요청에서는 historical immutable snapshot을 읽지 않는다. historical 날짜에서는 기존 snapshot-first 검증을 유지하고, current/future는 process/runtime cache 또는 live source 경계로 바로 이동해 불필요한 파일 I/O를 줄인다.
- 같은 원칙을 schedule, standings, records overview/leaderboard, team stats, team players, player detail에도 적용한다. historical key에서만 immutable snapshot을 읽고, current/future는 crawler 실패를 snapshot으로 숨기지 않으면서 불필요한 파일 read를 생략한다.
- 같은 상세 경계를 boxscore·lineup·relay에도 적용한다. current/live에서는 `runtime_*` cache read만 허용하고 immutable `boxscore`·`lineup`·`relay` snapshot read는 생략한다. historical에서는 기존 identity/completeness 검증과 snapshot-first/fallback을 유지하며, current failure를 과거 payload로 숨기지 않는다.
- `StandingsCrawler`는 현재 시즌의 최초 GET 응답이 available-season, selected season, hidden source season, source date year 검증을 모두 통과하면 그 HTML을 그대로 파싱한다. selector/source/date가 현재 시즌이 아니거나 초기 HTML 검증이 불가능한 경우에는 기존 WebForms season POST로 fallback하며, 최종 source season/date/rows 검증은 어느 경로에서도 생략하지 않는다.
- `PlayerStatsService`의 player detail miss도 team players와 같은 `SingleFlight` 경계를 사용한다. 동일 선수·시즌·player type의 동시 요청은 한 crawler 결과/예외를 공유하고, key가 다른 선수나 시즌은 독립적으로 진행한다.
- `PlayerStatsService`가 `player_type=None`으로 받은 상세를 성공시키면 payload의 실제 `playerType`을 명시 타입 cache key에도 alias한다. 자동 타입 key와 explicit 타입 key가 순차로 교차해도 같은 5분 payload를 재사용하며, payload type 불일치 검증과 current fresh-first 규칙은 유지한다.
- `TeamStatsService`도 팀·시즌 tuple을 key로 하는 `SingleFlight`를 사용한다. 같은 팀 기록 화면의 동시 miss는 crawler 한 번으로 합치고, cache 재확인 후 기존 historical snapshot/current fresh 경계를 적용한다.
- `TeamStatsCrawler`는 GET page의 season selector가 요청 current season과 같으면 WebForms POST를 생략한다. historical 또는 selector mismatch에서는 hidden form payload POST를 유지해 시즌 선택 결과를 바꾸지 않는다.
- `TeamStatsCrawler.get_team_stats`의 hitter/pitcher 병렬 원천도 `_team_stats_executor`를 사용한다. 한 테이블이 실패하면 sibling table의 crawler timeout을 기다리지 않고 오류를 전파하며, 성공 시에는 두 테이블 결과를 모두 기다리는 기존 payload 계약을 유지한다.
- `TeamStatsCrawler.get_team_stats`도 hitter/pitcher Future를 완료 순서로 먼저 검사한다. pitcher가 먼저 실패하는 역방향 경계도 hitter timeout을 기다리지 않고 전파하며, 정상 payload key와 두 표 모두 성공해야 하는 계약은 유지한다.
- `PlayerStatsCrawler.get_team_players`는 기존 6-worker enrichment pool 안에서 각 player profile Future와 초기 entry 선수의 total-stats Future를 함께 제출한다. profile 결과 후 최종 entry 여부를 다시 판정하고, profile/total 예외 fallback은 기존 row semantics를 유지한다.
- `PlayerStatsCrawler.get_player_detail`은 player type 결정 후 profile/total GET을 2-worker executor로 함께 시작한다. `_player_stats_executor`는 한 page 예외 시 sibling timeout을 기다리지 않고, 성공 시 두 HTML을 모두 수집한다.
- player detail의 profile/total GET은 완료 순서로 오류를 먼저 확인한다. Total page가 먼저 실패해도 profile page의 timeout을 기다리지 않고, 성공 시 두 HTML을 기존 파싱 순서로 사용한다.
- `PlayerStatsCrawler.get_team_players`의 position search와 player enrichment도 `_player_stats_executor`의 exception-only nonblocking shutdown을 사용한다. position group 하나가 실패하면 전체 API가 sibling crawler timeout을 기다리지 않지만, 성공 시 기존 group/player fan-out 수와 순서 보존을 우선한다.
- `PlayerStatsCrawler.get_team_players`는 한국어 공식 `Register.aspx` roster와 `RegisterAll.aspx` entry 목록을 먼저 함께 읽는다. roster가 비어 있거나 markup이 바뀐 경우에만 기존 영문 `PlayerSearch.aspx` four-group fan-out을 fallback으로 실행하므로, 정상 roster에서는 영문 GET/POST 8회를 반복하지 않는다. roster 원천 오류가 있어도 영문 검색이 성공하면 기존 fallback semantics를 유지하고, 두 원천이 모두 실패하면 오류를 숨기지 않는다.
- 한국어 roster row에 이름·role·투타·생년월일·체격이 모두 있으면 team-player 목록용 profile GET을 생략한다. entry row의 total stats GET과 영문 fallback row의 profile 보강은 유지하고, `/player/{playerId}` 상세 endpoint는 전체 profile/recent-games 조회를 계속 수행한다. 실제 로컬 KBO 계측에서 LG/KT 영문 검색은 각각 0 row였고 한국어 roster는 34 row였다.
- `PlayerStatsCrawler`는 team-player 원천에서 확인한 `(playerId, playerType)`을 5분 process-local cache에 기록한다. 앱의 player detail 요청처럼 type이 생략된 경우 cache를 먼저 사용해 `_guess_player_type` 판별 GET을 건너뛰고, cache miss에서는 기존 hitter→pitcher 판별을 유지한다. 상세 profile/total GET과 explicit type semantics는 변경하지 않는다.
- player type cache miss의 `_guess_player_type_with_html`은 판별 요청이 요청한 canonical type과 일치할 때 그 Basic HTML을 상세 profile 입력으로 재사용한다. hitter URL에서 pitcher profile이 드러나는 경우에는 URL 계약이 다르므로 재사용하지 않고 canonical pitcher Basic을 다시 읽는다. 따라서 잘못된 페이지를 profile로 오인하지 않으면서 중복 GET만 제거한다.
- current season의 완전한 한국어 roster는 `HitterBasic/BasicOld`, `HitterBasic/Basic2`, `PitcherBasic/Basic1`에 팀 filter를 적용한 3개 bulk page에서 player ID별 stats를 조합한다. `BasicOld + Basic2`로 hitter의 AVG/G/H/HR/RBI/SB와 SLG/OBP/OPS를 채우고, pitcher page는 ERA/G/W/L/SV/HLD/IP/SO/WHIP을 채운다. bulk page schema/filter 오류나 누락 player ID는 기존 `Total.aspx` 개별 fallback으로 남기며, historical/fallback English roster는 기존 경로를 유지한다.
- `BaseCrawler`의 `_request`는 owner thread의 기존 session을 보존하면서 worker thread마다 header를 복제한 독립 `requests.Session`을 lazy 생성한다. PlayerStatsCrawler의 직접 WebForms GET/POST도 같은 worker-local session을 사용해 한 form의 cookie/view state를 보존한다. 인증 relay는 `RelayCrawler`가 직접 소유한 session과 lock을 계속 사용한다.
- `BaseCrawler._breaker_state`는 여러 worker가 동시에 실패할 수 있으므로 read/increment/write를 `_breaker_lock` 아래에서 수행한다. 실패 시 현재 state를 다시 읽어 increment하고, success는 실패 state를 reset한다. HTTP 호출 자체는 lock 밖에 두어 정상 병렬 latency를 직렬화하지 않는다.
- `YoutubeHighlightService.fetch_highlights`는 lazy highlight endpoint의 `gameId + team names + limit` cache miss를 `SingleFlight`로 합친다. leader가 검색·oEmbed를 한 번 수행하고 동시 follower는 같은 결과/예외를 받으며, 빈 결과도 기존 10분 cache 정책으로 공유한다.
- `/team/{team_id}/records`의 players/stats 병렬 Future도 `_team_records_executor`를 사용한다. 한쪽이 실패하면 다른 원천 timeout을 기다리지 않고 오류를 전파하며, 정상 응답은 두 payload를 모두 조립한다.
- `/team/{team_id}/records`도 players/stats Future를 완료 순서로 확인해 stats 실패가 먼저 발생하는 경우 players timeout을 기다리지 않는다. 정상 응답은 기존 players·teamStats 조합을 유지한다.
- Home의 current/future section은 scoreboard 결과를 받은 직후 `FIRST_EXCEPTION`으로 이미 실패했거나 deadline 안에 실패한 section을 먼저 전파한다. no-failure timeout에서는 schedule·standings·records 중 실제 미완료 첫 operation의 오류명을 유지하며, historical partial fallback은 이 선검사를 건너뛴다.
- `LiveGameDataWarmService`는 한 경기의 relay를 먼저 fetch한 뒤 boxscore와 lineup을 병렬 warm한다. relay와 `BoxscoreCrawler`가 공유하는 인증 session lock을 동시에 건드리지 않으면서, 후반 상세 준비 시간은 두 독립 service의 최대 대기에 가까워진다. 여러 경기 간 cycle overlap은 기존 adaptive warmer 정책대로 허용하지 않는다.
- `LiveGameDataWarmService`가 먼저 가져온 game summary는 `RelayService.get_relay(game=...)`로 전달한다. game ID가 일치하는 제공 payload는 relay가 scoreboard를 다시 force lookup하지 않게 하며, 일반 API 호출이나 identity mismatch는 기존 lookup 경로로 fallback한다. relay 인증 session serial fence와 boxscore/lineup 후속 병렬화는 유지한다.
- `PushService.send_game_moment`의 scheduler/outbox 경로는 target claim을 먼저 모두 확보한 뒤 최대 3개 FCM send를 병렬 실행한다. 전송 결과는 원래 target 순서대로 registry에 mark해 retry 대상과 `completedAt` 판정을 보존한다. `event_id`가 없는 legacy 직접 호출은 기존 순차·첫 오류 중단 semantics를 유지한다.
- outbox claim/resolve는 `PushRegistry` batch mutation으로 각 이벤트당 registry lock/write를 claim 1회와 resolve 1회로 묶는다. 각 target의 claim ID는 개별 검증하므로 stale worker 완료가 다른 target이나 새 generation을 덮지 않는다.
- `PushRegistry`의 process/thread lock과 POSIX file lock은 기본 2초 bounded wait를 사용한다. contention은 `UpstreamBusyError`로 변환되어 기존 FastAPI 503 handler를 타며, lock 대기 중 registry write가 유실되지 않도록 `_mutate_data`의 정상 save 경계를 유지한다.
- `LiveActivityScoreboardSyncService`의 token fan-out은 revision ordering을 위해 serial `fence → send`를 유지한다. token별 APNs send를 병렬화하면 앞 token이 지연된 동안 뒤 token에 stale state가 먼저 전송될 수 있어 regression에서 `[old, new]` 순서가 관찰됐다. 모든 fence가 stale로 탈락한 경우에만 빈 `resolve_live_activity_updates` mutation을 생략한다.
- sync tick의 등록 gate는 `PushRegistry.live_activity_sync_registration_summary()` 한 번의 read에서 active Live Activity game IDs, active device 유무, active start-token 유무를 함께 계산한다. 기존 개별 selector의 의미와 KST/UTC TTL 판정은 유지하고, same-tick registry file lock/JSON parse 중복만 줄인다.
- `RelayService.get_relay`는 과거 경기의 완전한 canonical relay snapshot을 process cache/runtime snapshot보다 먼저 확인해 scoreboard game summary 원천 조회를 생략할 수 있다. snapshot은 game identity·상세 item 검증을 통과한 경우에만 사용하고, summary-only/current/live relay는 기존 경로를 유지한다.

## 2026-09-01 Backend two-level game-data cache

- 앱 로컬 cache만으로는 새 프로세스의 첫 상세 진입과 API/sync worker 프로세스 경계를 줄일 수 없다. 게임 상세 서비스의 정상 miss 경로는 `process-local TTL cache → shared runtime JSON snapshot → crawler → 검증 후 두 cache 저장` 순서로 둔다. 동일 process의 동시 miss는 `SingleFlight`로 한 번만 upstream을 호출한다.
- `runtime_*` namespace는 `SNAPSHOT_DIR` 아래에 저장하지만 historical immutable namespace와 분리한다. runtime payload는 `savedAt` 기준 TTL 안에서만 API가 재사용하고, TTL을 넘으면 current 데이터의 오류를 숨기지 않고 crawler/명시적 실패 경계로 돌아간다. KBO 경기일과 저장 시각의 timezone 규칙은 기존대로 KST/UTC instant를 각각 사용한다.
- sync worker는 기존 5초 lightweight scoreboard warm과 별도의 detailed warmer를 둔다. `/scoreboard/home`에서 `LIVE` 경기만 상세 3종(relay, boxscore, lineup)을 순차 수집해 API worker의 L2를 선행 채우며, `FINAL` 경기에는 같은 경로를 한 번 더 돌려 완전한 historical snapshot을 확정한다. relay/boxscore/lineup 중 하나가 미완성이면 finalization 완료로 표시하지 않는다.
- detailed warmer는 한 cycle이 끝나기 전에 다음 cycle을 시작하지 않는다. 로그에 `cycleDurationMs`, `nextIntervalSeconds`, live/final/finalized count와 구성요소별 error class를 남기고 다음 주기를 `max(minimum, measured * (1 + margin))`으로 정하되 상한을 둔다. 1경기 직접 호출 표본은 scoreboard 0.110초, relay 0.425초, boxscore 0.104초, lineup 0.132초(순차 합계 0.771초)였고, 실제 warm/finalization cycle은 relay 로그인과 서비스 조합을 포함해 2.981초였다. 다섯 경기 운영 p95는 배포 후 로그로 다시 측정해야 한다.
- API와 worker가 여러 ECS task로 늘어날 때 JSON runtime snapshot은 공유 EFS 같은 공용 저장소가 필요하다. 파일 snapshot은 crawler 분산 lock이 아니므로, 다중 writer를 도입할 때는 별도 distributed lease/queue를 추가하고 현재 단일 Lightsail worker 보장과 혼동하지 않는다.

## 2026-08-13 Bounded data delivery

- Dio의 `connectTimeout`/`receiveTimeout`만으로 전체 응답 시간을 제한할 수 없다. 앱 GET은 모든 attempt와 backoff를 포함하는 하나의 absolute deadline을 사용하고 deadline 시 `CancelToken`을 취소한다. transient GET만 한 번 재시도하며 정수 초 `Retry-After`를 존중한다. parse/일반 4xx/POST는 재시도하지 않는다.
- FastAPI의 sync route는 클라이언트 응답을 timeout해도 worker thread를 강제 종료할 수 없다. 화면 GET은 15초 response deadline과 8-slot bulkhead를 함께 사용하고, timeout된 작업이 실제 종료할 때까지 슬롯을 반환하지 않아 무제한 abandoned work를 만들지 않는다. 포화는 0.1초 안에 503으로 fail fast한다.
- `/home` fan-out은 request middleware에만 의존하지 않고 14초 이하 absolute aggregate budget과 bounded executor를 사용한다. section 하나가 고착돼도 context-manager executor 종료가 나머지 thread를 무한히 기다리게 하지 않는다.
- 앱 시즌 매치업 일정은 9개월 월별 Future를 최대 3개씩 읽더라도 전체 25초 deadline을 공유한다. 월별 worker가 늦게 끝나도 provider는 전체 오류로 종료하며, 3개 wave가 75초로 누적되지 않는다. 데이터 일부를 조용히 버리는 partial success는 공식 일정 truth를 훼손할 수 있어 허용하지 않는다.
- 홈 scoreboard와 경기 상세 refresh coordinator도 active 대기와 queued force refresh를 합친 하나의 25초 budget만 사용한다. 요청이 겹쳐도 두 번째 25초를 새로 시작하지 않고, 마지막 visible data와 다음 polling cadence를 유지한다.
- cookie 정합성을 위한 relay session lock과 force-refresh ordering을 위한 scoreboard date lock은 제거하지 않는다. 대신 lock 획득은 2초, SingleFlight follower는 전체 backend 예산보다 짧은 10초로 제한하고, 같은 live relay와 current team-player miss를 process 안에서 coalesce한다. follower를 2초로 자르면 정상 cold `/home`의 4~5초 leader까지 기다리지 못해 동시 사용자만 불필요하게 실패한다.
- sync worker의 scoreboard warm을 느린 relay/push delivery와 분리한다. `SCOREBOARD_WARM_INTERVAL_SECONDS` 기본 5초 monotonic cadence로 runtime singleton을 prime하므로 `PUSH_SYNC_INTERVAL_SECONDS`를 30/60초로 늘려도 warm은 느려지지 않는다. `LIVE_SCOREBOARD_MAX_AGE_SECONDS`는 warm interval + 5초 jitter 이상이어야 하며 기본 20초다. 이 보장은 warmer의 upstream call 자체가 끝나는 범위이며 분산 task coalescing을 의미하지 않는다.
- release-safe 실패 로그는 endpoint/elapsed/error class를 남기되 query, credential, upstream error 원문은 남기지 않는다. 503/504 envelope와 retry 분류는 앱/서버 회귀 테스트에서 함께 검증한다.
- deploy 중 worker가 `/var/lib/kbo-fans` registry를 atomic temp 파일로 교체할 수 있으므로, deploy script는 해당 runtime tree를 recursive `chown`하지 않고 안정적인 디렉터리 자체만 소유권을 맞춘다. 서비스가 생성하는 파일은 서비스 사용자로 이미 생성되며 transient temp 파일 race를 만들지 않는다.

## 2026-08-12 Eighth competitive audit

- Live Activity transient backoff는 worker 수명 동안 유지하되, 15분 이상 재시도되지 않은 delivery id를 매 tick 정리해야 한다. token unregister·rotation 뒤에도 만료 map entry를 남겨 두면 실제 발송 대상 없이 메모리가 선형 증가한다.
- API 일정 `SingleFlight`는 현재 프로세스 경계 안에서만 중복을 줄인다. API task를 수평 확장할 때의 분산 crawler coalescing은 별도 lease/queue와 운영 scale 정책이 필요하며, 이를 현재 구현의 보장으로 표현하지 않는다.
- Home·standings·records overview·leaderboard도 같은 process-local `SingleFlight` 규칙을 사용한다. `/home.myTeam`은 KBO 10개 팀 ID만 대문자로 정규화해 허용하므로 임의 key로 이 경계를 우회하지 못한다. 이 보장은 단일 API 프로세스 안의 동일 key에 한정된다.
- Push registration TTL은 물리 파일 GC와 발송 가능 여부를 분리한다. 등록 write는 기존 lock 안에서 stale entry와 종속 state를 정리하고, read/send selector는 registry를 다시 쓰지 않은 채 현재 UTC 기준 active view만 반환해 만료 token에 전송하지 않는다. timestamp가 없는 legacy entry는 기존 호환 정책대로 active로 본다.

## 2026-08-12 Seventh competitive audit

- 동시 요청을 줄이는 `SingleFlight`는 캐시보다 앞선 miss 경로에 붙여야 한다. 같은 프로세스에서 동일 월 일정을 동시에 요청하면 첫 crawler Future를 공유하고, 결과·예외를 모든 waiter에게 그대로 전달해야 한다. 캐시 hit와 historical snapshot identity 검증은 single-flight를 기다리지 않고 기존 순서를 유지한다.
- `SingleFlight`는 프로세스 로컬 seam이다. ECS API task를 여러 개로 늘리면 task별 coalescing만 제공하므로 분산 중복 fetch를 해결한다고 문서화하지 않는다. API scale-out이 필요하면 분산 lease/queue를 별도 설계하고, 현재 demo sync worker는 단일 task 정책을 유지한다.
- `JsonSnapshotStore`의 namespace별 retention/GC는 historical player·team·schedule 보존 계약과 직접 충돌할 수 있다. 정책 없이 오래된 파일을 삭제하지 말고 namespace별 파일 수·바이트를 측정해 80% 용량 경보를 먼저 두며, dry-run 승인 뒤 삭제 정책을 도입한다.
- 가로 지표 rail은 partial card만으로 스크롤을 추측하게 하지 않는다. 390/320/280px에서 마지막 카드가 잘릴 수 있는 rail에는 항상 보이는 짧은 scrollbar thumb/track을 제공하고, 1.6x 이상 큰 글씨에서는 세로 카드 목록으로 바꿔 scrollbar가 내용 높이를 압박하지 않게 한다.

## 2026-08-12 Fourth competitive re-audit

- Snapshot key만 믿는 것은 identity 검증이 아니다. team/player/schedule/scoreboard payload는 요청 key와 별도로 payload 안의 team/player/season/month/date/game identity와 root shape를 확인해야 한다. 손상 payload는 `.get()` 예외로 500을 만들지 말고 crawler 또는 명시적 unavailable 경계로 되돌린다.
- FastAPI의 `date` 타입은 연도 0001~9999를 허용하므로, KBO API route는 실제 upstream이 지원하는 1900~2100 범위를 별도 검사한다. 형식 검증만으로는 고카디널리티 crawler/cache key 오염을 막지 못한다.
- 웹은 제품 미리보기이므로 native debug diagnostics를 화면 위에 띄우지 않는다. `kIsWeb`에서는 DevConsole overlay를 끄고 browser console에 로그를 남기며, native local/debug에서만 명시 flag로 overlay를 켠다. root deep-link 화면은 router stack이 비어 있어도 `/records`로 돌아갈 visible leading을 소유해야 한다.
- GoRouter의 imperative `push`는 웹 주소에도 반영되도록 `optionURLReflectsImperativeAPIs`를 켠다. 그렇지 않으면 화면은 상세로 바뀌어도 hash가 `/schedule`·`/home`에 남아 새로고침·공유 시 상세 상태가 사라진다.

## 2026-08-12 Fifth competitive re-audit

- client metrics는 raw body 상한만으로 충분하지 않다. source별 process-local sliding window와 bounded source map을 함께 적용해 정상 진단량은 유지하면서 로그 회전·동기 I/O 폭주를 줄인다. 이 제한은 WAF/다중 worker 전역 rate limit을 대체하지 않는다.
- `player_type`처럼 외부 crawler 분기에서 의미가 바뀌는 query는 임의 문자열을 허용하지 말고 API schema에서 enum으로 닫아 unknown role이 타자 경로로 조용히 폴백하지 않게 한다.
- snapshot의 파일 key가 안전해도 root payload가 list이면 `.get()` 호출에서 500이 날 수 있다. historical overview/leaderboard 재사용 predicate는 root dict와 rank-one shape를 먼저 확인한다.
- JsonSnapshotStore의 namespace별 파일 수·총량 GC는 운영 정책과 충돌할 수 있어 이번 라운드에서는 변경하지 않았다. 현재 서비스 route의 season/key bounds와 runtime cache cap은 유지하며, 장기 EFS inode/backup 비용은 별도 운영 작업으로 추적한다.

## 2026-08-09~10 Competitive Audit Convergence

두 독립 비평이 사용자 여정·접근성 감사와 데이터/성능/운영 감사로 경쟁한 뒤, 공통 위험을 다음 구현 경계로 수렴시켰다.

## 2026-08-11 Follow-up hardening

- `TeamScore.scoreAvailable`은 모델 보조 플래그가 아니라 숫자 표시의 truth gate다. ScoreTab 합계·접근성 문구·relay score strip·home my-team LIVE card는 모두 `displayScore`를 사용하고, backend schedule fallback은 score/H/E/B를 실제 원천 값이 없을 때 `null`로 유지한다.
- `/scoreboard/home`의 lightweight builder는 `SCHEDULED`/`CANCELLED`에서 schedule·Main 목록의 `0`을 score로 merge하지 않는다. `/home` quick item도 해당 상태를 verified score로 인정하지 않아 legacy `팀 0 : 0 팀` payload가 남아도 `팀 vs 팀`으로 표시한다. 확인된 LIVE/FINAL 0:0은 그대로 유지한다.
- `LiveActivityScoreboardSyncService.sync_date`는 registry에 device/live/start registration이 없으면 KBO warm-up·pending moment scan·heartbeat full rewrite를 하지 않고 `idle=true, warmed=false`를 반환한다. 이 경계는 등록 사용자가 있는 cadence를 줄이는 것이 아니라 0-user worker의 불필요한 upstream/EFS 작업만 제거한다.
- 에러 화면은 pull-to-refresh만으로 복구를 암시하지 않는다. leaderboard는 provider key를 캡처한 명시 `다시 시도` button으로 invalidate하고, large-text relay fallback은 fixed height 대신 `minHeight`만 둬 안내가 natural height로 늘어난다. profile metadata는 trim 후 non-empty 값만 pill로 만든다.
- 공개 client metrics는 운영 telemetry이므로 임의 JSON을 그대로 받지 않는다. route가 raw body를 먼저 16 KiB로 제한하고 JSON object만 logger에 기록해 oversized body가 Pydantic/log serialization까지 도달하지 않게 한다.
- AWS ALB의 HTTP listener는 `UseHttps` 조건부 action으로 HTTPS 301 redirect를 사용한다. HTTP forward는 certificate/domain이 없는 일시적 smoke 모드에만 남긴다.
- 순위의 normal 56px 행은 1.4x부터 large-text variant로 전환한다. normal/large 행 모두 하나의 `Semantics(container: true)` label로 순위·팀·승패·승률·경기 차·연속을 읽게 하고 내부 장식 텍스트는 제외한다.
- API 입력은 crawler 호출 전에 route boundary에서 제한한다. month는 `YYYY-MM`, current/home/compact/push sync date는 실제 `YYYY-MM-DD` civil date, game id는 선두 날짜·KBO 두 팀 코드·bounded suffix, team id는 canonical KBO allowlist, player id는 영숫자·`_`·`-` bounded string, season은 1900~2100, leaderboard metric은 32자 이하 식별자로 고정한다. 구성 상태 diagnostics도 sync secret 없이는 503이다.
- `PushRegistry._mutate_data`는 90일 지난 runtime state와 7일 이상 pending outbox를 정리하고 pending outbox를 2,048건으로 제한한다. 전송 중인 outbox claim은 lease 만료 전 제거하지 않는다. `LiveScoreboardStore`는 shared JSON을 최근 14개 날짜로 제한해 날짜 rollover가 파일을 무한히 키우지 않게 한다.
- `record_sync_heartbeat`는 payload가 같으면 기본 30초 동안 기존 `updatedAt`을 유지해 no-op mutation이 registry 전체 JSON을 다시 쓰지 않게 한다. 실제 heartbeat payload가 바뀌거나 간격이 지나면 갱신하므로 diagnostics의 liveness 신호는 유지한다.
- Live Activity scoreboard sync의 transient APNs 실패는 worker 생명주기 동안 token/content signature별 지수 backoff(5·15·30·60초)를 유지한다. 새 content signature와 영구 token 실패는 backoff를 폐기해 정상 전환·prune을 막지 않는다. 15분 동안 재시도되지 않은 token backoff는 매 tick 정리해 token rotation·unregister 뒤 worker 메모리가 누적되지 않게 한다.
- APNs Live Activity sender는 lazy HTTP/2 client를 sender 수명 동안 공유하고 `close()`를 제공한다. 여러 token update/start fanout은 기본 최대 4개 bounded worker로 처리하되 executor 결과 순서는 기존 token 순서를 유지하고, 각 worker의 claim·generation·permanent prune 경계는 독립적으로 보존한다.
- CloudFormation sync worker는 단일 task로 제한해 같은 경기의 KBO crawl과 push diff를 중복 실행하지 않는다. EFS push registry는 암호화·AWS Backup 활성화·Retain 정책으로 stack 교체/삭제 시에도 보존한다.
- `BaseCrawler` circuit breaker는 열린 회로가 cooldown을 지나거나 비활성 실패 상태가 TTL을 지나면 제거하고, 고카디널리티 breaker key도 4,096개 상한을 넘기지 않는다. 임의 game id가 process-wide dict를 무한히 키우지 않게 하는 메모리 방어선이다.

### UI truth and lifecycle

- 홈/일정에서 상세 진입 전에 4초 refresh와 최대 80개 이미지 warm-up을 기다리게 하면 데이터 신선도보다 navigation latency가 더 큰 사용자 실패가 된다. 화면은 현재 카드의 `Game`/route로 즉시 열고 provider 갱신을 background로 넘긴다. 상세 화면이 마지막 정상 데이터, loading, 오류, 재시도를 소유해야 한다.
- timeout을 자동 갱신 중 spinner로 바꾸지 않는다. 라인업, push diagnostics, 알림함처럼 실패 의미가 다른 Future는 loading/error/retry를 독립 상태로 표현하고, 읽음 receipt 같은 보조 write 실패가 deep link를 막지 않게 한다.
- 긴 relay 목록은 `SliverList`로 lazy build하고 실제 scroll target이 아닌 item마다 `GlobalKey`를 만들지 않는다. 필터·정렬·segment처럼 시각적으로 선택 상태가 있는 공통 pressable에는 `semanticSelected`도 같이 전달한다.
- 날짜 문자열을 `build()`에서 다시 계산하는 것만으로는 켜진 화면이 KST 자정을 넘을 때 rebuild되지 않는다. root가 다음 `Asia/Seoul` 자정 timer와 resume에서 `kboDateProvider`를 갱신하고, home/schedule 같은 날짜 구독자가 provider key를 교체해야 한다. standings/records는 `followsCurrentSeason` 상태를 별도로 두어 현재 시즌 선택만 1월 1일 KST rollover를 따르고 명시적으로 고른 과거 시즌은 고정한다.
- 시즌 일정처럼 여러 월을 합치는 조회는 무제한 `Future.wait` 대신 최대 3개 worker로 bounded concurrency를 적용하고 indexed result에 담아 원래 월 순서를 보존한다. bounded helper를 repository에 직접 연결하면 기존 `scheduleProvider` cache/override seam을 우회하므로, 각 worker는 `scheduleProvider(yearMonth).future`를 읽어야 한다. 한 월 실패를 빈 월로 바꾸거나 부분 시즌을 정상 결과로 반환하지 않는다.
- 월별 일정과 시즌 aggregate는 별도 provider이므로 월 수동 갱신만 invalidate하면 매치업·구장별 전환에서 이전 월이 되살아난다. 달력·구장별·매치업 refresh는 현재 월과 `seasonScheduleProvider(season)`을 함께 무효화하고 새 Future를 기다린다.
- 기본 surface의 정상 설명·메타데이터에는 disabled 색이 아니라 4.5:1 이상을 보장하는 `textSupporting`을 사용한다. 고대비 dark의 accent도 모든 dark surface에서 4.5:1 이상이어야 한다. 아이콘형 뒤로가기는 visible icon만 두지 말고 `뒤로` semantics/tooltip을 제공하며, 앱에 한국어 localization delegate를 연결해 framework가 자동 생성한 leading도 영어 `Back`으로 남기지 않는다. 280px·320px와 240% 글자에서는 hero/탭/scorebug/선수·지표 카드, 리더보드 행, 알림 요약, 브리핑 filter를 고정 한 줄에 압축하지 않고 높이 증가나 `Wrap`으로 재배치한다.
- 데이터 브리핑도 화면을 연 시각의 문자열이 아니라 `kboDateProvider`를 watch해야 한다. KST 자정·resume 뒤 aggregate key와 refresh key를 모두 최신 `yyyy-MM-dd|myTeamId`로 바꾸지 않으면 전날 데이터가 계속 보인다.

### Data truth, storage, and security

- KBO 순위는 연도별 WebForms selector를 실제 요청하고 `requested season == selected season == hidden source season == sourceDate.year`를 검증한 뒤 cache/snapshot에 넣는다. historical fallback도 같은 exact-season 검증을 통과해야 한다.
- 박스스코어는 `official`, `live_context`, `official_unavailable`을 payload에 명시한다. current/LIVE에서 양 팀의 검증된 공식 타자·투수 line이 없으면 인접 경기나 과거 snapshot을 빌리지 않는다. 인접 경기 보정은 같은 팀 조합의 검증된 historical final에서만 허용한다.
- GET은 조회 결과 때문에 외부 알림을 발송하지 않아야 한다. lineup GET은 enrichment와 snapshot write까지만 수행하고 `lineup_opened` 감지·FCM 발송·registry mutation은 sync worker에 둔다.
- tracked snapshot seed와 runtime snapshot은 같은 디렉터리를 쓰지 않는다. container image의 `data/snapshots`는 read fallback seed이고, 기본 write는 `data/runtime/snapshots`; CloudFormation과 standalone ECS task definition의 API/worker는 모두 `SNAPSHOT_DIR=/var/lib/kbo-fans/snapshots`로 같은 공용 EFS runtime path를 사용한다. Lightsail current release는 `SNAPSHOT_SEED_DIR=/opt/kbo-fans/current/backend/data/snapshots`, runtime은 `/var/lib/kbo-fans/snapshots`를 사용하며 deploy가 seed를 runtime으로 복사하거나 기존 runtime을 덮어쓰지 않는다. 이 경계가 없으면 조회만 해도 tracked seed가 바뀌고 여러 task가 서로 다른 snapshot을 보게 된다.
- 앱 API cache는 현재 KBO 날짜·월·시즌과 일반 current/LIVE game payload를 `SharedPreferences`에 쓰지 않는다. 단, 경기 상세의 문자중계·박스스코어·라인업은 game identity·shape·표시 가능성 검증을 통과한 마지막 성공 응답만 60초 bounded local cache로 저장하며 정상 요청은 network-first를 유지한다. connection/timeout/gateway failure 때만 이 local cache를 사용하고 `RelayData.isStale`, `GameBoxscoreData.isStale`, `GameLineupData.isStale`로 화면에 저장 데이터 사용을 표시한다. 수동 상세 refresh는 cache fallback을 우회한다. historical entry는 key 192 bytes, entry 256 KiB, 64 entries, total 2 MiB 제한과 oldest-first eviction을 적용하고 cache mutation은 직렬화한다. 저장 불가능한 current fresh response는 같은 key의 마지막 검증 cache를 보존한다. identity와 완성도 검증을 통과한 `FINAL`/`CANCELLED` 경기, 과거 일정·순위, 과거 시즌 기록은 시간 만료만으로 background 재검증하지 않고 명시적 force/cache-key·schema 변경/사용자 초기화/capacity eviction 때만 다시 받는다. `SUSPENDED`, summary-only relay, 비공식·빈 boxscore, 불완전 lineup, 다른 identity나 rank gap payload는 표시할 수 있어도 immutable cache로 저장하지 않는다. 이미 저장된 payload의 identity·shape·완성도가 깨진 경우에는 폐기하며, current fresh 응답이 일시적으로 불완전할 때는 기존 검증 cache를 보존한다.
- backend 문자중계는 process-local L1 TTL과 worker/API가 공유하는 `runtime_relay` JSON L2를 함께 사용한다. 정상 원문은 두 계층에 저장하고, L1 만료 또는 API process 재시작 뒤에도 runtime TTL 안의 완전한 relay snapshot을 재사용한다. 강제 갱신으로 새 완전 원문을 얻으면 기존 L1을 새 payload로 교체하고, 일시적 요약/불완전 응답으로 기존 완전 payload를 덮어쓰지 않는다.
- backend Home cache는 LIVE 응답 8초, KBO 오늘의 non-LIVE 응답 30초, 비오늘 응답 300초로 분리한다. 오늘 예정/빈 응답을 stable cache에 넣으면 scheduled→LIVE 전환과 새 편성이 최대 5분 숨을 수 있다.
- 공개 앱의 `forceRefresh=true` query를 upstream 권한으로 쓰지 않는다. query는 기기 cache 우회 호환 힌트로만 받고 backend TTL은 유지하며, configured `PUSH_SYNC_SECRET`과 exact match하는 `X-KBO-Push-Sync-Secret` header가 있을 때만 server-side force를 전달한다. 잘못된/없는 header는 4xx 대신 normal cached request로 downgrade해 기존 앱을 깨지 않는다.
- Live Activity server mutation은 ownership과 operator auth를 분리한다. `/live-activity/update`는 configured `PUSH_SYNC_SECRET`이 필수이고 UTF-8 bytes로 constant-time 비교해 비 ASCII 입력도 인증 실패 401로 처리한다. unregister는 `gameId + activityPushToken + activityId + installationId` 전체 tuple이 모두 nonblank이며 registry owner와 일치해야 한다. upgrade 전 앱의 missing/null installation id 또는 missing/null/blank token·activity id는 422 대신 `removed=0` no-op로 받되 ownerless registration까지 삭제 권한을 주지 않는다. client pending queue는 네 필드를 불변 세대로 보존해 새 owner 세대가 이전 실패 요청을 덮지 않게 하고, exact duplicate만 합치며 malformed 제거와 최신 32개 cap을 적용한다.
- 앱 시작의 push-to-start/native sync가 pending unregister 32개를 직렬 네트워크 timeout까지 기다리게 하지 않는다. pending drain은 owner 불변 queue를 유지한 채 unawaited background 작업으로 시작하고, native token sync와 Workmanager 등록은 즉시 계속 진행한다.
- Live Activity register의 previous-token rotation도 삭제 권한으로 취급한다. 기존 entry의 `gameId + activityId + installationId`가 새 요청과 exact match하고 두 owner id가 비어 있지 않을 때만 이전 token과 delivery state를 제거한다. request schema는 `gameId` 32, 현재/이전 token 512, `activityId`/`installationId` 128자 cap으로 비정상 identity가 registry key/state를 키우지 못하게 한다.
- iOS restart에서 native previous activity/start token이 `''`일 수 있으므로 Dart는 blank를 “명시적으로 이전 owner 없음”으로 해석하지 않고 prefs의 current token으로 fallback한다. activity와 push-to-start 등록은 종류별 serial queue에서 처리하고 HTTP 성공 뒤에만 prefs current token을 전진시켜, A→B가 끝나기 전에 B→C가 잘못된 previous owner로 발송되는 순서를 막는다.
- push-to-start rotation은 server-side CAS도 필요하다. exact current token의 같은-owner 재등록은 no-op 멱등 성공이지만, 다른 token으로 회전할 때는 nonblank previous가 registry의 유일 current owner token과 정확히 같아야 한다. 앱 queue만 믿으면 지연 A 요청이 B를 되돌리는 replay를 막을 수 없다.
- public push의 `installationId`는 ownership correlator이지 secret이 아니다. 현재 self-test와 receipt는 exact `deviceToken + installationId`만 권한으로 인정하고, 기존 owner가 있는 device/Activity/start token의 재할당은 409로 거절한다. upgrade 전 missing/null self-test·receipt는 200 safe-noop로 호환하되 발송·기록·registry mutation을 하지 않고 ownerless entry의 `None == None`도 권한으로 인정하지 않는다. token·owner·game·목록·receipt data는 schema에서 bounded하고 receipt data는 8개/4 KiB로 제한한다.
- registry는 기본적으로 `devices`, `liveActivities`, `liveActivityStartTokens` 각각 5,000개와 전체 32 MiB를 넘는 write를 429로 거절한다. `/push/test-device`의 설치별 60초 cooldown과 전체 60초당 30회 window는 registry에 저장해 process restart와 token rotation에도 유지한다. corrupt JSON/root/security section/owner/rate timestamp는 빈 registry로 바꾸지 않고 503으로 fail closed하며 거절·미등록 경로는 no-op write여야 한다.
- 세 공개 register는 공용 registry의 신규-owner admission을 기본 60초/120건으로 영속화하고, `lastSeenAt` 기준 device/start token 90일·Live Activity 2일 stale GC를 registration lock 안에서 수행한다. exact owner refresh와 정상 rotation은 admission을 소모하지 않고, stale registration의 cooldown/delivery/claim 부속 상태도 exact token 기준으로 함께 정리한다. timestamp/admission 손상은 fail closed한다.
- TTL/admission도 공개 자기신고 id를 새로 만드는 paced Sybil을 막지 못한다. 공격자가 분당 120건 이하로 속도를 조절하거나 가짜 owner를 계속 refresh하면 5,000개 capacity를 다시 고갈시킬 수 있고, lazy 5,000-entry scan/JSON file lock도 CPU·lock DoS 표면이다. trusted edge/WAF IP rate limit과 App Attest/Play Integrity 같은 attestation이 별도 계층으로 필요하며 프로세스 내부 limiter만으로 해결됐다고 간주하지 않는다.

### Polling and delivery dedupe

- 한 sync tick에서 relay moment 탐색과 Live Activity 현재 타석 보강은 game별 한 relay fetch를 공유한다. 같은 원천을 두 번 읽으면 latency뿐 아니라 서로 다른 seq snapshot으로 side effect를 계산할 위험이 있다.
- Live Activity 일반 update는 `updatedAt`을 제외한 content signature와 monotonic desired revision을 token별 registry state에 저장한다. 동일 signature는 건너뛰고, 각 APNs 호출 직전에 claim revision이 current desired revision과 같은지 원자적으로 fence한 뒤 lease를 sender timeout보다 길게 갱신한다. 이 실제-send fence가 없으면 batch 첫 token 전송 중 뒤 token lease가 만료돼 새 worker의 S2 뒤에 옛 worker의 S1이 도착할 수 있다. 부분 실패 뒤에는 성공 token이 아니라 실패 token만 재시도하고, token별 claim/resolve는 batch mutation으로 묶으며 실제 데이터가 같은 registry mutation은 disk write를 생략한다. terminal `end`와 unregister는 token 제거와 함께 delivery signature/revision state도 정리한다.
- APNs non-2xx를 일반 예외 문자열로 합치지 않는다. status와 JSON reason을 typed error로 보존하고 `400 BadDeviceToken`, `400 DeviceTokenNotForTopic`, `410 Unregistered`만 영구 token 오류로 분류한다. Activity token 문자열만 CAS key로 쓰면 A→B→A 재등록 뒤 오래된 실패가 새 A를 지울 수 있으므로 registration generation도 저장한다. update prune은 exact generation을, end는 한 lock에서 얻은 claim id+generation을 성공·실패 완료까지 확인한 뒤 registration·delivery state를 원자적으로 정리한다. 429·5xx·네트워크·파싱 불가는 기존 transient retry를 유지한다.
- LIVE/SUSPENDED 점수 하향은 무조건 거절하면 공식 정정도 영구 차단한다. 첫 하향값을 영속 candidate로 저장하고 기본 8초 뒤 같은 값이 다시 확인될 때만 수용하되 이닝 회귀 등 다른 monotonic gate는 유지한다. 확정 정정은 Live Activity state만 바로잡고 득점·역전 이벤트를 새로 만들지 않는다.
- 앱의 FCM registration/topic convergence도 serial queue를 통과시켜 startup, 마이팀 변경, follow 변경이 서로의 최신 topic write를 덮지 않게 한다.

### Verification boundary

- widget/unit tests와 static analyze는 route timing, state rendering, cache predicate, owner/dedupe contract의 회귀 증거다. 운영 KBO 응답 변화, KST 자정 장시간 실행, APNs/FCM 전달, iOS Live Activity/Dynamic Island, Android background, TestFlight/운영 backend 배포는 별도 runtime·실기기 증거가 필요하다.

## Local / Dev Data Behavior

- Backend는 active runtime component다. API-backed data, snapshot generation, push notification, Live Activity / Dynamic Island sync를 다루는 작업은 `app/`과 `backend/`를 함께 본다.
- 모든 일반 local/dev/release/web/native 앱 실행은 backend API mode를 기본으로 사용한다.
- Flutter provider routing은 `USE_BACKEND_API` 미지정 시에도 API mode다. 스크립트/CI에는 `USE_BACKEND_API=true`를 명시하고, direct KBO는 `USE_BACKEND_API=false`를 명시한 parser/debug 세션에서만 사용한다.
- release build는 화면 데이터와 push / Live Activity token registration 모두 운영 backend URL 기준으로 검증한다.
- 앱 startup은 원격 API prefetch를 소유하지 않는다. local onboarding/my-team 상태 확인 후 첫 route로 넘기고, scoreboard/home/records/schedule 요청은 각 화면 provider가 소유한다.
- noisy fallback 로그가 과하면 `local` / 테스트 바인딩에서 prefetch, metric, push init을 완화하는 방향이 안전하다.
- local, dev, release API base URL은 화면 provider와 push registration이 함께 쓰는 backend endpoint 설정값이다.
- 웹 빌드도 `APP_ENV=local` / `APP_ENV=release`에서 backend API를 기본으로 사용한다.
- KBO의 오늘 날짜/현재 시즌/예매·경기 시각은 앱 기기나 AWS host timezone이 아니라 `Asia/Seoul` civil time으로 계산한다. API cache의 `cachedAt`, snapshot `savedAt`, TTL 경과시간은 UTC instant로 저장·비교하고 미래 timestamp는 fresh로 인정하지 않는다.
- iPhone local debug에서 `localhost` API는 실기기에서 직접 닿지 않는다.
  - Mac LAN IP를 `API_BASE_URL`로 주입하고 `USE_BACKEND_API=true` 를 함께 지정해야 한다.
- direct KBO source는 backend parser parity/debug 확인 기준이다.
  - scoreboard live status는 `Main.asmx/GetKboGameList` 를 우선 참고한다.
  - 일정 파서는 `GetScheduleList`의 빈 action cell에서도 `gameId`를 날짜+팀 코드로 복원해야 한다.
  - relay는 `LiveTextView2.aspx` markup(`#numCont*`, `p.present`, `.playerBox`) 기준으로 파싱한다.
  - direct relay 인증정보는 무시된 로컬 환경에서만 주입하고, 값이 없으면 로그인 요청 전에 명시적으로 실패한다. 코드·문서·공유 빌드에 평문 값을 넣지 않는다.
- local/mobile 알림은 remote push가 아니라 앱 내부 비교 로직이다.
  - scoreboard diff: 경기 시작 / 득점 / 역전 / 종료
  - relay diff: 홈런 / 이닝 교대
  - lineup diff: 선발 라인업 공개 / 변경
  - 따라서 앱이 완전히 죽어 있으면 서버 push처럼 즉시 오지 않는다.
- 앱이 꺼진 뒤에도 알림이나 Dynamic Island가 바뀌려면 앱 direct KBO 경로가 아니라 운영 백엔드가 상태 변화를 읽어야 한다.
  - FCM은 일반 push notification 전달 채널이다.
  - iOS Live Activity / Dynamic Island 원격 갱신은 ActivityKit push token + APNs `liveactivity` push 채널이다.
  - iOS 17.2+ 자동 시작은 ActivityKit push-to-start token + APNs `liveactivity` `event=start` 채널이다. 앱이 한 번 실행되어 `/push/live-activity/start-token/register`에 token과 `installationId`를 등록해야 하며, 설치 후 한 번도 실행하지 않은 앱이나 Live Activity/알림 권한이 꺼진 단말은 서버가 임의로 시작할 수 없다.
  - backend scheduler가 live 경기 중 5초 간격으로 scoreboard/relay sync를 실행하고, 시작 10분 전 예정 경기에는 push-to-start `event=start`, 등록된 ActivityKit token에는 update/end payload를 보낸다.
  - 같은 scheduler가 이전 scoreboard state와 비교해 FCM topic push용 `game_start_soon`, `lineup_opened`, `game_start`, `scoring`, `reversal`, `game_end`, `inning_change`, `at_bat` moment를 발행한다.
  - scoreboard/relay baseline이 2분 이상 오래되었거나 `updatedAt`을 해석할 수 없으면 scheduler는 그 차이를 FCM moment로 발행하지 않고 현재 scoreboard state/relay last seq만 저장한다. 푸시 설정 직후나 worker 재시작 뒤 밀린 lineup/hit/homerun을 backfill하지 않는 정책이다.
  - 일반 경기 event FCM은 backend가 원정팀/홈팀 topic과 `*_GAME_{gameId}` 경기별 topic으로만 발송한다. 앱은 마이팀 team topic을 자동 구독해, 사용자가 `푸쉬 중계 받기`를 누르지 않아도 마이팀 경기 시작/시작 임박/득점/안타/홈런/역전/종료/라인업/이닝 변경/타석 push를 받을 수 있다. selected-game GAME topic은 기존 enabled 기준을 쓰되, 선택 경기가 마이팀 경기이면 team topic만 유지해 중복 수신을 피한다. legacy `allGames=true`가 남아 있어도 game moment `*_ALL` topic은 앱/backend 모두 만들지 않는다.
  - `baseball_info`는 특정 경기 event가 아니므로 `followedGameIds`가 있어도 GAME topic을 만들지 않는다. 앱 registration은 `baseball_info_<팀>`을 기본으로 사용한다. long-running sync worker는 KST `09:30,16:00,22:30` 기본 슬롯에서 smart daily 브리프를 하루 한 번씩 시도하고, `PUSH_BASEBALL_INFO_SMART_DAILY_TIMES`로 슬롯 조정 또는 `off` 비활성화를 지원한다.
  - 일반 FCM message의 iOS APNs config는 `apns-push-type=alert`, app bundle `apns-topic`, `aps.alert`, `aps.content-available=1`, `apns-priority=10`, default sound를 명시한다. 앱 쪽은 `remote-notification` background mode와 Firebase background handler를 유지해야 한다. 앱 실행 시점에 몰려 보이는 증상이 재현되면 이 alert-class payload가 운영 image에 배포됐는지 먼저 확인한다. foreground 수신은 OS banner 대신 앱 내부 팝업으로 표시하고, 팝업 `보기` route는 sanitizer를 통과한 내부 route만 허용한다.
  - `GameEventAlertService`의 scoreboard/relay diff 기반 local notification은 local 개발 모드에서만 처리한다. release/dev에서 이 경로가 켜져 있으면 앱 resume/focus 시 지난 이벤트가 몰아서 표시될 수 있으므로 backend remote push와 역할을 섞지 않는다. 권한 off 상태에서도 snapshot baseline은 갱신하고, snapshot이 오래됐거나 settings signature가 바뀐 첫 tick은 알림 발행 없이 현재 상태만 저장한다. 회귀 확인용으로만 `--dart-define=ENABLE_LOCAL_GAME_EVENT_ALERTS=true`를 명시해 보조 로컬 알림 경로를 켤 수 있다. 이 로컬 경로도 legacy all-games 설정을 무시하고 마이팀 또는 직접 follow한 경기만 추적한다.
  - scoreboard diff만으로 확정하기 어려운 `homerun` moment는 같은 scheduler가 live relay seq baseline을 저장하고, 새 relay item의 `HOMERUN` event 또는 `홈런` 텍스트를 감지해 발행한다.
  - 앱 종료/백그라운드 push가 안 오면 먼저 `/push/register`가 실제 기기에서 성공해 registry `devices`가 채워졌는지 확인한다. 마이팀 자동 push라면 registry `topicCounts`의 `scoring_{팀}` / `hit_{팀}` / `game_start_soon_{팀}`와 `deviceSummaries`의 `installationIdSuffix` / `notificationsAllowed` / `authorizationStatus` / `apnsTokenReady`를 본다. 특정 타 팀 수동 경기 알림이라면 `followedGameIds`와 `scoring_GAME_{gameId}` / `hit_GAME_{gameId}` / `game_start_soon_GAME_{gameId}`도 같이 확인한다. 앱은 마이팀 선택 후 non-local 환경에서 최초 1회 권한 요청과 FCM registration sync를 자동 시도해야 한다.
  - 앱은 `/push/register`에 stable `installationId`를 함께 보내며, backend는 같은 설치 id로 새 FCM token이 들어오면 이전 token registration을 제거한다. owner가 설정된 token은 installation id 누락·불일치 갱신으로 가져갈 수 없다. 팔로우 경기 상태가 권한/APNs 준비된 현재 token이 아니라 오래된 token에 남는 증상이 보이면 `installationIdSuffix`와 `updatedAt`을 먼저 비교한다.
  - `deviceSummaries.updatedAt`은 앱이 `/push/register`를 보낸 시각이고, `topicsUpdatedAt`은 운영자가 registry 기반 topic resubscribe를 수행한 시각이다. 단말 최신성 판단에는 `updatedAt`과 권한/APNs 상태를 보고, resubscribe 성공 여부에는 `topicsUpdatedAt`과 topic count를 본다.
  - 배포 후 `GET /api/push/config-status` 또는 `python -m kbo_fans_backend.scheduler.push_config_status`로 Firebase/APNs/registry/scheduler secret 누락을 먼저 확인한다.
  - local·운영 backend 모두 `PUSH_SYNC_SECRET`이 없으면 공개 `config-status` diagnostics를 열지 않고 503으로 거절한다. `/push/test`, `/push/baseball-info`, `/push/resubscribe-topics`, `/push/live-activity/update`, `/push/live-activity/sync-scoreboard` 같은 mutation endpoint도 secret 미설정·불일치 상태에서는 Firebase/APNs까지 진행하지 않고 503/401로 막아야 한다. 로컬 진단은 `PushConfigurationDiagnostics`를 직접 실행하거나 secret을 명시한 readiness 경로로 수행한다.
  - 앱 내부 receipt 확인용 `/push/test-device`는 운영 secret을 요구하지 않는다. 대신 현재 앱이 FCM token과 stable `installationId`를 `/push/register`로 먼저 저장하고 self-test에도 exact owner tuple을 보내야 한다. backend는 registry에 없는 token·owner 불일치에는 발송하지 않으며, 설치별 cooldown과 전체 rate window를 registry에 영속화한다. legacy missing/null owner는 200 safe-noop라 배포 순서 호환은 유지하지만 테스트 push 권한을 얻지 않는다. 앱 번들에 `PUSH_SYNC_SECRET`을 넣지 않기 위한 self-test 경계이지 public attestation은 아니다.
  - 외부에서 `PUSH_SYNC_SECRET=<secret> ./scripts/push-readiness-check.sh https://api.kbofans.com/api`를 실행하면 `/health`와 push readiness를 같이 확인할 수 있다.
  - GitHub Actions secret 컨텍스트에서 원격 테스트 푸시를 보낼 때는 `Push Test Notification` workflow 또는 `./scripts/github-push-test-notification-run.sh --topic baseball_info_ALL --watch`를 사용한다. 이 helper는 secret/token 값을 출력하지 않는다.
  - `Push Test Notification`을 `*_GAME_<gameId>` topic으로 보낼 때는 backend가 `type`, `gameId`, `topic`, 상세 `route` data를 함께 실어 receipt 조회에서 해당 팔로우 경기 수신 여부를 필터링할 수 있어야 한다.
  - 실제 단말이 remote push를 처리했는지 확인할 때는 `PUSH_SYNC_SECRET=<secret> ./scripts/push-receipt-status.sh --expect-receipt --game-id <gameId> --type <type>` 또는 GitHub Actions `Push Receipt Status` workflow / `./scripts/github-push-receipt-status-run.sh --expect-receipt --game-id <gameId> --type <type> --watch`를 사용한다. 앱 receipt write도 등록된 `deviceToken + installationId` exact owner와 bounded data만 허용한다. 조회 경로는 `/push/config-status`의 `deviceSummaries`와 `recentPushReceipts`만 요약하고 raw device token은 출력하지 않는다.
  - 2명 안팎의 tester 상시 운영은 Lightsail 512MB native systemd 경로를 우선한다. `./scripts/lightsail-deploy.sh`는 backend runtime bundle만 SSH/SCP로 올리고, API와 `live_activity_sync_loop`를 같은 인스턴스에서 systemd로 실행한다. 이 경로는 Docker/ECR/ECS/ALB/EFS/Secrets Manager를 쓰지 않고 file secret(`/etc/kbo-fans`)과 local registry(`/var/lib/kbo-fans`)를 쓴다. current release seed는 `/opt/kbo-fans/current/backend/data/snapshots`, mutable runtime은 `/var/lib/kbo-fans/snapshots`로 분리하고 deploy는 runtime snapshot을 seed로 덮어쓰지 않는다.
  - 기존 AWS 비용 guard는 `kbo-fans-cost-guard` stack으로 AWS Budget SNS, Lambda, EventBridge scheduled check를 묶었지만, 15분마다 Cost Explorer actual/forecast API를 호출해 Cost Explorer 과금을 만들었다. 2026-07-08 기준 stack은 삭제했고 recurring guard는 운영 기본값이 아니다. 비용 확인은 Cost Explorer API를 반복 호출하기보다 ECS/ELB/EIP/NAT/Lightsail 같은 리소스 목록 audit과 native AWS Budgets 알림을 우선한다. `./scripts/aws-cost-guard-deploy.sh`는 사장님이 API 조회 비용을 승인한 비상용 도구로만 쓴다.
  - backend image는 `./scripts/aws-push-image.sh`로 ECR에 push하고, 출력되는 `CONTAINER_IMAGE_URI`를 CloudFormation 배포에 사용할 수 있다.
  - AWS ECS/Fargate에서는 Firebase Admin JSON, APNs `.p8`, KBO relay credential을 Secrets Manager에서 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`, `KBO_RELAY_USER_ID`, `KBO_RELAY_PASSWORD` env로 주입하는 것이 파일 mount보다 단순하다. 로컬/EC2 파일 배포는 `*_PATH`를 계속 쓸 수 있다.
  - ECS task definition의 `secrets` env 주입은 task execution role 권한에 의존한다. `./scripts/aws-push-task-definitions.sh`가 생성한 `iam-task-execution-secrets-policy.rendered.json`를 execution role inline policy로 붙이고, AWS managed `AmazonECSTaskExecutionRolePolicy`도 함께 붙인다.
  - ECS task 등록이나 service 생성 전 `./scripts/aws-push-deploy-check.sh`로 env, rendered JSON, secret, IAM role, ECR, EFS, CloudWatch log group을 한 번에 확인한다.
  - 수동 ECS 조립 대신 `./scripts/aws-push-cloudformation.sh`를 쓰면 ALB, API service, sync worker, EFS token registry, IAM role, log group을 한 stack으로 만든다. ECR image, VPC/subnet, Firebase/APNs secret ARN은 여전히 사전 준비가 필요하다. 도메인/ACM 전 임시 backend smoke는 `ENABLE_HTTPS=false`로 가능하지만, iPhone release token registration은 HTTPS로 되돌려야 한다.
  - CloudFormation deploy 후 `./scripts/aws-push-stack-outputs.sh`가 stack output `ApiBaseUrl`을 `RELEASE_API_BASE_URL` / `API_BASE_URL`로 저장한다.
  - 전체 시연 배포는 `./scripts/aws-push-demo-deploy.sh`를 우선 사용한다. 이 스크립트는 secret upload, ECR image push, CloudFormation deploy, stack output export, push readiness 순서로 실행한다.
  - scoreboard sync 기본 날짜는 AWS UTC가 아니라 KBO 경기일 기준인 `Asia/Seoul`로 계산해야 한다.
  - 5초 시연에는 `python -m kbo_fans_backend.scheduler.live_activity_sync_loop` long-running worker가 EventBridge 1분 one-shot보다 예측 가능하다.
  - `config-status.scheduler.lastSyncAt`은 sync worker가 실제로 registry에 heartbeat를 남겼는지 보는 운영 신호다. secret readiness와 worker activity를 구분해서 판단한다.
- 홈 scoreboard 자동 refresh cadence는 live 8초, scheduled 5분, terminal 정지로 둔다.
- 홈 수동 refresh는 provider invalidate 시점이 아니라 새 scoreboard Future 완료 시점까지 기다린다. API-backed 수동 refresh는 `forceRefresh=true`를 한 번 소비해 historical 기기 cache를 명시적으로 bypass하되, 공개 앱 요청은 current backend TTL을 유지한다. configured sync secret과 exact match하는 운영 header가 있을 때만 backend cache/live-state를 우회한다.
- 홈/상세 timer는 이전 data가 보인다는 이유만으로 refresh 완료로 판단하지 않는다. 진행 중 provider를 다시 invalidate하지 않고 요청 완료 뒤 one-shot timer를 재예약한다. 홈은 transient failure 뒤에도 visible data의 상태 cadence로 polling을 계속하고, 수동 refresh가 겹치면 force 의도를 보존한 직렬 queue로 합친다.
- app root lifecycle resume sync는 홈 coordinator와 같은 `scoreboardProvider(today)`가 loading 중이면 직접 invalidate하지 않고 active Future를 기다린 뒤 widget sync만 수행한다.
- 운영 sync worker는 push/Live Activity 등록이 없더라도 scoreboard warm-up을 수행하고, API service와 같은 runtime filesystem에 `live_scoreboard` state를 남긴다. API는 이 state가 현재 20초 window 안에서 fresh일 때만 `/scoreboard/home` 응답으로 사용하고, stale state는 snapshot처럼 fallback하지 않는다.
- backend `TtlCache`는 정상 조회에서 만료값을 반환하지 않되 historical 장애 fallback이 `get_stale()`로 읽을 수 있게 보존하고, 오래된 key가 무한히 쌓이지 않도록 항목 수를 제한한다. runtime singleton을 여러 요청이 공유하므로 cache store 조회·교체는 lock으로 보호하되, deepcopy는 lock 밖에서 수행한다. records overview/leaderboard cache와 snapshot은 핵심 리더 목록이 1위부터 시작할 때만 재사용한다.
- 경기 상세는 live 기본 탭 8초, 문자중계 foreground 원천 갱신은 5초 cadence로 맞춘다. LIVE 경기에서 스코어/문자중계/박스스코어/라인업 탭을 전환하면 타이머 tick을 기다리지 않고 현재 보이는 탭 provider를 즉시 갱신한다.
- 자동 상세 갱신과 수동 pull이 겹치면 자동 요청은 합치되 수동 요청은 버리지 않는다. 현재 Future가 끝난 뒤 한 번의 force refresh를 queue하고, relay transient error에는 previous data를 유지한다.
- backend `RelayCrawler`는 singleton `requests.Session`과 로그인 cookie를 공유하므로 login/fetch/validate/reset 전체 세션 경계를 직렬화한다. relay HTML shell이 파싱 후 `currentAtBat=None`, `relayItems=[]`이면 성공으로 cache하지 않고 재로그인 후 실패를 노출한다.
- backend scoreboard normal/force 요청은 full/home/prime/compact/game이 공유하는 KBO date 단위 직렬화 경계를 사용한다. force와 기존 normal을 서로 다른 SingleFlight key로만 분리하면 normal의 늦은 완료가 최신 cache를 되돌릴 수 있으므로, 같은 날짜는 반드시 같은 직렬화 경계를 통과한다.

## Backend Lint / Compatibility

- Backend는 `backend/pyproject.toml` 기준 Python `>=3.9`를 지원하므로, 기본 ruff gate는 `E,F,I,B`로 둔다.
- Python 3.9 정책이 유지되는 동안 pyupgrade(`UP`)를 기본 lint gate에 넣지 않는다. `Optional[...]` / `Union[...]`, `typing.Dict` / `typing.List` 같은 호환 표기를 강제로 바꾸면 repo 규칙과 충돌한다.

## Widget / Live Activity

- Live Activity 선택 우선순위:
  1. 진행중인 마이팀 경기
  2. 오늘 마이팀 라인업 공개 또는 시작 10분 전 예정 경기
  3. 진행중인 다른 경기
  4. 오늘 다른 라인업 공개 또는 시작 10분 전 예정 경기
- 라인업 공개/시작 10분 전 예정 경기 Live Activity는 `경기전` 상태와 양 팀 순위를 스코어 자리에 표시하고, 탭하면 라인업 탭으로 진입한다. 라인업 미공개 예정 경기는 시작 10분 전 window 전까지 follow session은 유지해도 Activity를 시작하지 않는다.
- 홈 위젯과 Live Activity는 가능한 한 같은 source scoreboard 를 기준으로 동기화한다.
- 중복 업데이트는 `updatedAt`을 제외한 content signature를 token별 registry state에 저장해 억제하고, 부분 실패 시 실패 token만 재시도한다.
- iOS 홈 위젯은 하나의 WidgetKit kind가 `systemSmall`, `systemMedium`, `systemLarge`, `accessoryInline`, `accessoryCircular`, `accessoryRectangular`를 family별로 다르게 렌더링한다. Android는 기존 단일 경기 `KboFansScoreWidgetProvider`와 오늘 경기 목록용 `KboFansSlateWidgetProvider`를 함께 등록한다.
- 위젯 family 다양화를 위해 backend 상세 스코어보드 크롤링을 새로 붙이지 않는다. foreground home scoreboard sync가 여러 경기 summary line을 채우고, background compact sync는 main 경기만 있어도 정상 상태로 degrade 되어야 한다.
- 앱이 native에서 resumed 될 때만 scoreboard 를 다시 invalidate 해 Live Activity 를 재동기화한다. 웹은 홈 위젯/Live Activity가 없으므로 전역 resume refresh를 등록하지 않는다.
- Live Activity 는 코드상 연결만으로 끝나지 않는다.
  - Widget extension signing
  - App Group entitlement
  - Push Notifications entitlement
  - ActivityKit push token backend registration
  - APNs provider key / team id / bundle id
  - 실제 기기 검증
  를 별도로 확인해야 한다.
- local iPhone debug에서는 `home_widget` / App Group / Workmanager 경로가 런타임 안정성을 해칠 수 있다.
  - `APP_ENV=local` + iOS 에서는 widget sync / periodic refresh 등록을 no-op 처리하는 편이 안전하다.
- foreground 기준 잠금화면 체감 갱신은 홈 scoreboard invalidate 주기에 의해 사실상 상한이 결정된다.
  - live game polling 간격은 홈 scoreboard 8초, 문자중계 foreground/sync worker 5초 기준으로 맞춘다.
  - static widget timeline은 1분 단위 재로드를 요청한다.
  - Live Activity / widget `updatedAt` 에는 초 단위 시각을 넣어 실제 갱신 여부를 구분한다.
- widget timeline reload와 Live Activity APNs delivery를 같은 정책으로 보지 않는다. widget은 timeline cadence로 갱신할 수 있지만, Live Activity APNs update는 content signature가 실제로 바뀔 때만 보내고 worker heartbeat는 별도 registry 신호로 관측한다.

## Launch / First Frame

- iOS/Android launch surface 는 앱 테마와 같은 다크 배경을 유지해 흰 화면 플래시를 줄인다.
- launch UI 를 바꾸면 `CHANGELOG.md` 와 `docs/WORKLOG.md` 에 같이 반영한다.

## iOS Build / Pod Warnings

- Pod deployment target 경고는 `Podfile` 의 `post_install` 에서 일괄 보정하는 편이 낫다.
- 플러그인 Objective-C 경고는 repo 코드가 아니라 pub cache / pod 소스라, 가능하면 설정으로 억제하고 근본 수정은 dependency upgrade 로 푼다.
- `dummy.o has no symbols` 는 보통 harmless warning 이다.
- Flutter가 생성하는 `Generated.xcconfig` / `flutter_export_environment.sh` 에 stale `CONFIGURATION_BUILD_DIR` 가 남으면 `Pods_Runner.framework not found` 같은 링크 오류가 날 수 있다.
- Flutter native asset `objective_c.framework` 는 실기기 빌드에서 simulator slice가 섞이거나 adhoc 서명으로 남을 수 있다.
  - 앱 타깃 build phase에서 플랫폼에 맞는 `objective_c.dylib` 를 선택해 덮어쓰고 프레임워크 번들 단위로 다시 codesign 하는 방식이 안전했다.

## Release / Preview

- 프리뷰 릴리즈를 만들 때는:
  1. 워크트리를 먼저 비운다
  2. 최신 `main` 기준 커밋/푸시를 끝낸다
  3. preview tag 를 만든다 (`0.0.1-preview`, 필요 시 `.1`, `.2`)
  4. GitHub prerelease 를 생성한다
- preview tag 는 최신 커밋과 어긋나기 쉬우므로, release 시점의 SHA 를 반드시 확인한다.

## Distribution Docs

- 배포 관련 반복 작업은 아래 문서를 같이 유지한다.
  - `docs/DISTRIBUTION_GUIDE.md`
  - `docs/ANDROID_SIGNING_GUIDE.md`
  - `docs/IOS_TESTFLIGHT_CHECKLIST.md`
