import 'package:flutter/widgets.dart';

/// Draws everything below it at the design text size, whatever the phone's own font-size setting
/// says (D-247). One widget at the app root, so the choice lives in one place and is one line to
/// undo — swap it for `MediaQuery.withClampedTextScaling` if the decision is reversed.
class FixedTextScale extends StatelessWidget {
  const FixedTextScale({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
    child: child,
  );
}
