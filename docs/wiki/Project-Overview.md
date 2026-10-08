# 프로젝트 개요

## 제품 목표

KBO Fans는 iOS와 Android의 KBO 팬을 위한 앱입니다. 내 팀 경기를 먼저 보여주고, 상세 중계·선수 기록·일정으로 이어지는 빠른 확인 경험을 지향합니다. Web은 로컬 확인과 빠른 화면 공유에도 사용합니다.

## 기술 스택

| 영역 | 구성 |
| --- | --- |
| 앱 | Flutter, Dart |
| 상태 관리 / 탐색 | Riverpod, go_router |
| HTTP | dio |
| 백엔드 | Python FastAPI, requests, BeautifulSoup |
| 일반 푸시 | Firebase Cloud Messaging |
| iOS 실시간 활동 | ActivityKit, APNs |
| 홈·잠금화면 위젯 | Flutter 연동과 플랫폼 네이티브 코드 |
| 운영 경로 | Lightsail native systemd; ECS/Fargate 확장 경로 |

백엔드는 화면 데이터, 공식 소스 수집, 스냅샷, 푸시, Live Activity 동기화를 담당하는 실제 런타임 구성요소입니다. 앱의 direct KBO 경로는 명시적인 파서 비교·디버깅용입니다.

## 구현 범위

스코어보드, 경기 상세의 스코어·중계·박스스코어·라인업, 일정, 순위, 팀·선수 기록실, 선수 비교와 지표 가이드, 데이터 브리핑, 알림함, 응원팀과 화면 모드 설정, 푸시·위젯 연동을 포함합니다. 소스에 기능이 존재한다는 사실과 실기기에서 전달·설치·실행이 검증됐다는 사실은 구분합니다.

## 저장소 구조

```text
app/          Flutter 앱, iOS·Android·Web 프로젝트
backend/      FastAPI, crawler, service, scheduler, push, tests
scripts/      플랫폼 실행, 스냅샷 생성, 배포·진단 진입점
infra/aws/    Lightsail, ECS/Fargate, CloudFormation 구성
docs/         제품 명세, 운영 가이드, 검증·작업 기록
docs/wiki/    GitHub Wiki 게시용 Markdown 원본
.claude/      프로젝트 맥락과 재사용 작업 스킬
```

## 상세 문서와 소스

- [제품 기획](https://github.com/godekd3133/kbo-fans/blob/main/docs/PLANNING.md)
- [프로젝트 맥락](https://github.com/godekd3133/kbo-fans/blob/main/CLAUDE.md)
