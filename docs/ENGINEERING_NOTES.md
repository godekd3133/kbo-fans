# Engineering Notes

## Purpose

이 문서는 구현 중 얻은 반복적인 인사이트와 운영/검증 메모를 모은다.
기획 문서보다는 구현 판단 기준에 가깝고, `AGENTS.md` / `CLAUDE.md` 를 보완하는 용도로 사용한다.

## 2026-08-13 Bounded data delivery

- Dio의 `connectTimeout`/`receiveTimeout`만으로 전체 응답 시간을 제한할 수 없다. 앱 GET은 모든 attempt와 backoff를 포함하는 하나의 absolute deadline을 사용하고 deadline 시 `CancelToken`을 취소한다. transient GET만 한 번 재시도하며 정수 초 `Retry-After`를 존중한다. parse/일반 4xx/POST는 재시도하지 않는다.
- FastAPI의 sync route는 클라이언트 응답을 timeout해도 worker thread를 강제 종료할 수 없다. 화면 GET은 15초 response deadline과 8-slot bulkhead를 함께 사용하고, timeout된 작업이 실제 종료할 때까지 슬롯을 반환하지 않아 무제한 abandoned work를 만들지 않는다. 포화는 0.1초 안에 503으로 fail fast한다.
- `/home` fan-out은 request middleware에만 의존하지 않고 14초 이하 absolute aggregate budget과 bounded executor를 사용한다. section 하나가 고착돼도 context-manager executor 종료가 나머지 thread를 무한히 기다리게 하지 않는다.
- 앱 시즌 매치업 일정은 9개월 월별 Future를 최대 3개씩 읽더라도 전체 25초 deadline을 공유한다. 월별 worker가 늦게 끝나도 provider는 전체 오류로 종료하며, 3개 wave가 75초로 누적되지 않는다. 데이터 일부를 조용히 버리는 partial success는 공식 일정 truth를 훼손할 수 있어 허용하지 않는다.
- 홈 scoreboard와 경기 상세 refresh coordinator도 active 대기와 queued force refresh를 합친 하나의 25초 budget만 사용한다. 요청이 겹쳐도 두 번째 25초를 새로 시작하지 않고, 마지막 visible data와 다음 polling cadence를 유지한다.
- cookie 정합성을 위한 relay session lock과 force-refresh ordering을 위한 scoreboard date lock은 제거하지 않는다. 대신 lock 획득은 2초, SingleFlight follower는 전체 backend 예산보다 짧은 10초로 제한하고, 같은 live relay와 current team-player miss를 process 안에서 coalesce한다. follower를 2초로 자르면 정상 cold `/home`의 4~5초 leader까지 기다리지 못해 동시 사용자만 불필요하게 실패한다.
- sync worker의 scoreboard warm을 느린 relay/push delivery와 분리한다. `SCOREBOARD_WARM_INTERVAL_SECONDS` 기본 5초 monotonic cadence로 runtime singleton을 prime하므로 `PUSH_SYNC_INTERVAL_SECONDS`를 30/60초로 늘려도 warm은 느려지지 않는다. `LIVE_SCOREBOARD_MAX_AGE_SECONDS`는 warm interval + 5초 jitter 이상이어야 하며 기본 20초다. 이 보장은 warmer의 upstream call 자체가 끝나는 범위이며 분산 task coalescing을 의미하지 않는다.
- release-safe 실패 로그는 endpoint/elapsed/error class를 남기되 query, credential, upstream error 원문은 남기지 않는다. 503/504 envelope와 retry 분류는 앱/서버 회귀 테스트에서 함께 검증한다.

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
- 앱 API cache는 현재 KBO 날짜·월·시즌과 current/LIVE game payload를 `SharedPreferences`에 쓰지 않는다. historical entry만 허용하되 key 192 bytes, entry 256 KiB, 64 entries, total 2 MiB 제한과 oldest-first eviction을 적용하고 cache mutation은 직렬화한다. 저장 불가능한 fresh response는 같은 key의 stale entry를 먼저 제거한다. 과거 scoreboard/home/compact/game도 payload 안의 모든 상태가 `FINAL`/`CANCELLED`일 때만 cacheable하며 `SUSPENDED`는 표시 후 저장하지 않고 기존 cache도 폐기한다.
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
