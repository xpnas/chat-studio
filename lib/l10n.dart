import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'l10n_catalog.dart';

/// App-owned translations. Chinese remains the default so existing installs
/// keep their current language; English can be selected in Profile settings.
class AppLocalizations {
  const AppLocalizations(this.locale);
  final Locale locale;

  static const delegate = _AppLocalizationsDelegate();
  static const supportedLocales = [Locale('zh', 'CN'), Locale('en')];

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('zh', 'CN'));

  bool get isEnglish => locale.languageCode == 'en';

  String t(String chinese) =>
      isEnglish ? (appEnglishCatalog[chinese] ?? chinese) : chinese;

  String format(String chinese, Map<String, Object?> values) {
    return t(chinese).replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final key = match[1]!;
      return values.containsKey(key) ? '${values[key]}' : match[0]!;
    });
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (item) => item.languageCode == locale.languageCode,
  );
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String chinese) => l10n.t(chinese);
}
