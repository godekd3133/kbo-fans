# 경기 상세의 기록 미제공 안내 개선

## 분석과 목표

박스스코어 consumer는 공식 데이터 미제공 또는 선택 팀의 displayable rows가 없을 때 항상 ‘공식 박스스코어 업데이트 전’으로 표시했다. 종료된 과거 경기에도 같은 문구가 적용되어 앞으로 업데이트될 것처럼 읽힐 수 있었다. 에러 화면은 원인을 확인하지 않고 네트워크 확인을 요청했다.

응답 상태로 확인할 수 있는 사실만 안내한다. 없는 기록과 조회 실패를 구분하고 team toggle·retry·선수 이동을 유지한다.

## 영향 범위·수정

- 앱 박스스코어 빈 응답 안내를 ‘현재 제공된 박스스코어가 없어요.’로 변경했다. LIVE/final 동일하게 미래 업데이트를 약속하지 않는다.
- 박스스코어·라인업 실패의 detail은 간결한 재시도 문구로 정리한다. 기술 진단은 기존 경로를 사용한다.
- 빈 박스스코어 카드의 178px 고정 최소 높이를 제거한다. 내용과 text scale에 맞춰 높이가 정해진다.
- backend officialAvailable/liveContext 계약과 선택팀 hasDisplayableRecords 조건은 유지한다. 데이터, fallback, API/provider/cache·infra·release 변경 없음.

## 검증

- Flutter analyze 무결함, 박스스코어/라인업 관련 37 테스트 통과. LIVE/final 빈 응답·placeholder·오류 retry·stale/live context·team/선수 이동·compact layout 기존 테스트 포함.
- 새 LIVE/final 테스트는 미래 업데이트 문구가 없고 빈 카드가 고정 빈 공간 없이 표시되는지 확인한다.
- 이번 변경의 빈 상태 실화면·실기기 검증은 not-run. 이전 웹 fixture의 정상 박스스코어로 빈 상태를 검증했다고 주장하지 않는다. 전체 목표는 진행 중이다.
