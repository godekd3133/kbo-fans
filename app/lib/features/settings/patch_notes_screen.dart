import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import 'release_notes.dart';

class PatchNotesScreen extends StatefulWidget {
  const PatchNotesScreen({super.key});

  @override
  State<PatchNotesScreen> createState() => _PatchNotesScreenState();
}

class _PatchNotesScreenState extends State<PatchNotesScreen> {
  static const _visibleReleaseCount = 12;

  late final Future<ReleaseNotesData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadPatchNotes();
  }

  Future<ReleaseNotesData> _loadPatchNotes() =>
      loadReleaseNotes(limit: _visibleReleaseCount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('업데이트 소식')),
      body: FutureBuilder<ReleaseNotesData>(
        future: _future,
        builder: (context, snapshot) {
          Widget child;
          if (snapshot.connectionState != ConnectionState.done) {
            child = Center(
              key: const ValueKey('patch-notes-loading'),
              child: CircularProgressIndicator(color: AppColors.live),
            );
            return AppMotionSwitcher(child: child);
          }
          if (snapshot.hasError || !snapshot.hasData) {
            child = _PatchNotesError(key: const ValueKey('patch-notes-error'));
            return AppMotionSwitcher(child: child);
          }

          final data = snapshot.data!;
          if (data.releases.isEmpty) {
            child = _PatchNotesError(key: const ValueKey('patch-notes-empty'));
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
                  isCurrent: isCurrentReleaseVersion(
                    release,
                    data.currentVersion,
                  ),
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
          Icon(
            Icons.system_update_alt,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
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
            style: TextStyle(
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
  final ReleaseNote release;
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
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSupporting,
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
      child: Text(
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
        Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 6, color: AppColors.live),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '업데이트 소식을 불러올 수 없습니다',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
