import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// A food photograph, at any size, with its credit reachable (D-83).
///
/// One widget for every place a food picture appears. The credit is not optional: 229 of these
/// images are CC BY or CC BY-SA and both licences require the author to be named wherever the work
/// is shown, so the long-press is built in here rather than left to each caller to remember.
///
/// A missing photograph draws a placeholder of the SAME size, never an empty box — 14 of the 281
/// foods have no image, and a gap where a picture should be reads as a broken row.
class FoodImage extends StatelessWidget {
  const FoodImage({
    required this.url,
    required this.attribution,
    super.key,
    this.size = 48,
    this.height,
    this.radius = AppRadius.card,
  });

  final String? url;
  final String? attribution;

  /// Width. Also the height unless [height] says otherwise — most callers want a square.
  final double size;

  /// Height, when the picture is not square. A card wants a landscape crop; a list row does not.
  final double? height;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final drawnHeight = height ?? size;

    final placeholder = Container(
      width: size,
      height: drawnHeight,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.restaurant, size: size * 0.35, color: theme.colorScheme.onSurfaceVariant),
    );

    final image = url == null
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            // A user's own meal photo arrives on a signed link whose expiry changes on every load
            // (D-240); keyed on the path, it is fetched once rather than every time Home refreshes.
            cacheKey: url!.split('?').first,
            width: size,
            height: drawnHeight,
            fit: BoxFit.cover,
            // No spinner: a list of them flickering reads as broken, and the placeholder is the
            // same shape so nothing moves when the picture arrives.
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );

    return GestureDetector(
      onLongPress: attribution == null ? null : () => _showCredit(context),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: image),
    );
  }

  void _showCredit(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.foodImageCreditTitle),
        content: Text(l.foodImageCreditBody(attribution!)),
      ),
    );
  }
}
