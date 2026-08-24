import 'package:health_pro/core/errors/failures.dart';

/// The four states every data screen must implement. docs/14 §3, CLAUDE.md rule 6.
///
/// Modelled explicitly so state is never inferred from a null. Exhaustive `switch` on this sealed
/// type is what makes "no infinite spinners" a compile-time property rather than a code review note.
sealed class ViewState<T> {
  const ViewState();
}

class Loading<T> extends ViewState<T> {
  const Loading();
}

class Empty<T> extends ViewState<T> {
  const Empty();
}

class Failed<T> extends ViewState<T> {
  const Failed(this.failure);

  final Failure failure;
}

class Ready<T> extends ViewState<T> {
  const Ready(this.data);

  final T data;
}
