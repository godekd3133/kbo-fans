import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';

class PatchNotesScreen extends StatefulWidget {
  const PatchNotesScreen({super.key});

  @override
  State<PatchNotesScreen> createState() => _PatchNotesScreenState();
}

class _PatchNotesScreenState extends State<PatchNotesScreen> {
  static const _assetPath = 'assets/bootstrap/patch_notes.md';
  static const _visibleReleaseCount = 12;

  late final Future<_PatchNotesData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadPatchNotes();
  }

  Future<_PatchNotesData> _loadPatchNotes() async {
    final raw = await rootBundle.loadString(_assetPath);
    final releases = _parsePatchNotes(
      raw,
    ).take(_visibleReleaseCount).toList(growable: false);
    final currentVersion = await _loadCurrentVersion(
      fallbackVersion: releases.isEmpty ? '확인 불가' : releases.first.version,
    );
    return _PatchNotesData(currentVersion: currentVersion, releases: releases);
  }

  Future<String> _loadCurrentVersion({required String fallbackVersion}) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('업데이트 소식')),
      body: FutureBuilder<_PatchNotesData>(
        future: _future,
        builder: (context, snapshot) {
          Widget child;
          if (snapshot.connectionState != ConnectionState.done) {
            child = const Center(
              key: ValueKey('patch-notes-loading'),
              child: CircularProgressIndicator(color: AppColors.live),
            );
            return AppMotionSwitcher(child: child);
          }
          if (snapshot.hasError || !snapshot.hasData) {
            child = const _PatchNotesError(key: ValueKey('patch-notes-error'));
            return AppMotionSwitcher(child: child);
          }

          final data = snapshot.data!;
          if (data.releases.isEmpty) {
            child = const _PatchNotesError(key: ValueKey('patch-notes-empty'));
            return AppMotionSwitcher(child: child);
          }

          child = ListView.separated(
            key: const ValueKey('patch-notes-ready'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemBuilder: (context, index) {
              if (index == 0) {
                return AppMotionListItem(
                  index: 0,
                  child: _CurrentVersionBanner(version: data.currentVersion),
                );
              }

              final release = data.releases[index - 1];
              return AppMotionListItem(
                index: index,
                child: _ReleaseCard(
                  release: release,
                  isCurrent: _isCurrentRelease(release, data.currentVersion),
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemCount: data.releases.length + 1,
          );
          return AppMotionSwitcher(child: child);
        },
      ),
    );
  }
}

List<_PatchRelease> _parsePatchNotes(String raw) {
  final releases = <_PatchRelease>[];
  _PatchReleaseDraft? current;

  void closeCurrent() {
    final draft = current;
    if (draft == null) {
      return;
    }
    releases.add(
      _PatchRelease(
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
      current = _PatchReleaseDraft.fromHeading(text.substring(3).trim());
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

bool _isCurrentRelease(_PatchRelease release, String currentVersion) {
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

class _PatchNotesData {
  final String currentVersion;
  final List<_PatchRelease> releases;

  const _PatchNotesData({required this.currentVersion, required this.releases});
}

class _PatchRelease {
  final String version;
  final String? subtitle;
  final List<String> notes;

  const _PatchRelease({
    required this.version,
    required this.subtitle,
    required this.notes,
  });
}

class _PatchReleaseDraft {
  static final _versionHeadingPattern = RegExp(
    r'^(?:버전\s+)?v?([0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?)\s*(?:[-–—]\s*(.+))?$',
  );

  final String version;
  final String? subtitle;
  final List<String> notes;

  _PatchReleaseDraft({
    required this.version,
    required this.subtitle,
    required this.notes,
  });

  factory _PatchReleaseDraft.fromHeading(String heading) {
    final match = _versionHeadingPattern.firstMatch(heading);
    if (match == null) {
      return _PatchReleaseDraft(
        version: heading,
        subtitle: null,
        notes: <String>[],
      );
    }
    return _PatchReleaseDraft(
      version: match.group(1)!,
      subtitle: match.group(2)?.trim(),
      notes: <String>[],
    );
  }
}

class _CurrentVersionBanner extends StatelessWidget {
  final String version;

  const _CurrentVersionBanner({required this.version});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.system_update_alt,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '현재 설치한 버전',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            version,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final _PatchRelease release;
  final bool isCurrent;

  const _ReleaseCard({required this.release, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent ? AppColors.live : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '버전 ${release.version}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    if (release.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        release.subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 10),
                const _CurrentReleaseBadge(),
              ],
            ],
          ),
          const SizedBox(height: 14),
          for (final note in release.notes) ...[
            _PatchBullet(note),
            if (note != release.notes.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CurrentReleaseBadge extends StatelessWidget {
  const _CurrentReleaseBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.live.withValues(alpha: 0.5)),
      ),
      child: const Text(
        '현재 설치됨',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppColors.live,
        ),
      ),
    );
  }
}

class _PatchBullet extends StatelessWidget {
  final String text;

  const _PatchBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 6, color: AppColors.live),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.42,
            ),
          ),
        ),
      ],
    );
  }
}

class _PatchNotesError extends StatelessWidget {
  const _PatchNotesError({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '업데이트 소식을 불러올 수 없습니다',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
