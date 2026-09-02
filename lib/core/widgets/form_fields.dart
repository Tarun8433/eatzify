import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_pro/core/format/time_of_day_text.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
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
  const NumberPickerConfig({required this.min, required this.max, this.step = 1, this.suffix});

  final num min;
  final num max;

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

/// The sheet itself: one wheel and a Done button.
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
  });

  final String title;
  final NumberPickerConfig config;
  final num? value;
  final ValueChanged<num> onChanged;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late num _current = widget.value ?? widget.config.midpoint;

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
            Text(widget.title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            WheelPicker(
              min: widget.config.min,
              max: widget.config.max,
              step: widget.config.step,
              suffix: widget.config.suffix,
              // `_current`, not `widget.value`: with nothing chosen yet the wheel must highlight
              // the number Done would commit, or the sheet shows one value and returns another.
              value: _current,
              onChanged: (v) {
                setState(() => _current = v);
                widget.onChanged(v);
              },
            ),
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
          ],
        ),
      ),
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
  });

  final IconData icon;
  final String label;
  final String value;

  /// Nothing chosen yet, so [value] is a placeholder rather than an answer.
  final bool muted;

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
                  style: theme.textTheme.headlineMedium?.copyWith(
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
