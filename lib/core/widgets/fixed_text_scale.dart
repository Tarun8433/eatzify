import 'package:flutter/widgets.dart';

/// Makes the app look the same on every phone (D-247, D-259).
///
/// - **Text** is drawn at the design size, whatever the phone's own font-size setting says.
/// - **Layout** is drawn at the design width — an iPhone 15 Pro's 393 points — and scaled to fit
///   the screen. Android's "Display size" setting (turned up by default on some OnePlus phones)
///   shrinks the width the app is given, which zoomed every screen in and squeezed narrow rows
///   until their text wrapped a letter at a time. Scaling the whole picture means every phone shows
///   the iPhone's layout, just larger or smaller.
///
/// Tablets and anything wider than a phone are left alone: blowing a phone layout up to 10 inches
/// would be worse than the problem. One widget at the app root, so the choice lives in one place
/// and is one line to undo.
class FixedTextScale extends StatelessWidget {
  const FixedTextScale({required this.child, super.key});

  final Widget child;

  /// The width every screen is designed and checked at (the user's own reference iPhone).
  static const designWidth = 393.0;

  /// Wider than this is a tablet or a foldable opened out; it keeps its real width.
  static const maxPhoneWidth = 600.0;

  @override
  Widget build(BuildContext context) {
    final real = MediaQuery.of(context);
    final locked = real.copyWith(textScaler: TextScaler.noScaling);
    final width = real.size.width;
    if (width <= 0 || width >= maxPhoneWidth || width == designWidth) {
      return MediaQuery(data: locked, child: child);
    }

    final scale = width / designWidth;
    final design = locked.copyWith(
      size: real.size / scale,
      devicePixelRatio: real.devicePixelRatio * scale,
      padding: real.padding / scale,
      viewPadding: real.viewPadding / scale,
      viewInsets: real.viewInsets / scale,
      systemGestureInsets: real.systemGestureInsets / scale,
    );

    return MediaQuery(
      data: design,
      child: SizedBox.expand(
        child: FittedBox(
          // Same aspect ratio in and out, so `fill` scales evenly and never stretches.
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: design.size, child: child),
        ),
      ),
    );
  }
}
