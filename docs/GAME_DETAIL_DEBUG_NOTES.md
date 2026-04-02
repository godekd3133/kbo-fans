# 게임 상세 디버깅 메모

> 작성일: 2026-03-31
> 범위: 기기 단독모드(iOS / Android)에서의 게임 상세 탭

## 증상

### 1. `GetMatchPlayerList` 500 반복
- 로그 예시:
  - `KBO FAIL /ws/Schedule.asmx/GetMatchPlayerList`
  - status `500`
- 영향:
  - 라인업 탭 진입 시 direct KBO 경로가 반복 호출되며 로그가 오염됨
  - 실시간 경기 상세 체감이 나빠짐

### 2. relay fallback 302
- 로그 예시:
  - `KBO relay fallback failed ... 302`
- 의미:
  - 로그인 기반 live relay 진입이 redirect 되었고, summary fallback 으로 내려가야 하는 상황

### 3. `RenderFlex overflow`
- 로그 예시:
  - `A RenderFlex overflowed by 74 pixels on the bottom`
- 의미:
  - 문자중계 또는 라인업 탭에서 작은 기기 높이 기준으로 세로 overflow 발생

## 현재 대응

### 라인업
- `GetMatchPlayerList` 는 같은 게임에 대해 한 번만 요청하도록 repository 레벨 dedupe
- 실패 시 `GetBoxScoreScroll` 기반 fallback lineup 생성
- 따라서 live 경기에서 KBO 라인업 API 가 깨져도 완전 빈 화면으로 남지 않게 함

### 문자중계
- relay 로그인 redirect(302)는 error 대신 summary fallback 으로 처리
- 현재 타석 hero 는 compact width 에서 세로 배치로 떨어져 overflow 를 피함

## 확인해야 할 로그
- `KBO lineup fallback for {gameId}: ...`
- `KBO relay login redirect for {gameId}, summary fallback 사용`
- `RenderFlex overflow` 재발 여부

## 기기 검증 체크리스트
- 라인업 탭 진입 시 `GetMatchPlayerList`가 같은 진입에서 여러 번 반복되지 않는지
- KBO 500 이어도 최소한 대체 라인업이 보이는지
- 문자중계 탭에서 현재 타석 hero 가 잘리는지 여부
- 긴 이벤트 텍스트에서 카드 높이/줄바꿈이 자연스러운지

## 권장 후속 조치
- 기기 로그 기준 500 횟수 감소 여부 확인
- 필요 시 lineups/pitchers 요청에 짧은 메모리 캐시 추가
- `RenderFlex overflow`가 남아 있으면 screenshot 과 기기 해상도 기준 추가 보정
