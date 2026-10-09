# 순위표와 선수 기록의 시즌 탐색 유지

## 문제·목표

기록실의 순위표/선수 기록 전환은 시즌 없는 `/standings`, `/records`로 이동했다. 순위 화면은 URL의 season을 받지 않았다. 과거 시즌을 보고 화면을 바꾸면 현재 시즌으로 초기화되어 재선택해야 했다.

양방향 전환에 선택 시즌과 current-follow 모드를 전달하고 순위 화면도 URL의 시즌을 적용한다. 현재 시즌을 보던 사용자만 KST 연도 변경을 따라가며, 과거 시즌은 고정한다. 순위 2001년 이후·선수 기록 2002년 이후의 기존 지원 범위/clamp는 유지한다.

## 영향 범위

- 앱: standings constructor/init/update와 router query 전달, 양방향 area switch location. API/provider의 season key와 원자료·cache 검증은 그대로 사용한다.
- backend: standings route의 season query와 records overview consumer 계약을 확인했다. 기존 정수 season 요청을 사용하며 서버·snapshot·scheduler 변경 없음.
- 인프라·푸시·위젯·릴리스: 변경 없음.

## 구현과 검증

- `season`을 양방향으로 전달한다. 현재 시즌 추적일 때만 `seasonMode=current`를 유지한다.
- 순위 화면은 명시적 initialSeason을 지원하고 같은 widget의 route 입력 변경도 적용한다.
- 양방향 과거 시즌 이동과 현재 시즌 이동을 검증한다. KST 새해를 진행시켰을 때 과거 시즌은 유지, current 모드는 다음 시즌으로 이동하는지 실제 provider 요청으로 확인한다.
- 기본 진입/큰 글자·기존 순위표 테스트도 함께 검증한다. 실행 로그와 화면은 `artifacts/ux-season-navigation-2026-10-09/`에 보존한다.

## 웹 확인

최종 build에서 `/records?season=2025` → `/standings?season=2025` → `/records?season=2025` 이동과 각 dropdown의 2025 표시를 확인했다. 로컬 reference API를 사용하므로 표시된 순위 rows를 실제 2025 공식 기록의 정확성 증거로 삼지 않는다. season routing과 선택 유지의 UI 증거만으로 사용한다. 저장 capture는 601x858이며 real-device/390px 검증은 not-run이다.

- 최종 전체 Flutter 테스트 636개 통과. analyze 무결함·웹 build 성공·diff whitespace 검사 통과. 전체 목표는 진행 중이다.
