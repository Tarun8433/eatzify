import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// One day of a week, the reference's chip: the LETTER inside the circle, a small green check
/// badge hung under a logged day, and today — when logged — a gold disc with a star. Not logged
/// stays a hollow circle: neutral, per docs/05 §6, never a red mark.
///
/// Shared by Home's streak card and Progress's consistency card (D-143), so the two week-rows
/// cannot drift apart.
class DayDot extends StatelessWidget {
  const DayDot({
    required this.date,
    required this.isLogged,
    required this.isToday,
    required this.locale,
    super.key,
  });

  final DateTime date;
  final bool isLogged;
  final bool isToday;
  final String locale;

  static const _size = 26.0;
  static const _badge = 12.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final letter = DateFormat.E(locale).format(date).characters.first;
    final isStarred = isToday && isLogged;

    return Semantics(
      label: isLogged ? l.homeStreakDayLogged(letter) : l.homeStreakDayNot(letter),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: _size,
              width: _size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isStarred ? AppColors.warning : scheme.surface,
                shape: BoxShape.circle,
                border: isStarred ? null : Border.all(color: scheme.outline),
              ),
              child: isStarred
                  ? Icon(Icons.star, size: _size * 0.6, color: scheme.surface)
                  : Text(
                      letter,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            // The badge overlaps the circle's foot; the box is always there so the dots align
            // whether or not a day earned its check.
            SizedBox(
              height: _badge,
              width: _badge,
              child: isLogged && !isStarred
                  ? Transform.translate(
                      offset: const Offset(0, -_badge / 2),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check, size: _badge * 0.75, color: scheme.surface),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
