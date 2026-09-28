import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:shimmer/shimmer.dart';

Widget wrap(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('a skeleton sweeps', (tester) async {
    await tester.pumpWidget(wrap(const Skeleton(child: SkeletonBox())));
    await tester.pump();

    expect(find.byType(Shimmer), findsOneWidget);
  });

  /// "Reduce motion" is an accessibility request, not a preference. The blocks stay — the page
  /// still has to read as loading — and only the sweep goes.
  testWidgets('reduced motion keeps the blocks and drops the sweep', (tester) async {
    await tester.pumpWidget(wrap(const Skeleton(child: SkeletonBox()), reduceMotion: true));
    await tester.pump();

    expect(find.byType(Shimmer), findsNothing);
    expect(find.byType(SkeletonBox), findsOneWidget);
  });

  /// The `shimmer` package has been a dependency since the skeletons were specified (NFR-8) and
  /// was never imported, so every loading state was flat grey blocks.
  testWidgets('the shared loading view sweeps too', (tester) async {
    await tester.pumpWidget(wrap(const LoadingView()));
    await tester.pump();

    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNWidgets(3));
  });

  testWidgets('a skeleton box paints its own fill, so it reads without the sweep', (tester) async {
    await tester.pumpWidget(wrap(const SkeletonBox(width: 40, height: 10)));
    await tester.pump();

    final box = tester.widget<Container>(find.byType(Container));
    expect((box.decoration! as BoxDecoration).color, isNotNull);
  });
}
