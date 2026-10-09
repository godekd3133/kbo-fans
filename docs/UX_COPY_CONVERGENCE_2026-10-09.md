# 반복 해설 제거와 전체 검증 범위 정리

## 분석·목표

점수 탭은 scoreboard에 보이는 리드/동점을 다시 문장으로 해설하고 ‘경기 한눈에’, ‘경기 전에 확인할 것’ 등의 안내 제목을 붙였다. 업데이트 소식은 제목 아래 제목의 의미를 반복했고 홈 빈 소식은 준비 중으로 표시됐다. 실제 데이터와 action을 남기고 자명한 안내·기계적인 해설을 덜어낸다.

## 구현·영향 범위

- GameReadingCard의 결과 headline 함수와 일반 안내 제목을 제거한다. 검증된 득점 이닝/누적 score와 실제 이동 action은 유지한다. 5개 초과면 최근 5개라는 범위를 표시한다.
- button은 문자중계/박스스코어로 표기한다. 예정 경기의 선발·라인업 action은 유지하며 취소/중단에서 표시할 events/actions가 없으면 빈 카드를 렌더하지 않는다.
- 업데이트 소식의 반복 subtitle 제거. 홈 빈 소식은 현재 등록된 소식 없음으로 표현한다.
- backend/API/데이터 routing/cache·push·infra·release 변경 없음. 이전 goal의 backend home 변경을 포함한 tests/test_home.py도 검증한다.
- 전체 완료 기준과 독립 증거/남은 항목은 `docs/UX_GOAL_ACCEPTANCE_2026-10-09.md`에 유지한다. 기능별 작은 통과로 전체 완료를 주장하지 않는다.

## 검증

- 관련 Flutter 68 tests passed. chronology·missing/negative/corrected score 검증, 320px/240% text·action 이동·score tab·home tests 포함. 처음 요청한 patch_notes_screen_test 파일은 존재하지 않아 test load 오류가 났으며, 실제 존재하는 test 대상으로 재실행한 최종 로그를 보존했다.
- analyze 무결함·웹 build 성공. backend home 44 tests passed (1 warning).
- reference fixture의 20260619SSLG0 스코어 탭에서 득점 이닝·누적 점수·실제 action label 표시를 확인했다. 20260613KTLG0는 fixture가 지원하지 않는 ID여서 404였다. 이를 운영 경기 오류나 정상 화면 증거로 사용하지 않는다.
- 저장 화면은 601x858 웹 fixture. 실기기·운영 최신성·이번 변경의 빈 상태 runtime visual은 not-run. 전체 목표는 active다.
