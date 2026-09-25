/// A change to today's step count, as the `+` sheet takes it (D-220): "add 500", "remove 200".
///
/// The change is kept apart from what the phone counted (D-221): the server stores the day's
/// running addition as `steps_added` and adds it to the device's count, so a sync replacing that
/// count leaves the person's change on top. A write replaces the stored addition, so a change has
/// to become the day's new addition before it is sent — the same shape as a glass of water (D-86).
/// Pure and separate from the screen, because a sum that decides what is stored does not belong in
/// a widget.
abstract final class AdjustSteps {
  /// docs/03 §2: the most steps a day may hold. The server refuses anything above it.
  static const max = 100000;

  /// The most that can be added to, or removed from, [current] without leaving the range.
  static int limit({required int? current, required bool remove}) =>
      remove ? (current ?? 0) : max - (current ?? 0);

  /// The day's new total, or null when [amount] would take it outside the range.
  ///
  /// Nothing recorded yet counts as nothing to remove from, and as zero to add to.
  static int? total({required int? current, required int amount, required bool remove}) {
    if (amount < 0) return null;
    final next = (current ?? 0) + (remove ? -amount : amount);
    return next < 0 || next > max ? null : next;
  }

  /// What to store as the day's `steps_added`: the addition so far, [previous], moved by [amount].
  /// Only meaningful once [total] has accepted the same change.
  static int added({required int? previous, required int amount, required bool remove}) =>
      (previous ?? 0) + (remove ? -amount : amount);
}
