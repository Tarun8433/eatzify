import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';

/// A series as a line, drawn the way the Progress tab draws one.
///
/// **Lifted out of `progress_page.dart` rather than copied.** That chart was private and bound to
/// the `Measurement` entity, so the coach screens had no way to reuse it and grew a sparkline
/// instead — two chart languages in one app for the same kind of question. This takes plain
/// numbers, so both sides draw the same picture.
///
/// No axes, no grid, no labels: the line answers "which way is this going" and the figure beside
/// it answers "where is it now". Anything more belongs on a screen of its own.
class TrendChart extends StatelessWidget {
  const TrendChart({
    required this.values,
    super.key,
    this.color,
    this.height = AppSizes.chartHeight,
  });

  final List<double> values;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Two points make a line; one makes a dot that implies a trend it cannot support.
    if (values.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final ink = color ?? theme.colorScheme.primary;

    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    // A flat series would otherwise collapse to a zero-height axis and read as a bug rather than
    // as somebody holding steady.
    final pad = (high - low) < 1 ? 1.0 : (high - low) * 0.2;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: low - pad,
          maxY: high + pad,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i += 1) FlSpot(i.toDouble(), values[i])],
              isCurved: true,
              color: ink,
              dotData: const FlDotData(show: false),
              // The line grounded on a soft fill, exactly as the Progress tab grounds it.
              belowBarData: BarAreaData(show: true, color: ink.withValues(alpha: 0.08)),
            ),
          ],
        ),
      ),
    );
  }
}
