# 위젯·문자중계·설정의 정보 배치 개선

## 목표와 필요

전체 사용자 흐름의 신뢰·편의·유용성·완성도를 높이는 목표를 이어간다. 이번 루프는 문자중계의 반복 점수/볼카운트, 설정의 중복 선택 설명, 위젯의 기호로 합친 정보를 대상으로 한다. 현재 타석과 읽을 중계가 더 빨리 보이고, 작은 위젯에서는 경기/상황을 독립 항목으로 읽어야 한다.

## 영향 범위

| 표면 | 범위 |
|---|---|
| Flutter | 현재 타석이 있으면 별도의 이닝표/팀 합계 요약을 반복하지 않음. 방송형 경기 상황의 B/S/O 한 세트만 유지하고 추가 카운트 카드/배지/미터를 제거. 타석이 없는 초기/실패 상태는 간결한 점수 요약 유지. 프리셋의 반복 제목/설명 제거 |
| iOS WidgetKit/ActivityKit | legacy payload 문자열을 받은 뒤 별도 Text 항목으로 배치. iOS 16+에서 가로 공간이 충분하면 HStack, 부족하면 VStack. iOS 15는 VStack. 접근성은 쉼표로 연결 |
| Android RemoteViews | slate 경기 행의 경기/점수와 상황을 별도 TextView로 배치. live/전체 count를 한 문장으로 중복 표시하지 않음 |
| backend | scoreboard, sync worker, ContentState, token register 흐름을 확인. API/push/Live Activity payload·scheduler·cache 변경 없음 |
| 인프라/릴리스 | 운영 배포·서명·TestFlight·secret 변경 없음. simulator용 extension 컴파일은 전달/실수신의 증거가 아님 |

## 계획 → 구현 → 검증

1. Dart widget/live activity service, native AppDelegate/AppGroup/target, Swift widget, Kotlin provider, backend scoreboard sync 경로를 확인한다.
2. 데이터 문자열 자체와 저장 키를 유지해 이전 저장값을 계속 읽고, 렌더링 경계에서 기호를 항목 배치로 전환한다.
3. 중계의 실제 상황·점수·선수·주자·마지막 플레이를 보존하며 반복 통계 표와 B/S/O 표현만 제거한다. 상세 통계는 기존 스코어/박스스코어 탭에서 확인한다.
4. 선택 동작/알림 권한/서비스 동기화의 회귀 테스트와 실제 Flutter 화면을 확인하고 native 컴파일을 별도로 검증한다.

## 구현 판단

- 같은 B/S/O가 방송형 상황 표시, compact badge, 세 개의 카드, meter에 반복돼 있었다. 방송형 표시 한 번으로 통합했다.
- 현재 타석 위의 전체 이닝표는 스코어 탭과 정보가 겹쳤다. 현재 타석이 있는 경우 생략하고 타석 없는 loading/fallback에서 팀·점수·이닝은 유지한다.
- 프리셋 선택 결과는 실제 토글에서 확인할 수 있으므로 "아래에서 하나씩 고르세요"와 선택 목록을 반복하는 문장을 제거했다. 알림 권한과 전달 조건의 중요한 안내는 유지한다.
- iOS inline widget은 시스템의 단일 줄 제약을 유지하고 구분 기호 없는 짧은 표현을 쓴다. 다른 widget/expanded Island/Live Activity의 메타데이터는 별도 항목으로 렌더한다.
- Android의 기존 summary 문자열은 유지하고 행의 새 context view에서 상황을 표시한다. 빈 행/context는 숨겨 불필요한 간격과 placeholder를 만들지 않는다.

## 증거 층과 한계

- 집중 Flutter 테스트: 70개 통과(중계, 설정, widget sync, Live Activity service).
- Flutter analysis: No issues found.
- iOS widget extension `xcodebuild -target KboFansWidget -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO`: BUILD SUCCEEDED. arm64/x86_64 compile 결과이며 실제 위젯 렌더·APNs 전달을 입증하지 않는다.
- Android 최초 offline compile은 Kotlin DSL plugin이 cache에 없어 실패했다. repository-declared plugin을 변경하지 않고 online dependency resolution으로 재검증한다.
- Simulator GUI 앱 접근은 현재 computer-use에서 불가하고 해당 Xcode 경로에 GUI bundle도 발견하지 못했다. simctl device inventory 자체는 확인했다. 다른 프로젝트의 실행 중인 Simulator는 사용하거나 종료하지 않았다.
- 전체 Flutter 검사, Android compile, 최신 웹 캡처의 최종 결과는 실행 결과대로 아래에 추가한다.

## 전체 목표의 남은 확인

네이티브 실제 화면, 위젯/알림 진입 후 복귀, real-device 전달과 접근성, 아직 남은 반복 문구/동적 metadata를 이어서 확인한다. 이 패킷의 Flutter/compile 결과만으로 전체 목표 완료를 판단하지 않는다.

## 2026-10-09 현재 환경 재검증

- 이전 /tmp 로그와 process handle이 현재 세션에 없음을 확인했다. 현재 결과는 artifact 폴더에 직접 기록했다.
- Flutter 전체 631개 통과, analysis No issues found.
- iOS Widget extension simulator SDK build 재실행: BUILD SUCCEEDED.
- Android는 기존 Java 8 대신 설치된 JDK 21을 이번 명령에만 지정해 Kotlin compile 성공. 199 tasks, BUILD SUCCESSFUL. global Java/프로젝트 plugin version은 변경하지 않았다.
- initial game link → onboarding → skip → 요청한 game/relay 복귀를 actual browser에서 확인했다. scoring filter와 결과 중심 preset의 실제 switch 상태 변화도 확인했다.
- PNG 저장에서 blank/wrong-area frame을 발견해 제외했다. 올바른 app surface를 캡처한 파일을 직접 다시 읽어 확인하고 exact bytes의 SHA-256도 확인했다. render-source lookup의 stale 표시와 실제 파일을 구분했다.
- 현재 source에는 경기 상황 한 세트, 선수/주자, 마지막 플레이와 대체 선수 정보, 필터를 유지한다. 반복 last-play paragraph도 제거했다.
- `artifacts/ux-native-relay-2026-10-08/current-verification.json`과 `review.html`을 함께 남겼다. actual native pixel/실기기 전달은 여전히 미검증으로 둔다.
