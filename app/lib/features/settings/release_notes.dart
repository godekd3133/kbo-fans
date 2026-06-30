import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

const releaseNotesAssetPath = 'assets/bootstrap/patch_notes.md';

Future<ReleaseNotesData> loadReleaseNotes({int? limit}) async {
  final raw = await rootBundle.loadString(releaseNotesAssetPath);
  final releases = parseReleaseNotes(raw);
  final visibleReleases = limit == null
      ? releases
      : releases.take(limit).toList(growable: false);
  final currentVersion = await loadCurrentAppVersion(
    fallbackVersion: visibleReleases.isEmpty
        ? '확인 불가'
        : visibleReleases.first.version,
  );
  return ReleaseNotesData(
    currentVersion: currentVersion,
    releases: visibleReleases,
  );
}

Future<ReleaseNotesData> loadReleaseNotesFromBundle({
  required AssetBundle bundle,
  int? limit,
}) async {
  final raw = await bundle.loadString(releaseNotesAssetPath);
  final releases = parseReleaseNotes(raw);
  final visibleReleases = limit == null
      ? releases
      : releases.take(limit).toList(growable: false);
  final currentVersion = await loadCurrentAppVersion(
    fallbackVersion: visibleReleases.isEmpty
        ? '확인 불가'
        : visibleReleases.first.version,
  );
  return ReleaseNotesData(
    currentVersion: currentVersion,
    releases: visibleReleases,
  );
}

Future<String> loadCurrentAppVersion({required String fallbackVersion}) async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    if (packageInfo.version.isEmpty) {
      return fallbackVersion;
    }
    final buildNumber = packageInfo.buildNumber.trim();
    return buildNumber.isEmpty
        ? packageInfo.version
        : '${packageInfo.version}+$buildNumber';
  } catch (_) {
    return fallbackVersion;
  }
}

List<ReleaseNote> parseReleaseNotes(String raw) {
  final releases = <ReleaseNote>[];
  _ReleaseNoteDraft? current;

  void closeCurrent() {
    final draft = current;
    if (draft == null) {
      return;
    }
    releases.add(
      ReleaseNote(
        version: draft.version,
        subtitle: draft.subtitle,
        notes: List.unmodifiable(draft.notes),
      ),
    );
  }

  for (final line in raw.split('\n')) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('# ')) {
      continue;
    }
    if (text.startsWith('## ')) {
      closeCurrent();
      current = _ReleaseNoteDraft.fromHeading(text.substring(3).trim());
      continue;
    }
    if (current == null) {
      continue;
    }
    if (text.startsWith('- ')) {
      current.notes.add(text.substring(2).trim());
    } else {
      current.notes.add(text);
    }
  }
  closeCurrent();

  return releases;
}

ReleaseNote? findInstalledReleaseNote(
  Iterable<ReleaseNote> releases,
  String currentVersion,
) {
  if (currentVersion.isEmpty || currentVersion == '확인 불가') {
    return null;
  }
  for (final release in releases) {
    if (release.version == currentVersion) {
      return release;
    }
  }

  final currentBaseVersion = currentVersion.split('+').first;
  for (final release in releases) {
    if (!release.version.contains('+') &&
        release.version == currentBaseVersion) {
      return release;
    }
  }
  return null;
}

bool isCurrentReleaseVersion(ReleaseNote release, String currentVersion) {
  if (currentVersion == '확인 불가') {
    return false;
  }
  if (release.version == currentVersion) {
    return true;
  }
  final currentBaseVersion = currentVersion.split('+').first;
  final releaseBaseVersion = release.version.split('+').first;
  return releaseBaseVersion == currentBaseVersion;
}

class ReleaseNotesData {
  final String currentVersion;
  final List<ReleaseNote> releases;

  const ReleaseNotesData({
    required this.currentVersion,
    required this.releases,
  });
}

class ReleaseNote {
  final String version;
  final String? subtitle;
  final List<String> notes;

  const ReleaseNote({
    required this.version,
    required this.subtitle,
    required this.notes,
  });
}

class _ReleaseNoteDraft {
  static final _versionHeadingPattern = RegExp(
    r'^(?:버전\s+)?v?([0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?)\s*(?:[-–—]\s*(.+))?$',
  );

  final String version;
  final String? subtitle;
  final List<String> notes;

  _ReleaseNoteDraft({
    required this.version,
    required this.subtitle,
    required this.notes,
  });

  factory _ReleaseNoteDraft.fromHeading(String heading) {
    final match = _versionHeadingPattern.firstMatch(heading);
    if (match == null) {
      return _ReleaseNoteDraft(
        version: heading,
        subtitle: null,
        notes: <String>[],
      );
    }
    return _ReleaseNoteDraft(
      version: match.group(1)!,
      subtitle: match.group(2)?.trim(),
      notes: <String>[],
    );
  }
}
