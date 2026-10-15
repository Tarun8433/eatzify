import 'package:flutter/material.dart';

/// Every bottom sheet in the app goes through here, never `showModalBottomSheet` directly.
///
/// Flutter's `useSafeArea` keeps a sheet off the status bar and notch but NOT off the bottom: on an
/// edge-to-edge Android the sheet's last button sat under the back / home / recents bar, out of
/// reach. The bottom inset is added here once, so no sheet has to remember it. (With the keyboard
/// up the inset is already zero, so a sheet that pads for the keyboard is not padded twice.)
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
  bool isDismissible = true,
  bool enableDrag = true,
  ShapeBorder? shape,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  showDragHandle: showDragHandle,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  shape: shape,
  builder: (sheet) => SafeArea(top: false, child: builder(sheet)),
);
