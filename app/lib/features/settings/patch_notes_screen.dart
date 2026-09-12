import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_design_system.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import 'release_notes.dart';

typedef PatchNotesLoader = Future<ReleaseNotesData> Function();

class PatchNotesScreen extends StatefulWidget {
  final PatchNotesLoader? loadNotes;

  const PatchNotesScreen({super.key, this.loadNotes});

  @override
  State<PatchNotesScreen> createState() => _PatchNotesScreenState();
}

class _PatchNotesScreenState extends State<PatchNotesScreen> {
  static const _visibleReleaseCount = 12;

  late final Future<ReleaseNotesData> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadNotes?.call() ?? _loadPatchNotes();
  }

  Future<ReleaseNotesData> _loadPatchNotes() =>
      loadReleaseNotes(limit: _visibleReleaseCount);

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    void goBack() {
      if (router?.canPop() == true) {
        router!.pop();
      } else if (router != null) {
        router.go('/settings');
      } else {
        Navigator.of(context).maybePop();
      }
    }

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: AppPageHeader(
                  eyebrow: 'KBO Fans',
                  title: '업데이트 소식',
                  subtitle: '최근에 바뀐 경기 확인과 기록 기능을 한눈에 봅니다.',
                  onBack: goBack,
                ),
              ),
              Expanded(
                child: FutureBuilder<ReleaseNotesData>(
                  future: _future,
                  builder: (context, snapshot) {
                    Widget child;
                    final colors = AppTheme.colorsOf(context);
                    if (snapshot.connectionState != ConnectionState.done) {
                      child = Center(
                        key: const ValueKey('patch-notes-loading'),
                        child: CircularProgressIndicator(color: colors.accent),
                      );
                      return AppMotionSwitcher(child: child);
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      child = _PatchNotesError(
                        key: const ValueKey('patch-notes-error'),
                      );
                      return AppMotionSwitcher(child: child);
                    }

                    final data = snapshot.data!;
                    if (data.releases.isEmpty) {
                      child = _PatchNotesError(
                        key: const ValueKey('patch-notes-empty'),
                      );
                      return AppMotionSwitcher(child: child);
                    }

                    child = ListView.separated(
                      key: const ValueKey('patch-notes-ready'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return AppMotionListItem(
                            index: 0,
                            child: _CurrentVersionBanner(
                              version: data.currentVersion,
                            ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentVersionBanner extends StatelessWidget {
  final String version;

  const _CurrentVersionBanner({required this.version});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('patch-notes-current-version-semantics'),
      container: true,
      label: '현재 설치한 버전 $version',
      child: ExcludeSemantics(
        child: Container(
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
        ),
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
    final colors = AppTheme.colorsOf(context);
    final semanticLabel = [
      '버전 ${release.version}',
      ?release.subtitle,
      if (isCurrent) '현재 설치됨',
      ...release.notes,
    ].join(', ');
    return Semantics(
      key: ValueKey('patch-notes-release-semantics-${release.version}'),
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCurrent ? colors.accent : colors.divider,
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
        ),
      ),
    );
  }
}

class _CurrentReleaseBadge extends StatelessWidget {
  const _CurrentReleaseBadge();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        '현재 설치됨',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: colors.accent,
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
    final colors = AppTheme.colorsOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 6, color: colors.accent),
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
