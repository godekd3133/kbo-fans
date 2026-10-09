# 모바일 실행 환경과 실제 API 계약 검증

## 목표와 현재 상태

첫 진입·탭 이동·위젯 등의 실기기 증거가 없어 native 실행 경로를 확인했다. 저장소 ios-device-run-action 스킬에 따라 Flutter devices와 Xcode showdestinations를 함께 확인했다. 현재 iPhone은 양쪽 모두 eligible이며 iPhone Mirroring은 기기 사용 중으로 연결하지 못했다. 사용자는 지금 기기를 사용 중이라고 답했다. 설치·실행하지 않고 독립적인 빌드/연결 검증을 수행한다.

## iOS 빌드

- Flutter iOS Debug, APP_ENV=local, USE_BACKEND_API=true, 명시적인 API_BASE_URL, no-codesign/no-pub로 현재 working tree를 compile했다.
- pod install과 Xcode build 성공, build/ios/iphoneos/Runner.app 생성 확인.
- unsigned local QA build다. physical install/run·signed artifact·upload·TestFlight·device display 증거가 아니다. signing/project/Podfile.lock에 새 tracked 변경 없음.
- 다른 프로젝트의 부팅된 simulator를 사용하거나 설정을 변경하지 않았다. Simulator.app UI는 현재 선택한 Xcode 위치에서 찾을 수 없었다.

## API 확인과 QA 계약 수정

- 구성된 운영 API health: HTTP200/success/status ok.
- scoreboard/home 요청은 HTTP200/success/date 2026-10-09/3 games 응답. source freshness·실제 점수 정확성·푸시 전달까지 증명하지 않는다.
- 세이브 최초 확인 요청은 개발자가 leaderboard path를 잘못 사용해 404였다. 실제 app consumer와 backend producer는 `/records/leaderboard?season=2025&metric=saves`. 정확한 요청은 HTTP200/success/season2025/metric saves/30 rows/rank1 시작이었다.
- ReferenceApiHandler도 path metric 방식으로 구현돼 실제 app query와 불일치했다. 실제 계약으로 수정했다. production app/backend contract는 변경하지 않는다.
- opt-in repository snapshot의 2026 avg fixture 30 rows/identity/rank1 시작과 invalid metric 차단을 확인했다. 기존 웹 build의 unchanged leaderboard consumer에서도 순위 표시를 확인했다. capture 601x858이며 current official freshness나 새 settings failure UI의 증거로 사용하지 않는다.

## 남은 검증

실기기 사용 가능 시 설치/실행·권한·탭 이동·재진입·큰 글자·widget/Island render를 확인한다. 현재 기기 사용 중이라는 응답은 유지하며 다시 요청하거나 설치하지 않는다. 전체 목표는 active다.
