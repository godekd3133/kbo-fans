# Bootstrap Fallback Data

## Purpose
- 시즌별 `standings`
- 시즌별 `records_overview`

API가 완전히 실패해도 앱이 최소한의 과거 데이터와 리더보드를 보여주게 하기 위한 번들 스냅샷 생성/갱신 워크플로우다.

## When To Use
- 순위/기록실 요약이 API 없이도 보여야 할 때
- 시즌 범위를 확장할 때
- 스냅샷 JSON을 재생성해야 할 때

## Source Of Truth
- 생성 스크립트: `scripts/generate_bootstrap_snapshots.py`
- 앱 asset: `app/assets/bootstrap/standings.json`
- 앱 asset: `app/assets/bootstrap/records_overview.json`
- 앱 fallback 로더: `app/lib/data/bootstrap/bootstrap_repository.dart`

## Rules
- 수동으로 JSON을 편집하지 말고 먼저 생성 스크립트를 갱신하거나 재실행한다.
- 생성 스크립트는 live API를 시즌별로 반복 호출하지 않고 `backend/data/snapshots/`의 검증된 snapshot에서 번들 데이터를 만든다.
- fallback 범위는 `standings`, `records_overview` 로 제한한다.
- 현재 시즌 standings / records overview 는 `generatedAt` 기준 fresh snapshot만 fallback으로 사용하고, 검증되지 않은 과거 시즌은 빈 exact snapshot 으로 둔다.
- 팀 전체 선수 목록/엔트리 payload는 번들 스냅샷 대상으로 키우지 않는다.
- 시즌 선택 범위를 바꾸면 관련 UI 드롭다운도 같이 갱신한다.
- 작업 후 `README.md`, `docs/APP_SPEC.md`, `docs/WORKLOG.md` 반영 여부를 확인한다.

## Checklist
1. 로컬 백엔드가 떠 있는지 확인한다.
2. `python3 scripts/generate_bootstrap_snapshots.py` 실행
3. 생성된 asset 범위와 크기 확인
4. `ApiGameRepository.getStandings()`, `ApiPlayerRepository.getRecordsOverview()` fallback 경로 점검
5. `fvm flutter analyze --no-fatal-infos`
6. `cd backend && source .venv/bin/activate && pytest -q`
