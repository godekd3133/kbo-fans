# 아키텍처

## 데이터의 흐름

```text
KBO 공식 소스
  → backend crawlers
  → services + 공용 런타임 캐시 + 검증된 스냅샷
  → FastAPI /api
  → Flutter API repositories
  → Riverpod providers
  → 화면 / 위젯 연동

sync worker
  → 스코어보드·경기 상세 워밍 / 스냅샷 저장
  → 경기 상태 변화 감지
  → FCM 일반 푸시 / APNs Live Activity
```

앱이 닫힌 이후의 서버 푸시와 Live Activity 갱신은 실행 중인 백엔드·worker가 담당합니다.

## 코드 위치

| 영역 | 위치와 역할 |
| --- | --- |
| 앱 시작·환경 | `app/lib/main.dart`, `core/config/app_config.dart` |
| 탐색 | `core/router/app_router.dart`, `core/widgets/main_scaffold.dart` |
| 상태·소스 선택 | `app/lib/data/providers.dart` |
| API·캐시 | `app/lib/data/api/api_client.dart`, `data/repositories/api_*` |
| 도메인 모델 | `app/lib/data/models/` |
| 화면 | `app/lib/features/` |
| FastAPI 진입점 | `backend/src/kbo_fans_backend/main.py` |
| 라우팅·서비스 공유 | `api/router.py`, `api/routes/`, `api/runtime_services.py` |
| 공식 수집 | `crawlers/` |
| 도메인 처리·스냅샷 | `services/` |
| 환경 설정 | `core/config.py`, `backend/.env.example` |
| 푸시·정기 작업 | `push/`, `scheduler/` |

백엔드 API 형제 endpoint는 `runtime_services.py`의 서비스 singleton을 공유해 동일한 TTL 캐시를 사용합니다. API와 worker를 분리할 때는 `SNAPSHOT_DIR`과 push registry의 공유·영속 저장소 구성이 필요합니다.

## 변경할 때 확인할 범위

데이터 라우팅, 캐시, 스냅샷, 푸시, Live Activity, API 계약을 바꾸면 `app/`의 소비자와 `backend/`의 생산자를 함께 확인합니다. 운영 환경 변수, scheduler, 배포 입력과 release URL 영향까지 확인한 후 실제 변경 범위를 좁힙니다.

Python 최소 지원 버전은 3.9입니다. FastAPI/Pydantic 코드의 타입은 `Optional[...]`, `Union[...]` 등 호환 문법을 유지합니다.

## 상세 문서와 소스

- [Provider](https://github.com/godekd3133/kbo-fans/blob/main/app/lib/data/providers.dart)
- [FastAPI](https://github.com/godekd3133/kbo-fans/blob/main/backend/src/kbo_fans_backend/main.py)
- [공유 서비스](https://github.com/godekd3133/kbo-fans/blob/main/backend/src/kbo_fans_backend/api/runtime_services.py)
- [구현 노트](https://github.com/godekd3133/kbo-fans/blob/main/docs/ENGINEERING_NOTES.md)
