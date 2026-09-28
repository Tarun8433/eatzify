import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_pro/core/format/time_of_day_text.dart';
import 'package:health_pro/core/format/weight_units.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/carousel_picker.dart';
import 'package:health_pro/core/widgets/ruler_slider.dart';
import 'package:health_pro/core/widgets/wheel_picker.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The three input controls shared by onboarding and the You tab's edit sheets.
///
/// They started private inside `onboarding_page.dart`. The edit sheets need exactly the same
/// controls — a profile edit must accept a value the same way onboarding did, or the two drift and
/// one of them starts allowing what the other rejects (D-72).

/// A numeric field that validates when the user is FINISHED, not on every keystroke.
///
/// Validating per character means typing "72" is judged at "7" and the user is told their weight is
/// out of range while they are still typing it. Ranges are checked on blur or submit; the value is
/// cleared as they type so a stale reject never lingers.
class NumberField extends StatefulWidget {
  const NumberField({
    required this.label,
    required this.onLiveChange,
    required this.onCommit,
    super.key,
    this.decimal = false,
    this.helperText,
    this.icon,
    this.initial = '',
    this.picker,
    this.pickerWhy,
    this.pickerNote,
    this.pickerHint,
  });

  /// Pre-fills the field. Empty for onboarding, the stored value when editing — an edit sheet that
  /// opens blank invites the user to retype what was already correct, or to leave it blank and
  /// wonder what happened to it.
  final String initial;

  final String label;
  final bool decimal;
  final String? helperText;

  /// Drawn in a tinted circle at the leading edge. See [FieldIcon].
  final IconData? icon;

  /// When set, the field grows a button that opens a wheel in a bottom sheet (D-95). Null leaves
  /// it a plain typed field — a medicine count has no sensible range to scroll through.
  final NumberPickerConfig? picker;

  /// One sentence on why the app asks — shown on the picker sheet in a [HintCard] under the
  /// wheel. Null hides the card; a field whose purpose is obvious does not need to defend itself.
  final String? pickerWhy;

  /// A second note under the why-card — "you can update this later from your profile". Rendered
  /// as its own [HintCard] with the progress-chart glyph.
  final String? pickerNote;

  /// A suggestion computed WHEN THE SHEET OPENS, not when the field is built — the target
  /// weight's healthy band depends on the height entered moments earlier on the same step, and a
  /// string captured at build time would read a height that was not there yet. Returning null
  /// draws nothing.
  final String? Function()? pickerHint;

  /// Fires on every keystroke. Records a valid value without complaining about an incomplete one.
  final ValueChanged<String> onLiveChange;

  /// Fires on blur or submit. This is where a rejection is allowed to appear.
  final ValueChanged<String> onCommit;

  @override
  State<NumberField> createState() => NumberFieldState();
}

class NumberFieldState extends State<NumberField> {
  late final _controller = TextEditingController(text: widget.initial);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit(_controller.text);
    });
    // The unit is only drawn once there is a number for it to belong to (D-107), so the field has
    // to repaint when the text goes from empty to not. Reserving those 14 pt while the field is
    // still empty is what cut "Height (cm)" to "Height …".
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Writes a wheel's choice into the field, then reports it exactly as typing would.
  ///
  /// Going through the same `onLiveChange`/`onCommit` pair is the point: the picker cannot choose
  /// a value the keyboard would have been refused, and the caller has one path to validate.
  void _take(num value, {required bool commit}) {
    final text = WheelPicker.formatValue(value);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onLiveChange(text);
    if (commit) widget.onCommit(text);
  }

  Future<void> _openPicker(NumberPickerConfig config) async {
    // The keyboard and the sheet compete for the bottom of the screen, and the keyboard wins by
    // default — leaving the wheel behind it.
    FocusScope.of(context).unfocus();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Without this the sheet is capped at 9/16 of the screen, and a wheel plus a button does not
      // fit: Done was laid out past the bottom edge, so a tap aimed at it hit the barrier and
      // dismissed the sheet instead of choosing anything. Invisible, because dismissing looks the
      // same as cancelling.
      isScrollControlled: true,
      builder: (_) => _PickerSheet(
        title: widget.label,
        config: config,
        icon: widget.icon,
        why: widget.pickerWhy,
        note: widget.pickerNote,
        hint: widget.pickerHint?.call(),
        value: num.tryParse(_controller.text),
        onChanged: (v) => _take(v, commit: false),
      ),
    );

    // On close, not on every notch: a rejection while the wheel is still moving would flash a
    // message the next notch withdraws.
    if (mounted) widget.onCommit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final picker = widget.picker;

    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(widget.decimal ? '[0-9.]' : '[0-9]')),
      ],
      decoration: InputDecoration(
        // A HINT, not a non-floating label (D-107). Material hides a non-floating label as soon as
        // the field takes focus, so the reference's "Age" placeholder vanished the instant it was
        // tapped and the user was left typing into an unlabelled box. A hint survives focus and
        // still names the field for a screen reader.
        labelText: widget.icon == null ? widget.label : null,
        hintText: widget.icon == null ? null : widget.label,
        prefixIcon: FieldIcon.maybe(widget.icon),
        // docs/03 §2 ranges, shown up front rather than only as a rejection after the fact.
        helperText: widget.helperText,
        // Only beside a value. Empty, the hint needs the whole width; "165" without "cm" is the
        // thing that would be ambiguous, and by then the hint has gone anyway.
        suffixText: _controller.text.isEmpty ? null : picker?.suffix,
        suffixIcon: picker == null
            ? null
            : IconButton(
                // A chevron, not `unfold_more` (D-106): with the label sitting flat the field
                // reads as a thing that opens, and the reference draws that as a caret down.
                icon: const Icon(Icons.keyboard_arrow_down),
                // Icon-only, so it needs a name a screen reader can read out (rule 12).
                tooltip: l.pickerOpen(widget.label),
                onPressed: () => _openPicker(picker),
              ),
      ),
      onChanged: widget.onLiveChange,
      onSubmitted: widget.onCommit,
      onEditingComplete: () => widget.onCommit(_controller.text),
    );
  }
}

/// Turns a [NumberField] into a field you can either TYPE into or SCROLL to (D-95).
///
/// The wheels were inline and each one cost five rows of screen, so the basics step ran past the
/// fold with four of them on it. As a field plus a sheet the same four take four lines, and the
/// typed path comes back — a wheel is quick for 26 and slow for 92, and nothing about scrolling
/// beats typing a number you already know.
class NumberPickerConfig {
  const NumberPickerConfig({
    required this.min,
    required this.max,
    this.step = 1,
    this.suffix,
    this.feetInches = false,
    this.horizontal = false,
    this.ruler = false,
    this.kgPounds = false,
    this.caption,
    this.flag,
    this.opensAt,
  });

  /// Draws the sheet's picker as the reference's weight ruler — a horizontal [RulerSlider] in a
  /// recessed track with the reading in a chip over its centre. Wins over [horizontal].
  final bool ruler;

  /// Adds a kg ⇄ lb toggle to the sheet's header. Display-only, like [feetInches]: the ruler
  /// shows pounds but the field, the controller and the wire stay in kilograms (docs/09 §4).
  final bool kgPounds;

  /// The label flying over a ruler's chip — "Selected weight". Null draws no flag.
  final String? flag;

  /// Where the picker opens when nothing has been chosen yet. Null falls back to [midpoint];
  /// set it where the middle of the legal range is not a plausible first answer — the age range
  /// runs to 99, and opening on 59 suggested the app expects a 59-year-old.
  final num? opensAt;

  final num min;
  final num max;

  /// Lays the sheet's picker on its side — the reference's age carousel — instead of the
  /// vertical wheel. See [CarouselPicker].
  final bool horizontal;

  /// The unit written as words under a horizontal picker's chip — "Years old". The vertical
  /// wheel's [suffix] sits beside the number instead.
  final String? caption;

  /// Adds a cm ⇄ ft & in toggle to the sheet. Display-only: the wheel shows 5'7" but the field,
  /// the controller and the wire all stay in centimetres — docs/03 §2 types height_cm as an int,
  /// and a second stored unit is a second source of truth.
  final bool feetInches;

  /// Distance between neighbours ON THE WHEEL only. A typed value is not snapped to it: someone
  /// who weighs 70.3 kg is not made to say 70.5 because the wheel cannot show a third decimal.
  final num step;

  final String? suffix;

  /// Where the wheel opens when nothing has been chosen. The middle of the range, which is what
  /// [WheelPicker] does with a null value — kept in step with it so the highlighted number and the
  /// one Done commits are never different.
  num get midpoint {
    final steps = ((max - min) / step / 2).round();
    return min + steps * step;
  }
}

/// The sheet itself: a named header, one wheel, an optional why-card, and a Done button.
///
/// Changes are committed live, as the inline wheel did, so the number behind the sheet is always
/// the number under the lane. Done closes; there is no Cancel, because there is nothing to undo
/// that re-scrolling cannot.
class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.config,
    required this.value,
    required this.onChanged,
    this.icon,
    this.why,
    this.note,
    this.hint,
  });

  final String title;
  final NumberPickerConfig config;
  final num? value;
  final ValueChanged<num> onChanged;

  /// The field's own disc, repeated on the sheet so it visibly belongs to the field that opened
  /// it — four sheets that all open as a bare title read as the same sheet four times.
  final IconData? icon;

  /// See [NumberField.pickerWhy].
  final String? why;

  /// See [NumberField.pickerNote].
  final String? note;

  /// See [NumberField.pickerHint] — already evaluated by the time the sheet is built.
  final String? hint;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late num _current = widget.value ?? widget.config.opensAt ?? widget.config.midpoint;

  /// Whether the wheel is showing feet-and-inches. [_current] stays in the config's own unit
  /// either way — this only changes what the wheel prints and by how much a notch moves.
  bool _imperial = false;

  /// What a ruler sheet is reading in. Same rule as [_imperial]: display only, kilograms stored.
  WeightUnit _unit = WeightUnit.kg;

  /// Bumped to remount the wheel centred on a restored value. The wheel's scroll controller is
  /// created once with its initial row, so it cannot be re-aimed from outside; a new key can.
  int _wheelEpoch = 0;

  /// Puts the wheel back on the value the sheet opened with — the undo for a scroll taken too
  /// far, matching the reference's "Use previous height" action.
  void _restorePrevious() {
    final previous = widget.value;
    if (previous == null) return;
    setState(() {
      _current = previous;
      _wheelEpoch++;
    });
    widget.onChanged(previous);
  }

  static const _cmPerInch = 2.54;

  int get _minInches => (widget.config.min / _cmPerInch).ceil();
  int get _maxInches => (widget.config.max / _cmPerInch).floor();

  static String _feetInchesLabel(num inches) => "${inches ~/ 12}'${(inches % 12).toInt()}\"";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return SafeArea(
      // Scrollable as well as scroll-controlled: at 200 % font scale the wheel's five rows alone
      // are taller than a short phone, and a Done button you cannot reach is worse than a sheet
      // you have to scroll (rule 12).
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.icon != null) FieldIcon(widget.icon!),
                if (widget.icon != null) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      // The same string the opener button speaks (pickerOpen), doing subtitle
                      // duty — one key, one translation, no drift between the two.
                      Text(
                        l.pickerOpen(widget.title),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // The reference puts the weight units in the header's corner, where the height
                // sheet centres its toggle under the header — each per its own mock.
                if (widget.config.kgPounds)
                  _UnitToggle(
                    leftLabel: l.pickerUnitKg,
                    rightLabel: l.pickerUnitLb,
                    isRight: _unit == WeightUnit.lb,
                    onChanged: (right) =>
                        setState(() => _unit = right ? WeightUnit.lb : WeightUnit.kg),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.config.feetInches) ...[
              Center(
                child: _UnitToggle(
                  leftLabel: l.pickerUnitCm,
                  rightLabel: l.pickerUnitFtIn,
                  isRight: _imperial,
                  onChanged: (right) => setState(() => _imperial = right),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (widget.config.ruler)
              _RulerPicker(
                config: widget.config,
                unit: _unit,
                title: widget.title,
                valueKg: _current.toDouble(),
                onChangedKg: (kg) {
                  setState(() => _current = kg);
                  widget.onChanged(kg);
                },
              )
            else if (widget.config.horizontal)
              CarouselPicker(
                key: ValueKey('carousel-$_wheelEpoch'),
                min: widget.config.min,
                max: widget.config.max,
                step: widget.config.step,
                caption: widget.config.caption,
                value: _current,
                onChanged: (v) {
                  setState(() => _current = v);
                  widget.onChanged(v);
                },
              )
            else if (_imperial)
              WheelPicker(
                // Keyed per unit: the wheel's scroll controller is created once, so the same
                // widget re-ranged from 120..220 to 48..86 would open on the wrong row.
                key: ValueKey('imperial-$_wheelEpoch'),
                min: _minInches,
                max: _maxInches,
                format: _feetInchesLabel,
                value: (_current / _cmPerInch).round().clamp(_minInches, _maxInches),
                onChanged: (inches) {
                  final cm = (inches * _cmPerInch).round().clamp(
                    widget.config.min,
                    widget.config.max,
                  );
                  setState(() => _current = cm);
                  widget.onChanged(cm);
                },
              )
            else
              WheelPicker(
                key: ValueKey('metric-$_wheelEpoch'),
                min: widget.config.min,
                max: widget.config.max,
                step: widget.config.step,
                suffix: widget.config.suffix,
                // `_current`, not `widget.value`: with nothing chosen yet the wheel must
                // highlight the number Done would commit, or the sheet shows one value and
                // returns another.
                value: _current,
                onChanged: (v) {
                  setState(() => _current = v);
                  widget.onChanged(v);
                },
              ),
            if (widget.hint != null) ...[
              const SizedBox(height: AppSpacing.md),
              // The lightbulb the step's own healthy-weight note uses — a suggestion, not a rule.
              HintCard(icon: Icons.lightbulb_outline, text: widget.hint!),
            ],
            if (widget.why != null) ...[
              const SizedBox(height: AppSpacing.md),
              HintCard(
                icon: Icons.verified_user_outlined,
                title: l.pickerWhyTitle,
                text: widget.why!,
              ),
            ],
            if (widget.note != null) ...[
              const SizedBox(height: AppSpacing.sm),
              HintCard(icon: Icons.show_chart, title: l.pickerTrackTitle, text: widget.note!),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () {
                // Commits even if the wheel was never scrolled, so opening the sheet and pressing
                // Done chooses what is visibly centred rather than nothing at all.
                widget.onChanged(_current);
                Navigator.of(context).pop();
              },
              child: Text(l.pickerDone),
            ),
            // Only once there IS a previous value: on a first fill the row would restore to
            // nothing, and a dead action under the primary button is worse than no action.
            if (widget.value != null) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                onPressed: _restorePrevious,
                icon: const Icon(Icons.refresh, size: AppSpacing.lg),
                label: Text(
                  l.pickerUsePrevious(
                    '${WheelPicker.formatValue(widget.value!)}'
                    '${widget.config.suffix == null ? '' : ' ${widget.config.suffix}'}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The reference's unit pill, shared by the height and weight sheets: the chosen unit is a
/// filled primary capsule, the other rides the sheet's own surface. Material's default paints
/// the selection in `secondaryContainer` — beige here — which read as disabled.
class _UnitToggle extends StatelessWidget {
  const _UnitToggle({
    required this.leftLabel,
    required this.rightLabel,
    required this.isRight,
    required this.onChanged,
  });

  final String leftLabel;
  final String rightLabel;
  final bool isRight;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: false, label: Text(leftLabel)),
        ButtonSegment(value: true, label: Text(rightLabel)),
      ],
      selected: {isRight},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        // Rule 12: the default segment height is under the 48 dp floor.
        minimumSize: const WidgetStatePropertyAll(Size(0, AppSpacing.minTouchTarget)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? theme.colorScheme.primary
              : theme.colorScheme.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
        ),
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
      ),
    );
  }
}

/// The reference's weight picker: a "Selected weight" flag over a recessed track holding a
/// [RulerSlider], the reading in a tinted chip over the ruler's fixed centre marker, and a
/// chevron stepper at each end.
///
/// The value is HELD in kilograms and only read in [unit] — same contract as the height sheet's
/// feet and inches, for the same reason: the wire takes kg and nothing else (docs/09 §4).
class _RulerPicker extends StatelessWidget {
  const _RulerPicker({
    required this.config,
    required this.unit,
    required this.title,
    required this.valueKg,
    required this.onChangedKg,
  });

  final NumberPickerConfig config;
  final WeightUnit unit;
  final String title;
  final double valueKg;
  final ValueChanged<double> onChangedKg;

  /// Ring on the track's baseline under the chip — the same handle the vertical wheel draws.
  static const _ring = 18.0;
  static const _ringStroke = 3.0;

  /// Whole numbers at the shown unit's bounds: the ruler's labels sit on its majors, and a range
  /// starting at 66.1 lb would put "67" half a pound away from where 67 actually is.
  double get _shownMin => unit == WeightUnit.kg
      ? config.min.toDouble()
      : unit.fromKg(config.min.toDouble()).ceilToDouble();
  double get _shownMax => unit == WeightUnit.kg
      ? config.max.toDouble()
      : unit.fromKg(config.max.toDouble()).floorToDouble();
  double get _step => config.step.toDouble();

  void _change(double shown) {
    // Read in the shown unit, stored to a tenth of a kilogram — the precision the field and the
    // wire already speak (docs/03 §2).
    final kg = (unit.toKg(shown) * 10).roundToDouble() / 10;
    onChangedKg(kg.clamp(config.min.toDouble(), config.max.toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final shown = unit.fromKg(valueKg);

    return Column(
      children: [
        if (config.flag != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              config.flag!,
              style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimary),
            ),
          ),
          // The flag's tail, aiming at the chip below it.
          ExcludeSemantics(
            child: Icon(Icons.arrow_drop_down, size: AppSpacing.lg, color: scheme.primary),
          ),
        ],
        Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            // The page's own colour, so the track reads as recessed into the white sheet — the
            // same treatment as the carousel's track.
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              StepCircleButton(
                icon: Icons.chevron_left,
                label: l.pickerPrev,
                onTap: () => _change((shown - _step).clamp(_shownMin, _shownMax)),
              ),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RulerSlider(
                      value: shown,
                      min: _shownMin,
                      max: _shownMax,
                      // The unit's own tenth, NOT config.step: the ruler's 7 pt tick gap is
                      // tuned for it — at half-unit notches a whole unit is 14 pt and every
                      // label lands on its neighbour. Ten minors per major, like the reference.
                      step: unit.notch,
                      majorEvery: (1 / unit.notch).round(),
                      // "70.0", the way the reference writes a weight (docs/14: one decimal).
                      labelDigits: 1,
                      semanticLabel: title,
                      onChanged: _change,
                    ),
                    // The reading, riding the ruler's fixed centre marker. Pointer-transparent,
                    // so the drag underneath still lands.
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(AppRadius.tile),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                textBaseline: TextBaseline.alphabetic,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                children: [
                                  Text(
                                    shown.toStringAsFixed(1),
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(unit.label, style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, size: AppSpacing.lg, color: scheme.primary),
                            Container(
                              height: _ring,
                              width: _ring,
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: scheme.primary, width: _ringStroke),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              StepCircleButton(
                icon: Icons.chevron_right,
                label: l.pickerNext,
                onTap: () => _change((shown + _step).clamp(_shownMin, _shownMax)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Free text. Used for a name, a medicine list and food dislikes — none of which we parse.
///
/// Deliberately unvalidated beyond a length cap: "Metformin 500 twice daily, and vitamin D in
/// winter" is more use to a coach than anything a form could have forced it into.
class FreeTextField extends StatefulWidget {
  const FreeTextField({
    required this.label,
    required this.onChanged,
    super.key,
    this.helperText,
    this.icon,
    this.maxLength = 500,
    this.maxLines = 1,
    this.initial = '',
  });

  /// Pre-fills the field — see [NumberField.initial].
  final String initial;

  final String label;
  final String? helperText;

  /// Drawn in a tinted circle at the leading edge. See [FieldIcon].
  final IconData? icon;

  final int maxLength;
  final int maxLines;
  final ValueChanged<String> onChanged;

  @override
  State<FreeTextField> createState() => FreeTextFieldState();
}

class FreeTextFieldState extends State<FreeTextField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLength: widget.maxLength,
    maxLines: widget.maxLines,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(
      // See NumberField: a hint rather than a label, so it is still there once the field is
      // focused, with the helper line under the field carrying the explanation.
      labelText: widget.icon == null ? widget.label : null,
      hintText: widget.icon == null ? null : widget.label,
      prefixIcon: FieldIcon.maybe(widget.icon, extraLines: widget.maxLines - 1),
      helperText: widget.helperText,
      counterText: '',
    ),
    onChanged: widget.onChanged,
  );
}

/// The tinted circle at the leading edge of a field (D-106).
///
/// The same disc `ChoiceTile` puts on an option, for the same reason: it is decoration, never
/// meaning — the label carries that, and it is excluded from semantics so a screen reader is not
/// read a decorative glyph before every field. What it buys is a column of answers that can be
/// told apart without reading all of them.
class FieldIcon extends StatelessWidget {
  const FieldIcon(this.icon, {super.key, this.extraLines = 0});

  final IconData icon;

  /// How many lines BEYOND the first the field can grow to (D-111).
  ///
  /// `InputDecorator` centres a prefix over the whole field and offers no way to align it
  /// otherwise — `Align` inside the prefix does nothing, because the box it is aligning in is the
  /// one being centred. On the three-line medicines box that left the disc floating in the middle
  /// of an empty area with the placeholder above it, belonging to nothing.
  ///
  /// So the box is made TALLER by the lines the field can grow, and the centring then puts the
  /// disc back on the first one. `xl` is one line of `body` at its 1.45 line height, near enough.
  final int extraLines;

  /// Null in, null out — so a field can pass its optional icon straight to `prefixIcon`.
  static Widget? maybe(IconData? icon, {int extraLines = 0}) =>
      icon == null ? null : FieldIcon(icon, extraLines: extraLines);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      // A prefix stretches to the field's height, so the disc is centred in a box rather than
      // sized by one — at 200 % font scale a fixed-height prefix would clip the text beside it.
      child: Padding(
        // Equal on both sides, and it has to be set HERE (D-108): `InputDecorator` drops
        // `contentPadding.left` entirely when a prefix is present, so the gap between the disc and
        // the text is whatever this padding leaves — it was 4 pt against the border and 4 pt plus
        // the glyph's own bearing against the text, which reads as a disc shoved into the corner.
        padding: EdgeInsets.only(
          left: AppSpacing.sm,
          right: AppSpacing.sm,
          bottom: AppSpacing.xl * extraLines,
        ),
        child: Center(
          widthFactor: 1,
          child: Container(
            // Smaller than the disc on an option row: two of these fields share a phone's width
            // with a picker button each, and at `ringSmall` the label between them was cut to
            // "Heig…" — the exact defect D-104 caught on the same screen.
            height: AppSpacing.xxl,
            width: AppSpacing.xxl,
            decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: AppSpacing.lg, color: scheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }
}

/// A time of day, picked rather than typed. Stores "HH:MM" — see OnboardingSubmission for why a
/// time of day is not a DateTime.
class TimeField extends StatelessWidget {
  const TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.fallback,
    super.key,
    this.icon,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;

  /// Turns the field into a ROW (D-109): a tinted disc, the question above the answer, and a
  /// chevron. Used wherever a time is an answer to read back rather than text waiting to be
  /// entered — which, since D-113, is every time the app asks for one. The bare-field branch below
  /// is what a form with a dozen of them would need, and no screen has a dozen.
  final IconData? icon;

  /// Where the picker opens when nothing is stored yet — a plausible time for THIS field.
  ///
  /// Opening at `TimeOfDay.now()` meant tapping breakfast at 9:57 pm and pressing OK recorded
  /// "breakfast 21:56", which looks like the app misunderstood rather than like the user's slip.
  final TimeOfDay fallback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Displayed in the phone's own 12/24-hour format, so it reads back the way the clock the user
    // just picked from showed it. The stored value stays 24-hour "HH:MM" — see TimeOfDayText.
    final display = TimeOfDayText.formatWire(context, value);
    final glyph = icon;

    if (glyph != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: ValueRow(
          icon: glyph,
          label: label,
          value: display ?? l.onboardingTimeNotSet,
          muted: display == null,
          onTap: () => _pick(context),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InputDecorator(
          // Shape, fill and padding all come from `inputDecorationTheme` now (D-106), including
          // the 48 dp touch target (rule 12) the vertical padding used to set by hand.
          decoration: InputDecoration(labelText: label),
          child: Text(
            display ?? l.onboardingTimeNotSet,
            style: display == null
                ? theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)
                : theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDayText.parse(value) ?? fallback,
    );
    if (picked == null) return;
    onChanged(TimeOfDayText.toWire(picked));
  }
}

/// A card that reads as a question already answered (D-109): a tinted disc, the label small above,
/// the value large below, and a chevron saying it can be changed.
///
/// Not an `InputDecorator`. A stored time is not text being entered — it is a decision the user has
/// already made, and putting it at body size behind a field's floating label made the screen look
/// like a form waiting to be filled rather than a summary of what was said.
class ValueRow extends StatelessWidget {
  const ValueRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
    this.muted = false,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Nothing chosen yet, so [value] is a placeholder rather than an answer.
  final bool muted;

  /// A step down in value size, for a value that is a list rather than a word — four meal times
  /// at titleLarge wrap into a two-line billboard on a phone.
  final bool dense;

  /// Null where the row is an answer being read back rather than one being set — the summary step
  /// (D-114). `AppCard` already draws an untappable card; without this the recap would have to
  /// reimplement the row to avoid a press animation that leads nowhere.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              height: AppSizes.ringSmall,
              width: AppSizes.ringSmall,
              decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: AppSpacing.xl, color: scheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  value,
                  // titleLarge, down from headlineMedium: at 28 pt every answer row was a
                  // billboard — the summary's meal times wrapped to two lines and four rows
                  // filled the screen. The reference sets the value a step above body, bold,
                  // and lets the row stay a row.
                  style: (dense ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: muted ? scheme.onSurfaceVariant : scheme.primary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // No chevron where there is nothing to tap: it is the mark that says "this opens", and
          // drawing it on a row that does not is the same lie as a dead back arrow (D-109).
          if (onTap != null)
            ExcludeSemantics(child: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
