# 전 화면 수용 범위 매트릭스

2026-08-13 현재 소스와 회귀 테스트를 기준으로 정리한 범위다. 정적·위젯·웹 미리보기 증거와 실제 단말/운영 증거를 섞지 않는다.

| 영역 | 사용자 가치/검수 포인트 | 현재 근거 | 남은 게이트 |
| --- | --- | --- | --- |
| 온보딩·마이팀 | 첫 화면에서 팀을 고르고 건너뛰어도 홈으로 복귀, 작은 화면에서 CTA 도달 | `onboarding_screen_test.dart`, current web onboarding capture | 실제 iOS/Android 첫 설치 |
| 홈 scoreboard | 오늘 경기 우선, 미확정 점수 `–`, 실제 FINAL 최근 결과만 표시, nested CTA 없음 | `home_screen_test.dart`, `my_team_game_card_test.dart`, current home 390/320 capture | 실제 API freshness·KST 자정·단말 네트워크 |
| 경기 상세 | 스코어·문자중계·박스스코어·라인업, 상태/뒤로가기/240% reflow, follow 저장과 전달 분리 | `game_detail_navigation_test.dart`, `score_tab_test.dart`, `relay_tab_test.dart`, `boxscore_tab_test.dart`, `lineup_tab_test.dart` | APNs/FCM/Live Activity 실기기 |
| 일정 | 캘린더·구장·매치업, 월 refresh invalidation, 상세 즉시 진입, 320/240% | `schedule_screen_test.dart`, `schedule_game_card_test.dart` | 실제 KST 시즌 전환·KBO 원천 변동 |
| 순위·기록 | 시즌 rollover, 정확한 snapshot identity, leaderboard/team/player retry, 240%·scroll affordance | `standings_screen_test.dart`, `leaderboard_screen_test.dart`, `records_screen_error_test.dart`, `player_image_surfaces_test.dart` | 실제 시즌 원천과 보조기술 기기 |
| 데이터 브리핑 | 외부 기사로 가장하지 않음, 동일 fact만 dedupe, 서로 다른 metric/story 보존, 320 필터 reflow | `news_screen_test.dart` 12 tests, current news 390/320 capture | 향후 새 metric taxonomy 제품결정 |
| 알림·설정·진단 | 권한/등록/receipt 상태 분리, 오류 재시도, 44px target, update-notes scroll | `notification_inbox_screen_test.dart`, `settings_screen_test.dart`, `api_diagnostics_screen_test.dart`, `release_notes_prompt_test.dart` | 실제 FCM/APNs receipt, OS 권한 상태 |
| 공통 디자인·접근성 | dark/light/high contrast, supporting text 대비, 44/48px target, URL/back, 280/320/240% | `app_theme_test.dart`, `app_motion_test.dart`, `app_router_test.dart`, focused screen suites | VoiceOver/TalkBack 실기기 |
| Backend/API | 입력 경계, current truth, historical snapshot identity, push registry ownership/capacity, sync 효율 | backend 전체 `560 passed`, Ruff/compileall | 운영 ALB/EFS/AWS, 원천 장애·다중 task |

## 판단 규칙

- 정적 테스트 통과는 실제 전달·실기기 접근성·운영 배포 성공을 의미하지 않는다.
- current/future 데이터는 historical snapshot으로 위장하지 않으며, 확인 불가 값은 0으로 만들지 않는다.
- 제품결정이 필요한 알림 기본값·새 CTA·정보량 cap은 코드에서 임의로 확정하지 않는다.
