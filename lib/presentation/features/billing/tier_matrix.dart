import 'package:flutter/material.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// One cell of the comparison table: a tick, a cross, or a figure.
///
/// A figure rather than a tick wherever the tiers differ by AMOUNT — "2 a day" against "3 a day"
/// is the actual difference, and two ticks in a row that both mean yes would hide it.
typedef TierCell = ({bool included, String? figure});

/// One row: what it is called, the mark beside it, and what each tier gets.
typedef CompareRow = ({IconData icon, String label, Map<String, TierCell> byTier});

/// The BASIC/PRO comparison, mirroring `api/src/billing/tiers.ts` — **the entitlements the backend
/// actually enforces**, not a features list written for a sales page.
///
/// CLAUDE.md rule 3 keeps entitlement DECISIONS on the server, and they stay there: nothing here
/// gates anything, it only describes. But that makes this table a copy, and a copy goes stale —
/// `GET /billing/prices` returns the price matrix and could return this beside it, at which point
/// this function should read the response instead of restating it (D-160).
///
/// Every row is a key of `Entitlements` in that file. A row that is not one is a promise the
/// backend cannot keep, which is what the paywall in the old build shipped.
List<CompareRow> compareRows(AppLocalizations l) => [
  (
    icon: Icons.refresh,
    label: l.premiumFeatRegen,
    byTier: {
      'BASIC': (included: true, figure: l.premiumRegenPerDay(2)),
      'PRO': (included: true, figure: l.premiumRegenPerDay(3)),
    },
  ),
  (
    icon: Icons.history,
    label: l.premiumFeatHistory,
    byTier: {
      'BASIC': (included: true, figure: l.premiumHistoryDays(90)),
      // docs/11 §1 calls PRO "unlimited history"; the wire carries 36500 days, which is that
      // sentence spelled as a number and must not be shown as one.
      'PRO': (included: true, figure: l.premiumHistoryAll),
    },
  ),
  (
    icon: Icons.swap_horiz,
    label: l.premiumFeatAlternates,
    byTier: {'BASIC': (included: false, figure: null), 'PRO': (included: true, figure: null)},
  ),
  (
    icon: Icons.picture_as_pdf_outlined,
    label: l.premiumFeatExport,
    byTier: {'BASIC': (included: false, figure: null), 'PRO': (included: true, figure: null)},
  ),
  (
    icon: Icons.chat_bubble_outline,
    label: l.premiumFeatCoach,
    byTier: {'BASIC': (included: false, figure: null), 'PRO': (included: true, figure: null)},
  ),
  (
    icon: Icons.support_agent,
    label: l.premiumFeatSupport,
    byTier: {'BASIC': (included: false, figure: null), 'PRO': (included: true, figure: null)},
  ),
];
