import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_design_system.dart';

/// A content-sized state with a clear way forward, including at large text sizes.
class AppStatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryAction;

  const AppStatusCard({
    super.key,
    this.icon = Icons.wifi_off_rounded,
    required this.title,
    required this.description,
    this.actionLabel = '다시 시도',
    required this.onAction,
    this.actionKey,
    this.secondaryLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return AppSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 28, color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                height: 1.3,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: actionKey,
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
              if (secondaryLabel != null && onSecondaryAction != null)
                TextButton(
                  onPressed: onSecondaryAction,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(secondaryLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
