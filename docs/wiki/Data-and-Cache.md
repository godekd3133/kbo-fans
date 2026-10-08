# 데이터와 캐시

## 기본 라우팅

모든 일반 빌드는 `USE_BACKEND_API=true`로 화면 데이터를 받습니다. direct KBO 경로는 `USE_BACKEND_API=false`를 명시한 파서 비교·디버깅용입니다. API 실패 후 화면 일부만 몰래 direct나 mock 데이터로 바꾸지 않습니다.

## 현재와 과거 데이터

| 데이터 | 기본 처리 |
| --- | --- |
| 현재 날짜/월/시즌의 스코어보드·일정·순위·기록 요약·리더보드 | 최신 원천을 사용하고 실패를 드러냄 |
| 현재 시즌 팀 선수·팀 스탯·선수 상세 | 원천 실패를 과거/번들 스냅샷으로 정상 처리하지 않음 |
| 검증된 과거 일정·순위·기록 | 정확한 날짜·시즌과 완성도를 확인한 저장 데이터 우선 |
| 완성된 종료 경기 | 공식 박스스코어·라인업·중계 등 검증 후 종료 스냅샷 재사용 |
| 현재 경기 상세 | 제한된 수명과 재검증을 갖는 공유 runtime cache; 세부 정책은 서비스별 확인 |

앱 API 캐시의 오류 fallback은 기본 비활성화이며 과거 경로만 명시적으로 허용합니다. 현재 summary API 실패와 현재 경기 상세의 제한된 runtime-cache 서빙은 서로 다른 정책입니다.

## 스냅샷의 품질 기준

게임 ID, 팀, 날짜, 시즌 등 identity가 맞아야 합니다. 기록 요약·리더보드는 rank 오름차순이고 1위부터 시작해야 합니다. 다른 시즌을 복제하거나 미완성 중계, 빈/비공식 박스스코어, 불완전 라인업을 완성된 과거 기록으로 저장하지 않습니다.

검증된 immutable history는 시간 만료만으로 다시 수집하지 않습니다. 명시적 강제 갱신, 캐시 키·스키마 변경, 사용자 초기화, 용량 eviction을 재조회 경계로 사용합니다. 당일 종료 경기는 종료·완성도 마커의 서비스별 구현을 확인합니다.

## 실시간 성능과 오류

- `/scoreboard/home`, `/scoreboard/compact`는 경기별 상세 크롤링을 수행하지 않는 가벼운 요약 경로입니다.
- 홈의 추가 aggregate는 첫 스코어보드 프레임 이후에 구독합니다.
- LIVE 점수는 유효한 공식 main-list 점수를 fallback 0:0보다 우선합니다.
- 현재 박스스코어가 공식 미제공이면 `official_unavailable`/`live_context` 등 명시적 상태로 처리하며 이전 경기 선수 기록을 빌리지 않습니다.
- 상세 경로의 singleflight busy 상황은 마지막 usable runtime payload가 있을 때 사용하고 없으면 503을 전달합니다.
- 앱 GET은 bounded retry 전체를 포함하는 absolute deadline과 transport cancellation을 사용합니다. Riverpod 전역 자동 retry는 비활성화입니다.
- 백엔드 GET은 response deadline, bounded bulkhead, 유한 lock/follower 대기를 사용합니다.

경기일·현재 시즌·예매 시각은 `Asia/Seoul` 기준입니다. 저장 시각과 TTL 경과는 UTC instant 기준입니다.

## 상세 문서와 소스

- [데이터 작업 기준](https://github.com/godekd3133/kbo-fans/blob/main/AGENTS.md)
- [API 캐시](https://github.com/godekd3133/kbo-fans/blob/main/app/lib/data/api/api_client.dart)
- [서비스 구현](https://github.com/godekd3133/kbo-fans/tree/main/backend/src/kbo_fans_backend/services)
