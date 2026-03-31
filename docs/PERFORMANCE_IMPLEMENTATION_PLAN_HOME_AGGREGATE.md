# 홈 Aggregate 구현 계획

## 목적

[`docs/PERFORMANCE_PROPOSAL_HOME_AGGREGATE.md`](/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/docs/PERFORMANCE_PROPOSAL_HOME_AGGREGATE.md) 에서 제안한 홈 전용 aggregate endpoint를 **사이드이펙트를 최소화하는 방식**으로 실제 구현하기 위한 작업 계획입니다.

이 문서는 설계 제안이 아니라, 바로 작업 착수 가능한 수준의 단계별 계획을 다룹니다.

## 구현 원칙

- 기존 endpoint는 유지한다.
- 새 endpoint는 추가만 한다.
- 홈 화면만 우선 전환한다.
- 실패 시 기존 provider 조합으로 fallback 한다.
- 각 단계는 독립 검증 가능해야 한다.
- 단계별로 롤백이 쉬워야 한다.

## 범위

이번 구현 범위:

- 서버 `GET /api/home` 추가
- 서버 `HomeService` 추가
- 홈 전용 schema 추가
- 클라이언트 `homeAggregateProvider` 추가
- 홈 화면에서 aggregate 우선 사용
- aggregate 실패 시 기존 로직 fallback
- 테스트 및 기본 성능 측정 추가

이번 범위에서 제외:

- 기존 `scoreboard`, `schedule`, `standings`, `records/overview` 제거
- 다른 화면을 aggregate endpoint로 전환
- 배치/사전생성 파이프라인 구축
- 운영 플래그 시스템 도입

## 작업 단계

### 1. 서버 응답 계약 정의

파일 후보:

- `backend/src/kbo_fans_backend/schemas/home.py`

정의 대상:

- `HomeAggregateResponse`
- `HomeTodayBrief`
- `HomeMyTeamBrief`
- `HomeQuickItem`
- 필요 시 내부용 TypedDict 또는 dataclass

원칙:

- 홈 화면이 실제로 사용하는 필드만 정의
- 상세 화면용 무거운 데이터 제외
- 기존 모델 재활용 가능하면 재활용

완료 기준:

- FastAPI response_model 에 연결 가능한 최소 schema 확정

### 2. 서버 조합 서비스 추가

파일 후보:

- `backend/src/kbo_fans_backend/services/home.py`

역할:

- `scoreboard`, `schedule`, `standings`, `records_overview` 를 조합
- 홈 전용 brief/quick items 계산
- 짧은 TTL 캐시 적용
- 일부 하위 서비스 실패 시 부분 응답 가능하도록 설계

권장 동작:

- `scoreboard` 는 핵심 필수 데이터
- `schedule`, `standings`, `records_overview` 는 부분 실패 허용
- `scoreboard` 실패 시에만 endpoint 실패

권장 캐시:

- live 포함 시: `30초`
- scheduled 위주 시: `5분`
- final만 존재 시: `5분~15분`

완료 기준:

- 입력: `date`, `myTeam`
- 출력: 홈 화면 렌더에 필요한 aggregate payload

### 3. 서버 라우트 추가

파일 후보:

- `backend/src/kbo_fans_backend/api/routes/home.py`
- `backend/src/kbo_fans_backend/api/router.py`

추가 경로:

- `GET /api/home`

파라미터 후보:

- `date`: optional, 기본값 오늘
- `myTeam`: optional

주의:

- `myTeam` 미지정 시에도 동작해야 함
- 홈 전용 endpoint이므로 불필요한 범용화는 피함

완료 기준:

- 로컬에서 `/api/home` 응답 확인 가능

### 4. 서버 테스트 추가

파일 후보:

- `backend/tests/test_home.py`

필수 테스트:

- 정상 aggregate 응답
- `myTeam` 없는 경우
- `schedule` 실패 시 partial payload
- `records_overview` 실패 시 partial payload
- `scoreboard` 실패 시 에러 또는 fallback 정책 검증

권장 추가 테스트:

- live/scheduled/final 케이스별 캐시 정책 검증

완료 기준:

- `pytest` 에 포함

### 5. 클라이언트 모델 추가

파일 후보:

- `app/lib/data/models/home_aggregate.dart`

포함 대상:

- home aggregate response model
- brief/quick item model

원칙:

- widget이 직접 Map 을 읽지 않도록 model 로 감싼다
- 홈 화면이 이미 쓰는 뷰 모델과 최대한 구조를 맞춘다

### 6. 클라이언트 repository/provider 추가

파일 후보:

- `app/lib/data/repositories/api_home_repository.dart`
- `app/lib/data/providers.dart`

추가 대상:

- `homeAggregateProvider`

권장 정책:

- aggregate endpoint는 로컬 캐시 사용
- 실패 시 예외를 바로 UI로 올리지 않고 홈 화면에서 fallback 하게 둔다

완료 기준:

- provider 단위로 aggregate fetch 가능

### 7. 홈 화면 조건부 연결

파일 후보:

- `app/lib/features/home/home_screen.dart`

변경 방식:

- aggregate 성공 시:
  - `scoreboard`
  - `todayBrief`
  - `myTeamBrief`
  - `quickItems`
  를 aggregate 값으로 렌더
- aggregate 실패 시:
  - 기존 `scoreboardProvider`
  - `scheduleProvider`
  - `standingsProvider`
  - `recordsOverviewProvider`
  조합 유지

중요:

- 기존 렌더링 함수는 최대한 재사용
- widget 계층 전체를 새로 짜지 않음
- fallback 경로는 현재 동작 그대로 유지

완료 기준:

- 홈 화면에서 aggregate 우선 사용
- 실패해도 현재 홈 동작 유지

### 8. 로깅 및 계측

권장 추가 항목:

- home aggregate loaded time
- fallback 사용 여부
- aggregate source: `aggregate` / `legacy`

파일 후보:

- `app/lib/features/home/home_screen.dart`
- `backend/logs/client_metrics.log`

완료 기준:

- 성능 비교가 가능한 로그 확보

### 9. 성능 검증

비교 대상:

- 홈 첫 진입 시간
- 홈 재진입 시간
- 네트워크 요청 수
- fallback 발생 여부

검증 방법:

- Dev Console 로그
- `client_metrics.log`
- 브라우저 네트워크 탭 또는 로그

목표:

- 홈 첫 진입 요청 수 감소
- 홈 보조 카드 등장 시간 단축
- 홈 재진입 시 네트워크 요청 수 감소

## 단계별 롤백 전략

### 서버 롤백

- `/api/home` 라우트 미사용 상태면 서버 추가만으로는 영향이 거의 없음
- 문제 발생 시 홈 클라이언트에서 aggregate 사용만 제거

### 클라이언트 롤백

- `homeAggregateProvider` 사용 분기 제거
- 기존 provider 조합만 사용

핵심:

- 기존 endpoint와 기존 provider 조합은 남겨둔다

## 예상 작업 순서

권장 순서:

1. `schemas/home.py`
2. `services/home.py`
3. `routes/home.py`
4. `backend` 테스트 추가
5. `app` 모델 추가
6. `homeAggregateProvider` 추가
7. 홈 화면 연결
8. 계측 추가
9. 성능 검증

## 완료 정의

다음 조건을 만족하면 완료로 본다.

- `/api/home` 가 정상 응답한다.
- 홈 화면이 aggregate 성공 시 이를 사용한다.
- aggregate 실패 시 기존 경로로 정상 동작한다.
- 백엔드 테스트 통과
- Flutter analyze 통과
- 홈 첫 진입 시간 또는 요청 수가 기존 대비 감소

## 오픈 질문

구현 전 확정이 필요한 항목:

1. `myTeam` 는 query param 으로 받을지, 클라이언트에서 post-process 할지
2. aggregate endpoint의 캐시 TTL을 고정값으로 둘지, 게임 상태 기반으로 동적으로 둘지
3. 홈 quick item 계산을 서버 완성형으로 만들지, 일부만 서버에서 주고 클라이언트가 조립할지

권장 답:

1. `myTeam` query param 수용
2. 상태 기반 TTL
3. 서버 완성형 quick item 우선

## 결론

이 구현 계획은 기존 계약을 깨지 않고, 홈 화면만 점진적으로 전환하는 안전한 경로입니다.

핵심은 아래 두 가지입니다.

- 새 endpoint는 추가만 한다.
- 클라이언트는 항상 기존 경로로 fallback 가능하게 둔다.

이 원칙을 지키면 성능 개선과 안정성을 동시에 가져갈 수 있습니다.
