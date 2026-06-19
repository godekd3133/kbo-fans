# 2026-06-19 UI Image Reference

## Goal

현재 KBO Fans UI를 텍스트 기획만이 아니라 이미지 기반 레퍼런스와 생성 mock 기준으로 조정한다.

## External References Checked

- Apple Sports: 빠른 점수 확인, 개인화된 리그/팀/대회 follow, Live Activities 중심의 단순한 스포츠 앱 구조를 참고했다.
  https://apps.apple.com/us/app/apple-sports/id6446788829
- MLB App FAQ: iPhone Live Activities에서 점수와 진행 상태를 한눈에 보여주는 경기 follow 구조를 참고했다.
  https://www.mlb.com/apps/mlb-app/faq-apple
- SofaScore home screen update: 상단 quick access, favorites/date navigation, cleaner home 구조를 참고했다.
  https://www.sofascore.com/news/sofascores-new-home-screen-a-smarter-faster-way-to-follow-sports
- SofaScore statistics tab update: 경기 상세의 얇은 탭 underline, 팀 컬러 기반 stat grouping, 어두운 배경 위 dense record surface 구성을 참고했다.
  https://www.sofascore.com/news/statistics-tab-a-fresh-new-look/
- Sports mobile app concept: 다크 스포츠 UI에서 카드 밀도와 action row를 배치하는 방식을 참고하되, 스타일은 그대로 복제하지 않았다.
  https://dribbble.com/shots/25393724-Sports-Mobile-App-Design

## Generated References

- `2026-06-19-home-scoreboard-reference.png`: 홈 scoreboard / quick action / 경기 목록 방향
- `2026-06-19-standings-reference.png`: 순위표 summary rail / dense table 방향
- `2026-06-19-game-detail-reference.png`: 경기 상세 live scorebug / 상황 카드 방향
- `2026-06-19-game-news-records-more-reference.png`: 경기 상세 박스스코어, 하단 `홈/경기/기록/뉴스/더보기` 탭, 기록 CTA를 한 화면에서 맞춘 생성 레퍼런스

## Decisions Applied

- 큰 장식 hero보다 얇은 야구 이미지 스트립과 데이터 카드 조합을 유지한다.
- 순위 화면은 표만 비워두지 않고 `1위 경쟁`, `마이팀`, `연승`을 먼저 요약한다.
- 순위 데이터가 빈 배열일 때는 헤더만 남기지 않고 이미지 기반 empty state와 재확인 CTA를 보여준다.
- 온보딩 모바일 팀 그리드는 390x844에서 CTA와 붙어 보이지 않도록 팀 카드와 hero strip 높이를 줄인다.
- 경기 상세 탭은 pill container보다 얇은 underline 탭을 우선하고, 박스스코어는 큰 카드 대신 `오늘 기록 요약`, 핵심 선수 record row, 타자/투수 dense row, `선수 기록 보기` CTA로 정리한다.
- 하단 탭은 `홈 / 경기 / 기록 / 뉴스 / 더보기` 5개를 유지하고 선택 상태만 compact 원형 accent로 표시한다.
