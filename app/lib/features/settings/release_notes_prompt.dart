import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import 'release_notes.dart';

const releaseNotesSeenVersionPrefsKey = 'release_notes.seen_version';
typedef CurrentVersionLoader = Future<String> Function();
typedef ReleaseNotesLoader = Future<ReleaseNotesData> Function();

Future<void> showReleaseNotesPromptIfNeeded(
  BuildContext context, {
  GoRouter? router,
  CurrentVersionLoader? currentVersionLoader,
  ReleaseNotesLoader? releaseNotesLoader,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final currentVersion = currentVersionLoader != null
      ? await currentVersionLoader()
      : await loadCurrentAppVersion(fallbackVersion: '');
  if (currentVersion.isEmpty ||
      prefs.getString(releaseNotesSeenVersionPrefsKey) == currentVersion) {
    return;
  }

  final data = releaseNotesLoader != null
      ? await releaseNotesLoader()
      : await loadReleaseNotes();
  final release = findInstalledReleaseNote(data.releases, currentVersion);
  if (release == null || release.notes.isEmpty) {
    await prefs.setString(releaseNotesSeenVersionPrefsKey, currentVersion);
    return;
  }

  if (!context.mounted) {
    return;
  }
  final action = await showDialog<_ReleaseNotesPromptAction>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: true,
    builder: (_) => _ReleaseNotesPromptDialog(release: release),
  );
  await prefs.setString(releaseNotesSeenVersionPrefsKey, currentVersion);

  if (action == _ReleaseNotesPromptAction.openFullNotes) {
    if (!context.mounted) {
      return;
    }
    (router ?? GoRouter.of(context)).push('/release-notes');
  }
}

enum _ReleaseNotesPromptAction { close, openFullNotes }

class _ReleaseNotesPromptDialog extends StatelessWidget {
  final ReleaseNote release;

  const _ReleaseNotesPromptDialog({required this.release});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxNotesHeight = (media.size.height * 0.46).clamp(220.0, 430.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.live.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.live.withValues(alpha: 0.36),
                      ),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      size: 19,
                      color: AppColors.live,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '업데이트 소식',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '버전 ${release.version}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop(_ReleaseNotesPromptAction.close),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              if (release.subtitle != null) ...[
                const SizedBox(height: 12),
                Text(
                  release.subtitle!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.32,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxNotesHeight),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final note in release.notes) ...[
                        _ReleaseNoteBullet(note),
                        if (note != release.notes.last)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pop(_ReleaseNotesPromptAction.close),
                      child: const Text('닫기'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pop(_ReleaseNotesPromptAction.openFullNotes),
                      child: const Text('전체 보기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReleaseNoteBullet extends StatelessWidget {
  final String text;

  const _ReleaseNoteBullet(this.text);

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
              height: 1.42,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
