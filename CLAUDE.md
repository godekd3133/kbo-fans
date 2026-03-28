# KBO Fans 프로젝트

## 프로젝트 개요
KBO 프로야구 팬을 위한 실시간 경기 정보 모바일 앱 (iOS/Android)

## 기술 스택
- **모바일**: Flutter + Dart
- **백엔드**: Python FastAPI (AWS 배포)
- **크롤링**: requests + BeautifulSoup (KBO 홈페이지)
- **상태관리**: Riverpod
- **네비게이션**: go_router
- **HTTP**: dio
- **인프라**: AWS (EC2/ECS + RDS PostgreSQL + ElastiCache Redis)
- **푸시**: Firebase Cloud Messaging

## 프로젝트 구조

```text
kbo_fans/
├── CLAUDE.md              # 이 파일
├── docs/
│   ├── PLANNING.md        # 서비스 기획서
│   ├── APP_SPEC.md        # 앱 상세 기획서 (화면별 + API 명세)
│   └── WORKLOG.md         # 작업 이력
├── design_docs.docx       # 수업 제출용 기획서
├── backend/               # Python FastAPI 서버 (예정)
└── app/                   # Flutter 앱 (예정)
```

## Git 설정
- **레포**: github.com/godekd3133/kbo-fans (Private)
- **SSH**: `github-personal` alias → `~/.ssh/andy` 키 → godekd3133 계정
- **remote**: `git@github-personal:godekd3133/kbo-fans.git`

## 작업 규칙
- 모든 작업 상황은 MD 파일로 기록한다
- 피처/작업 단위의 컨텍스트를 `docs/` 아래에 MD로 남긴다
- 작업 이력은 `docs/WORKLOG.md`에 누적한다
- 커밋은 한글로 작성한다

## 데이터 소스
- KBO 공식 홈페이지 (koreabaseball.com) 크롤링
- 경로 1: ASP.NET SSR 페이지 → GET + BeautifulSoup
- 경로 2: ASMX 내부 API → POST → JSON
- 상세 내용은 `docs/PLANNING.md` 참조

## MVP 기능 (Phase 1)
1. 실시간 스코어보드
2. 문자중계
3. 박스스코어
4. 푸시 알림
5. 마이팀 설정
6. 경기 일정 / 팀 순위
