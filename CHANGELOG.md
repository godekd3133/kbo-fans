# Changelog

이 문서는 사용자 입장에서 의미 있는 저장소 변경 사항을 기록합니다.

형식 원칙:

- 날짜 기준 역순 기록
- 사용자에게 보이는 기능/구조 변화 위주 기록
- 세부 작업 로그는 `docs/WORKLOG.md`에서 관리

## [Unreleased]

### Changed

- 경기 시작, 득점, 라인업, 타석 같은 경기 푸시가 마이팀 또는 직접 `푸쉬 중계 받기`로 따라가는 경기 외에는 먼저 오지 않도록 리그 전체 경기 moment topic 경로를 제거

### Fixed

- 앱 실행 중 원격 푸시를 받으면 앱 내부 팝업으로 확인하고, 팝업/알림 진입 route가 잘못된 내부 경로로 이동해 오류가 나지 않도록 보정

## [0.1.16] - 2026-07-02

### Changed

- TestFlight release build가 새 Lightsail HTTPS backend를 운영 API로 사용하도록 배포 기준을 전환
- 저비용 tester 운영을 위해 Lightsail native systemd backend 경로, Caddy HTTPS reverse proxy, file-secret 기반 push / Live Activity 운영 runbook을 추가
- AWS ECS/Fargate demo path와 Lightsail low-cost path를 문서와 Codex 실행 entrypoint에서 분리

### Fixed

- Lightsail 배포 backend가 root-owned release tree 안에 로그를 쓰려다 실패하지 않도록 `LOG_DIR` 환경변수 override를 지원
- Lightsail snapshot 저장 경로와 June 2026 standings snapshot을 backend runtime bundle에 맞게 정리
- AWS monthly actual/forecast cost가 USD 10에 도달하면 KBO Fans runtime resource를 중단하는 cost guard 배포 절차를 추가

## [0.1.15] - 2026-07-01

### Changed

- 홈과 일정에서 경기 상세로 들어갈 때 최신 경기정보와 첫 진입 탭 데이터를 먼저 준비한 뒤 이동하도록 상세 진입 로딩을 보강
- TestFlight 외부 테스터 배포에서 새 빌드가 Beta Review 승인되기 전 마지막 승인 빌드를 유지해 테스터 화면이 비지 않도록 배포 절차를 보정

### Fixed

- 경기 상세 진입 전 선수사진 cache warm-up이 background로 밀려 상세 화면에서 다시 로딩되어 보일 수 있던 문제를 보정
- 문자중계 선수사진 URL이 과거 경기에서도 현재 연도 이미지 경로를 만들 수 있던 문제를 보정
- 박스스코어 타자/투수 row의 선수 id/image URL을 backend/app 계약에 보존해 이름 매칭 실패 시에도 선수사진 prefetch 후보가 비지 않도록 보정

## [0.1.14] - 2026-07-01

### Fixed

- 리그 리더보드에서 기록 API payload 오류가 발생할 때 내부 cache key나 `Bad state` 문구가 그대로 보이지 않도록 보정
- 홈 마이팀 브리프에서 두산 등 일부 팀의 `팀 홈런 1위`와 `뜨는 선수`가 `선수 기록 없음`으로 보이던 엔트리 파싱 문제를 보정
- 월초 홈 마이팀 브리프가 이전 달 마지막 경기 결과를 놓쳐 `최근 결과 없음`으로 보이던 문제를 보정

## [0.1.13] - 2026-07-01

### Changed

- backend sync worker가 live scoreboard 요약을 짧은 fresh window의 runtime state로 미리 덥히고, 홈 scoreboard API가 이 값을 즉시 읽어 첫 응답 지연을 줄이도록 개선
- 같은 날짜 scoreboard 원천 schedule/main list 결과를 backend service 안에서 공유해 home/compact/detail 진입 사이의 중복 KBO 호출을 줄임
- 지난 경기/일정/순위와 과거 시즌 기록실 데이터는 더 긴 로컬 캐시와 backend snapshot-first 응답을 사용해 불필요한 원천 재조회와 로딩을 줄임

## [0.1.12] - 2026-07-01

### Changed

- 문자중계 라이트모드 카드 색과 배지 대비를 다듬고, 선수 프로필 이미지 위에 등번호 배지를 표시하도록 개선
- 홈에서 경기 상세로 들어갈 때 기본 경기정보만 짧게 확인하고, 문자중계/박스스코어/라인업 첫 탭 데이터와 선수사진 캐시 준비는 병렬 백그라운드 warm-up으로 넘겨 화면 이동 대기감을 줄임
- 홈에서 경기 상세로 들어가기 전 `경기 정보 갱신 중` 상태에 진행률 숫자와 게이지바를 함께 표시하도록 개선
- 기록실 리그 리더보드를 `타자` / `투수` 탭으로 나누고, 타율·홈런·OPS·wRC+와 ERA·다승·세이브·탈삼진을 한 화면에서 전환해 볼 수 있게 개선
- 일정 `매치업` 보기는 지난 경기를 가까운 순서에 섞지 않고, 오늘 기준 앞으로 남은 맞대결만 날짜 가까운 순으로 보여주도록 정리

### Fixed

- 종료 경기 상세 상단에서 `9회`처럼 회차가 남아 보이지 않고 `경기 종료` 상태로 보이도록 보정
- 라인업 탭에서 일시적인 API timeout이 발생해도 `DioException` 전문이 노출되지 않고 자동 갱신 대기 상태로 보이도록 보정

## [0.1.11] - 2026-07-01

### Changed

- 뉴스/KBO 브리프가 검수된 기록 달성 데이터를 받으면 `최형우 2000루타 달성`, `역대 n번째` 같은 마이팀 기록 소식을 기록 뉴스로 보여주도록 확장
- 기록실 첫 화면에 `마운드 체크` 패널을 추가해 ERA, 다승, 세이브, 탈삼진 투수 리더를 바로 볼 수 있게 개선
- 뉴스 탭이 순위표 기반 소식을 25개 이상 노출하고, 홈런왕/승수 페이스, 상위권 연패/중하위권 연승 같은 특이 흐름을 기사형 제목으로 보여주도록 확장
- 일정 `매치업` 보기가 현재 월이 아니라 시즌 전체 맞대결을 모아 오늘과 가까운 날짜순으로 보여주고, 지난 경기는 어둡게 표시하도록 정리
- 기록실 `오늘 읽을 기록`에서 내부 데이터 개수나 소스 설명 대신 타율/홈런/ERA 리더와 격차를 바로 보여주도록 정리
- 홈의 전체 팀 결과 버블 섹션명을 `최근 흐름`에서 `최근 5경기`로 바꿔 표시 기준을 더 직접적으로 이해할 수 있게 정리
- 푸시 알림 설정을 `경기 전후 요약만 받기` / `경기 중 실시간 알림받기` 같은 프리셋 선택 없이 항목별 토글로 바로 켜고 끄도록 정리
- 화면 이동 전환 시간을 기존 대비 두 배로 늘려 탭 이동과 상세 화면 진입이 덜 급하게 보이도록 조정

### Fixed

- 라이트모드에서 두산 베어스 팀 로고가 어두운 받침과 겹쳐 과하게 어둡게 보이던 문제를 보정
- records overview의 투수 featured가 OPS 타자 리더를 `monthPitcher`로 내려줄 수 있던 분류를 보정
- backend API를 끈 direct KBO 경로에서도 선수 상세 최근 5경기 표가 비어 보이지 않도록 시즌 판정을 보정
- 종료 경기 라인업 탭 선발 비교에서 승패, 이닝, 평균자책, WHIP가 `-`로만 보이던 문제를 보정
- 홈 마이팀 브리프에서 선수 기록 하이라이트가 아직 로딩 중이어도 팀 타율/ERA와 순위는 먼저 표시되도록 보정
- 리그 전체 경기 푸시를 켠 기기가 같은 경기 알림을 리그 전체 topic과 마이팀 topic으로 두 번 받을 수 있던 구독 경로를 보정
- 홈에서 경기 상세로 들어가기 전 최신 갱신이 실패해도 이미 보이던 경기정보로 상세 화면에 들어가도록 보정
- 자정 이후 오늘 경기가 아직 시작 전이면 홈 `오늘 경기` 섹션에 어제 종료 경기 결과도 함께 보이도록 보정
- 뉴스 카드에서 순위/기록/일정 화면으로 들어간 뒤 왼쪽 스와이프로 뉴스 화면에 돌아올 수 있게 보정
- 종료 경기 상세를 다른 탭으로 열어도 하이라이트 검색/영상 로드를 스코어 탭 진입 전부터 시작하도록 보정
- 경기 상세 상단 스코어보드에서 `12`처럼 두 자리 점수가 세로로 갈라져 보이던 문제를 보정
- 경기 상세 박스스코어의 핵심 기록/선수 row에서도 선수 사진을 미리 로딩해 실제 프로필 이미지로 표시하도록 보정

## [0.1.10] - 2026-06-30

### Changed

- 경기 일정 탭에 `매치업` 보기를 추가해 두 팀을 선택하고 현재 월의 맞대결 일정을 홈/원정 무관으로 모아볼 수 있게 개선
- 홈 KBO 브리프와 뉴스 탭에 경기 실책이 많은 날, 시즌 타율 리더, 오늘의 타자/투수 같은 데이터 기반 야구 정보를 더 다양하고 많이 노출
- 일정 카드와 정규시즌 순위표에서 저장된 마이팀 경기를 팀 컬러 accent와 `마이팀` 배지로 더 분명하게 강조
- 홈 마이팀 브리프에서 실제 팀 기록 API 기준 팀 타율/ERA와 각 순위, 팀 홈런 1위, OPS/AVG/ERA 기준으로 눈에 띄는 선수를 함께 보여주도록 개선
- 경기 상세 박스스코어에서 팀 비교와 루타, 장타, 장타율, 투구수, 경기 ERA/WHIP 같은 확장 지표를 선수 row 아래에서 바로 훑을 수 있게 개선
- `경기 전후 요약만 받기` 푸시 알림에서도 `핵심`, `기본`, `자세히`로 요약 디테일을 골라 시작/종료만 받을지, 라인업과 야구 브리프까지 받을지 조정할 수 있게 개선
- `경기 중 실시간 알림받기` 푸시 알림에도 `핵심`, `기본`, `자세히` 실시간 디테일을 추가해 득점/홈런/역전 중심부터 안타/라인업, 타석/이닝/브리프까지 빠르게 조정할 수 있게 개선

### Fixed

- 두산처럼 오늘 경기가 있는 팀의 경기 전 push가 과거 상대팀 알림으로 잘못 오거나 상대팀 없이 팀명만 보이던 문제를 보정
- 홈에서 경기 상세로 들어간 뒤 선수사진이 뒤늦게 뜨지 않도록, 기본/문자중계/박스스코어/라인업 진입 전에 라인업 선수사진 source와 이미지 캐시를 먼저 준비하도록 보정
- 라인업, 박스스코어, 홈, 일정, 기록, 설정 화면에서 검정/어두운 팀 컬러가 다크모드 배경과 섞여 타순·배지·강조 텍스트가 안 보이던 문제를 보정
- 경기 전 박스스코어 빈 상태 카드가 화면 높이만큼 늘어나고 안내 문구가 하단에 붙어 보이던 문제를 보정
- 경기 상세 문자중계에서 `득점` 필터를 선택했을 때 원문에 있는 친 선수와 홈인 주자를 별도 라인으로 확인할 수 있도록 보강
- 선수 상세에서 공식 최근 경기 표가 있어도 시즌 라벨 판정 실패로 최근 기록이 비어 보이던 문제를 보정하고, `최근 5경기` 기록으로 정리
- 기록실 `오늘 읽을 기록`에서 대표 선수 한 명만 크게 보여 타자/투수 중 한쪽이 빠져 보일 수 있던 문제를 보정
- 종료 경기 상세 상단에서 `경기 종료`, 시작 시각, `최종 기록`이 반복 표시되지 않고 이닝 중심으로 보이도록 정리
- 라이트모드에서 홈 상단 로고/알림/검색 아이콘과 홈 카드 텍스트 색상이 다크모드 팔레트와 섞여 흐리거나 안 보이던 문제를 보정
- 라이트모드에서 기록실 배경·카드·리더보드가 어두운 표면과 어두운 텍스트로 섞여 보이던 문제를 보정
- 일정 캘린더에서 현재 월 바깥에 보이는 다음달 1일을 눌렀을 때 해당 다음달로 달력이 자동 이동하도록 보정

## [0.1.9] - 2026-06-30

### Changed

- 앱 업데이트 후 첫 접속 시 현재 설치 버전의 업데이트 소식을 팝업으로 한 번 보여주고, 전체 내용은 기존 업데이트 소식 화면으로 이어지도록 변경
- iOS 홈/잠금화면 위젯을 소형·중형·대형·accessory 크기별 경기판으로 확장하고, Android에는 오늘 경기 목록을 볼 수 있는 별도 경기판 위젯을 추가
- 뉴스 탭의 선택 필터를 밑줄 대신 배경 하이라이트로 표시하고, `오늘의 3분 브리핑` / `경기 전 체크포인트`처럼 AI스럽게 보이는 브리프 문구를 제거
- iOS Live Activity / Dynamic Island가 마이팀 또는 선택 경기 시작 10분 전부터 앱을 다시 열지 않아도 APNs push-to-start로 뜨고, 경기 전 상태로 갱신되도록 보강
- 경기 상세의 문자중계/박스스코어 탭에서 선수 사진 썸네일과 장식용 artwork 이미지를 제거하고, 텍스트·팀 로고·기록 중심 UI로 정리
- 경기 상세 문자중계 탭 상단 스코어보드에 이닝별 득점과 함께 `R/H/E` 합계를 표시하도록 보강
- 홈에서 마이팀 경기가 진행 중이면 마이팀 브리프 아래에 `내 경기 진행 중` 카드를 띄우고, 탭하면 해당 경기 문자중계로 바로 이동하도록 보강
- 홈 `오늘 경기`와 `순위` 섹션에서 `전체 보기` 축약 동선을 없애고, 오늘 전체 경기와 현재 시즌 전체 팀 순위를 바로 보여주도록 변경
- 홈 `순위` 바로 아래에 `최근 흐름`을 배치하고, 일부 팀이 아니라 현재 순위의 전체 팀 흐름을 한 번에 볼 수 있도록 정리
- 홈 KBO brief 카드 제목을 `오늘의 KBO 인사이트 팩`에서 `오늘의 KBO 소식`으로 정리
- 홈 인사이트/정보 카드를 전체 폭 row 카드로 정리해 긴 팀명과 전적 문구가 잘리지 않게 하고, 순위 인사이트에는 선두 팀 로고를 표시
- 홈 KBO brief 카드에서 `오늘 남은 경기` footer와 남은 경기 전용 항목을 제거
- 설정 탭에서 홈/경기/기록/뉴스로 반복 이동하는 `빠른 이동` 섹션을 제거해 마이팀, 알림함, 세부 설정 중심으로 정리
- 하단 `더보기` 탭과 화면 제목을 실제 역할에 맞게 `설정`으로 정리
- 설정 탭에 `시스템`, `라이트`, `다크` 화면 모드 선택을 추가하고 라이트모드 색상 토큰을 앱 테마에 추가
- 설정 탭에 푸시 알림 3단계 모드(`경기 전후 요약만 받기`, `경기 중 실시간 알림받기`, `안받기`)와 선택 모드별 세부 토글을 추가
- 마이팀 경기와 따라가기 경기 push topic도 `안받기` 및 꺼진 세부 토글을 존중하도록 앱/backend topic 계산을 정리
- 앱 전역 폰트를 Jua 기준으로 바꿔 홈, 경기 상세, 일정, 기록 화면의 텍스트 톤을 더 둥글고 아기자기하게 조정

### Fixed

- 종료/과거 경기 스코어탭에서 하이라이트가 자동으로 뜨지 않는 경우를 보정하고, 영상 ID가 없을 때도 유튜브 검색/공식 영상 링크를 앱 안에서 바로 열 수 있도록 보강
- 홈에서 진행 중 경기 상세 문자중계/라인업으로 들어가기 전 양 팀 로스터와 라인업 선수 사진을 앱 캐시에 먼저 올리고, 문자중계 선수 카드에 사진 썸네일을 다시 표시하도록 보정
- 알림함 안의 `설정` 링크가 빈 화면처럼 보이는 상태로 남지 않고 설정 탭 본문으로 바로 이동하도록 보정
- 홈 KBO 소식의 예정 경기 스트립이 `LIVE` 배지와 B/S/O·주자 그래픽으로 보이던 상태 표시 오류를 보정
- 경기 종료 후 문자중계와 Live Activity가 마지막 타석의 B/S/O·타자·투수 정보를 현재 진행 중 상태처럼 계속 보일 수 있던 문제를 보정

## [0.1.8] - 2026-06-30

### Changed

- 마이팀 경기 알림은 저장된 끄기/전달 방식과 무관하게 경기 시작, 시작 임박, 득점, 안타, 홈런, 역전, 종료, 라인업, 이닝 교대, 타석 push topic을 모두 구독하도록 보강
- Live Activity / Android 라이브 경기 알림은 마이팀 live 또는 라인업 공개 예정 경기를 다른 선택 경기보다 우선하도록 정리하고, 홈 카드의 모호한 `따라가기` 문구를 마이팀 알림 기준으로 변경
- iOS 17.2+에서 앱이 push-to-start token을 백엔드에 등록하고, 마이팀/선택 경기가 LIVE가 되면 앱을 열지 않아도 Live Activity / Dynamic Island를 APNs로 시작하도록 보강

### Fixed

- 라인업 화면에서 저장된 과거 경기나 현재 시즌 roster 조회 실패 때문에 선수 사진이 첫 글자 fallback으로 보이던 경로를 보강
- 홈에서 경기 상세로 들어갈 때 상세 경기 정보와 첫 탭 데이터를 먼저 새로고침하고 로딩 후 진입하도록 보정
- 푸시 알림 설정 직후 오래된 scoreboard/relay 기준점 때문에 라인업, 안타, 홈런 같은 지난 경기 알림이 몰아서 다시 오지 않도록 서버/로컬 알림 baseline을 현재 상태로 재기준화
- Live Activity, Dynamic Island, 홈 위젯에서 두 자리 점수와 현재 타석 기록 문장이 좁은 영역에 잘리지 않도록 점수/타석 텍스트 폭과 축소 기준을 보정
- 홈 상단 알림 아이콘 라벨을 실제 진입 화면인 알림함에 맞추고, 더보기 알림함 카드에서 알림함으로 이동되는 회귀 경로를 보강
- 진행 중 경기의 공식 박스스코어가 아직 비어 있어도 relay 현재 타석에서 계산 가능한 오늘 타수/안타/타율은 박스스코어 live context에 표시하도록 보강
- 진행 중 경기 상세에서 탭을 옮길 때 현재 탭 데이터를 즉시 새로고침해 수동 pull-to-refresh 없이 최신 문자중계/박스스코어/라인업을 다시 받도록 보강

## [0.1.7] - 2026-06-24

### Changed

- 온보딩 상단의 독립 경기장 이미지 카드를 제거하고 팀 선택/마이팀 미리보기 중심으로 정리
- 더보기 탭에서 홈/일정/순위/기록/뉴스 탭의 요약 정보를 반복 노출하지 않고, 마이팀 선택, 알림함, 빠른 이동, 세부 설정/지원 같은 실제 액션 중심으로 정리

### Fixed

- 온보딩에서 팀 선택 후 `시작하기`를 눌렀을 때 홈 진입 준비가 끝날 때까지 `시작 중입니다` 로딩 상태를 보여주고 중복 탭을 막도록 보정
- 라인업, 문자중계, 박스스코어, 기록실, 선수 상세에서 선수 사진 URL이 API/프로필 경로로 전달되지 않아 이름 첫 글자만 보이던 문제를 보정
- 경기 시작/종료/라인업 공개 같은 원격 push 문구에서 `SS`, `SK`, `HH` 같은 KBO 팀 ID가 그대로 보이지 않도록 `삼성`, `SSG`, `한화` 같은 짧은 팀명으로 보정
- 로컬 경기 이벤트 알림, 예매 알림, Live Activity, Android 경기 따라가기 알림, 홈 위젯, 홈 quick card, relay summary fallback도 `SS`, `SK` 같은 팀 코드 대신 `삼성`, `SSG` 같은 짧은 팀명으로 보이도록 보정
- 경기 안타/홈런 원격 push가 relay 현재 주자/아웃 상황을 `현재 1사 1,2루`처럼 함께 보여주고, 홈런 문구에서 어색한 `홈런 발생` 표현을 제거
- 득점/역전/이닝/타석 원격 push와 로컬 relay 알림 문구도 짧은 사건명 제목, `현재` 주자상황, `스코어` 점수 형식으로 정리
- 0:0 동점에서 첫 득점이 난 상황을 `역전` push로 잘못 보내지 않도록 보정
- 경기 취소/서스펜디드 원격 push가 `경기 종료` / `최종 스코어`처럼 확정 종료 문구로 보이지 않도록 별도 문구로 분리
- 로컬 경기 이벤트 알림도 0:0 동점에서 첫 득점이 난 상황을 `역전`으로 잘못 보내지 않도록 보정
- API 진단의 `원격 푸시 테스트`가 Firebase 발송 거부를 generic 서버 오류로만 보여주지 않고, 등록된 기기 기준의 발송 실패 사유를 응답으로 돌려주도록 보정
- `원격 푸시 테스트` 실패 기록을 backend 진단에 남겨 FCM token 만료, Firebase 프로젝트 불일치, APNs 인증 문제를 단말 권한 문제와 구분할 수 있도록 보강
- Firebase Admin 인증 오류가 `서버 진단에서 상세 사유를 확인` 문구로만 보이지 않도록, 서비스 계정 인증 문제로 분류해 API 진단과 운영 진단에서 확인 가능하게 보강
- iOS 기기 토큰 전송에서 Firebase `ThirdPartyAuthError`가 발생할 때 `Firebase 서비스 계정` 문제가 아니라 Firebase Console의 iOS Cloud Messaging APNs 키 설정 문제로 안내하도록 보정

## [0.1.6] - 2026-06-22

### Changed

- 마이팀 경기 알림은 `푸쉬 중계 받기`를 누르지 않아도 `off`가 아닌 경기 moment를 팀 topic으로 자동 구독하도록 보강
- 특정 타 팀 경기를 따라갈 때는 마이팀 팀 topic을 유지하면서 해당 타 팀 경기만 `*_GAME_<gameId>` topic으로 추가하고, 마이팀 경기를 따라갈 때는 중복 GAME topic을 만들지 않도록 정리
- 백엔드 sync worker가 KST 기본 슬롯에 맞춰 야구 브리프(`baseball_info`) smart daily push를 자동 발행하도록 연결
- 알림함 화면 기준 이미지가 문서와 생성 스크립트가 가리키는 저장소 경로에 포함되도록 보강

### Fixed

- `summary` 또는 `liveOnly`로 저장된 마이팀 경기 종료, 라인업 공개, 이닝 변경 같은 enabled moment가 원격 push topic에서 빠질 수 있던 문제를 보정
- 백엔드 sync worker가 라인업 공개 상태 변화를 자동 감지해 `lineup_opened` 원격 push를 발행하고, 라인업 API 경로와 중복 발송하지 않도록 보정

## [0.1.5] - 2026-06-22

### Changed

- 특정 경기를 따라갈 때는 설정에서 켜진 경기 moment가 `summary` 또는 `liveOnly` 상태여도 해당 경기의 `*_GAME_<gameId>` 일반 push topic으로 구독되도록 보강
- 팀/전체 push는 기존처럼 `immediate` 기준을 유지하고, 팔로우 경기만 selected-game GAME topic으로 더 촘촘하게 받도록 정리

### Fixed

- 팔로우 경기에서 경기 종료, 라인업 공개, 이닝 변경 같은 enabled moment가 delivery mode 때문에 일반 push topic에서 빠질 수 있던 문제를 보정

## [0.1.4] - 2026-06-22

### Changed

- 뉴스, 일정, 기록 탭 디자인 QA 문서가 참조하던 레퍼런스 이미지를 저장소에 포함해 문서 링크가 깨지지 않도록 정리
- 알림함 화면 레퍼런스를 재생성할 수 있는 프로젝트 스크립트를 추가해 향후 알림 UI polish 기준을 반복 가능하게 보강

### Notes

- 앱 런타임, backend API, push, Live Activity 동작 변경은 없는 문서/레퍼런스 정합성 릴리스입니다.
- TestFlight 업로드는 수행하지 않았습니다.

## [0.1.3] - 2026-06-22

### Changed

- 앱 원격 push 등록에 설치 단위 `installationId`를 추가해 TestFlight 업데이트나 FCM token 교체 후에도 같은 앱 설치를 backend가 구분할 수 있도록 보강
- backend push 진단이 token suffix와 별개로 설치 id suffix를 보여줘, 팔로우 경기 상태가 오래된 token에 남았는지 확인할 수 있도록 확장

### Fixed

- 같은 앱 설치에서 새 FCM token이 등록될 때 이전 token registration을 제거해, 팔로우 경기 push 대상이 stale token과 현재 token으로 갈라지는 문제를 줄임

## [0.1.2] - 2026-06-22

### Changed

- 앱이 원격 push 등록 시 알림 허용 상태, iOS 권한 상태, APNs token 준비 여부를 backend에 함께 보내도록 보강
- backend push 진단이 팔로우 경기 등록 기기의 권한/APNs 준비 상태와 앱 등록 시각, topic 재동기화 시각을 token 원문 없이 보여주도록 확장

### Fixed

- topic 재등록이 앱 등록 `updatedAt`을 덮어써서 실제 단말 재등록 여부를 흐리던 문제를 `topicsUpdatedAt`으로 분리

## [0.1.1] - 2026-06-22

### Changed

- 원격 push를 앱이 처리할 때 backend에 receipt를 남기도록 보강해 팔로우 경기 알림의 실제 수신 확인 경로를 추가
- backend `config-status`가 최근 push receipt 요약을 token 원문 없이 보여주도록 확장

### Fixed

- 팔로우 경기 topic 발송은 성공했지만 실제 단말 receipt 확인이 운영 registry에 남지 않던 관측 공백을 보정

## [0.1.0] - 2026-06-22

### Changed

- 사장님 요청으로 팔로우 경기 push topic 범위 보정 릴리즈를 `0.1.0 (67)` TestFlight build로 승격
- `0.0.66`의 followed-game immediate topic 정리와 외부 테스터 handoff 기준을 `0.1.0` milestone으로 다시 맞춤

### Fixed

- 특정 경기를 따라갈 때 `summary`, `liveOnly`, `off` 설정이 즉시 원격 push topic으로 다시 확장되지 않는 기준을 최신 공개 빌드에 재반영

## [0.0.66] - 2026-06-22

### Changed

- `0.0.65` 업로드 직후 main에 반영된 팔로우 경기 push topic 범위 보정을 포함해 새 TestFlight build `0.0.66 (66)`로 다시 맞춤
- 따라가는 경기가 있으면 immediate 경기 moment는 팀 topic 대신 해당 경기의 `*_GAME_<gameId>` topic으로만 구독해 같은 팀의 다른 경기 push로 넓어지지 않도록 정리

### Fixed

- `summary`, `liveOnly`, `off`로 저장된 moment가 즉시 원격 push topic으로 다시 살아나지 않도록 앱/backend topic 계산과 테스트를 맞춤

## [0.0.65] - 2026-06-22

### Changed

- `0.0.64`의 경기별 push topic, 라인업 공개 전 Live Activity, 원격 푸시 self-test, 업데이트 소식 정리 상태를 새 TestFlight build `0.0.65 (65)`로 다시 맞춤
- iOS Widget extension도 앱과 같은 build name/build number를 사용하도록 Xcode build 설정을 보정해 TestFlight IPA의 Runner/Widget 버전 기준을 일치시킴

### Fixed

- App Store Connect에 이미 올라간 build `64`를 재업로드하려던 경로를 중단하고, 새 tester-facing build `65`로 승격

## [0.0.64] - 2026-06-22

### Changed

- 마이팀 경기 핵심 알림은 별도 알림 플레이북 설정 없이 자동 수신되도록 바꾸고, 더보기 화면의 알림 프리셋/플레이북/리그 전체 토글 노출을 제거
- iOS Live Activity가 라인업 공개된 경기 전부터 뜨도록 하고, 이 상태에서는 `경기전`과 양 팀 순위를 스코어 대신 표시하도록 변경

### Fixed

- 기존 알림 delivery 설정이 꺼져 있거나 따라가는 경기가 있어도 마이팀 경기 시작/득점/안타/홈런/역전/종료/라인업/타석 topic이 유지되도록 앱과 backend topic 재계산 경로를 보정

### Added

- API 진단 화면에서 현재 iPhone/Android 기기에 backend 원격 테스트 푸시를 직접 요청하는 `원격 푸시 테스트` 버튼 추가

### Changed

- 더보기의 `패치노트` 진입점을 `업데이트 소식`으로 바꾸고, 앱 안에서는 최근 변경사항을 배포/서버 세부가 아니라 사용자 체감 변화 중심 문구로 보여주도록 정리
- 앱 전역 폰트를 둥근 획의 NanumSquareRound로 바꿔 홈, 경기 상세, 일정, 기록 화면의 텍스트 톤을 더 아기자기하게 조정
- 따라가는 경기가 있으면 득점, 안타, 홈런, 타석, 라인업 공개 같은 경기 순간 push 구독을 팀 토픽보다 `*_GAME_<gameId>` 경기별 토픽으로 우선 생성하도록 변경
- backend push worker도 경기 순간/라인업 공개 발송 시 팀/전체 토픽과 함께 경기별 토픽을 같이 발송하도록 보강
- 경기 탭 일정 화면을 새 생성 레퍼런스 기준으로 재정렬해 월 헤더, 필터, 범례, 캘린더 경기일 outline/dot, 선택 날짜, 경기 카드 밀도를 더 실제 다크 스포츠 앱 화면에 가깝게 조정
- backend API/worker 배포, topic 재등록, TestFlight 업로드, 외부 테스터 최신 build 연결 기준을 새 TestFlight build `0.0.64 (64)`로 다시 맞춤

### Fixed

- 로컬 경기 이벤트 알림이 release/dev/TestFlight 기본값에서는 중복 방지를 위해 꺼져 있음을 API 진단 화면에 노출하고, 회귀 확인용 `ENABLE_LOCAL_GAME_EVENT_ALERTS` 플래그로 명시 활성화할 수 있게 보강
- API 진단 화면에서 OS 로컬 알림 경로를 즉시 확인할 수 있는 로컬 알림 테스트 action 추가
- 앱 내부 원격 푸시 테스트가 운영용 `PUSH_SYNC_SECRET`에 의존하지 않도록, 등록된 자기 기기 FCM token에만 고정 테스트 알림을 보내는 backend self-test endpoint 추가
- GitHub Actions secret 컨텍스트에서 topic/token 대상 원격 테스트 푸시를 발송하는 `Push Test Notification` workflow와 dispatch helper 추가
- local backend에 `PUSH_SYNC_SECRET`이 없을 때 test push endpoint가 Firebase 초기화 500으로 떨어지지 않고 설정 누락 503을 반환하도록 보강
- 진행 중 경기 박스스코어가 공식 rows 업데이트 전이어도 KBO 실시간 현재 타자/투수 context를 `실시간 기록 추적`으로 표시하도록 보강
- 기록 탭 첫 화면의 spotlight 카드 하단 텍스트와 리더보드 `ERA` 탭이 390px 폭에서 잘리지 않도록 레이아웃 폭/높이를 보정
- topic 재등록 시 기존 팀 기준 경기 순간 토픽을 남기지 않고 follow 중인 경기별 토픽으로 재계산되도록 backend registry 갱신 경로를 보정

## [0.0.63] - 2026-06-20

### Changed

- `0.0.62`의 backend API 기본 모드, Live Activity 실시간 AVG, live 박스스코어 context, 푸쉬 중계 CTA, 배포 gate 보정 기준을 새 TestFlight build `0.0.63 (63)`로 다시 맞춤

### Fixed

- 로컬 backend 실행 액션이 iPhone 실기기용 LAN health 체크와 맞지 않게 localhost에만 바인딩되던 문제를 보정
- AWS backend API/worker task definition, Secrets Manager upload, GitHub Actions deploy workflow에 `KBO_RELAY_USER_ID` / `KBO_RELAY_PASSWORD` secret 주입을 추가해 live relay API runtime 500 경로를 보정

## [0.0.62] - 2026-06-20

### Changed

- `0.0.61`의 backend API 기본 모드, Live Activity 실시간 AVG, live 박스스코어 context, 푸쉬 중계 CTA 보강을 새 TestFlight build `0.0.62 (62)` 기준으로 다시 맞춤
- Push / Live Activity preflight가 현재 `LiveActivityService`의 API base URL handoff 구조를 정확히 확인하도록 배포 gate 문자열을 보정
- GitHub Release, backend deploy, topic 재등록, release API health 기준을 새 numeric release checkpoint로 재정렬

## [0.0.61] - 2026-06-20

### Changed

- 모든 일반 local/dev/release/web/native 빌드의 화면 데이터 라우팅을 backend API mode 기본값으로 고정하고, direct KBO는 `USE_BACKEND_API=false` 명시 parser/debug 경로로 제한
- release/web/iOS/Android 실행 스크립트와 GitHub Actions 앱 산출물을 backend API data mode 기준으로 정리
- 경기 상세 라이브 follow 영역을 설명 카드 대신 `푸쉬 중계 받기` / `푸쉬 중계 끄기` 단일 버튼으로 단순화
- 뉴스 탭의 필터/브리프 구성을 더 조밀한 스포츠 정보 화면으로 재정리하고, 일정/기록 탭의 버튼/카드 밀도를 보정
- 뉴스 탭을 새 레퍼런스 시안 기준의 기사형 row 구조로 다시 조정해 반복 큰 카드, `뉴스 믹스` rail, 2x2 signal grid를 줄이고 팀 로고/선수 이미지 중심으로 더 실제 스포츠 뉴스 앱처럼 보이게 개선
- 공식 박스스코어가 아직 비어 있는 LIVE 경기는 backend main-list 현재 타자/투수 context를 임시 live 기록으로 표시하고, 이 payload는 historical snapshot으로 저장하지 않도록 정리
- 2026년 6월 schedule snapshot과 records overview fixture를 최신 경기/기록 상태로 갱신

### Fixed

- 뉴스 카드 visual fallback이 `삼성 라이온즈`를 `삼라`처럼 임의 축약해 표시하던 문제를 없애고, 팀 관련 row는 공통 reference team logo를 우선 표시하도록 수정
- 홈 마이팀 브리프의 팀 로고가 아래로 잘려 보이던 배치를 고치고, 삼성 로고 reference asset을 공식 원본 기반 고해상도 PNG로 교체
- 두산 베어스 팀 로고를 공식 2025 현재 엠블럼 기준으로 교체해 온보딩, 앱 공용 팀 로고, iOS 위젯/Live Activity 자산에서 구형 로고가 보이지 않도록 수정
- 홈 순위 프리뷰의 팀 행을 눌러도 팀 기록실로 튀지 않고 `전체 보기`와 같은 전체 순위 화면으로 이동하도록 수정
- iOS Live Activity가 앱 direct/resume/widget sync로 갱신될 때도 현재 타석의 타율, ERA, 투구수, B-S-O를 보존하도록 보강하고, 초/말 공격 방향에 맞춰 타자·투수 표시와 베이스 다이아몬드/중앙 레이아웃을 조정
- Live Activity 타자 타율을 시즌 타율 그대로가 아니라 오늘 경기 완료 타석의 안타/타수까지 더한 실시간 AVG로 계산하도록 수정

## [0.0.60] - 2026-06-20

### Changed

- 기록 탭 상단 배경을 생성형 stadium bitmap asset으로 교체해 프리미엄 레퍼런스의 실제 야구장 질감에 더 가깝게 조정
- 2026 기록 overview bootstrap/snapshot을 최신 KBO 기록 기준으로 다시 갱신하고 stale current-season bootstrap guard 테스트 기준도 함께 갱신
- direct/local 데이터 모드라도 `API_BASE_URL`이 주입된 release 빌드에서는 remote push 등록과 자동 권한 요청을 유지하도록 정리

### Fixed

- iOS Live Activity에서 초/말에 따라 현재 타자/투수가 뒤바뀌던 표시를 보정하고, relay 기반 타율/ERA/투구수/B-S-O 정보를 Lock Screen 표면에 함께 표시하도록 개선
- 문자중계 주자 상태가 `주자1,2루` 또는 KBO `ground_base*` 코드로 들어와도 베이스 다이아몬드가 올바르게 채워지도록 보정

## [0.0.59] - 2026-06-19

### Changed

- 기록 탭 리그 진입 화면을 생성형 프리미엄 레퍼런스 기준으로 다시 다듬어 headline 리더, 지표 spotlight, 탭형 TOP3 리더보드 table, 팀 기록실 진입 순서로 더 많은 기록 정보를 첫 화면에서 읽히도록 개선
- 2026 기록 overview bootstrap/snapshot을 최신 KBO 기록 기준으로 갱신하고 stale current-season bootstrap guard 테스트 기준도 함께 갱신
- 온보딩을 이미지 레퍼런스형 구조로 재정렬하고 시작 CTA, MY TEAM 카드, reference-cropped 팀 로고를 적용해 첫 팀 선택 화면을 더 촘촘한 스포츠 앱 톤으로 개선
- Dev Console overlay를 `SHOW_DEV_CONSOLE=false` dart define으로 끌 수 있게 해 release/web QA 캡처에서 개발 UI가 섞이지 않도록 개선
- 알림함이 깨진 로컬 저장 payload를 만나도 빈 상태로 복구되도록 방어하고, 로드 실패 시 기본 push 설정으로 화면을 유지
- `/api/push/test` receipt 확인을 위한 `scripts/push-test-notification.sh`를 추가해 topic/token 대상 테스트 푸시를 secret-safe하게 반복 실행할 수 있게 정리

## [0.0.58] - 2026-06-19

### Changed

- 기록 탭 리그 진입 화면을 `오늘 읽을 기록`, 지표 spotlight rail, 지표별 TOP 3 preview, 팀 기록실 섹션으로 재구성해 시즌 리더 정보를 더 많이 보여주되 먼저 해석된 순서로 읽히도록 개선
- 뉴스 탭을 생성 레퍼런스 기준의 편집형 브리프 화면으로 강화해 `오늘 읽을 순서`, `뉴스 믹스`, 경기/순위/기록/마이팀 신호 grid, quick item/순위 preview/최근 경기 기반 카드와 선수 이미지/fallback mark까지 함께 보여주도록 개선
- 더보기 탭을 `KBO 팬 허브`로 재구성해 마이팀 요약, 오늘 챙길 정보, 빠른 이동, 앱 밖 표면, 알림 플레이북을 한 화면 흐름으로 정리
- 더보기 탭의 경기/순위/기록/뉴스/푸시/라이브 액티비티/브리프 아이콘을 레퍼런스 기반 custom glyph 세트로 교체해 Material 기본 아이콘 혼용을 줄임
- 온보딩, 더보기, 경기 상세/박스스코어/라인업/중계 화면에서 팀 로고와 선수 이미지가 더 안정적으로 보이도록 공통 팀 로고 위젯과 이미지 기반 row를 보강
- home brief의 기록 레이더 항목에 선수 이미지와 fallback label을 포함하고, off-day CTA를 일정 화면으로 연결
- 홈 인사이트/빠른 정보의 넓은 CTA를 뉴스 브리프로 연결하고, backend/app aggregate에서 들어온 동적 내부 route를 검증해 잘못된 링크가 기록실 등 엉뚱한 화면으로 튀지 않도록 보강
- Android 백그라운드/종료 상태 FCM 표시가 OS fallback 채널에 의존하지 않도록 원격 푸시 기본 채널을 명시하고 high-importance 채널을 생성

## [0.0.57] - 2026-06-19

### Changed

- 홈 하단 정보 흐름을 생성 레퍼런스처럼 `순위 -> 인사이트 팩 -> 지금 보면 좋은 정보` 순서로 재배치하고, 인사이트 팩을 8개 신호 기반 카드뉴스형 구성으로 확장
- `0.0.56` TestFlight 업로드 checkpoint 이후 들어온 홈 인사이트 팩 재정렬까지 포함해 새 TestFlight build `0.0.57 (57)`로 승격

## [0.0.56] - 2026-06-19

### Changed

- 경기 상세 박스스코어와 하단 `홈 / 경기 / 기록 / 뉴스 / 더보기` 탭의 이미지 기반 레퍼런스를 보강하고, 박스스코어를 큰 카드보다 dense record row와 `선수 기록 보기` CTA 중심으로 정리
- 홈 `오늘의 KBO 관전 포인트` 점수 strip을 팀명/스코어/B-S-O/루상 표시 중심으로 조밀하게 정리하고, 미니 카드가 선수 활약, 팀 흐름, 기록 레이더, 선발/투수 체크 순서로 우선 노출되도록 보강
- backend push worker 배포 기준을 새 TestFlight build `0.0.56 (56)`로 재업로드

## [0.0.55] - 2026-06-19

### Changed

- 홈 하단 `오늘의 KBO 관전 포인트`와 `지금 보면 좋은 정보`를 생성 레퍼런스 이미지 기준의 인사이트 카드/2열 quick info 배치로 정리하고, reference API QA 데이터도 함께 채움
- 홈 최근 흐름 행과 순위 snapshot 행을 팀 기록 화면으로 이어지는 tap target으로 보강하고 선택 haptic feedback을 추가
- `0.0.54`는 TestFlight upload/Git tag checkpoint로 남기고, 최신 GitHub Release/backend deploy/TestFlight tester 연결 기준은 `0.0.55`로 승격

## [0.0.54] - 2026-06-19

### Fixed

- 경기 상세 상단 scorebug 위젯 추출 누락으로 release analyze/test가 막히던 상태를 복구

### Changed

- 홈 첫 화면을 통합 비주얼 참조처럼 `KBO` 헤더와 `마이팀 브리프 → 오늘 경기 → 최근 흐름 → 순위` 대시보드 구조로 재배치
- 홈 상단의 독립 비주얼 레일과 별도 스코어보드 리스트를 제거하고, KBO 브랜드 마크/팀 로고/결과 버블/compact 경기 행/순위표 안에 비주얼과 데이터를 통합
- 홈 팀 로고 일부를 reference 전용 bundled logo asset으로 고정해 첫 화면의 팀 마크가 더 선명하게 보이도록 조정
- 하단 탭을 참조 이미지처럼 `홈 / 경기 / 기록 / 뉴스 / 더보기` 라벨과 단순 아이콘 스타일로 정리
- 하단 `뉴스` 탭이 `/standings`를 임시 재사용하지 않고 `/news` 실제 브리프 화면으로 열리도록 라우팅, 필터, 빈 상태, 카드 구조를 추가
- 일정, 순위, 더보기 알림 영역의 정상 화면 보조 이미지 rail을 제거해 경기/표/설정 정보 밀도를 우선하도록 정리
- live 경기 상태 badge가 `7회말` 같은 inning label을 그대로 쓰고 live accent로 보이도록 정리
- release dart-define에서 `USE_BACKEND_API=true`가 bool environment로 들어와도 정상 인식하도록 보강
- 마이팀 최근 흐름 집계를 최근 3경기에서 최대 5경기로 확장해 홈 브리프와 최근 흐름 카드의 결과 버블 밀도를 레퍼런스에 맞춤
- backend `/home` 응답에 `standingsPreview`를 추가해 홈 순위 snapshot이 별도 current-season standings provider 호출 없이 aggregate 응답으로 렌더링되도록 정리
- 일정 탭 캘린더 모드의 필터, 캘린더, 경기 목록을 단일 세로 스크롤 표면으로 묶어 캘린더 영역에서 위아래로 밀어도 목록 스크롤이 자연스럽게 이어지도록 개선
- 기록 탭 정상 화면의 상단 artwork 카드와 비주얼 rail을 제거해 시즌 선택, 리더보드, 팀 목록이 더 위에서 보이도록 레이아웃을 압축
- 공통 화면 모션 기본값을 키워 로딩/오류/완료 상태, 반복 리스트, 값 변경, 카드/탭 터치 피드백이 앱 전반에서 더 분명하게 보이도록 개선

## [0.0.53] - 2026-06-19

### Changed

- 홈 참조 대시보드 release checkpoint. 업로드 전 일정/기록/모션 UX와 경기 상세 scorebug source sync가 추가되어 GitHub release/tag/backend deploy 없이 `0.0.54`로 supersede

## [0.0.52] - 2026-06-19

### Changed

- 홈 참조 대시보드 TestFlight upload checkpoint. 업로드 중 reference team logo asset source sync가 추가되어 GitHub release/tag/backend deploy 없이 `0.0.53`으로 supersede

## [0.0.51] - 2026-06-19

### Changed

- 홈 참조 대시보드 TestFlight upload checkpoint. 업로드 중 홈 헤더 액션 icon size source sync가 추가되어 GitHub release/tag/backend deploy 없이 `0.0.52`로 supersede

## [0.0.50] - 2026-06-19

### Changed

- 홈 참조 대시보드 TestFlight upload/backend deploy checkpoint. 업로드와 backend deploy 후 홈 헤더 밀도, 최근 흐름 streak 표시, reference API metrics sink source sync가 추가되어 GitHub Release 없이 `0.0.51`로 supersede

## [0.0.49] - 2026-06-19

### Changed

- 홈 참조 대시보드 TestFlight upload checkpoint. 업로드 후 패치노트/하단 `뉴스` 탭 source sync가 추가되어 GitHub release/tag 없이 `0.0.50`으로 supersede

## [0.0.48] - 2026-06-19

### Changed

- 홈 참조 대시보드 TestFlight upload checkpoint. 업로드 직후 source sync 확인 과정에서 하단 탭 label 고정과 최신 소스 동기화가 필요해 GitHub release/tag 없이 `0.0.49`로 supersede

## [0.0.47] - 2026-06-19

### Changed

- 홈 참조 대시보드 TestFlight upload checkpoint. 업로드 후 하단 탭 label/route 정합성 수정이 추가되어 GitHub release/tag 없이 `0.0.48`로 supersede

## [0.0.46] - 2026-06-19

### Changed

- 홈 참조 대시보드 TestFlight upload checkpoint. 업로드 후 홈 UI compact 마감 수정이 추가되어 GitHub release/tag 없이 `0.0.47`로 supersede

## [0.0.45] - 2026-06-19

### Changed

- 앱 동작 변경 없이 `0.0.44` WebP-only 비주얼 자산 구성을 새 TestFlight build `0.0.45 (45)`로 재업로드
- Apple TestFlight 처리 빌드와 Git tag/GitHub Release 기준을 한 번 더 맞춘 배포 checkpoint로 정리

## [0.0.44] - 2026-06-19

### Changed

- 대표 artwork 상수도 캐주얼 WebP 대표 이미지로 전환해 홈/일정/순위/기록실/알림/온보딩의 비주얼 톤을 한 계열로 정리
- release asset manifest에서 기존 PNG 대표 이미지를 제거하고 `casual_*.webp` 175개만 명시해 TestFlight IPA 자산 구성을 더 작고 예측 가능하게 고정
- `0.0.43` TestFlight 처리 빌드를 최신 WebP-only 소스 기준 `0.0.44`로 재업로드해 Git 태그와 배포 바이너리 기준을 다시 맞춤

## [0.0.43] - 2026-06-19

### Changed

- 홈, 경기 상세, 일정, 순위, 기록실, 설정, 온보딩에 175개 캐주얼 2.5D 야구 비주얼 리소스 레일을 추가해 기존 리얼 계열 이미지보다 가벼운 앱 톤으로 조정
- `casual_*.webp` 비주얼 리소스를 release asset manifest에 명시해 TestFlight 빌드와 깨끗한 checkout 빌드가 같은 자산 구성을 사용하도록 정리
- `0.0.42` TestFlight 처리 빌드를 최신 소스 기준 `0.0.43`으로 재업로드해 Git 태그와 배포 바이너리 기준을 다시 맞춤

## [0.0.42] - 2026-06-19

### Changed

- 일정/순위 정상 화면에 남아 있던 생성 비주얼 상단 배너를 헤더/요약 rail 배경 레이어로 통합하고, 홈 마이팀 브리프도 같은 surface-background 원칙으로 문서화
- API 진단, 패치노트, 경기 상세 라인업 탭의 로딩/완료 상태와 반복 카드/선수 행에 공통 등장 모션을 적용해 보조 화면 전환도 부드럽게 보이도록 개선
- 일정 화면의 별도 야구 이미지 스트립을 월 헤더 배경으로 통합해 월 이동 컨트롤과 화면 맥락을 한 덩어리로 정리
- 순위 화면의 별도 순위 레이스 이미지를 요약 rail 배경으로 통합해 `1위 경쟁` / `마이팀` / `연승` 정보를 더 밀도 있게 노출
- 통합 비주얼 UI mockup을 문서 자산으로 보존해 이후 홈/일정/순위 화면 polish 기준을 추적할 수 있도록 정리

## [0.0.41] - 2026-06-19

### Changed

- 하단 탭 화면 이동 방향을 실제 탭 순서에 맞춰 좌우 slide/fade/parallax로 정렬
- 일정 월 이동과 오늘 버튼 이동을 380ms ease-in-out 슬라이드로 보강해 캘린더 이동 체감을 더 부드럽게 조정
- 생성 비주얼과 재시도 상태 문서화를 보강해 홈/일정/순위 cold error 표현 기준을 명확히 정리
- 순위 화면에 `1위 경쟁` / `마이팀` / `연승` 요약 rail과 이미지 기반 빈 상태를 추가해 데이터가 없거나 읽기 전에도 화면 맥락이 끊기지 않도록 개선
- 온보딩 팀 선택 그리드를 모바일 화면에 맞게 압축해 생성 이미지와 CTA가 팀 카드 영역을 답답하게 밀지 않도록 조정

## [0.0.40] - 2026-06-19

### Fixed

- 장시간 백그라운드 후 홈 스코어보드 refresh가 실패해도 기존 홈 화면을 유지하고 `다시 시도` 오류 화면으로 전환되지 않도록 보정
- 홈 화면에서 타구장 경기가 `오늘의 야구` 요약과 `다른 경기` 리스트에 중복 노출되지 않도록 정리
- 기록실에서 KBO 원천이 현재 시즌 rows로 되돌려 보내는 2001년 이하 선수 기록을 선택/저장하지 않도록 제한

### Changed

- 진행 중 경기의 문자중계 foreground 갱신과 backend scoreboard/relay sync worker 기본 주기를 5초로 낮춰 중계 반영 체감을 개선
- 홈 경기 없음 상태에 `일정 보기` / `기록실` 바로가기를 추가해 비경기일에도 다음 행동이 이어지도록 개선
- 알림 설정의 현재 프리셋 표시가 실제 Moment 설정에 맞춰 `내 팀 집중` 또는 `커스텀`으로 바뀌도록 조정
- 하단 탭 화면 이동을 더 부드러운 slide/fade/parallax 전환으로 조정하고, 경기 상세/기록 상세/설정 서브 화면에서 iOS식 스와이프 뒤로가기를 사용할 수 있도록 정리
- 순위탭에서 시즌을 선택해 2001년부터 현재 시즌까지 연도별 순위를 확인할 수 있도록 연결
- 온보딩, 홈 마이팀 브리프/빈/재시도 상태, 일정 빈 상태, 순위, 경기 상세 스코어/문자중계/박스스코어/라인업, 기록실, 알림 설정, 부트 스플래시에 AI 생성 야구 비주얼 리소스를 적용해 앱의 스포츠 앱 톤을 강화
- 알림 설정에 `야구 브리프`를 추가하고, backend가 월요일 주간 체크/경기일 체크/라인업 체크/라이벌 경기/비경기일/기록실 확인 같은 다양한 야구 정보 push 메시지를 팀별 copy, 스마트 daily 계획, 발송 전 미리보기로 보낼 수 있도록 확장
- 앱 전역 텍스트가 시스템 fallback 대신 번들된 Pretendard variable font를 사용하도록 정리해 경기 화면 한글 가독성과 선명도를 개선
- 홈 마이팀 브리프를 상태 pill, 한 줄 상황 헤드라인, 다음 행동 CTA 중심으로 재구성해 경기 전/중/후 판단을 빠르게 확인할 수 있도록 개선
- 홈 화면의 진행 중 경기 박스는 버튼을 따로 누르지 않아도 경기 상세 문자중계 탭으로 바로 진입
- 경기 상세 문자중계 탭을 방송형 현재 타석 스코어버그, 주요 장면 필터, 새 중계 도착 배너, 절제된 타석 카드 톤으로 개선
- iOS Live Activity / Dynamic Island를 예제 잠금화면처럼 좌우 팀명, 중앙 점수/베이스 다이아몬드, B-S-OUT 점, 하단 상황 pill 중심으로 재구성
- 경기 상세 화면에서 경기 시작 2시간 전부터 예매 정보 카드를 숨기도록 조정
- 순위표와 마이팀 순위 요약에 연승/연패 정보를 표시하도록 조정

## [0.0.39] - 2026-06-19

### Fixed

- TestFlight/release 앱을 다시 열거나 포커스했을 때 홈 화면 로컬 경기 이벤트 알림이 지난 득점/안타/종료를 몰아서 띄우지 않도록, 경기 이벤트 로컬 알림 처리를 local 개발 모드로 제한
- 원격 푸시가 잠금/백그라운드 상태에서 앱 실행 시점까지 밀리지 않도록 backend FCM 메시지에 iOS APNs `alert` push type/topic/alert payload/우선순위/사운드와 Android high priority/사운드 옵션을 명시

## [0.0.38] - 2026-06-18

### Fixed

- `game_start_soon` push를 눌렀을 때 경기 상세 문자중계 탭으로 안전하게 연결되도록 내부 route 매핑을 보강
- `game_start_soon` / `hit` topic과 relay 상황 텍스트 계약을 앱 테스트와 backend 테스트로 명시

## [0.0.37] - 2026-06-18

### Changed

- 진행 중 경기의 홈 scoreboard, 경기 상세, API cache, iOS Live Activity 원격 sync worker 기준 갱신 주기를 8초로 통일
- iOS Live Activity / Dynamic Island를 홈 경기 카드와 같은 팀 로고-스코어 중심 구조로 정리
- 앱 전역 다크 팔레트를 중립 차콜 톤으로 낮추고, 사용자 화면의 장식형 영어 라벨과 이모지 사용을 축소
- 홈 화면 헤더와 보조 섹션 카드를 팀 엠블럼, 얇은 컬러 rail, 8px 카드 체계 중심으로 정리해 스캔성과 시각 일관성을 개선
- 마이팀 live 경기 자동 따라가기 상태가 backend push registry의 `followedGameIds`에 자동 반영되도록 변경
- 마이팀이 선택된 release/dev 앱은 최초 1회 알림 권한 요청과 FCM 등록 동기화를 자동으로 실행해 앱 종료/백그라운드 push 수신 준비를 보강
- backend/app push moment에 `game_start_soon`과 `hit`을 추가해 경기 시작 10분 전과 안타 relay 변화를 즉시 알림 대상으로 포함

## [0.0.36] - 2026-06-13

### Added

- 기존 push registry 토큰을 현재 moment/topic 계약으로 다시 구독시키는 backend 운영 endpoint 추가

### Fixed

- TestFlight iOS 앱 번들에 Firebase `GoogleService-Info.plist`가 포함되지 않아 푸시 초기화가 실패하던 경로를 보정
- API 진단 화면의 push 카드가 release 환경 초기화 실패 사유를 함께 표시하도록 보강

## [0.0.35] - 2026-06-13

### Added

- 새 타자가 타석에 들어설 때 문자중계 탭으로 연결되는 `타석` 바로 알림 moment를 추가

### Fixed

- 앱이 백그라운드/종료 상태일 때도 홈런 알림이 계속 올 수 있도록 backend scheduler가 relay seq diff 기반 `homerun` FCM moment를 발행하게 보정
- 진행 중 경기 박스스코어 탭/API가 공식 rows 없이 선발/현재 투수 placeholder만 받은 경우, 0값 기록 카드 대신 업데이트 전 상태를 표시하도록 보정

## [0.0.34] - 2026-06-12

### Changed

- 진행 중 경기의 문자중계 탭이 화면에 열려 있을 때 자동 갱신 주기를 15초로 줄여 중계 반영 체감을 개선

### Fixed

- 문자중계 탭의 현재 타석/주요 장면 선수 카드가 선수 프로필 이미지 URL을 놓쳐 이니셜 fallback으로 보이던 문제를 보정
- 홈 마이팀 경기 카드의 진행 중 상태 배지가 `LIVE 경기중` 대신 간결한 `LIVE`만 표시되도록 보정
- 문자중계 회차 버튼에 `1회초 두산공격...` 같은 원문 이닝 전환 배너가 별도 버튼처럼 노출되던 문제를 보정
- 라인업 공개 푸시/로컬 알림을 눌렀을 때 앱이 안전한 내부 route로 경기 상세 라인업 탭을 열도록 보정
- 경기 전 KBO 원천에서 이미 공개된 라인업이 있어도 경기 상세 라인업 탭이 “경기 시작 후” 안내로 막히던 경로를 보정
- 장시간 화면 꺼짐 뒤 경기 상세 refresh가 실패해도 기존 경기 상세를 유지하도록 보정

## [0.0.33] - 2026-06-12

### Changed

- TestFlight 빌드가 배포 완료된 AWS push backend URL을 `API_BASE_URL`로 주입해 push / Live Activity token registration을 실제 backend로 보낼 수 있도록 변경
- HTTPS 도메인 연결 전 smoke 검증을 위해 현재 AWS ALB host에만 iOS ATS HTTP 예외를 임시로 추가

## [0.0.32] - 2026-06-12

### Changed

- 마이팀 경기 시작 알림을 기본 `바로 알림` 대상으로 변경해 신규/기본 설정 사용자가 `game_start_<팀>` FCM topic을 구독하도록 보강
- Push 등록 backend가 앱의 `deliveryModes`를 반영해 `summary`, `live_only`, `off` moment를 즉시 push topic에서 제외하도록 정렬
- 홈에서 진행 중인 경기 카드를 열면 경기 상세가 `문자중계` 탭으로 바로 시작하고, 마이팀 `중계 보기` CTA는 문자중계 본문이 먼저 보이도록 상세 상단을 접는 focus 진입을 사용하도록 변경
- `0.0.31` GitHub 릴리즈 이후 TestFlight 재검증을 위해 앱 버전과 빌드번호를 `0.0.32+32`로 증가

### Fixed

- 문자중계 현재 타석/타석 카드의 타자 표기가 등번호 대신 라인업 기준 타순, 이름, 포지션으로 보이도록 보정
- Live Activity / Dynamic Island 동기화가 사용자가 먼저 `따라가기`를 누른 경기만 처리하던 경로를 보정해, 마이팀 live 경기가 감지되면 widget/resume sync에서도 자동 follow target으로 잡히도록 변경

## [0.0.31] - 2026-06-12

### Added

- 앱 종료 후 일반 푸시와 iOS Live Activity / Dynamic Island를 갱신할 수 있도록 ActivityKit push token 등록, backend token registry, APNs liveactivity 발송 경로를 추가
- 운영 백엔드가 scoreboard를 읽어 등록된 Live Activity 세션에는 update/end payload를 보내고, score diff 기반 일반 FCM moment push도 발행할 수 있는 sync trigger를 추가
- Firebase/APNs/registry/scheduler secret 설정 누락을 확인하는 backend push config diagnostics API/CLI를 추가
- 배포 후 `/health`와 push readiness를 한 번에 확인하는 `scripts/push-readiness-check.sh`를 추가
- AWS ECS/Fargate에서 API service와 long-running sync worker를 나눠 배포할 수 있는 템플릿을 추가
- Firebase Admin JSON, APNs `.p8`, push sync secret을 AWS Secrets Manager에 생성/갱신하는 배포 보조 스크립트를 추가
- backend Docker image를 ECR에 build/tag/push하고 `CONTAINER_IMAGE_URI` export를 생성하는 배포 보조 스크립트를 추가
- AWS ECS task definition placeholder를 환경변수 기반으로 렌더링/검증하는 배포 보조 스크립트를 추가
- AWS push 배포 전 env, rendered JSON, secret, IAM role, ECR, EFS, CloudWatch log group을 점검하는 사전점검 스크립트를 추가
- ALB, ECS Fargate API service, scoreboard sync worker, EFS registry, IAM, CloudWatch log group을 만드는 CloudFormation stack 템플릿과 배포 스크립트를 추가
- CloudFormation stack output의 `ApiBaseUrl`을 release build용 `RELEASE_API_BASE_URL` / `API_BASE_URL` env로 추출하는 스크립트를 추가
- secret upload, ECR image push, CloudFormation deploy, stack output export, readiness를 순서대로 실행하는 AWS push demo 통합 배포 스크립트를 추가
- 배포 전 Firebase client 파일, APNs/Live Activity capability, backend secret env, AWS env 형태를 확인하는 Push / Live Activity preflight 스크립트를 추가
- 로컬 AWS CLI credential과 Docker daemon 상태를 확인하는 tooling check 스크립트와, GitHub Actions에서 push demo deploy를 수동 실행하는 workflow를 추가
- 로컬 env 파일과 Firebase client config 파일을 기준으로 GitHub Actions push deploy secrets/variables를 dry-run 또는 실제 업로드할 수 있는 `gh` CLI 보조 스크립트를 추가
- GitHub Actions `Push Demo Deploy` workflow를 CLI에서 dispatch하고, 원격 workflow 미등록 상태를 명확히 안내하는 보조 스크립트를 추가
- GitHub Actions `Push Demo Deploy` dispatch 전에 필수 secrets/variables 누락을 로컬에서 확인하는 사전검사를 추가
- push demo env checklist를 GitHub Actions secrets/variables 업로드까지 포함하도록 보강하고, obvious placeholder 값 업로드를 차단
- 앱 종료 후 push / Live Activity 시연 준비 상태를 앱 파일, env, GitHub Actions, 로컬 tooling 기준으로 감사하는 스크립트를 추가
- Push demo readiness audit이 로컬 파일/env 값이 이미 준비된 항목은 새 발급이 아니라 GitHub Actions 업로드 액션으로 안내하도록 보강
- push demo env 초안 생성, GitHub Actions OIDC role dry-run, readiness audit, 다음 명령 안내를 한 번에 실행하는 setup status 스크립트를 추가
- push demo env 초안 생성 시 repo 인자를 받아 후속 OIDC/audit 명령에 실제 GitHub repo를 표시하도록 개선
- push demo env 초안과 AWS deploy env example에 Firebase/Admin/APNs/AWS 값의 발급 위치와 GitHub 업로드 대상 주석을 추가
- push demo setup status 출력에 Firebase/Apple/AWS/GitHub에서 가져올 값과 env/GitHub/AWS 반영 위치를 정리한 Required Values checklist를 추가
- Push / Live Activity preflight가 release 빌드/CI의 `API_BASE_URL` token-registration handoff까지 확인하도록 보강
- GitHub Actions push demo dispatch 사전검사 실패 시 secrets 업로드 복구 명령에 실제 GitHub repo를 표시하도록 개선
- GitHub Actions가 장기 AWS access key 없이 push demo backend를 배포할 수 있도록 `AWS_ROLE_TO_ASSUME` OIDC role 생성 스크립트와 CloudFormation 템플릿을 추가
- AWS Secrets Manager 값을 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8` env로 주입해 FCM/APNs를 설정할 수 있도록 backend secret 입력 방식을 보강
- 운영 중 scoreboard sync worker 실행 여부를 확인할 수 있도록 push config diagnostics에 scheduler heartbeat를 추가

### Changed

- 앱/웹/릴리즈/CI artifact 기본 데이터 경로를 backend API 없이 direct KBO + 허용된 snapshot 경로로 전환
- 진행 중 경기에서는 일정 카드와 경기 상세의 예매 정보를 숨기도록 예매 노출 정책을 경기 전 전용으로 정리
- GitHub Actions `App Build Artifacts` workflow의 signing/config/metadata 파일 생성을 runner 들여쓰기와 무관하게 동작하도록 보강
- GitHub Actions `checkout` / `setup-python`을 Node.js 24 대응 major로 올려 runner Node.js 20 deprecation 리스크를 줄임
- 오래된 원격 푸시 보관 메모가 현재 Firebase/Admin/APNs/AWS 설정 상태와 충돌하지 않도록 최신 Push / Live Activity backend setup 기준으로 안내를 보정
- Backend API 사용은 `USE_BACKEND_API=true` 명시 opt-in 경로로 분리
- Release direct 빌드는 데이터 경로를 no-backend로 유지하면서 push / Live Activity token 등록용 운영 `API_BASE_URL`을 함께 주입하도록 보강
- 웹 기록실/선수 direct 조회가 KBO source를 CORS proxy 경로로 접근하도록 보강
- Android `home_widget`의 Glance 동적 의존성이 최신 alpha를 잡아 SDK/AGP 요구사항을 끌어올리지 않도록 Glance 안정 버전 고정
- Live Activity scoreboard sync와 push readiness one-shot sync 기본 날짜를 AWS UTC가 아닌 KBO 경기일(`Asia/Seoul`) 기준으로 계산하도록 변경
- Push readiness check가 scheduler heartbeat 최신성을 확인해 sync worker가 멈춘 배포를 통과시키지 않도록 변경
- Push token registry가 파일락과 atomic write를 사용해 API service와 sync worker의 동시 저장 중 token / heartbeat 갱신을 잃지 않도록 변경
- iOS TestFlight 업로드 후 앱 암호화 문서 prompt가 반복되지 않도록 App Store export compliance 선언을 Info.plist에 고정
- 홈에서 live 마이팀 경기를 자동으로 따라가는 상태로 표시하고, 홈 `따라가기` 버튼을 누르면 같은 자리에서 `따라가는 중` 체크 상태가 되도록 변경
- 마이팀 경기 시작 알림 기본값을 묶음 요약에서 바로 알림으로 바꾸고, backend topic 구독은 immediate delivery moment만 대상으로 보정
- 경기 상세가 첫 route로 열린 경우 뒤로가기가 빈 화면으로 빠지지 않고 홈으로 복귀하도록 변경

### Fixed

- TestFlight direct 라인업 탭이 박스스코어 원천 실패에 막혀 타자 라인업과 KBO 라인업 지표를 비워두던 경로를 `GetLineUpAnalysis` 우선 조회로 보정
- 문자중계 현재 타석과 주요 장면 선수 라벨이 라인업 타순/포지션 정보를 우선 사용하도록 보정
- iOS TestFlight에서 위젯 백그라운드 갱신 task id가 허용됐지만 launch handler가 등록되지 않아 앱 시작 직후 종료되던 경로 차단

## [0.0.30] - 2026-06-11

### Fixed

- iOS TestFlight에서 마이팀 미선택 상태로 위젯 데이터를 동기화할 때 `null`이 App Group 저장소로 전달되어 앱이 종료되던 경로 차단

### Changed

- iOS 위젯 백그라운드 갱신과 push background 처리를 위해 release plist 선언을 보강

## [0.0.29] - 2026-06-04

### Fixed

- 일정 화면에서 다음 달/이전 달로 이동한 뒤 선택된 `일정` 하단 탭을 다시 누르면 현재 달로 초기화되던 경로 차단
- 일정 월 데이터가 실패한 상태에서도 캘린더와 월 이동 컨트롤은 유지되도록 보정
- KBO 취소 사유가 `우천취소`로 내려오는 경우 일정/홈/상세/위젯 상태 문구에 우천취소 라벨을 표시
- 문자중계에서 포일 이벤트가 일반 플레이 배지로 보이던 분류를 포일 표기로 보정
- 롯데 자이언츠 팀 로고가 흰 사각 배경과 함께 보이던 CDN 이미지 경로를 투명 배경 경로로 보정
- API를 쓰지 않는 direct-primary 문자중계 빌드에서 현재 타석 선수 이미지가 비어 글자 fallback으로 보일 수 있던 경로 보정
- API를 쓰지 않는 direct-primary 박스스코어/라인업에서 영문 선수목록 이름과 한글 경기 원본 이름이 매칭되지 않아 선수 이미지가 빠질 수 있던 경로 보정
- direct-primary 문자중계 요약 fallback이 예정 경기에서도 1회초/1회말 skeleton을 만들어 실제 중계처럼 보일 수 있던 경로 차단

## [0.0.28] - 2026-05-20

### Fixed

- LIVE/당일 박스스코어가 비어 있을 때 같은 팀 조합의 전날 경기 박스스코어를 대체 데이터로 붙일 수 있던 경로 차단
- 기록실 overview 리더보드가 KBO 응답 row 순서 흔들림으로 1위가 아닌 항목부터 내려와 첫 화면이 오류 상태로 보일 수 있던 경로 차단

## [0.0.27] - 2026-05-20

### Fixed

- LIVE 홈/위젯 요약 스코어보드에서 schedule payload의 0:0 값이 KBO main list의 실제 득점 갱신을 막아 진행 중 경기가 0:0으로 남을 수 있던 경로 보정

## [0.0.26] - 2026-05-20

### Changed

- backend current data routes가 공통 runtime service singleton을 공유하도록 정리해 `/scoreboard/home` 직후 `/home` 또는 game detail 계열 호출에서 같은 TTL 캐시를 재사용하도록 변경
- 홈 화면 secondary `/home` aggregate provider 구독을 scoreboard 첫 데이터 프레임 이후로 지연해 첫 화면 렌더 전에 부가 API가 시작되지 않도록 변경
- 홈 자동 refresh timer가 unrelated rebuild 때마다 재시작되지 않도록 scoreboard signature 기반으로 안정화

### Fixed

- 홈 로딩 스켈레톤의 작은 카드가 모바일/테스트 뷰포트에서 overflow 될 수 있던 간격 보정

## [0.0.25] - 2026-05-20

### Changed

- 앱 `Game` 모델에 팀별 H/E/B 통계 존재 여부를 보존하는 `hasStats` 플래그 추가
- 스코어 탭과 문자중계 요약에서 H/E/B 원천값이 없으면 `0` 대신 `-`로 표시
- 홈 마이팀 경기 카드에서 양 팀 H/E/B가 확인되지 않은 경우 해당 요약 행을 숨기도록 변경
- KBO 브리프의 `안타 공방` 후보는 양 팀 안타/실책/사사구 통계가 실제로 내려온 경기만 사용하도록 변경

### Fixed

- 홈/상세/중계 화면이 결측 team totals를 `0안타`, `0실책`, `0볼넷`처럼 확정 통계로 오인하게 만들 수 있던 표시 경로 차단

## [0.0.24] - 2026-05-20

### Changed

- backend `/scoreboard/home`과 `/scoreboard/compact`가 홈/위젯 표면에 필요한 schedule + main list 기반 요약만 만들도록 변경해 경기별 상세 스코어보드 크롤링을 첫 로딩 경로에서 제거
- full `/scoreboard`와 `/game/{gameId}` 경로는 기존처럼 상세 스코어보드 크롤러와 View1 보강을 유지
- current `/scoreboard/home`도 원천 실패 시 fresh snapshot으로 정상 응답을 만들지 않도록 회귀 테스트 추가

### Fixed

- 홈 첫 로딩과 compact/widget 갱신이 경기 수만큼 상세 스코어보드 원천 호출을 늘릴 수 있던 fan-out 경로 차단

## [0.0.23] - 2026-05-20

### Changed

- GitHub Actions app artifact workflow가 Android/Web/iOS 빌드 전에 backend pytest를 먼저 실행하도록 변경
- backend 현재 시즌 팀 선수, 팀 스탯, 선수 상세 API가 crawler 실패 시 fresh/stale snapshot이나 stale in-memory cache로 정상 응답을 만들지 않도록 변경
- 과거 시즌 팀 선수, 팀 스탯, 선수 상세는 기존처럼 저장 snapshot 우선 및 crawler 실패 fallback 정책 유지

### Fixed

- 현재 시즌 기록실 팀/선수 화면이 원천 조회 실패 상태인데도 저장 snapshot 때문에 최신 데이터처럼 보일 수 있던 경로 차단

## [0.0.22] - 2026-05-20

### Changed

- 현재 날짜 스코어보드, 홈 aggregate, 경기 상세, 문자중계, 박스스코어, 라인업, 현재 월 일정, 현재 시즌 순위/기록실/팀 기록은 API 실패 시 TTL 안의 로컬 API cache를 정상 데이터처럼 재사용하지 않도록 변경
- backend 현재 스코어보드, 일정, 순위, 기록실 요약, 리더보드도 crawler 실패 시 fresh snapshot을 정상 응답처럼 반환하지 않도록 변경
- 홈 첫 로딩에서 오늘 스코어보드 별도 로컬 cache를 먼저 렌더링하던 경로 제거
- 과거 날짜/시즌/월 조회만 기존 cached-first 또는 snapshot fallback 정책을 유지해 히스토리 화면의 빠른 조회는 보존
- 2026-05-20 취소 경기와 현재 순위/기록실 snapshot 저장 시각을 최신 수집본 기준으로 갱신

### Fixed

- 서버/API가 죽었는데 웹/앱에 남은 fresh API cache 때문에 현재 경기나 현재 기록이 최신 정보처럼 보일 수 있던 masking 경로 차단
- backend 현재 데이터 crawler 실패가 current snapshot으로 숨겨질 수 있던 경로 차단

## [0.0.21] - 2026-05-20

### Changed

- 앱 공통 `ApiClient.getCached`에 payload validator를 추가해 캐시를 읽거나 새로 저장하기 전에 malformed 응답을 차단
- records overview API cache key를 `v4`, leaderboard API cache key를 `v3`로 올려 웹/앱에 남은 구형 기록실 캐시를 무효화
- 앱 전역 Riverpod retry를 비활성화해 API 실패가 반복 재시도 뒤에 숨지 않고 화면 오류 상태로 바로 전달되도록 변경
- backend 2013 타율 리더보드 snapshot과 records overview featured 카드를 시즌 공식 리더 기준으로 보강

### Fixed

- 기록실 웹/API cache에 남은 1위 누락 리더보드가 2013 타율처럼 다시 표시될 수 있던 경로 차단
- 2013 타율 리더보드 fallback이 이병규 1위부터 시작하지 못하던 snapshot 누락 보강
- 기록실 리그 요약 실패가 빈 공간처럼 숨겨지던 화면을 오류 카드와 다시 시도 버튼으로 노출하도록 보강
- 팀 기록실 오류 상태에 사용자용 실패 문구를 표시하고 refresh 실패는 Dev Console에 기록하도록 정리

## [0.0.20] - 2026-05-20

### Changed

- backend `/home` aggregate는 현재/미래 날짜에서 schedule, standings, records overview 하위 호출 실패를 빈 섹션/placeholder로 조용히 대체하지 않도록 변경
- 과거 날짜 `/home` aggregate만 기존 partial fallback을 유지해 히스토리 조회 안정성은 보존
- records overview crawler와 2011 snapshot의 featured 카드를 canonical 시즌 리더 기준으로 정리하고 회귀 테스트 추가
- runtime data 정책 문서와 skill에 home aggregate current-date fail-fast 기준 추가

### Fixed

- 홈 첫 화면에서 현재 데이터 일부가 실패했는데도 `오늘 경기 없음`, 빈 순위, 빈 기록 카드처럼 정상 상태로 오해될 수 있던 경로 차단
- records overview snapshot 재생성 시 OPS 하위권 선수가 `시즌 OPS 리더`로 노출될 수 있던 데이터 생성 경로 차단
- 기록실 디바이스 snapshot에 남은 구형 `recordsOverview` 캐시가 1위가 누락된 리더보드를 계속 표시할 수 있던 경로 차단
- records overview / leaderboard device snapshot은 핵심 리더보드가 1위부터 시작할 때만 저장/재사용하도록 보강

## [0.0.19] - 2026-05-20

### Changed

- 현재/진행 예정 경기의 박스스코어와 라인업은 과거 snapshot을 실패 fallback으로 쓰지 않고 최신 원천 실패를 그대로 노출하도록 변경
- LIVE 경기 문자중계는 crawler 실패 시 요약/과거 snapshot으로 조용히 대체하지 않고 실패를 전파하도록 변경
- 팀 기록 API는 선수 목록이나 팀 스탯 중 한쪽 실패를 빈 payload로 숨기지 않고 API 실패로 처리하도록 변경
- `./scripts/codex-run.sh web` 기본 실행을 release API health gate를 통과한 static web release 경로로 변경
- Chrome debug 세션용 실행 경로를 `./scripts/codex-run.sh web-dev`와 `scripts/codex-run-web-dev.sh`로 분리
- README, APP_SPEC, 릴리즈 문서를 current/live failure masking guard와 web 기본 실행, web-dev, web-release 역할 기준으로 정리

### Fixed

- 현재 경기 상세/라인업/중계가 오래된 snapshot 또는 요약 fallback으로 정상 데이터처럼 보일 수 있던 경로 차단
- 팀 기록에서 부분 실패가 빈 선수 목록이나 빈 팀 스탯처럼 표시되어 데이터가 없는 것처럼 오해될 수 있던 경로 차단
- release API DNS/TLS/API health gate를 거치지 않은 웹 기본 실행 명령으로 release 검증을 착각할 수 있던 경로 차단

## [0.0.18] - 2026-05-20

### Changed

- backend historical leaderboard snapshot에 2011 ERA, 2013 HR 저장본을 추가해 원천 조회 실패 시에도 대표 과거 리더보드가 복구되도록 보강
- 2011 ERA 1위 `윤석민 2.45`, 2013 HR 1위 `박병호 37`처럼 은퇴 선수가 포함된 snapshot 상위 리더를 회귀 테스트로 고정
- Codex 웹 wrapper를 release API health gate 경로로 맞추고, Android/Web release 전용 wrapper를 추가

### Fixed

- 2011 ERA, 2013 HR 단건 리더보드 endpoint가 원천 조회 실패 시 snapshot fallback 없이 비어 있거나 실패할 수 있던 경로 보강

## [0.0.17] - 2026-05-20

### Changed

- 앱/홈 aggregate/widget background의 direct KBO 라우팅을 `APP_ENV=local`, 네이티브 런타임, `API_BASE_URL` 미지정, `PREFER_DIRECT_SCRAPE=true` 조건을 모두 만족할 때만 허용하도록 통일
- provider routing 회귀 테스트를 추가해 웹, release, API override 빌드가 direct KBO 경로로 빠지지 않도록 검증
- local backend 없이 검증하는 `android-release`, `web-release` 실행 경로를 추가하고 release API health gate 통과 URL만 주입하도록 정리
- 일반 API-backed 앱 모드에서는 현재 시즌 순위/기록실 요약/리더보드 API 실패를 앱 번들 bootstrap으로 대체하지 않도록 변경
- device records overview snapshot은 AVG/HR/OPS/ERA가 모두 있는 완성본만 저장/재사용하도록 제한

### Fixed

- `PREFER_DIRECT_SCRAPE=true` 하나만으로 API override가 있는 local native나 widget background 경로가 direct KBO를 선택할 수 있던 위험 차단
- 기본 운영 API 도메인이 DNS/TLS/API health gate를 통과하지 못하면 release 실행/빌드가 시작되지 않도록 로컬 실행 경로까지 차단
- 원격 API가 없는 상황에서 현재 시즌 순위/기록실 요약/리더보드가 앱 번들 데이터로 조용히 표시될 수 있던 경로 차단
- 불완전한 records overview 응답이 device snapshot으로 저장되어 이후 기록실 첫 화면을 부분 데이터로 오염시킬 수 있던 경로 차단

## [0.0.16] - 2026-05-20

### Changed

- backend 현재 날짜 스코어보드와 현재 시즌/월 일정/순위/기록실 요약/리더보드 snapshot fallback도 `savedAt` 기준 6시간 이내 저장본만 사용하도록 제한
- 과거 날짜/시즌/월 스코어보드, 일정, 순위, 기록실 snapshot은 기존처럼 저장본 우선 fallback을 유지하도록 current 데이터 freshness와 분리
- 현재 날짜 scoreboard snapshot fallback은 fresh + terminal 상태일 때만 허용해 진행 중 경기의 오래된 snapshot 재노출을 차단
- 앱 기록실 선수/리더 모델과 device/local snapshot 직렬화에서 `isRetired` 플래그를 보존하도록 변경
- 앱 API cached-first 요청은 원격 실패 시에도 TTL이 지난 cache를 fallback으로 반환하지 않도록 제한
- 현재 시즌 records overview 번들은 `generatedAt` 기준 최신 snapshot만 fallback으로 사용하도록 제한
- 홈 스코어보드 로컬 cache는 `savedAt` 포함 payload만 인정하고 경기 상태별 TTL을 적용하도록 변경
- 현재 시즌 팀 선수 API 요청은 오래된 cache 우선 표시를 피하고 원격 최신값을 먼저 시도하도록 변경

### Fixed

- 원천 조회 실패 시 오래된 현재 날짜/시즌 backend snapshot이 최신 데이터처럼 재노출될 수 있던 경로 차단
- 과거 시즌 기록실 리더보드가 은퇴 선수를 누락해 `2, 9, 13위`처럼 보이거나 2011 ERA가 빈 데이터로 표시되던 문제를 수정
- 앱 재실행 직후 오래된 홈 스코어보드 로컬 cache가 최신 현재 경기처럼 먼저 보일 수 있던 경로 차단

## [0.0.15] - 2026-05-20

### Changed

- 순위 번들 fallback도 exact-season-only 정책으로 고정하고, 현재 시즌 순위는 6시간 이내 생성본만 사용하도록 제한
- bootstrap snapshot 생성 스크립트가 live API를 여러 시즌에 팬아웃하지 않고, backend 저장 snapshot만 앱 번들로 동기화하도록 변경
- 웹 `APP_ENV=local` 빌드가 명시적 `API_BASE_URL` 없이 `localhost`를 보지 않고 운영 API 기본값을 사용하도록 변경
- 2009~2013, 2020 기록실 요약 backend snapshot을 실제 시즌 리더 데이터로 보강
- KT 2026 팀 선수/팀 스탯 번들 snapshot을 최신 backend snapshot 기준으로 갱신

### Fixed

- 2026 시즌 초반 2경기 기준 순위가 2001~2025 시즌까지 반복되어 보일 수 있던 번들 데이터 제거

## [0.0.14] - 2026-05-20

### Changed

- 앱 기기 snapshot 저장 형식을 `savedAt` + `payload` envelope로 감싸 현재 시즌 기록실 캐시 신선도를 판정할 수 있도록 변경
- 현재 시즌 팀 선수/팀 스탯/팀 기록/리더보드 기기 snapshot은 6시간 이내 저장본만 fallback으로 사용하도록 제한
- 현재 시즌 번들 팀 선수/팀 스탯 asset도 `savedAt` 기준 6시간 이내가 아니면 빈 상태로 처리해 오래된 2026 기록이 재노출되지 않도록 변경

### Fixed

- `savedAt`이 없는 구형 기기 snapshot이 현재 시즌 기록실에 남아 있을 때 오래된 팀 기록을 다시 보여줄 수 있던 경로 차단

## [0.0.13] - 2026-05-20

### Changed

- 구단 로고 URL을 KBO `fixed/emblem_*_L.png` 자산으로 교체해 온보딩, 홈, 일정, 상세, 순위의 로고 원본 해상도와 안정성을 개선
- 기록실 번들 overview fallback을 exact-season-only 정책으로 고정해 다른 시즌의 리더 데이터를 빌려 보여주지 않도록 변경
- 현재 시즌 팀 선수/팀 스탯은 저장 snapshot을 먼저 쓰지 않고 원천 조회를 우선하며, 실패 시에도 6시간 이내 snapshot만 fallback으로 사용하도록 보강
- backend 홈런 리더보드 2026 snapshot을 추가해 원천 조회가 느릴 때도 현재 시즌 홈런 순위 fallback을 사용할 수 있도록 보강
- KT 2026 팀 선수/팀 스탯 snapshot을 최신 원천 기준으로 갱신

### Fixed

- 번들 `records_overview.json`에 남아 있던 오래된 2026-03-31 기준 허경민/함덕주 등 잘못된 리더 데이터를 제거

## [0.0.12] - 2026-05-20

### Changed

- 기록실 첫 화면에서 미지원 `WAR` 카드 대신 `wRC+` 리더보드를 노출
- 라인업 탭 선발투수 카드의 박스 높이와 선수 사진 비율을 맞춰 빈 공간과 과도한 얼굴 확대를 줄이도록 조정
- 홈 마이팀 브리프 아래에 리그 전체 관전 포인트를 요약하는 `KBO 브리프` 카드 추가
- 경기 전 상태의 홈/일정 경기 표기는 점수 대신 `vs` 중심으로 보이도록 조정
- 경기 카드, 일정 카드, 기록실 카드/필터, 하단 탭, 온보딩 구단 카드에 짧은 press 피드백을 추가하고 점수 변경 모션을 더 부드럽게 개선
- 경기 상세의 회차/문자중계/박스스코어, 홈 보조 카드, 일정 달력, 설정 행에도 같은 micro motion을 확장 적용

### Fixed

- 2013년 등 과거 시즌 기록실 선수 이미지가 존재하지 않는 시즌별 CDN 폴더를 바라보던 문제를 수정
- 홈 `홈런왕` quick item이 선수 사진 대신 이름 첫 글자만 보이던 문제를 수정
- 종료/과거 경기의 박스스코어, 라인업, 문자중계가 완성된 저장 snapshot을 우선 사용해 불필요한 원천 재조회와 빈 상세 fallback을 줄이도록 수정
- 최근 3경기 흐름에 예정/취소/미완료 경기가 끼어들지 않도록 종료 경기만 집계

## [0.0.11] - 2026-05-20

### Changed

- 앱 버전을 `0.0.11+11`로 올리고 현재 테스트 가능한 릴리즈 기준을 `0.0.11`로 정리
- 과거 preview/prerelease 표기를 제거하고 GitHub 릴리즈, 앱 내 패치노트, 버전 정책을 `0.0.1`부터 이어지는 숫자 릴리즈 기준으로 재작성
- 라인업 탭 첫 진입에서 박스스코어 파생 타자/투수 fallback 조회를 제거해 `/game/{gameId}/lineup`과 양 팀 선수 이미지 조회만 사용하도록 축소
- 라인업 선발 비교에서 박스스코어가 없을 때 `0.00` 같은 가짜 수치 대신 `-`와 `선발 발표` 상태로 표시
- 홈 scoreboard 자동 refresh를 live 30초, scheduled 5분, terminal 정지로 조정
- 홈 스코어보드 캐시 payload가 같을 때 중복 저장과 불필요한 화면 갱신을 피하도록 보정
- 웹에서는 홈 위젯/Live Activity용 resume observer를 등록하지 않아 기록실/일정 복귀 시 전역 scoreboard refresh가 끼어들지 않도록 정리

## [0.0.10] - 2026-05-20

### Changed

- 임시 direct-primary iPhone 빌드에서 2025/2024 등 과거 시즌 기록실이 빈 결과로 보이던 문제를 수정
- KBO WebForms 세션 cookie와 전체 form state를 유지해 과거 시즌 records overview, leaderboard, team stats POST를 정상화
- 과거 시즌 팀 기록실은 현재 로스터 검색 대신 시즌/팀 필터가 걸린 KBO 기록 테이블에서 야수/투수 기록을 구성하도록 변경
- 앱 startup에서 원격 API prefetch 죽은 코드와 `startupScoreboardProvider` 의존성을 제거하고, 첫 route 진입은 local onboarding/my-team 상태만 확인하도록 정리
- backend records/team stats crawler도 동일한 WebForms payload 방식으로 보정해 snapshot 재생성 안정성을 개선

## [0.0.9] - 2026-05-20

### Changed

- 홈 화면에서 `/home` aggregate 로딩 중 별도 `recordsOverviewProvider`를 호출하던 보조 섹션 제거
- 홈 첫 화면 데이터 흐름을 `scoreboardProvider`와 지연 `homeAggregateProvider`로 고정
- aggregate 실패 시 schedule/standings/records 로컬 조립 fallback이 다시 실행되지 않도록 데이터 경로 문서와 구현 기준 정리
- direct-primary 정책 표현을 AGENTS/CLAUDE/엔지니어링 문서에 맞춰 동기화

## [0.0.8] - 2026-05-20

### Added

- 설정 화면에서 버전별 패치노트를 볼 수 있는 `패치노트` 진입점 추가
- 루트 `README.md` 추가
- 루트 `CHANGELOG.md` 추가
- GitHub Actions 수동 빌드 워크플로우 추가 (`.github/workflows/app-build-artifacts.yml`)
  - Android `apk` / `aab`
  - iOS simulator 앱 zip
  - 선택적 signed iOS `ipa`
  - Web 정적 빌드 zip
- Codex 앱 실행 액션용 `scripts/codex-run.sh` 추가
- 플랫폼 분리 Codex 실행 액션용 래퍼 스크립트 추가
  - `scripts/codex-run-ios.sh`
  - `scripts/codex-run-android.sh`
  - `scripts/codex-run-web.sh`
- 문서 유지관리 규칙에 `README.md`와 `CHANGELOG.md` 갱신 원칙 추가
- Flutter web 플랫폼 추가 (`app/web`)
- 하단 탭 `기록실` 추가
- 팀 엔트리 / 엔트리 제외 / 부상 상태와 간단 기록을 확인하는 선수 기록실 화면 추가
- 선수 프로필, 시즌 기록, 최근 기록을 보여주는 선수 상세 화면 추가
- 기록실에 `야수 / 투수` 탭과 `타율 / OPS / ERA / WHIP` 정렬 추가
- `/api/team/{teamId}/players`, `/api/player/{playerId}` 선수 API 추가
- 일정 화면에 경기별 예매처 / 예매 오픈 시간 표시 추가
- 경기 상세 화면에 예매처 바로가기와 예매 오픈 알림 설정 추가
- 경기 상세 화면에 KBO 공식 / 유튜브 하이라이트 카드와 웹 연결 추가
- 일정 구장별 보기에 구장 퀵링크 버튼을 추가해 원하는 구장 섹션으로 바로 이동할 수 있도록 개선
- web deep-link 라우터 회귀 테스트 추가
- Android release signing 예시 파일 추가 (`app/android/key.properties.example`)
- release 빌드 전 production API DNS/TLS/핵심 endpoint를 검증하는 health gate 스크립트와 GitHub Actions 차단 단계를 추가
- API 미구현 영역을 iPhone release-mode에서 검증할 수 있도록 임시 direct-primary `ios-local-release` / `codex-run-ios-local-release.sh` 경로 추가
- release API backend 준비 항목을 `docs/RELEASE_API_BACKEND_TODO.md`로 분리

### Changed

- 설정 화면의 `앱 밖 표면` 설명 블록을 제거하고, 장면별 알림 picker 안에서만 전달 방식을 고르도록 정리
- 홈, 일정, 순위, 기록실, 선수 상세의 로딩/데이터 전환과 주요 리스트 행 등장에 공통 모션을 적용해 화면 내부 변화도 부드럽게 보이도록 개선
- local native 실행에서 `API_BASE_URL`이 없을 때 dev API DNS 실패로 홈/일정/순위/기록실이 깨지지 않도록 실행 스크립트가 local backend URL을 주입하고, 실패 시 중단하도록 보정
- `ios-local-release`는 API 실패 fallback이 아니라 `PREFER_DIRECT_SCRAPE=true` 를 명시한 임시 direct-primary 경로로 분리
- 기록실 팀 선수 bootstrap asset을 2022~2026 전 구단으로 확장하고, 과거 시즌 팀 로스터는 현재 등록 선수 direct 검색 대신 snapshot을 사용하도록 보정
- 기록실 팀 스탯은 타격/투구가 모두 있는 complete snapshot만 앱에 포함하고, partial payload가 UI에 노출되지 않도록 보정
- 기록실 local asset fallback이 없는 시즌에서 다른 시즌 데이터를 빌려 보여주지 않도록 변경
- 임시 direct-primary iPhone 빌드에서 2025/2024 등 과거 시즌 기록실이 빈 결과로 보이던 문제를 수정. KBO WebForms 세션/form state를 유지하고, 과거 시즌 팀 기록은 시즌/팀 필터가 걸린 KBO 기록 테이블에서 직접 구성
- 홈 초기 로딩 화면에서 여러 카드가 각각 spinner를 보여 중복 로딩처럼 보이던 UI를 skeleton 중심으로 정리
- 설정 화면의 `버전` 항목이 하드코딩 값 대신 실제 앱 메타데이터 버전을 표시하도록 개선
- 설정의 앱 정보 및 지원 영역에서 이용약관, 개인정보처리방침, 오픈소스 라이선스, 문의하기가 실제로 열리도록 정리
- 홈/기록실의 홈런 관련 리더 표현을 팬에게 더 자연스러운 `홈런왕` 중심 카피로 정리
- v4 UX 평가 후 홈 대표 경기 CTA를 상태별로 `경기 정보 / 중계 보기 / 경기 기록 / 하이라이트`로 분리하고, 종료 경기에서 알림 중심 CTA가 보이지 않도록 개선
- web preview에서 `/#/schedule`, `/#/records`, `/#/game/...` 직접 진입 시 앱 부트스트랩 이후 `/home`으로 돌아가던 라우터 상태 보존 문제를 수정
- 일정 화면 최초 로딩에서 새로고침 indicator와 중앙 loading spinner가 동시에 보일 수 있던 중복 로딩 UI를 단일 spinner로 정리
- 하단 탭, 부트/온보딩, 경기 상세/진단 화면 전환에 공통 모션을 적용해 앱 화면 이동이 더 부드럽게 보이도록 개선
- iOS Widget / Live Activity / Dynamic Island에서 현재 타석 정보가 없을 때 B/S/O가 `0`으로 보이지 않도록 개선
- 홈 위젯을 누르면 현재 표시 중인 경기 상세로 바로 이동하고, 갱신이 늦은 위젯은 `업데이트 지연`으로 표시되도록 개선
- 현재 날짜/현재 시즌 데이터 요청에서 fresh cache도 먼저 반환하던 공통 캐시 분기를 수정해, 오늘 경기/일정/순위/기록실이 정상 상황에서는 API 최신 응답을 먼저 받도록 개선
- 온보딩 구단 선택 카드가 초소형 엠블럼 이미지를 확대하지 않도록 더 큰 공식 엠블럼 경로와 고품질 필터링을 적용
- 경기 상세에서 종료 경기 하이라이트가 탭 진입을 가리지 않도록 스코어 탭 하단으로 이동하고, `중계 보기` 진입 시 중계 탭이 우선 보이도록 정리
- 설정의 알림 전달 용어를 `바로 알림 / 묶음 요약 / 따라가기만 / 끄기`로 정리
- 기록실 overview snapshot이 오래된 shape여도 OPS+ 리더보드를 현재 API 계약에 맞춰 보정해 빈 카드가 나오지 않도록 개선
- 설정의 `알림 플레이북`과 경기 상세 `경기 따라가기`를 v4 Moment Subscription / Surface Strategy 시안에 맞춰 정리하고, Push / 따라가기 / 홈 위젯 역할을 더 명확하게 표시
- Android에서도 `경기 따라가기`를 진행형 알림으로 표시해 스코어, 이닝, 업데이트 시각을 앱 밖에서 따라볼 수 있도록 개선
- 홈, 경기 상세, 일정, 기록실, 설정 화면의 실제 Flutter UI를 v4 compact dark sports 톤으로 정리하고, 390px 모바일 폭 기준 카드/탭/헤더 밀도를 조정
- 설정 화면의 알림 설정을 `알림 플레이북`으로 바꿔 경기 시작, 득점, 홈런, 역전, 경기 종료, 라인업, 이닝 교대별로 `바로 / 요약 / Live만 / 끄기`를 선택할 수 있도록 개선
- 앱 시작 직후 알림 권한을 요청하지 않고, 사용자가 권한 확인, 바로 알림, 경기 따라가기 같은 명시적 동작을 선택한 뒤에만 OS 권한을 요청하도록 조정
- 경기 상세 라이브 경기 화면에 `경기 따라가기`를 추가하고, Live Activity는 앱이 자동으로 고른 경기가 아니라 사용자가 선택한 경기만 따라가도록 변경
- 위젯 / Live Activity 갱신이 별도 KBO direct crawling 루프를 만들지 않도록 compact scoreboard API를 사용하고, current-at-bat 직접 조회를 제거
- 최초 실행 원격 데이터 prefetch가 끝나지 않아 시작 화면에 머무를 수 있던 구조를 제거하고, 홈 화면 진입 뒤 백그라운드로 갱신하도록 조정
- KBO 라이브 상세 응답에서 총점 필드가 비어 있고 이닝별 점수만 있는 경우에도 합산 점수로 라이브 스코어를 표시하도록 보정
- 경기 상세가 오늘/미래 경기의 오래된 snapshot을 먼저 사용하지 않도록 조정해 경기 중 0:0 상세가 남는 문제를 수정
- 경기 종료 전환 직후 KBO scroll scoreboard가 비어도 보조 이닝표와 main score로 상세 스코어/이닝표를 표시하도록 보강
- 웹 경기 상세 캐시 키를 갱신해 기존 0:0 상세 캐시를 재사용하지 않도록 조정
- 기본 앱 데이터 경로에서 direct KBO crawling fallback과 과도한 startup/detail preload를 제거해, 홈/일정/경기 상세 진입 시 불필요한 웹 원본 호출이 발생하지 않도록 조정
- 백엔드가 같은 날짜 scoreboard 동시 요청을 한 번의 원천 조회로 합치고, 경기 단건 상세 조회가 같은 날짜 전체 경기 상세를 함께 불러오지 않도록 조정
- KBO 원천 웹 응답이 느리거나 깨질 때 일정/기록실이 더 버티도록 월간 일정 snapshot 저장 조건을 완화하고 records leaderboard snapshot 및 앱 bundled overview fallback을 추가
- 박스스코어와 문자중계의 현재 타석 주자 상태가 KBO 응답의 베이스 이미지 경로를 못 읽은 경우에도 주자 이름 기반으로 `주자1루`, `주자1,3루`, `만루` 등으로 표시되도록 보강
- 라인업 탭 선발투수 카드가 선수목록 조회 지연/이름 표기 차이에 막히지 않도록 KBO main game의 선발투수 id 기반 이미지 URL을 직접 사용하고, 백엔드 라인업 API도 starter id/imageUrl을 함께 내려주도록 보강
- local iPhone direct KBO 모드에서 문자중계가 startup/history warm 요청과 선수 프로필 대량 조회 뒤에 밀려 로딩 상태에 오래 머무를 수 있던 경로를 줄이고, 경기 상세 자동 새로고침이 진행 중 요청을 반복 invalidate 하지 않도록 조정
- 홈/일정/경기 상세 진입 경로에서 문자중계, 박스스코어, 라인업 데이터와 주요 선수 프로필 이미지를 미리 로딩해 상세 탭 첫 진입 대기감을 줄이도록 조정
- 일정 탭의 오늘 경기 상태를 `Main.asmx` live 메타데이터로 보정해 진행 중 경기가 `경기 전`으로 표시되는 문제를 수정
- 마이팀을 선택하지 않았을 때 마이팀 경기 푸시가 리그 전체 토픽으로 잘못 연결될 수 있던 동작을 수정
- FCM 토큰 갱신 시 현재 저장된 응원팀 기준으로 푸시 토픽을 다시 동기화하도록 보정
- 종료/취소/서스펜디드 경기에서는 일정 카드와 경기 상세의 예매 정보를 숨기도록 정리
- 경기 상세 문자중계 탭에서 현재 타석과 주요 플레이에 선수 프로필 이미지를 함께 보여주고, 볼/스트라이크/아웃 카운트를 색상 중심으로 더 빠르게 읽을 수 있도록 개선
- 경기 상세 문자중계에서 이닝 칩을 눌러 특정 회차 중계만 골라 볼 수 있도록 개선
- 경기 상세 문자중계를 타석별 카드 중심 레이아웃으로 다듬어, 선수 프로필과 투구 로그를 한 번에 읽기 쉽게 개선
- 경기 상세 박스스코어의 핵심 타자/핵심 투수 카드에 선수 프로필 이미지와 더 강한 텍스트 대비를 적용해 가독성을 개선
- 홈 `지금 보면 좋은 정보`의 선수 카드 탭 시 최근 기록 요약을 먼저 보고 선수 상세로 이어질 수 있도록 개선
- iOS 잠금화면 Live Activity에서 점수 영역이 양끝으로 벌어지지 않도록 중앙 배치로 조정
- iOS 잠금화면 Live Activity와 iOS 위젯 점수 영역에 팀 로고를 함께 표시하도록 개선
- iOS 잠금화면 Live Activity와 iOS 위젯에 현재 타석 타자/투수와 투구 수를 함께 표시하도록 개선
- `local` 환경에서도 홈 경기 이벤트 로컬 알림이 동작하도록 조정
- 경기 이벤트 알림 범위를 홈런, 이닝 교대, 선발 라인업 공개/변경까지 확장
- 설정 화면 알림 토글에 `라인업`, `이닝 교대`를 추가하고 로컬/원격 등록 payload를 함께 정리
- 배포/서명 문서에 GitHub Actions 기반 빌드본 추출 절차와 필요한 CI 시크릿 항목을 추가
- 웹에서 온보딩, 홈, 일정, 순위, 설정 화면이 브라우저 전체 폭으로 과도하게 늘어나지 않도록 모바일 폭 기준 레이아웃으로 정리
- 홈 화면의 마이팀 미선택 상태 CTA와 오늘의 야구 빠른 이동 동선을 보강
- 일정 화면에 달력 범례를 추가해 마이팀 경기일과 일반 경기일을 더 쉽게 구분하도록 개선
- 순위 화면 상단에 마이팀 현재 위치 요약 카드를 추가해 핵심 순위를 먼저 확인할 수 있도록 개선
- 설정 화면에 알림별 설명 문구를 추가해 어떤 알림이 오는지 더 쉽게 이해할 수 있도록 개선
- 앱 부트스트랩에 timeout/fallback 을 추가해 웹에서 저장소 응답 지연 시 스플래시 화면에 오래 머무를 가능성을 줄이도록 보강
- 웹 HTML 스플래시에 DOM 감지/timeout 제거 fallback 을 추가해 초기 렌더 지연 시 검은 대기 화면이 오래 남지 않도록 보강
- 정적 빌드 기반 웹 프리뷰 실행 경로(`./scripts/codex-run.sh web-static`, `./scripts/codex-run-web-static.sh`)를 추가
- 기본 웹 실행 래퍼(`./scripts/codex-run-web.sh`)를 정적 프리뷰 기준으로 전환하고, Chrome 디버그 실행을 `./scripts/codex-run-web-dev.sh`로 분리
- 백엔드 스코어보드 API가 `yyyyMMdd` 형식 날짜 요청도 처리하도록 보강해 웹 홈 화면에서 발생하던 날짜 포맷 오류를 줄임
- 웹 경기 상세 하이라이트에서 인라인 재생을 유지하면서 `스크롤 / 플레이어 조작` 모드 전환으로 스크롤 잠김을 줄이도록 조정
- 앱 시작 직후 홈, 일정, 순위, 기록실 데이터를 백그라운드로 미리 불러오도록 조정해 첫 탭 진입 대기시간을 줄임
- 앱이 FCM 토큰과 토픽 구독을 실제로 동기화할 수 있도록 원격 푸시 등록 경로를 연결
- 백엔드에 Firebase Admin 기반 테스트 푸시 발송 endpoint를 추가
- 홈 화면 상단에 `마이팀 브리프`, `오늘의 야구`, `빠른 콘텐츠` 영역을 추가해 경기 없는 날에도 야구 정보가 먼저 보이도록 개선
- 기록실 팀 화면이 선수 목록과 팀 스탯을 한 번에 받아오도록 바꿔 초기 로딩 지연을 완화
- 백엔드 기록실 크롤링 일부를 병렬화해 팀 기록 관련 최초 응답 속도를 개선
- 백엔드가 팀 기록실 응답을 짧게 캐시하도록 조정해 같은 팀 재진입 속도를 개선
- 기록실 팀 선택 화면이 웹에서 모든 구단 선수 데이터를 한꺼번에 불러오지 않도록 정리해 초기 진입 속도와 안정성을 개선
- 기록실 첫 화면에서 리그 리더보드/추천 선수 중심으로 먼저 보여주고, 팀 상세 진입 시에만 선수 데이터를 조회하도록 조정
- 기록실 첫 화면 리더보드에 리그 홈런 순위를 추가
- 크롤링 기반 기록 API가 느릴 때 웹에서 먼저 끊기지 않도록 앱 API 타임아웃을 완화해 기록실 상세 안정성을 개선
- 설정 화면의 `전체 경기 알림` 안내 문구가 실제 스위치 상태와 일치하도록 수정
- 일정 화면 경기 카드 상태 문구를 `경기 전 / 경기 중 / 경기 종료`로 정리하고, 점수가 있는 경기는 카드 중앙에 스코어를 함께 표시하도록 개선
- 저장소 소개, 실행 방법, 문서 우선순위를 루트 README에서 바로 확인할 수 있도록 정리
- README에 Codex 앱 실행 액션 등록용 공용 명령 추가
- `scripts/codex-run.sh`에 Chrome 기반 웹 실행 명령 추가
- Codex 액션 등록 권장 경로를 `ios/android/web` 분리 스크립트 기준으로 정리
- 에이전트/프로젝트 컨텍스트 문서에 README 및 CHANGELOG 지속 갱신 규칙 반영
- 백엔드 타입 힌트를 Python 3.9 호환 문법으로 정리해 `uvicorn` 실행 오류 수정
- Firebase iOS 플러그인 요구사항에 맞춰 iOS 최소 배포 버전을 `15.0`으로 상향
- 웹/릴리즈 기록실이 KBO 기반 백엔드 선수 API를 사용하도록 연결
- iOS Xcode 프로젝트의 플랫폼 설정을 시뮬레이터/기기 공용으로 정리
- 일정 화면에서 종료 경기 상세 진입 시 `경기를 찾을 수 없습니다`가 뜨던 문제를 수정해 `gameId` 기반 상세 재조회가 가능하도록 보완
- 백엔드에 `/game/{gameId}` 단건 조회를 추가해 웹/릴리즈 환경에서도 경기 상세 진입이 동작하도록 수정
- 일정/상세 API 응답에 예매처와 예매 오픈 시간 정보를 포함하도록 확장
- 디바이스 로컬 예약 알림으로 예매 오픈 시각 알림을 받을 수 있게 보완하고, 리마인드를 하루 전 / 1시간 전 / 10분 전으로 확장
- 경기 상세 API에서 KBO 공식 하이라이트 링크와 유튜브 검색 기반 메타데이터를 함께 내려주도록 확장
- 문자중계 API 미구현 상태에서 상세 탭에 raw 오류가 노출되지 않도록 경기 상태별 안내 문구로 정리
- 문자중계 탭의 중복 API 호출을 제거하고, relay API가 빈 응답을 반환하도록 정리해 웹 콘솔 오류를 줄임
- KBO 일정의 `START_PIT` 프리뷰 링크를 예정 경기로 인식하도록 보정해 예정 경기 상세 상태가 `UNKNOWN`으로 내려오지 않게 수정
- 종료 경기 문자중계 탭에 이닝별 득점 흐름과 최종 결과를 보여주는 summary relay를 추가
- KBO 로그인 세션이 설정된 경우 `LiveTextView2.aspx` 기반의 실제 play-by-play relay를 파싱해 문자중계 탭에 제공하도록 확장
- relay 서비스가 종료 경기에서는 요약형 득점 흐름을 우선 사용하고, live 경기에서는 현재 타석 정보를 더 안정적으로 보강하도록 정리
- 경기 상세 화면의 누락된 라인업 탭 파일과 생성자 불일치를 수정해 웹 빌드 실패를 해결
- 예정 경기 scoreboard 응답에 세부 테이블이 없어도 홈 화면이 500 없이 열리도록 보강하고, 예정 경기 문구를 올바르게 표시하도록 수정
- 홈/순위 화면 에러 메시지를 사용자용 문구로 정리하고, 개발 환경에서는 API 응답 시간을 Dev Console 에 기록하도록 보강
- 기록실 캐시를 공통 TTL 캐시 유틸로 정리하고, 예정 경기에서는 YouTube 하이라이트 검색을 생략해 첫 로딩 불필요 호출을 줄임
- 날짜별 스코어보드 응답도 짧게 캐시하고 경기별 enrich 를 병렬화해 홈 재진입 속도를 추가로 개선
- 홈/기록실 실측 지표를 서버 로그로도 수집하고, 웹에서 `API 진단` 화면으로 `health / scoreboard / schedule` 상태를 함께 확인할 수 있도록 추가
- KBO 원본 호출에 circuit breaker 와 stale cache fallback 을 도입해 외부 응답 불안정 시 홈/기록실 복원력을 높임
- 라인업 탭을 모바일 가독성 중심 카드형 레이아웃으로 개편하고, `AWAY/HOME`와 함께 실제 팀명과 로고를 표시하도록 개선
- 홈 진입 속도 개선을 위해 스코어보드 API에서 상세용 유튜브 하이라이트 검색을 분리
- iOS/Android 런치 스크린을 다크 테마로 정리해 앱 시작 시 흰 화면이 길게 보이는 현상을 완화
- Android release signing 이 `key.properties` 기반 구조를 사용하도록 정리
- 지난 경기 결과, 선수 과거 기록, 지난 날짜 순위를 저장된 snapshot 우선으로 읽는 데이터 전략을 문서 기준으로 확정해 히스토리 화면 로딩 없이 즉시 보여줄 수 있는 방향을 정리

## [0.0.7] - 2026-05-19

### Changed

- 설정의 알림 전달 방식을 `바로 알림`, `묶음 요약`, `따라가기만`, `끄기`로 정리
- 경기 상세에서 라이브 경기 `경기 따라가기`를 사용자가 직접 시작하도록 변경
- iOS 위젯과 Live Activity에서 점수, 팀 로고, 현재 타석 정보를 더 안정적으로 표시하도록 개선
- 초기 rolling snapshot의 마지막 기준으로 정리

## [0.0.6] - 2026-05-19

### Changed

- compact scoreboard, 위젯/Live Activity 데이터, release API health gate 방향 정리
- 홈과 경기 상세의 앱 밖 표면을 API-first 기준으로 축소
- release 빌드 전 production API DNS/TLS/핵심 endpoint를 확인하는 guard 도입

## [0.0.5] - 2026-04-11

### Changed

- Firebase, Android/iOS 배포 준비, signing 문서, tester 공유 흐름 정리
- 알림과 경기 따라가기 표면을 외부 테스트 준비 기준으로 확장

## [0.0.4] - 2026-04-11

### Changed

- 기록실, 선수 상세, 팀 기록, 경기 상세의 기본 구조를 앱 주요 화면으로 확장
- 일정, 순위, 예매 정보, 하이라이트 연결을 MVP 화면 흐름에 포함

## [0.0.3] - 2026-03-31

### Changed

- 마이팀 중심 UX, Dynamic Island/Live Activity 방향, 일정/상세 polish를 초기 검증
- 현재 진행 중이거나 오늘 예정된 마이팀 경기를 앱 밖 표면의 우선 후보로 다루는 방향 정리

## [0.0.2] - 2026-03-31

### Changed

- 초기 실행 스크립트, 문서, 위젯/Live Activity 후속 방향 보강
- 반복 작업을 `.claude/skills/`로 분리하고 AGENTS/CLAUDE 문서 기준을 동기화

## [0.0.1] - 2026-03-31

### Added

- Flutter 앱 골격, FastAPI backend 골격, MVP 화면 구조, 프로젝트 문서의 첫 릴리즈

## [2026-03-30]

### Added

- `AGENTS.md` 작성 및 저장소 작업 규칙 정리
- `backend/` FastAPI 기본 구조, 라우터 스텁, health endpoint, 테스트 추가
- `docs/TASK_DIVISION.md` 협업 운영 문서 정리

### Changed

- 모바일 기준 스택을 Flutter + Dart로 재확인
- `CLAUDE.md`와 `AGENTS.md`를 `docs/FIGMA_PROMPT.md` 및 최근 결정 기준으로 보강

## [2026-03-28]

### Added

- 프로젝트 초기 문서 세트 작성
  - `CLAUDE.md`
  - `docs/PLANNING.md`
  - `docs/APP_SPEC.md`
  - `docs/WORKLOG.md`
- Git 저장소 초기 설정

### Changed

- 모바일 프레임워크 방향을 React Native(Expo)에서 Flutter로 변경
- 인프라 방향을 AWS 기반으로 확정
