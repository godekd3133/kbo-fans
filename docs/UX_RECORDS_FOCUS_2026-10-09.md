# 기록실 탐색 집중도 개선

## 분석과 목표

실제 기록실 화면에서 같은 투수 1위가 시즌 요약·가로 지표 카드·리더보드·마운드 체크에 반복됐다. 지표 버튼 바로 위 설명도 버튼 이름을 재차 나열했다. 순위를 탐색한 사용자가 팀 기록으로 이동할 때 같은 정보를 한 번 더 지나쳐야 했다.

이번 루프는 중복 마운드 패널을 제거하고 투수 순위 탐색을 기존 리더보드의 타자/투수 전환에 통합한다. 시즌 대표 선수와 가로 지표 바로가기는 유지한다. 별도 패널 제거로 투수 정보 접근이 사라지지 않도록 ERA/W/SV/SO 전환과 전체 보기 경로를 검증한다.

## 영향 범위와 구현

- 앱 기록실 렌더링만 변경. 중복 마운드 체크 패널과 dead helper, 지표를 나열하는 설명 문장을 제거했다.
- 리더보드 위/아래에 중복되던 전체 보기 action을 아래 한 곳으로 통합했다. 정상 결과에서는 선택한 선수군·지표·시즌을 유지하는 기존 route를 사용하며 빈 지표에서는 표시하지 않는다.
- backend producer/API 계약·provider·cache·snapshot·푸시·인프라·릴리스 변경 없음. 같은 overview 원자료를 소비한다.
- 기존 light mode·큰 글자·team/season 탐색 검증은 유지한다. 중복 패널에 고정된 테스트는 실제 투수 지표 전환 검증으로 바꾼다.

## 검증 경계

실행 로그와 화면은 `artifacts/ux-records-focus-2026-10-09/`에 기록한다. 로컬 reference snapshot 화면은 운영 API freshness의 증거가 아니다. 실기기/푸시/서명/배포는 별도 검증이며 전체 목표는 진행 중이다.

## 이번 검증 결과

- Flutter analyze 무결함, 기록실 관련 42개 테스트 통과. 지표 전환·빈 결과·시즌/선수 비교·large text/light mode 포함.
- 웹 build 성공. 실제 화면에서 반복 패널과 지표 나열 설명 제거, ERA→SV 전환 확인.
- SV 전체 보기는 `/records/leaderboard/saves?season=2026`으로 이동했다. 검증용 API의 전체 순위가 실패해 오류 화면을 확인했으며 데이터 표시 성공은 미확인이다. 뒤로 복귀하면 SV 선택·시즌·스크롤 위치가 유지됐다.
- 저장 화면은 601x858이며 실기기 또는 390px 실화면 증거로 주장하지 않는다.

후속 원인 확인: local reference API가 실제 query 방식 leaderboard route를 처리하지 않았다. QA route를 actual contract로 수정해 avg30 rows 화면을 확인했다. 운영 saves는 정확한 query 요청에서 200/season2025/metric saves/30 rows였다. 이전 fixture 오류를 운영 contract 실패로 일반화하지 않는다.
