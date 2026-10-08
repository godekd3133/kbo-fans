# 문서 관리

## 원본과 게시본

Wiki Markdown 원본은 앱 저장소의 `docs/wiki/`에 저장합니다. GitHub Wiki는 별도 Git 저장소 `kbo-fans.wiki.git`에 게시합니다. 원본을 검토한 후 같은 파일을 Wiki 저장소에 반영합니다. `Home.md`는 시작 화면, `_Sidebar.md`는 탐색, `_Footer.md`는 하단 안내입니다.

이번 Wiki는 소스·명세를 읽기 쉽게 요약한 진입점입니다. 상세 계약을 중복 작성하기보다 실제 repository 문서·source에 연결합니다. 수작업으로 관리하며 자동 동기화 workflow는 없습니다.

## 변경할 문서

| 변경 | 함께 확인할 문서 |
| --- | --- |
| UX·화면·API | `docs/APP_SPEC.md`, `docs/WORKLOG.md`, 해당 Wiki 페이지 |
| 실행·운영·저장소 구조 | `README.md`, 관련 runbook, 해당 Wiki 페이지 |
| 사용자 기능·release | `CHANGELOG.md`, 버전 문서와 앱 내 업데이트 소식 |
| 디자인 | `docs/FIGMA_PROMPT.md`, 디자인 산출물과 캡처 |
| 반복되는 작업 | 적용 `.claude/skills/`, 기존 정책과의 호환 검토 |

새로운 작업 정책은 이번 문서화만으로 승인된 것으로 간주하지 않습니다. `AGENTS.md` 변경 제안은 근거와 호환 영향을 정리해 사용자 검토를 받습니다.

## Wiki 게시 순서

저장소 루트에서 원본을 수정하고 링크·명령을 확인한 뒤 docs만 커밋·push합니다. 앱·backend의 관련 없는 미커밋 변경은 보존합니다. Wiki 저장소를 clone할 별도 경로를 정합니다.

```bash
git clone git@github-personal:godekd3133/kbo-fans.wiki.git /tmp/kbo-fans-wiki
cp docs/wiki/*.md /tmp/kbo-fans-wiki/
git -C /tmp/kbo-fans-wiki diff --check
git -C /tmp/kbo-fans-wiki add '*.md'
git -C /tmp/kbo-fans-wiki commit -m 'Wiki 문서 갱신'
git -C /tmp/kbo-fans-wiki push origin HEAD
```

기존 clone이 있으면 먼저 최신 원격 변경을 확인해 pull하고 diff를 검토합니다. 원격 사용자가 수정한 페이지를 확인 없이 덮어쓰지 않습니다. GitHub 웹에서 바로 수정한 경우 그 결과를 `docs/wiki/`에도 반영합니다.

## 게시 후 확인

Home 목차와 sidebar, 상대 Wiki 링크, 저장소 source 링크, 코드 block을 확인합니다. push 성공 후 원격 SHA를 비교하고 clone한 게시본과 원본 파일을 대조합니다. 기록에는 확인 날짜·기준 SHA·검증 범위를 남기고 실제 실행하지 않은 배포나 단말 검증은 완료로 적지 않습니다.

## 상세 문서와 소스

- [문서 동기화 스킬](https://github.com/godekd3133/kbo-fans/blob/main/.claude/skills/kbo-doc-sync/SKILL.md)
- [작업 정책](https://github.com/godekd3133/kbo-fans/blob/main/AGENTS.md)
- [작업 이력](https://github.com/godekd3133/kbo-fans/blob/main/docs/WORKLOG.md)
