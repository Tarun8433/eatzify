import 'package:get/get.dart';

/// The tabs of the one client shell. docs/14 §1.
///
/// Adding a value here requires an ADR. That rule exists because the previous build shipped four
/// different bottom navigation bars plus a hamburger menu duplicating most of them.
enum ClientTab { home, plan, progress, you }

/// The coach shell, same binary, role-gated. docs/14 §1.
enum CoachTab { clients, checkIns, messages, you }

/// Holds which tab is selected. Deliberately the only thing it does — navigation state is not a
/// place for business logic (CLAUDE.md rule 2).
class NavController extends GetxController {
  final selected = ClientTab.home.obs;

  ClientTab get current => selected.value;

  set current(ClientTab tab) => selected.value = tab;

  /// The centre `+` button is not a tab. It opens the log sheet and never changes the selected destination,
  /// which is why it is absent from ClientTab.
  int indexOf(ClientTab tab) => ClientTab.values.indexOf(tab);
}
