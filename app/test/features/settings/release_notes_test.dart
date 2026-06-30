import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/features/settings/release_notes.dart';

void main() {
  test('release notes parser keeps version subtitles and user notes', () {
    final releases = parseReleaseNotes('''
# 업데이트 소식

## 0.1.8+75 - 라이브 경기 알림

- 알림을 더 안정적으로 받을 수 있습니다.
- 경기 상세을 더 빠르게 최신 상태로 맞춥니다.

## 0.1.7+74 - 화면 흐름 정리

- 설정 화면을 정리했습니다.
''');

    expect(releases, hasLength(2));
    expect(releases.first.version, '0.1.8+75');
    expect(releases.first.subtitle, '라이브 경기 알림');
    expect(releases.first.notes.first, '알림을 더 안정적으로 받을 수 있습니다.');
  });

  test('installed release matching prefers exact version and build', () {
    const releases = [
      ReleaseNote(version: '0.1.8+75', subtitle: '현재 빌드', notes: ['현재 버전입니다.']),
      ReleaseNote(version: '0.1.8', subtitle: '버전 단위 노트', notes: ['버전 노트입니다.']),
    ];

    expect(findInstalledReleaseNote(releases, '0.1.8+75')?.subtitle, '현재 빌드');
    expect(
      findInstalledReleaseNote(releases, '0.1.8+76')?.subtitle,
      '버전 단위 노트',
    );
  });
}
