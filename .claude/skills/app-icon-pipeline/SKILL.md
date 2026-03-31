# App Icon Pipeline

## Purpose
앱 아이콘 시안 생성, 변형 비교, 최종안 적용, iOS/Android 아이콘 리소스 갱신 작업용 워크플로우다.

## Source Of Truth
- 생성 스크립트: `scripts/generate_app_icons.py`
- 현재 적용 원본: `app/assets/branding/app_icon_source_1024.png`
- 비교 시안:
  - `app/assets/branding/app_icon_variant_sleek.svg`
  - `app/assets/branding/app_icon_variant_sport.svg`

## Rules
- 최종 적용은 1024 원본 하나를 기준으로 iOS/Android 리소스를 함께 갱신한다.
- 아이콘 논의 중에는 비교 시안 파일을 남겨도 되지만, 실제 적용본은 항상 `app_icon_source_1024.png` 기준으로 본다.
- 사용자가 확정하면 iOS `AppIcon.appiconset` 과 Android `mipmap-*` 를 같이 맞춘다.
- 아이콘 작업은 문서화보다 리소스 일관성이 우선이다. 필요 시 `docs/WORKLOG.md` 정도만 간단히 남긴다.

## Checklist
1. 시안 방향 결정
2. `scripts/generate_app_icons.py` 수정
3. 원본/비교용 PNG 생성
4. 최종안으로 `app_icon_source_1024.png` 덮기
5. iOS `AppIcon.appiconset` 전 사이즈 재생성
6. Android `mipmap-*` 전 사이즈 재생성
7. 실제 파일 존재 확인
