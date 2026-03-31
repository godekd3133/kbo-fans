---
name: kbo-doc-sync
description: Use when a KBO Fans task changes architecture, API behavior, UX flow, or recurring workflow and the related docs and context files must be kept in sync across AGENTS.md, CLAUDE.md, README.md, CHANGELOG.md, APP_SPEC.md, WORKLOG.md, and .claude/skills.
---

# KBO Doc Sync

## Goal

작업 결과가 코드에만 남고 문서가 뒤처지지 않게 만드는 동기화 스킬이다.

## Use This Skill When

- 화면 구조, UX 흐름, API 계약, 캐시 전략, 실행 방식이 바뀔 때
- 반복되는 작업 패턴이 생겨 `.claude/skills`로 승격할 가치가 있을 때
- AGENTS / CLAUDE / spec / worklog 사이에 내용 차이가 생길 가능성이 있을 때

## Sync Matrix

- UX / 화면 상태 / API 계약 변경
  - `docs/APP_SPEC.md`
  - `docs/WORKLOG.md`
- 실행 / 운영 / 구조 변경
  - `README.md`
- 사용자 체감 기능 / 마일스톤 변경
  - `CHANGELOG.md`
- 장기 작업 규칙 / 반복 워크플로우 변경
  - `AGENTS.md`
  - `CLAUDE.md`
  - `.claude/skills/*`
- 장기 인사이트 / 구현 패턴 축적
  - `docs/ENGINEERING_NOTES.md`

## Rules

1. 문서는 "무엇을 바꿨는지"보다 "앞으로 어떻게 일해야 하는지"가 남아야 한다.
2. `WORKLOG`에는 원인과 검증을 남긴다.
3. `CHANGELOG`에는 사용자 체감 결과만 남긴다.
4. 새로운 skill 을 만들면 AGENTS 와 CLAUDE 에서 해당 skill 또는 notes 위치를 찾을 수 있게 연결한다.
5. 실제로 하지 않은 Figma/MCP/배포 작업은 완료로 적지 않는다.

## Validation

- 변경 후 `git diff` 로 문서 범위가 과하거나 누락되지 않았는지 확인한다.
- 같은 내용이 `AGENTS.md`와 `CLAUDE.md`에서 서로 충돌하지 않는지 확인한다.
