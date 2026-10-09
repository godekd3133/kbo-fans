# 알림 연결 복구와 390px 정렬

## 문제·목표

알림 entry의 route가 유효하지 않을 때 pushAppRoute fallback이 홈을 열어 사용자가 읽던 알림 목록을 잃었다. 정상 경기 연결과 읽음 처리는 유지하며 malformed 연결은 현재 화면에서 안내한다.

기존 viewport override와 screenshot preview가 실제 저장 크기를 보장하지 못했다. CDP device metrics로 논리 390x844/visual viewport 390/scale1을 확인하고 fromSurface PNG를 저장한다. 이는 모바일 웹 검증이며 실기기 증거가 아니다.

## 수정·범위

- 알림 route를 fallback null로 검증하고 invalid이면 snackbar 안내만 제공한다. 알림의 읽음 처리와 정상 deep link 이동, 읽음 저장 실패 시에도 이동하는 기존 동작은 유지한다.
- 390px capture에서 empty card의 좁은 중앙 정렬을 확인했다. 본문 전체 폭으로 정렬한다.
- app consumer UI만 변경. notification entry 저장/등록 payload·backend push·cache·infra/release 변경 없음.

## 검증

알림함 11 tests passed, analyze 무결함. invalid route에서 notifications path와 목록 유지·read callback·안내 표시를 확인한다. 기존 unread/filter·큰 글자·정상 연결·settings 복귀 검증 포함. runtime invalid entry는 별도 fixture가 없어 not-run. 전체 목표는 active다.

- 최종 알림함 11 tests·웹 build 통과. CDP fromSurface PNG390x844와 DOM logical width390/scale1 확인. empty card 본문 폭 정렬과 settings CTA 실제 route 이동 확인. override clear 완료. invalid route 실화면·실기기는 not-run.
