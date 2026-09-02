import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/account/profile_photo.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The greeting and photo control that head the You tab (D-59, restyled by D-144 to the Profile
/// mock: the avatar with its camera control, "Hi, {name}!", a warm line).
///
/// The walker and his stage stand beside it, shell-owned and un-clipped, exactly as on Home
/// (D-152). This widget is only what stands next to them.
class ProfileFrame extends StatelessWidget {
  const ProfileFrame({
    required this.name,
    required this.photoUrl,
    required this.onPhotoChanged,
    super.key,
  });

  /// The profile's name; null greets without one rather than inventing a placeholder.
  final String? name;

  final String? photoUrl;
  final Future<void> Function() onPhotoChanged;

  static const _avatar = 64.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final greeting = name == null || name!.trim().isEmpty ? l.accountHiThere : l.accountHi(name!);

    // The mock's row: avatar left, the words beside it — not stacked.
    return Row(
      children: [
        ProfilePhoto(photoUrl: photoUrl, onChanged: onPhotoChanged, diameter: _avatar),
        const SizedBox(width: AppSpacing.md),
        // Decoration, not a target: it must not take the taps meant for the list around it.
        Expanded(
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        greeting,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const ExcludeSemantics(
                      child: Icon(Icons.waving_hand, size: AppSpacing.lg, color: AppColors.warning),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l.homeStreakBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
