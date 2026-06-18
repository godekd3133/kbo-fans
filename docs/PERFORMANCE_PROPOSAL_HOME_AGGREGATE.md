# 홈 성능 개선 제안서

## 목적

현재 홈 화면은 아래 데이터를 개별 API로 조합해 렌더링합니다.

- `scoreboard`
- `schedule`
- `standings`
- `records/overview`

이 구조는 안전하고 디버깅이 쉽지만, 홈 첫 진입 시 네트워크 요청 수와 데이터 조합 비용이 커집니다.  
본 제안서는 **기존 계약을 유지한 채**, 홈 전용 aggregate endpoint를 추가해 체감 속도를 줄이는 안전한 개선안을 정리합니다.

## 목표

- 홈 첫 진입 시 필요한 API 호출 수를 줄인다.
- 기존 화면 동작과 모델 계약을 최대한 유지한다.
- 새 경로 실패 시 즉시 기존 경로로 fallback 하도록 설계한다.
- 점진적 전환이 가능하도록 한다.

## 현재 병목

홈은 현재 다음 흐름으로 구성됩니다.

1. `scoreboard` 로 첫 화면 렌더
2. `schedule`, `standings` 로 마이팀 브리프 계산
3. `records/overview` 로 리그 추천 카드 계산

현재까지 캐시와 지연 렌더링을 적용해 체감은 좋아졌지만, 구조적으로는 여전히 홈 1개 화면을 위해 여러 endpoint를 조합해야 합니다.

## 제안

새 API를 추가합니다.

- `GET /api/home`

이 endpoint는 홈 화면에 필요한 데이터를 서버에서 한 번에 조합해 반환합니다.

예상 응답 범위:

- `scoreboard`
- `todayBrief`
- `myTeamBrief`
- `quickItems`
- `meta`

핵심 원칙:

- 기존 `scoreboard`, `schedule`, `standings`, `records/overview` 는 유지한다.
- 새 endpoint는 **추가만** 하고 기존 클라이언트 경로를 깨지 않는다.
- 홈 화면만 우선적으로 새 endpoint를 사용한다.
- 새 endpoint 실패 시 기존 provider 조합으로 즉시 fallback 한다.

## 권장 응답 형태

```json
{
  "scoreboard": {
    "date": "2026-03-31",
    "games": []
  },
  "todayBrief": {
    "headline": "지금 2경기 진행 중",
    "detail": "마이팀 경기부터 확인하세요."
  },
  "myTeamBrief": {
    "teamId": "LG",
    "standing": {
      "rank": 1
    },
    "todayGameId": "20260331HTLG0",
    "nextGameId": "20260401HTLG0"
  },
  "quickItems": [
    {
      "eyebrow": "마이팀 순위",
      "title": "1위 · LG 트윈스",
      "subtitle": "2승 0패",
      "route": "/standings"
    }
  ],
  "meta": {
    "generatedAt": "2026-03-31T16:30:00+09:00"
  }
}
```

주의:

- 응답은 새로운 전용 DTO로 관리하되, 내부 계산에는 기존 서비스 결과를 재사용한다.
- 홈 전용 데이터만 담고, 상세 화면용 무거운 필드는 넣지 않는다.

## 구현 전략

### 1단계: 서버 추가

- `HomeService` 추가
- `GET /api/home` 라우트 추가
- 내부적으로 기존 서비스 재사용
  - `ScoreboardService`
  - `ScheduleService`
  - `StandingsService`
  - `RecordsOverviewService`
- 서버 내부에서 병렬 조합
- 홈 전용 response schema 정의

### 2단계: 클라이언트 연결

- `homeRepository` 또는 `homeProvider` 추가
- 홈 화면에서 새 endpoint 우선 사용
- 실패 시 기존 조합 provider 사용

예시 정책:

- `homeAggregateProvider` 성공: aggregate 데이터 사용
- `homeAggregateProvider` 실패: 기존 `scoreboardProvider + scheduleProvider + standingsProvider + recordsOverviewProvider` 유지

### 3단계: 점진 전환

- 홈 화면만 우선 전환
- 일정/순위/기록실 화면은 기존 endpoint 유지
- 안정화 후 필요 시 다른 진입 화면도 aggregate 고려

## 사이드이펙트 최소화 전략

### 계약 안정성

- 기존 endpoint 삭제 금지
- 기존 모델 변경 최소화
- 새 endpoint는 독립 추가

### fallback 보장

- 서버 실패 시 클라이언트는 기존 provider 조합으로 자동 복귀
- aggregate 응답 일부 누락 시에도 홈 주요 영역은 기존 스코어보드로 유지

### 캐시 안전성

- `/api/home` 자체에 짧은 TTL 캐시 적용
- live 게임 포함 시 `8초`
- scheduled 중심이면 `5분`
- final만 존재하면 더 긴 TTL 가능

### 배포 리스크 완화

- 초기에는 개발/로컬에서만 사용
- 이후 feature flag 또는 환경 조건으로 활성화
- 문제 발생 시 홈은 기존 provider 조합만 사용하도록 쉽게 롤백 가능

## 기대 효과

- 홈 첫 진입 API 왕복 수 감소
- 홈 계산 로직의 클라이언트 조합 비용 감소
- 지연 렌더링 의존도 감소
- 캐시 일관성 향상

## 예상 리스크

### 1. 서버 응답 비대화

위험:

- 홈에 필요 없는 데이터를 많이 실으면 오히려 느려질 수 있음

대응:

- 홈 전용 최소 필드만 반환
- 상세 화면용 데이터 제외

### 2. 데이터 중복 관리

위험:

- 같은 정보가 기존 endpoint와 aggregate endpoint에 동시에 존재

대응:

- aggregate는 기존 서비스 결과를 재가공만 하도록 구현
- 원본 로직은 기존 서비스에 남기고, aggregate는 조합만 담당

### 3. fallback 분기 복잡도

위험:

- 홈 코드가 이중 경로를 갖게 됨

대응:

- provider 계층에서만 분기
- widget 계층은 가능한 한 동일한 뷰 모델 사용

## 검증 계획

### 서버

- `GET /api/home` 단위 테스트
- 일부 하위 서비스 실패 시 fallback payload 테스트
- live / scheduled / final 케이스별 응답 테스트

### 클라이언트

- aggregate 성공 시 홈 정상 렌더
- aggregate 실패 시 기존 provider 조합으로 정상 렌더
- 홈 네비게이션/당겨서 새로고침 회귀 확인

### 성능

- 홈 최초 진입 시간 비교
- 홈 재진입 시간 비교
- 요청 수 비교
- Dev Console / `client_metrics.log` 비교

## 권장 우선순위

1. 서버 `GET /api/home` 추가
2. 홈 화면에서 aggregate 우선 + 기존 fallback 연결
3. 개발 환경에서 성능 비교
4. 안정화 후 기본 경로로 승격 검토

## 결론

가장 안전한 다음 단계는 **기존 endpoint를 유지한 채 홈 전용 aggregate endpoint를 추가**하는 것입니다.

이 방식은 다음 조건을 만족합니다.

- 기존 기능 계약 유지
- 롤백 쉬움
- 홈 체감 성능 개선 가능
- 점진 적용 가능

즉, “사이드이펙트를 최소화하면서 더 큰 성능 개선”을 하려면 이 방향이 가장 현실적입니다.
