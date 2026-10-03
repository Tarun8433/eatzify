import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/announcement.dart';
import 'package:health_pro/domain/repositories/announcements_repository.dart';

/// The team's announcements and important updates at the top of Home (admin panel plan, Phase C).
///
/// Quiet by design: nothing while loading, nothing on failure, nothing when there is nothing to
/// say — an announcement is never worth an error on the screen people open most. A critical one is
/// drawn in the warm container so it cannot be scrolled past unseen.
class AnnouncementsStrip extends StatefulWidget {
  const AnnouncementsStrip({super.key});

  @override
  State<AnnouncementsStrip> createState() => _AnnouncementsStripState();
}

class _AnnouncementsStripState extends State<AnnouncementsStrip> {
  List<Announcement> _items = const [];
  final _dismissed = <String>{};

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<AnnouncementsRepository>()) return;
    Get.find<AnnouncementsRepository>().active().then((result) {
      if (!mounted) return;
      result.fold((_) {}, (items) => setState(() => _items = items));
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where((a) => !_dismissed.contains(a.id)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final a in visible) ...[
          _Card(announcement: a, onClose: () => setState(() => _dismissed.add(a.id))),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.announcement, required this.onClose});

  final Announcement announcement;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final urgent = announcement.priority != AnnouncementPriority.normal;
    final background = announcement.priority == AnnouncementPriority.critical
        ? scheme.tertiaryContainer
        : scheme.secondaryContainer;
    final foreground = announcement.priority == AnnouncementPriority.critical
        ? scheme.onTertiaryContainer
        : scheme.onSecondaryContainer;

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Icon(
                urgent ? Icons.campaign_outlined : Icons.info_outline,
                color: foreground,
                size: AppSpacing.xl,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      announcement.body,
                      style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: Icon(Icons.close, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
