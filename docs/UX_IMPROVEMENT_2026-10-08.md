# 2026-10-08 사용자 흐름 개선

## 목표와 니즈

앱을 여는 팬은 응원팀의 경기와 점수를 빠르고 정확하게 확인하고, 중계·기록·일정으로 자연스럽게 이동해야 한다. 첫 선택에서 모든 팀을 내려본 뒤 완료 버튼을 다시 찾는 부담, 오류 상태의 장식과 개발 용어, 확대 글자에서 잘리는 정보를 줄인다. 기존에 선택된 조용한 다크 스코어보드와 실제 구단 로고, Jua 기반 UI를 유지한다.

## 영향 범위

| 표면 | 이번 작업 |
|---|---|
| Flutter 앱 | 온보딩, 홈 LIVE 카드/순위 요약, 공통 헤더와 상태 카드, 일정·순위의 오류/빈 상태, 기록 리더보드의 확대 글자 스크롤, 설정 문구 |
| FastAPI | scoreboard·schedule·standings producer와 앱 API repository consumer, 응원팀 저장 이후 push 등록 수렴 경로를 확인. 응답 계약·수집·캐시·scheduler 코드는 변경하지 않음 |
| 인프라 | 배포 변경 없음. 별도 로컬 FastAPI health와 API 계약 테스트로 검증 |
| 릴리스 | 버전·태그·커밋·업로드·테스터 그룹 변경 없음. 로컬 검증용 웹 빌드를 사용 |

## 분석 → 계획 → 구현 → 검증

1. 현재 체크아웃을 API 모드로 실행하고 390×844 화면에서 팀 선택, 홈, 상세 4개 탭, 일정, 기록/순위, 브리핑, 설정을 살핀다. 기존 실행 산출물과 신규 빌드를 구분하며 새 origin에서 브라우저 캐시 영향도 분리한다.
2. 첫 진입의 행동을 고정하고, 오류/빈 상태의 다음 행동을 명확히 하며, 실제 경기 점수의 팀 연결과 확대 글자 동작을 우선 수정한다.
3. 구현 후 280/320px·200/240% 글자, 응원팀의 홈/원정 역할, 선택 이후 건너뛰기, 저장 중 중복 탭을 검증한다.
4. 전체 Flutter 검사에서 드러난 리더보드 고정 높이의 overflow까지 수정하고 재검증한다. 단순 캡처가 아니라 navigation/provider 회귀 테스트와 함께 판단한다.

## 변경 결과

- 온보딩의 `시작하기`/`선택 완료`와 `나중에 선택`/`취소`는 SafeArea 안의 고정 하단 영역에 둔다. 본문만 스크롤되며 하단 영역은 실제 내용 높이만 차지한다.
- 최초 진입에서 `나중에 선택`은 임시 선택을 저장하지 않는다. 완료를 누른 경우만 선택팀을 저장한다. 편집의 취소는 기존 팀을 유지하고 원래 화면으로 돌아간다. 느린 push 등록 수렴은 진입을 막지 않는다.
- 홈 LIVE 카드는 응원팀을 왼쪽에 표시하는 만큼 점수·색·스크린리더도 응원팀→상대팀 순서다. 팀 로고 아래 짧은 구단명을 표시하며 큰 글자에서는 팀 식별 영역과 스코어를 위아래로 분리한다. 숫자는 공간이 부족한 경우에만 전체 값이 보이도록 축소하고 접근성 이름에는 양 팀과 전체 점수를 보존한다.
- 홈 순위 요약은 340px 미만 또는 140% 이상 글자에서 팀별 행과 줄바꿈 가능한 기록으로 전환한다. 정상 모바일 기본 글자에서는 기존 표를 유지한다.
- 공통 페이지 헤더는 제목·설명을 줄임표로 끊지 않는다. Jua의 단일 regular 서체를 쓰는 공통 헤더·온보딩·LIVE 카드에서는 과도한 합성 굵기를 줄인다.
- 리더보드는 확대 글자에서 헤더·지표 선택·결과가 한 스크롤에 흐른다. normal 글자 크기의 기존 결과 리스트 스크롤은 유지한다.
- 홈·일정·순위의 오류와 순위 빈 상태는 내용 높이에 맞는 `AppStatusCard`로 표시한다. 홈 첫 요청 실패에는 재시도와 `일정 보기`를 함께 제공한다. 실제 오류를 데이터 없음으로 바꾸거나 cache로 숨기지 않는다.
- 사용자 안내의 `백엔드 상태`, `팀 기록 API`, `기기 등록` 같은 용어를 행동 중심의 한국어로 바꾼다. 알림 권한과 인터넷/경기 갱신에 따른 지연 가능성은 유지한다.

## 화면 증거와 재현

`artifacts/ux-improvement-2026-10-08/`에 이번 실행의 캡처를 저장하고 실제 저장된 이미지를 확인한다. 결과 갤러리는 같은 폴더의 `review.html`이다.

화면 데이터는 로컬 reference fixture 및 명시적으로 읽은 기존 repository snapshot이다. 예시의 경기일·득점·기록은 운영 최신성의 증거가 아니다. 조회 원본의 season/month/저장 시각을 바꾸지 않는다. fixture에 없는 월/선수는 실패 상태를 유지하며 다른 identity의 데이터를 대신 제공하지 않는다.

```sh
python3 scripts/kbo-reference-api.py --port 8037 --include-snapshots
cd app
fvm flutter build web --release --no-pub --no-wasm-dry-run \
  --dart-define=APP_ENV=local --dart-define=USE_BACKEND_API=true \
  --dart-define=API_BASE_URL=http://127.0.0.1:8037/api \
  --dart-define=SHOW_DEV_CONSOLE=false
python3 -m http.server 7358 --bind 127.0.0.1 --directory build/web
```

`--include-snapshots`는 시각 QA 전용 opt-in이다. production backend의 current 데이터 정책과 관계없고 원래 snapshot payload를 그대로 사용한다. 일반 run/release entrypoint의 기본 API 경로는 변경하지 않는다.

## 검증 경계

Flutter 분석/테스트, reference API 브라우저 화면, 실제 로컬 FastAPI health/API 테스트를 별도 결과로 기록한다. 이 작업으로 실기기 성능, 실제 경기의 최신성, 알림 실수신, 앱 종료 후 Live Activity, 서명 아티팩트, TestFlight 처리·설치 가능성을 입증하지 않는다. Figma 캔버스는 수정하지 않았다.

## 최종 검증 결과

- `cd app && fvm flutter analyze --no-pub`: No issues found.
- `cd app && fvm flutter test --no-pub --reporter expanded`: 629 passed, 0 failed.
- API mode 웹 release 빌드 통과. 390×844 및 320×568의 새 origin에서 화면 readback 수행.
- `cd backend && .venv/bin/pytest -q tests/test_health.py tests/test_schedule.py tests/test_teams.py`: 26 passed.
- 별도 로컬 FastAPI `GET /api/health`: HTTP 200 / status ok. reference fixture health와 구분한다.
- reference helper의 Python 3.9 syntax 검사와 py_compile 통과. opt-in snapshot endpoint 4종 readback HTTP 200.
- 정상 홈·상세 4탭·과거 일정·기록실·순위·브리핑·설정과 의도된 일정 조회 실패 캡처를 저장 후 직접 열어 확인했다. 상세 직접 진입 후 뒤로가기는 홈으로 복귀했다.
- 최종 로그와 `verification.json`, 전후 갤러리를 `artifacts/ux-improvement-2026-10-08/`에 보존했다.
