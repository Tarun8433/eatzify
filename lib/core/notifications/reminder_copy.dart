import 'dart:ui';

import 'package:health_pro/data/repositories/reminder_repository_impl.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The phone's language, as the app would pick it: its own when the app speaks it, else English.
/// Read when reminders are scheduled, which may be in a background isolate with no widget tree.
AppLocalizations phoneLocalizations() {
  final language = PlatformDispatcher.instance.locale.languageCode;
  final supported = AppLocalizations.supportedLocales.any((l) => l.languageCode == language);
  return lookupAppLocalizations(Locale(supported ? language : 'en'));
}

/// The reminders' words (D-222). docs/05 §6: nothing here says what someone has not done.
ReminderCopy reminderCopy() {
  final l = phoneLocalizations();
  return (
    channel: l.reminderChannel,
    waterTitle: l.reminderWaterTitle,
    waterBody: l.reminderWaterBody,
    logGlass: l.reminderLogGlass,
    mealTitle: l.reminderMealTitle,
    mealBodies: {
      'breakfast': l.reminderBreakfastBody,
      'lunch': l.reminderLunchBody,
      'dinner': l.reminderDinnerBody,
    },
    dayEndTitle: l.reminderDayEndTitle,
    dayEndBody: l.reminderDayEndBody,
    workoutTitle: l.gymReminderTitle,
    workoutBody: l.gymReminderText,
  );
}
