import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/weight_units.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/ruler_slider.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Log a weight. docs/09 §4: the server decides the diary day and whether the value is suspect.
abstract final class LogWeightSheet {
  /// Weight by default; any measurement kind with [kind] and [unit] (D-87). One sheet, because a
  /// waist reading is entered exactly the way a weight is and a second copy would drift.
  static Future<void> show(
    BuildContext context,
    ProgressController controller, {
    String kind = ProgressController.weightKind,
    String unit = 'kg',
    String? title,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // ponytail: the sheet scrolls, not the form - weight_log_tab.dart already scrolls around
    // LogWeightForm, and nesting two vertical scroll views would unbound the inner one.
    builder: (_) => SingleChildScrollView(
      child: LogWeightForm(controller: controller, kind: kind, unit: unit, title: title),
    ),
  );
}

/// The form itself, so the `+` sheet's weight tab is the same form rather than a second copy of it
/// (D-87): one place that knows the suspect rule, the server's message, and the reload.
class LogWeightForm extends StatefulWidget {
  const LogWeightForm({
    required this.controller,
    super.key,
    this.kind = ProgressController.weightKind,
    this.unit = 'kg',
    this.title,
    this.autofocus = true,
  });

  final ProgressController controller;
  final String kind;
  final String unit;
  final String? title;

  /// False inside a tab bar: a neighbouring tab is built before it is looked at, and a keyboard
  /// that opens on a tab the user swiped past is a bug rather than a shortcut.
  final bool autofocus;

  @override
  State<LogWeightForm> createState() => _LogWeightFormState();
}

class _LogWeightFormState extends State<LogWeightForm> {
  final _field = TextEditingController();
  bool _valid = false;

  /// Display only. The server's `weight` kind is bounded in kilograms and refuses anything else,
  /// so a pound reading is converted on the way out and never on the wire.
  WeightUnit _unit = WeightUnit.kg;

  /// When the reading was taken. Null is "now", and null is what is sent — a client that stamps
  /// every write with its own clock is a client whose readings drift with the phone's timezone.
  DateTime? _at;

  /// Where the ruler sits when the field is empty: the last weight the server has, because the
  /// next one is nearly always within a kilogram of it. The FIELD stays empty — a prefilled figure
  /// plus a Save button is a way to log a stale weight without noticing.
  late final double _anchor = _lastKnownKg();

  /// Where the ruler OPENS when nothing has been typed. Not a limit — the ruler runs the whole
  /// legal range; this is only which part of it is under the marker to begin with.
  late double _opensAt = _unit.fromKg(_anchor);

  double get _shown => double.tryParse(_field.text) ?? _opensAt;

  double _lastKnownKg() {
    final state = widget.controller.state.value;
    if (state is! Ready<MeasurementHistory>) return _defaultAnchorKg;
    final points = state.data.points;
    return points.isEmpty ? _defaultAnchorKg : points.last.value;
  }

  /// Only used when the app has never seen a weight — the middle of the adult range, so the ruler
  /// opens somewhere plausible rather than at zero.
  static const _defaultAnchorKg = 70.0;

  /// What the server will accept for a weight (docs/09 §4 bounds). The ruler spans all of it —
  /// a ruler that stops a few kilograms from where it opened cannot answer the question somebody
  /// came with, and every reading outside these is refused anyway.
  static const _minKg = 20.0;
  static const _maxKg = 300.0;

  bool get _isWeight => widget.kind == ProgressController.weightKind;

  void _setValue(double value) {
    // One decimal, because that is what a bathroom scale reads and what the field accepts.
    final text = value.toStringAsFixed(1);
    if (text == _field.text) return;
    _field.text = text;
    setState(() => _valid = true);
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final current = _at ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      // A weight cannot have been taken tomorrow, and a reading from before the app existed is a
      // typo rather than history.
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? current.hour,
      time?.minute ?? current.minute,
    );
    // Later than now means the phone's clock or the user's finger slipped; either way the server
    // would reject it, and refusing here is quieter than a round trip.
    setState(() => _at = picked.isAfter(now) ? now : picked);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final shown = double.tryParse(_field.text);
    if (shown == null) return;

    // Weight is the only kind with a unit choice; a waist in cm goes through unconverted.
    final value = _isWeight ? _unit.toKg(shown) : shown;

    final suspect = await widget.controller.recordKind(
      widget.kind,
      value,
      unit: widget.unit,
      at: _at,
    );
    if (!mounted) return;

    // A failure keeps the sheet open so the server's message stays visible next to the field.
    if (suspect == null && widget.controller.error.value != null) return;

    Navigator.of(context).pop();
    // docs/09 §4: is_suspect ⇒ confirm. The value is already saved, so this asks rather than blocks.
    if ((suspect ?? false) && mounted) await _confirmSuspect();
  }

  Future<void> _confirmSuspect() async {
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.progressSuspectTitle),
        content: Text(l.progressSuspectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.progressSuspectRedo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.progressSuspectKeep),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title ?? l.logWeightYour,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    // Weight is the only kind with two units anyone reads it in. A waist in
                    // inches is a different conversation, and the server takes cm.
                    if (_isWeight) _UnitToggle(unit: _unit, onChanged: _onUnitChanged),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _WeightField(
                  controller: _field,
                  autofocus: widget.autofocus,
                  suffix: _isWeight ? _unit.label : widget.unit,
                  hint: _opensAt.toStringAsFixed(1),
                  onChanged: _onTyped,
                ),
                const SizedBox(height: AppSpacing.sm),
                // The fine adjustment. Typing is still the fast path for a number read off a
                // scale; this is for the last two tenths.
                // Weight only. A waist in centimetres has its own bounds and its own habits, and
                // a ruler drawn to a weight's range would be the wrong ruler for it.
                if (_isWeight) ...[
                  RulerSlider(
                    value: _shown,
                    min: _unit.fromKg(_minKg),
                    max: _unit.fromKg(_maxKg),
                    semanticLabel: widget.title ?? l.logWeightYour,
                    onChanged: _setValue,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                HintCard(
                  icon: Icons.show_chart,
                  title: l.logWeightHintTitle,
                  text: l.logWeightHintBody,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _WhenRow(at: _at, onTap: _pickWhen),
          const SizedBox(height: AppSpacing.lg),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.controller.error.value != null) ...[
                  Text(
                    widget.controller.error.value!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                SizedBox(
                  height: AppSizes.primaryButton,
                  child: FilledButton.icon(
                    onPressed: _valid && !widget.controller.saving.value ? _save : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_isWeight ? l.logWeightSave : l.commonSave),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onTyped(String raw) => setState(() => _valid = double.tryParse(raw) != null);

  void _onUnitChanged(WeightUnit unit) {
    if (unit == _unit) return;
    final previous = _unit;
    final shown = double.tryParse(_field.text);
    setState(() {
      _unit = unit;
      // The reading does not change when the label does: 70.5 kg becomes 155.4 lb, not 70.5 lb.
      // The ruler's window travels with it, or the ticks would still be counting kilograms.
      _opensAt = unit.fromKg(previous.toKg(_opensAt));
      if (shown != null) _field.text = unit.fromKg(previous.toKg(shown)).toStringAsFixed(1);
    });
  }
}

/// kg or lb. Two buttons rather than a dropdown: with two options a menu is a tap to see what you
/// could already have read.
class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.unit, required this.onChanged});

  final WeightUnit unit;
  final ValueChanged<WeightUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Semantics(
      label: l.logWeightUnit,
      child: SegmentedButton<WeightUnit>(
        showSelectedIcon: false,
        segments: [
          for (final u in WeightUnit.values)
            ButtonSegment<WeightUnit>(value: u, label: Text(u.label)),
        ],
        selected: {unit},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// The figure itself. Large, centred, with the unit beside it — the one thing on the card the eye
/// should land on, and the one thing the user came here to change.
class _WeightField extends StatelessWidget {
  const _WeightField({
    required this.controller,
    required this.autofocus,
    required this.suffix,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool autofocus;
  final String suffix;

  /// Where the ruler is sitting, greyed. Not a value — an empty field with a "0.0" hint next to a
  /// ruler resting on 69 showed the reading twice and disagreed with itself.
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      autofocus: autofocus,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,1}'))],
      style: theme.textTheme.displayLarge?.copyWith(
        fontSize: AppSizes.inputFigure,
        color: theme.colorScheme.primary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.displayLarge?.copyWith(
          fontSize: AppSizes.inputFigure,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        suffixText: suffix,
        suffixStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

/// When the reading was taken. "Now" for the common case; a picker for the one anybody actually
/// needs it for — the weight they took this morning and are logging tonight.
class _WhenRow extends StatelessWidget {
  const _WhenRow({required this.at, required this.onTap});

  final DateTime? at;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final when = at;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              height: AppSizes.ringSmall,
              width: AppSizes.ringSmall,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_today_outlined,
                size: AppSpacing.lg,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              l.logWeightWhen,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            when == null
                ? l.logWeightNow
                : '${DateFormat.yMMMd(locale).format(when)} · ${DateFormat.jm(locale).format(when)}',
            style: theme.textTheme.bodySmall,
          ),
          Icon(Icons.chevron_right, size: AppSpacing.xl, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
