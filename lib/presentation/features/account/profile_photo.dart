import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';

/// Profile photo with tap-to-change. Not in any doc — added on request.
///
/// docs/13: a face photo is personal data. It is optional, removable, and never logged. The image
/// is downscaled and compressed on device before upload, so a 12 MP camera shot does not become a
/// 5 MB request on a phone plan the user is paying for.
class ProfilePhoto extends StatefulWidget {
  const ProfilePhoto({
    required this.photoUrl,
    required this.onChanged,
    super.key,
    this.diameter = AppSizes.avatar,
  });

  final String? photoUrl;
  final Future<void> Function() onChanged;

  /// Sized by the caller. Inside the profile frame it is the small edit affordance beside the
  /// figure, not a second portrait of the same person (D-60); never below
  /// [AppSpacing.minTouchTarget], which rule 12 makes the floor.
  final double diameter;

  @override
  State<ProfilePhoto> createState() => _ProfilePhotoState();
}

class _ProfilePhotoState extends State<ProfilePhoto> {
  static const _maxDimension = 800.0;
  static const _quality = 85;

  bool _busy = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      imageQuality: _quality,
    );
    if (picked == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await Get.find<ProfileRepository>().uploadPhoto(picked.path, picked.name);

    if (!mounted) return;
    await result.fold(
      (failure) async => setState(() {
        _busy = false;
        // Rule 7: the server's own message.
        _error = failure.userMessage;
      }),
      (_) async {
        await widget.onChanged();
        if (mounted) setState(() => _busy = false);
      },
    );
  }

  Future<void> _remove() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await Get.find<ProfileRepository>().removePhoto();

    if (!mounted) return;
    await result.fold(
      (failure) async => setState(() {
        _busy = false;
        _error = failure.userMessage;
      }),
      (_) async {
        await widget.onChanged();
        if (mounted) setState(() => _busy = false);
      },
    );
  }

  void _showOptions() {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l.accountPhotoTakePhoto),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.accountPhotoChooseGallery),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(ImageSource.gallery);
              },
            ),
            if (widget.photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l.accountPhotoRemove),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _remove();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // D-145: the affordance is the camera badge on the avatar's corner (the Profile mock's own),
    // not a caption under it. The whole avatar is the button; the badge is decoration.
    const badge = 26.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // min, or the column takes ALL the height its row offers and top-pins the avatar — which
      // is exactly how the greeting ended up floating a hundred points below it (D-147).
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: l.accountPhotoChange,
          button: true,
          child: InkWell(
            onTap: _busy ? null : _showOptions,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: widget.diameter,
              height: widget.diameter,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: _busy
                        ? const Center(child: CircularProgressIndicator())
                        : CircleAvatar(
                            radius: widget.diameter / 2,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            child: widget.photoUrl == null
                                ? Icon(
                                    Icons.person_outline,
                                    size: AppSpacing.xxl,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )
                                : ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: widget.photoUrl!,
                                      width: widget.diameter,
                                      height: widget.diameter,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => const Icon(Icons.person_outline),
                                    ),
                                  ),
                          ),
                  ),
                  Positioned(
                    right: -AppSpacing.xs / 2,
                    bottom: -AppSpacing.xs / 2,
                    child: ExcludeSemantics(
                      child: Container(
                        height: badge,
                        width: badge,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: AppElevation.card(theme.brightness),
                        ),
                        child: Icon(
                          Icons.photo_camera_outlined,
                          size: AppSpacing.lg,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}
