// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:dr/app_state.dart';
import 'package:dr/app_subject_translation_controller.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class AppLocalizations {
  AppLocalizations._({
    required this.locale,
    required Map<String, String> translations,
  }) : _translations = translations;

  final Locale locale;
  final Map<String, String> _translations;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(localizations != null, 'AppLocalizations not found in context');
    return localizations!;
  }

  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('it'),
    Locale.fromSubtags(languageCode: 'de', countryCode: 'LLD'),
    Locale('en'),
  ];

  static const Map<String, Map<AppLanguage, String>> _subjectTranslations = {
    'Deutsch': {
      AppLanguage.en: 'German',
      AppLanguage.it: 'Tedesco',
      AppLanguage.lld: 'Todësch',
    },
    'Italienisch': {
      AppLanguage.en: 'Italian',
      AppLanguage.it: 'Italiano',
      AppLanguage.lld: 'Talian',
    },
    'Englisch': {
      AppLanguage.en: 'English',
      AppLanguage.it: 'Inglese',
      AppLanguage.lld: 'Ingles',
    },
    'Französisch': {
      AppLanguage.en: 'French',
      AppLanguage.it: 'Francese',
      AppLanguage.lld: 'Franzes',
    },
    'Spanisch': {
      AppLanguage.en: 'Spanish',
      AppLanguage.it: 'Spagnolo',
      AppLanguage.lld: 'Spagnol',
    },
    'Latein': {
      AppLanguage.en: 'Latin',
      AppLanguage.it: 'Latino',
      AppLanguage.lld: 'Latin',
    },
    'Ladinisch': {
      AppLanguage.en: 'Ladin',
      AppLanguage.it: 'Ladino',
      AppLanguage.lld: 'Ladin',
    },
    'Weitere Fremdsprachen': {
      AppLanguage.en: 'Other foreign languages',
      AppLanguage.it: 'Altre lingue straniere',
      AppLanguage.lld: 'Autres lingac forestes',
    },
    'Mathematik': {
      AppLanguage.en: 'Mathematics',
      AppLanguage.it: 'Matematica',
      AppLanguage.lld: 'Matematica',
    },
    'Informatik': {
      AppLanguage.en: 'Computer science',
      AppLanguage.it: 'Informatica',
      AppLanguage.lld: 'Informatica',
    },
    'Mathematik/Informatik': {
      AppLanguage.en: 'Mathematics/Computer science',
      AppLanguage.it: 'Matematica/Informatica',
      AppLanguage.lld: 'Matematica/Informatica',
    },
    'Mathematik / Informatik': {
      AppLanguage.en: 'Mathematics / Computer science',
      AppLanguage.it: 'Matematica / Informatica',
      AppLanguage.lld: 'Matematica / Informatica',
    },
    'Naturkunde': {
      AppLanguage.en: 'Natural science',
      AppLanguage.it: 'Scienze naturali',
      AppLanguage.lld: 'Scienzes naturèles',
    },
    'Naturwissenschaften': {
      AppLanguage.en: 'Natural sciences',
      AppLanguage.it: 'Scienze naturali',
      AppLanguage.lld: 'Scienzes naturèles',
    },
    'Biologie': {
      AppLanguage.en: 'Biology',
      AppLanguage.it: 'Biologia',
      AppLanguage.lld: 'Biologia',
    },
    'Chemie': {
      AppLanguage.en: 'Chemistry',
      AppLanguage.it: 'Chimica',
      AppLanguage.lld: 'Chimica',
    },
    'Physik': {
      AppLanguage.en: 'Physics',
      AppLanguage.it: 'Fisica',
      AppLanguage.lld: 'Fisica',
    },
    'Geschichte': {
      AppLanguage.en: 'History',
      AppLanguage.it: 'Storia',
      AppLanguage.lld: 'Storia',
    },
    'Geografie': {
      AppLanguage.en: 'Geography',
      AppLanguage.it: 'Geografia',
      AppLanguage.lld: 'Geografia',
    },
    'Politische Bildung': {
      AppLanguage.en: 'Civic education',
      AppLanguage.it: 'Educazione civica',
      AppLanguage.lld: 'Educazion zivica',
    },
    'Bürgerkunde': {
      AppLanguage.en: 'Civics',
      AppLanguage.it: 'Educazione civica',
      AppLanguage.lld: 'Educazion civica',
    },
    'Wirtschaft und Recht': {
      AppLanguage.en: 'Economics and law',
      AppLanguage.it: 'Economia e diritto',
      AppLanguage.lld: 'Economia y dërt',
    },
    'Recht und Wirtschaft': {
      AppLanguage.en: 'Law and economics',
      AppLanguage.it: 'Diritto ed economia',
      AppLanguage.lld: 'Dërt y economia',
    },
    'Wirtschaftskunde': {
      AppLanguage.en: 'Economics',
      AppLanguage.it: 'Economia',
      AppLanguage.lld: 'Economia',
    },
    'Sozialkunde': {
      AppLanguage.en: 'Social studies',
      AppLanguage.it: 'Scienze sociali',
      AppLanguage.lld: 'Scienzes soziales',
    },
    'Kunst': {
      AppLanguage.en: 'Art',
      AppLanguage.it: 'Arte',
      AppLanguage.lld: 'Arte',
    },
    'Bildnerisches Gestalten': {
      AppLanguage.en: 'Visual arts',
      AppLanguage.it: 'Arti visive',
      AppLanguage.lld: 'Arti visives',
    },
    'Musik': {
      AppLanguage.en: 'Music',
      AppLanguage.it: 'Musica',
      AppLanguage.lld: 'Musica',
    },
    'Grafik': {
      AppLanguage.en: 'Graphics',
      AppLanguage.it: 'Grafica',
      AppLanguage.lld: 'Grafica',
    },
    'Design': {
      AppLanguage.en: 'Design',
      AppLanguage.it: 'Design',
      AppLanguage.lld: 'Design',
    },
    'Mediengestaltung': {
      AppLanguage.en: 'Media design',
      AppLanguage.it: 'Design dei media',
      AppLanguage.lld: 'Design di media',
    },
    'Bewegung und Sport': {
      AppLanguage.en: 'Physical education and sport',
      AppLanguage.it: 'Educazione fisica e sport',
      AppLanguage.lld: 'Educazion fisica y sport',
    },
    'Leibeserziehung': {
      AppLanguage.en: 'Physical education',
      AppLanguage.it: 'Educazione fisica',
      AppLanguage.lld: 'Educazion fisica',
    },
    'Technik': {
      AppLanguage.en: 'Technology',
      AppLanguage.it: 'Tecnologia',
      AppLanguage.lld: 'Tecnologia',
    },
    'Technische Erziehung': {
      AppLanguage.en: 'Technical education',
      AppLanguage.it: 'Educazione tecnica',
      AppLanguage.lld: 'Educazion tecnica',
    },
    'Werken': {
      AppLanguage.en: 'Crafts',
      AppLanguage.it: 'Lavori manuali',
      AppLanguage.lld: 'Lëures manuels',
    },
    'Textverarbeitung': {
      AppLanguage.en: 'Word processing',
      AppLanguage.it: 'Elaborazione testi',
      AppLanguage.lld: 'Elaborazion de tesć',
    },
    'Digitale Kompetenzen': {
      AppLanguage.en: 'Digital skills',
      AppLanguage.it: 'Competenze digitali',
      AppLanguage.lld: 'Competënzes digitales',
    },
    'Religion': {
      AppLanguage.en: 'Religion',
      AppLanguage.it: 'Religione',
      AppLanguage.lld: 'Religiun',
    },
    'Ethik': {
      AppLanguage.en: 'Ethics',
      AppLanguage.it: 'Etica',
      AppLanguage.lld: 'Etica',
    },
    'Umweltbildung': {
      AppLanguage.en: 'Environmental education',
      AppLanguage.it: 'Educazione ambientale',
      AppLanguage.lld: 'Educazion ambientala',
    },
    'Gesundheitserziehung': {
      AppLanguage.en: 'Health education',
      AppLanguage.it: 'Educazione alla salute',
      AppLanguage.lld: 'Educazion ala sanité',
    },
    'Medienbildung': {
      AppLanguage.en: 'Media literacy',
      AppLanguage.it: 'Educazione ai media',
      AppLanguage.lld: 'Educazion ai media',
    },
    'Berufsorientierung': {
      AppLanguage.en: 'Career orientation',
      AppLanguage.it: 'Orientamento professionale',
      AppLanguage.lld: 'Orientament profescionel',
    },
    'Philosophie': {
      AppLanguage.en: 'Philosophy',
      AppLanguage.it: 'Filosofia',
      AppLanguage.lld: 'Filosofia',
    },
    'Psychologie': {
      AppLanguage.en: 'Psychology',
      AppLanguage.it: 'Psicologia',
      AppLanguage.lld: 'Psicologia',
    },
    'Pädagogik': {
      AppLanguage.en: 'Pedagogy',
      AppLanguage.it: 'Pedagogia',
      AppLanguage.lld: 'Pedagogia',
    },
    'Soziologie': {
      AppLanguage.en: 'Sociology',
      AppLanguage.it: 'Sociologia',
      AppLanguage.lld: 'Sociologia',
    },
    'Kunstgeschichte': {
      AppLanguage.en: 'Art history',
      AppLanguage.it: "Storia dell'arte",
      AppLanguage.lld: "Storia dl'arte",
    },
    'Musiktheorie': {
      AppLanguage.en: 'Music theory',
      AppLanguage.it: 'Teoria musicale',
      AppLanguage.lld: 'Teoria musicales',
    },
    'Sporttheorie': {
      AppLanguage.en: 'Sports theory',
      AppLanguage.it: 'Teoria dello sport',
      AppLanguage.lld: 'Teoria dl sport',
    },
    'Laborübungen': {
      AppLanguage.en: 'Lab exercises',
      AppLanguage.it: 'Esercitazioni di laboratorio',
      AppLanguage.lld: 'Ejercizi de laboratorie',
    },
    'Naturwissenschaftliches Labor': {
      AppLanguage.en: 'Science lab',
      AppLanguage.it: 'Laboratorio scientifico',
      AppLanguage.lld: 'Laboratorie scientific',
    },
    'Wirtschaft': {
      AppLanguage.en: 'Economics',
      AppLanguage.it: 'Economia',
      AppLanguage.lld: 'Economia',
    },
    'Marketing': {
      AppLanguage.en: 'Marketing',
      AppLanguage.it: 'Marketing',
      AppLanguage.lld: 'Marketing',
    },
    'Verwaltung': {
      AppLanguage.en: 'Administration',
      AppLanguage.it: 'Amministrazione',
      AppLanguage.lld: 'Aministrazion',
    },
    'Finanzwesen': {
      AppLanguage.en: 'Finance',
      AppLanguage.it: 'Finanza',
      AppLanguage.lld: 'Finanza',
    },
    'Tourismus': {
      AppLanguage.en: 'Tourism',
      AppLanguage.it: 'Turismo',
      AppLanguage.lld: 'Turism',
    },
    'Gastronomie': {
      AppLanguage.en: 'Gastronomy',
      AppLanguage.it: 'Gastronomia',
      AppLanguage.lld: 'Gastronomia',
    },
    'Küchenführung': {
      AppLanguage.en: 'Kitchen management',
      AppLanguage.it: 'Gestione cucina',
      AppLanguage.lld: 'Gestion dla cüjina',
    },
    'Restaurantführung': {
      AppLanguage.en: 'Restaurant management',
      AppLanguage.it: 'Gestione ristorante',
      AppLanguage.lld: 'Gestion dl restaurant',
    },
    'Empfangslehre': {
      AppLanguage.en: 'Reception studies',
      AppLanguage.it: 'Tecniche di ricevimento',
      AppLanguage.lld: 'Tecniches de receziun',
    },
    'Handwerkliche Praxis': {
      AppLanguage.en: 'Practical craftsmanship',
      AppLanguage.it: 'Pratica artigianale',
      AppLanguage.lld: 'Pratica artisianala',
    },
    'Fachpraxis': {
      AppLanguage.en: 'Professional practice',
      AppLanguage.it: 'Pratica professionale',
      AppLanguage.lld: 'Pratica profescionela',
    },
    'Betriebswirtschaft': {
      AppLanguage.en: 'Business administration',
      AppLanguage.it: 'Economia aziendale',
      AppLanguage.lld: 'Economia aziendala',
    },
    'Rechnungswesen': {
      AppLanguage.en: 'Accounting',
      AppLanguage.it: 'Contabilità',
      AppLanguage.lld: 'Contabilità',
    },
    'Projektarbeit': {
      AppLanguage.en: 'Project work',
      AppLanguage.it: 'Lavoro di progetto',
      AppLanguage.lld: 'Lëur de proiet',
    },
    'Interdisziplinäre Projekte': {
      AppLanguage.en: 'Interdisciplinary projects',
      AppLanguage.it: 'Progetti interdisciplinari',
      AppLanguage.lld: 'Proiec interdisciplinars',
    },
    'Griechisch': {
      AppLanguage.en: 'Greek',
      AppLanguage.it: 'Greco',
      AppLanguage.lld: 'Grech',
    },
    'FÜ': {
      AppLanguage.en: 'Interdisciplinary',
      AppLanguage.it: 'Interdisciplinare',
      AppLanguage.lld: 'Interdisciplinar',
    },
  };

  static Future<AppLocalizations> load(Locale locale) async {
    final language = AppLanguage.fromLocale(locale);
    final translations = await _loadLanguageMap(language);
    return AppLocalizations._(
      locale: locale,
      translations: translations,
    );
  }

  static Future<Map<String, String>> _loadLanguageMap(
    AppLanguage language,
  ) async {
    final merged = <String, String>{};
    for (final assetPath in <String>[
      'assets/locales/de.json',
      if (language != AppLanguage.de) 'assets/locales/${language.code}.json',
    ]) {
      try {
        final raw = await rootBundle.loadString(assetPath);
        final decoded = json.decode(raw) as Map<String, dynamic>;
        merged.addAll(
          decoded.map((key, value) => MapEntry(key, value.toString())),
        );
      } catch (_) {
        // Missing optional language file; keep fallback values.
      }
    }
    if (merged.isNotEmpty) {
      return merged;
    }
    throw FlutterError('No localization assets found for ${language.code}.');
  }

  String text(
    String key, {
    Map<String, String> args = const {},
  }) {
    var value = _translations[key] ?? _translations['i18n.missing'] ?? key;
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  AppLanguage get _language => AppLanguage.fromLocale(locale);

  Map<String, String> get _currentSubjectTranslations {
    if (!appSubjectTranslationController.enabled ||
        _language == AppLanguage.de) {
      return const {};
    }
    final translations = <String, String>{};
    for (final entry in _subjectTranslations.entries) {
      final translated = entry.value[_language];
      if (translated != null) {
        translations[entry.key] = translated;
      }
    }
    return translations;
  }

  String translateSubjectName(String input) {
    final normalized = input.trim();
    if (!appSubjectTranslationController.enabled ||
        normalized.isEmpty ||
        _language == AppLanguage.de) {
      return input;
    }
    for (final entry in _subjectTranslations.entries) {
      if (equalsIgnoreCase(entry.key, normalized)) {
        return entry.value[_language] ?? entry.key;
      }
    }
    return input;
  }

  String translateProfileRole(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized == 'schüler/in' ||
        normalized == 'schueler/in' ||
        normalized == 'schüler' ||
        normalized == 'schueler') {
      return text('profile.role.student');
    }
    if (normalized == 'eltern' ||
        normalized == 'elternteil' ||
        normalized == 'erziehungsberechtigte') {
      return text('profile.role.parent');
    }
    return input;
  }

  String translateAuthServerText(String input) {
    final trimmed = input.trim();
    final connectionMatch = RegExp('^Keine Verbindung mit "(.+)" möglich')
        .firstMatch(trimmed);
    if (connectionMatch != null) {
      return text(
        'login.noConnectionWithUrl',
        args: {'url': connectionMatch.group(1)!},
      );
    }
    final replacements = <String, String>{
      'Bitte gib etwas ein': text('login.emptyCredentials'),
      'Dieser Benutzertyp wird nicht unterstützt.':
          text('login.userTypeUnsupported.message'),
    };
    return replacements[trimmed] ?? input;
  }

  String semesterLabel(Semester semester) {
    if (semester == Semester.first) {
      return text('semester.first');
    }
    if (semester == Semester.second) {
      return text('semester.second');
    }
    return text('semester.all');
  }

  String dashboardDayLabel(UtcDateTime date) {
    final today = UtcDateTime(now.year, now.month, now.day);
    final difference = date.difference(today);
    if (difference.inDays == 0) {
      return text('day.today');
    }
    if (difference.inDays == 1) {
      return text('day.tomorrow');
    }
    if (difference.inDays == -1) {
      return text('day.yesterday');
    }
    final weekdayKey = switch (date.weekday) {
      DateTime.monday => 'weekday.monday',
      DateTime.tuesday => 'weekday.tuesday',
      DateTime.wednesday => 'weekday.wednesday',
      DateTime.thursday => 'weekday.thursday',
      DateTime.friday => 'weekday.friday',
      DateTime.saturday => 'weekday.saturday',
      _ => 'weekday.sunday',
    };
    return text(
      'day.weekdayDate',
      args: {
        'weekday': text(weekdayKey),
        'date': DateFormat('d.M.', locale.toLanguageTag()).format(date),
      },
    );
  }

  String translateDashboardServerText(String input) {
    final replacements = <String, String>{
      'Heute': text('day.today'),
      'Morgen': text('day.tomorrow'),
      'Gestern': text('day.yesterday'),
      'Montag': text('weekday.monday'),
      'Dienstag': text('weekday.tuesday'),
      'Mittwoch': text('weekday.wednesday'),
      'Donnerstag': text('weekday.thursday'),
      'Freitag': text('weekday.friday'),
      'Samstag': text('weekday.saturday'),
      'Sonntag': text('weekday.sunday'),
      'Erinnerung': text('dashboard.reminder'),
      'Hausaufgabe': text('dashboard.homework'),
      'Beobachtung': text('dashboard.observation'),
      'Bewertung': text('dashboard.grade'),
      'Testarbeit': text('dashboard.testwork'),
      'Schularbeit': text('dashboard.schoolwork'),
      'Prüfung': text('dashboard.exam'),
      'Test': text('dashboard.test'),
    };

    var result = input;
    final orderedKeys = replacements.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in orderedKeys) {
      result = result.replaceAllMapped(
        RegExp('\\b${RegExp.escape(key)}\\b'),
        (_) => replacements[key]!,
      );
    }
    final subjectTranslations = _currentSubjectTranslations;
    final subjectKeys = subjectTranslations.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in subjectKeys) {
      result = result.replaceAll(key, subjectTranslations[key]!);
    }
    return result;
  }

  String translateSchoolTerm(String input) {
    final replacements = <String, String>{
      'Praktischer Test': text('schoolTerm.practicalTest'),
      'Praktische Arbeit': text('schoolTerm.practicalTest'),
      'Schularbeit': text('schoolTerm.schoolwork'),
      'Test': text('schoolTerm.test'),
      'Präsentation': text('schoolTerm.presentation'),
      'Referat': text('schoolTerm.presentation'),
      'Prüfung': text('schoolTerm.exam'),
      'Anderes': text('schoolTerm.other'),
      'anderes': text('schoolTerm.other'),
      'Sonstige Bewertung': text('schoolTerm.other'),
      'Beobachtung': text('schoolTerm.observation'),
      'Plus': text('schoolTerm.plus'),
      'Minus': text('schoolTerm.minus'),
      'Hausaufgabe': text('dashboard.homework'),
      'Mitarbeit': text('schoolTerm.participation'),
    };
    var result = input;
    final orderedKeys = replacements.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in orderedKeys) {
      result = result.replaceAllMapped(
        RegExp('\\b${RegExp.escape(key)}\\b'),
        (_) => replacements[key]!,
      );
    }
    return result;
  }

  String translateCreatedText(String input) {
    final match = RegExp(
      r'^Von (.+) am ([0-9]{1,2}\.[0-9]{1,2}\.[0-9]{4}) eingetragen$',
    ).firstMatch(input.trim());
    if (match != null) {
      return text(
        'schoolTerm.createdByOn',
        args: {
          'name': match.group(1)!,
          'date': match.group(2)!,
        },
      );
    }
    return translateSchoolTerm(input);
  }

  String gradeCountLabel(int count) {
    return text(
      count == 1
          ? 'gradeCalculator.gradeCount.one'
          : 'gradeCalculator.gradeCount.other',
      args: {'count': count.toString()},
    );
  }

  String attachmentLabel(int count) {
    return text(
      count == 1 ? 'messages.attachment.one' : 'messages.attachment.other',
    );
  }

  String absenceJustificationLabel(AbsenceJustified justified) {
    return switch (justified) {
      AbsenceJustified.justified => text('absences.status.justified'),
      AbsenceJustified.forSchool =>
        text('absences.justification.schoolJustified'),
      AbsenceJustified.notJustified => text('absences.status.notJustified'),
      AbsenceJustified.notYetJustified => text('absences.justification.notYet'),
      _ => text('absences.justification.notYet'),
    };
  }

  String formatAbsenceSignature(DateTime timestamp, String signature) {
    return text(
      'absences.future.recordedBy',
      args: {
        'timestamp': DateFormat(
          "EEE d.M.yyyy 'um' HH:mm",
          locale.toLanguageTag(),
        ).format(timestamp),
        'signature': signature,
      },
    );
  }

  String formatTimeAgo(UtcDateTime dateTime) {
    final diff = UtcDateTime.now().difference(dateTime);
    if (diff.inDays >= 1) {
      return text(
        diff.inDays == 1 ? 'time.dayAgo.one' : 'time.dayAgo.other',
        args: {'count': diff.inDays.toString()},
      );
    }
    if (diff.inHours >= 1) {
      return text(
        diff.inHours == 1 ? 'time.hourAgo.one' : 'time.hourAgo.other',
        args: {'count': diff.inHours.toString()},
      );
    }
    if (diff.inMinutes >= 1) {
      return text(
        diff.inMinutes == 1 ? 'time.minuteAgo.one' : 'time.minuteAgo.other',
        args: {'count': diff.inMinutes.toString()},
      );
    }
    return text(
      diff.inSeconds == 1 ? 'time.secondAgo.one' : 'time.secondAgo.other',
      args: {'count': diff.inSeconds.toString()},
    );
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((supported) {
        return supported.languageCode == locale.languageCode &&
            supported.countryCode == locale.countryCode;
      });

  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String t(String key, {Map<String, String> args = const {}}) =>
      l10n.text(key, args: args);
}
