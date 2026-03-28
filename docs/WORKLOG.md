# 작업 이력 (Work Log)

---

## 2026-03-28: 프로젝트 초기 세팅 + 기획 완료

### 완료
- [x] Git 레포 생성 (godekd3133/kbo-fans, Private)
- [x] SSH 설정 (`github-personal` alias → `~/.ssh/andy` 키 → godekd3133)
- [x] `.gitignore` 작성
- [x] `CLAUDE.md` 프로젝트 컨텍스트 작성
- [x] `docs/PLANNING.md` 서비스 기획서 작성 (경쟁사 상세 분석 + 차별화 전략 포함)
- [x] `docs/APP_SPEC.md` 앱 상세 기획서 작성 (화면 6개 와이어프레임 + API 7개 명세)
- [x] `design_docs.docx` 수업 제출용 기획서 채움 (팀 정보, 기능 명세, 화면 목록, 패키지, 일정)
- [x] `docs/WORKLOG.md` 작업 이력 문서 생성

### 결정 사항
- **프레임워크**: Flutter + Dart (수업 필수 요구사항)
- **타겟 사용자**: 코어팬 + 라이트팬 모두
- **서비스 목표**: 앱스토어 출시
- **MVP 기능 4개**: 실시간 스코어보드, 문자중계, 박스스코어, 푸시 알림
- **백엔드 인프라**: AWS (EC2/ECS + RDS PostgreSQL + ElastiCache Redis)
- **상태관리**: Riverpod
- **라우팅**: go_router
- **HTTP**: dio

### 변경 이력
- React Native (Expo) → **Flutter (Dart)** 로 변경 (수업 요구사항)
- 인프라 미정 → **AWS** 로 확정
- 경쟁사 분석: 네이버 스포츠, SPORTS.i, 야구보구, ESPN 상세 분석 추가
- 차별화 전략 6가지 수립

### 파일 구조
```
kbo_fans/
├── CLAUDE.md
├── design_docs.docx
├── docs/
│   ├── PLANNING.md
│   ├── APP_SPEC.md
│   └── WORKLOG.md
```

### Figma
- 디자인 파일: https://www.figma.com/design/VZdeXTfwxJYBxy2xOJrl8c/Kbo-Fans
- Figma MCP 서버 연결 필요 (현재 미연결 상태)

### 다음 할 일
- [ ] Figma MCP 서버 연결 → 와이어프레임 직접 생성
- [ ] Flutter 프로젝트 셋업 (flutter create)
- [ ] 백엔드 프로젝트 구조 셋업 (FastAPI)
- [ ] 크롤링 프로토타입 (스코어보드 + 문자중계)
- [ ] 스코어보드 화면 구현
