/// Which shell this account gets. docs/10 §1 and CLAUDE.md rule 1.
///
/// The app has exactly two shells and adding a third needs an ADR. So this is NOT a copy of the
/// server's eight roles — it is the question the shell actually asks, which is "client tabs or
/// coach tabs", and every server role maps onto one of those answers.
///
/// **A role is not permission to see a client.** docs/10 §1 is explicit: "the level does not grant
/// access. The consent grant does." This type decides navigation and nothing else — anything that
/// reads it to decide whether a coach may see a person is reading the wrong thing, and the server
/// would refuse that read anyway.
enum SessionRole {
  /// The person whose data it is.
  client,

  /// A coach, of any level. The levels differ in what a grant MAY contain, not in which tabs they
  /// get, so the shell does not distinguish them.
  coach,

  /// Admin, support, partner organisation. These have no Flutter surface: doc 20 §3 puts admin in
  /// a separate web panel, and CLAUDE.md rule 1 lists only two shells. They land on the client
  /// shell with their own data, which is honest — they are also people with an account.
  other;

  /// The server's wire names (docs/10 §1), mapped to the shell they get.
  ///
  /// An unknown role is a CLIENT, not a coach. A server that starts sending a role this build has
  /// never heard of must not be able to hand somebody the coach tabs by accident.
  static SessionRole fromWire(Iterable<String> roles) {
    for (final role in roles) {
      switch (role.toLowerCase()) {
        case 'coach_l1':
        case 'coach_l2':
        case 'coach_l3':
        case 'affiliate partner':
        case 'verified coach':
        case 'coaching partner':
          return SessionRole.coach;
        case 'admin':
        case 'super_admin':
        case 'super admin':
        case 'support':
        case 'partner_org':
        case 'partner organisation':
          return SessionRole.other;
      }
    }
    return SessionRole.client;
  }
}
