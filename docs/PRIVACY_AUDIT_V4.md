# Abschlussbericht Datenschutz / Telemetrie v4

Stand: **1. Oktober 2026**. Bestehendes Flutter-Projekt geprüft und gezielt ergänzt. Keine Firebase-/GA4-/BigQuery-/Store-Einstellungen außerhalb des Repositorys verändert. Keine Garantie vollständiger DSGVO-Konformität; offene rechtliche und administrative Punkte stehen unten.

## A. Gefundener Ausgangszustand

Das Repository enthielt bereits Datenschutzversion 4, einen zentralen `PrivacyController`, drei granulare Entscheidungen, lokale Altersberechtigung, default-off Native-Bootstrap, `ProductAnalytics`, `DiagnosticsService`, eine geschlossene Analytics-Allowlist, 45 technische Crashlytics-Keys, UUIDv4-Identitäten und akademische Snapshot-Deduplizierung. Die vier App-Sprachen sind Deutsch, Italienisch, Englisch und Ladinisch.

Gefundene Lücken: Analytics-Collection wurde vor Consent Mode aktiviert; `school_id` wurde schon mit reiner Nutzungsanalyse gesetzt. Die Plattformregel war adapterabhängig statt gemeinsam. Fehlgeschlagene Firebase-Initialisierung konnte erneut versucht werden. Apple-Bootstrap berücksichtigte eine fehlende Konfigurationsressource nicht vor dem Analytics-Aufruf. Lokale Logs, Absenz-Debuglogs, Netzwerkprotokoll und Supportformular konnten rohe URLs, Payloads oder Exception-Texte enthalten. Mehrere ältere Oberflächen verwendeten deutsche Literale; Ladin enthielt deutsche Datenschutztexte. Datenschutzinventur und die angeforderten externen Checklisten fehlten.

## B. Geänderte Dateien

Die vollständige Dateiliste steht im Anhang. Wesentliche Gruppen: bestehende Telemetrieadapter und Services; gemeinsamer Capability-Layer und lokaler Logger; Wrapper/Middleware/Netzwerkprotokoll; vier Sprachkataloge und bisher unübersetzte Oberflächen; Apple-Bootstrap und iOS-Ressourcen; Regressionstests und Dokumentation. Einige vorhandene Import-/const-/Klammer-Stilhinweise wurden durch Dart-Fixes bereinigt; diese verändern kein Produktverhalten. Abhängigkeiten, Schul-ID-Reservierungen und Kern-Notenberechnung blieben erhalten.

## C. Bereits korrekt vorhanden und erhalten

- Version 4 verlangt neue Entscheidung für v3 und ältere/ungültige Daten; neue Installation und Lesefehler erlauben keine optionalen Zwecke.
- `unknown` und `under14` sperren alle optionalen Zwecke; kein Geburtsdatum oder genaues Alter, kein Upload des Altersstatus.
- Diagnostik, Nutzung und akademische Statistik sind getrennt; akademische Statistik benötigt zusätzlich Nutzungsanalyse. Kernfunktionen funktionieren bei Ablehnung.
- Native Android-/Apple-Collection und Werbe-/Screen-Defaults aus; Android-Werbeberechtigungen entfernt; kein Performance/FCM/ATT hinzugefügt.
- Zufällige kryptografische UUIDv4 pro lokalem Account/Installation; kein personenbezogener deterministischer Hash und keine Cross-Device-Verknüpfung.
- Geschlossene Event-/Property-Schemata, technische Screen-Namen, kontrollierte technische Diagnosewerte und synthetische E-Codes. Kein Crashlytics Account-User-Identifier.
- Alle 229 unveränderlichen Schulreservierungen erhalten; mehrdeutige URLs ergeben keine Schul-ID.
- Akademische Statistik nutzt `overallGradeAverage(state)` wie die sichtbare Gesamtnote, Integer-Zehntel, Count-Buckets, lokale normalisierte Fingerprints und Account-/Semester-Provenienz. Einzelnoten und Demo-Daten ausgeschlossen.
- Logout/Accountwechsel schließen alte Arbeit per Epoch-Gate und löschen alte Attribution. Widerruf schließt Gates synchron, löscht Properties/ID, setzt lokale Analytics-Daten zurück und bereinigt nicht gesendete Crashreports.

## D. Neu implementiert bzw. korrigiert

- Opt-in setzt zuerst alle Google-Consent-Signale, einschließlich dauerhaft verweigerter Werbezwecke, danach Collection und anschließend erlaubte Identität/Properties/Events.
- Die zentrale Property-Grenze blockiert `school_id` ohne akademischen Consent oder im Demo-Modus, auch für direkte zukünftige Aufrufer; Widerruf bereinigt den alten Kontext.
- `TelemetryCapabilities` verwendet die tatsächliche Laufzeitplattform. Windows-/Linux-/Web-Policy schaltet Analytics/Crashlytics aus; UI-Plattform-Overrides können Windows-Telemetrie nicht einschalten.
- Firebase-Initialisierung wird pro Prozess nur einmal versucht; ein Fehlschlag bleibt bis Neustart fail-closed. Bestehende Controller/Service-Catches halten optionale Pluginfehler von Kernfunktionen fern.
- Ein lokaler Debug-Logger lässt nur feste technische Kategorien zu; Release schreibt daraus keine Logs. Rohfehler, URL-/Dateinamen, Kalender-/Account-IDs und API-Payloads werden nicht ausgegeben.
- Absenz-Payload-/Antwortlogs entfernt. Netzwerkprotokoll speichert ausschließlich minimierte Kategorien/Status mit redigierten Parametern; Reducer prüft auch fremde Aufrufer und begrenzt auf 100 Einträge.
- Supportformular erhält keinen vorgefüllten rohen Fehlerbericht. Technische Fehlerseiten/2FA/Profil- und Absenzmeldungen sind lokalisiert und rendern keine ungefilterten Plugin-/Serverfehlermeldungen als Diagnostik.
- Stack-Filter verlangt vollständige zulässige Symbolframes und verwirft angehängte persönliche Texte, URLs und Dateisystempfade.

## E. Datenschutz / Einwilligung

Eine zentrale lokale Entscheidung bleibt die einzige Autorisierung. Keine neue vorausgewählte Option oder implizite Zustimmung. Die UI zeigt spätere Änderungsmöglichkeit und bei bestehenden Nutzern den aktualisierten Hinweis. Keine Zustimmung aus Info-Seiten oder Dialog-Abbruch. Die gespeicherte lokale Altersentscheidung ist nur `unknown`, `atLeast14` oder `under14`.

Verantwortlicher und Kontakt wurden vom Eigentümer bestätigt und in allen Sprachen ergänzt: **Tobias Bucci, Mühlenweg 51, St. Sigmund, Italien (Bozen)**; **buccitobias774@gmail.com**. Kein automatischer serverseitiger Löschablauf wird behauptet.

## F. Android

Bestehende Manifest-Defaults und PrivacyApplication erhalten: Analytics/Crashlytics aus, Werbe-ID-Erfassung aus, alle Werbeconsents verweigert, automatische Screenberichte aus, FirebaseInitProvider entfernt, Backup aus. Laufzeit-Consent-Reihenfolge ist korrigiert. Android-Release-Build wird in der abschließenden Validierung dokumentiert. Geräteverkehr, Restart/Purge und symbolisierte native Berichte bleiben reale Gerätetests.

## G. iOS / bestehender macOS-Pfad

Apple-Bootstrap gibt ohne echte `GoogleService-Info.plist` keine Firebase-Readiness frei. Keine erfundene Bundle-ID, App-Store-ID oder Fake-Konfiguration. iOS Face-ID-Verwendungszweck ist in de/en/it/lld `InfoPlist.strings` hinterlegt und als Xcode-Variant-Ressource registriert. Native Berechtigungsdialoge wählen die Sprache nach Betriebssystem-Einstellungen. Default-off Plists strukturell validiert. Apple-Kompilation und Symbolupload wurden auf diesem Windows-Rechner nicht verifiziert; siehe [iOS-Checkliste](IOS_FIREBASE_SETUP.md).

## H. Windows

Analytics und Crashlytics bleiben Produktions-No-op; Tests prüfen, dass Collection-, Lösch-, Reset- und Diagnoseadapter weder Firebase initialisieren noch Plugins aufrufen. Lokale Datenschutzentscheidungen und UI funktionieren weiterhin. Windows-Debug-Build erfolgreich erstellt.

## I. Datenschutzerklärung / Dokumentation / vier Sprachen

Alle vier Kataloge enthalten **840 gleiche Schlüssel** mit geprüften Platzhaltern. Ergänzt/korrigiert: Datenschutz, Verantwortlicher/Kontakt, notwendige lokale Registerdaten, Gesundheitsbezug möglicher Absenzgründe, separate Einwilligungszwecke, pseudonyme Schulzuordnung, Google/Firebase-Empfänger, mögliche internationale Verarbeitung, Rechte/Beschwerde, Löschung und Speicherfristen. Deutsche Ladin-Fallbacktexte ersetzt.

Bisher feste App-Texte in Prüfungs-/Lernplan-Kalender, Prognose, Historie/Statistik, Diagramm-Legende, Dateidialogen, Netzwerkprotokoll, Debug-/Spendenansicht sowie Fehler-/Absenz-/Profil-/2FA-Meldungen sind lokalisiert. Generierte Lernphasen/Aufwand/Countdowns werden übersetzt; persönliche Freitexte, Schulnachrichten, Dateinamen und eigene Notizen bleiben Originalinhalte. [Dateninventur](PRIVACY_DATA_INVENTORY.md), [Store-Checkliste](STORE_PRIVACY_CHECKLIST.md), [Firebase-Setup](FIREBASE_ANALYTICS_SETUP.md) und bestehende Dokumente wurden ergänzt.

## J. GA4 / BigQuery

Console-Werte aus der Vorgabe als vom Eigentümer berichtet dokumentiert, nicht als live verifiziert: EU Daily Export, kein Streaming/Advertising-ID-/User-Data-Export, GA4 14 Monate/reset bei Aktivität, keine Ads/Signals. Keine Definitionen dupliziert oder akademischen Conversions hinzugefügt.

SQL verwendet weiterhin neuesten gültigen Snapshot pro pseudonymer ID + Schuljahr + Semester statt Event-Mittelwert; akademischer Schulkontext erfordert nun zusätzliche Einwilligung. Veröffentlichte Gruppen unter 30 unterschiedlichen pseudonymen IDs bleiben unterdrückt: interne Engineering-Regel, keine gesetzliche Anonymitätsgarantie. [BigQuery-Retention](BIGQUERY_RETENTION.md) behandelt eigene Dataset-/Table-/Partition-TTL, bestehende Tabellen und tatsächliche Speicherfristen.

## K. Tests und Ergebnisse

- Gezielte Datenschutz-Suite: **53 Tests bestanden** vor den letzten ergänzenden Regressionstests.
- Abschließende vollständige Suite: `flutter test --no-pub --concurrency=4 --reporter expanded`: **310 Tests bestanden** (20 Sekunden).
- Windows: `flutter build windows --debug --no-pub`: **erfolgreich**, `build/windows/x64/runner/Debug/DigitalesRegister.exe`.
- `flutter analyze --no-pub`: keine Fehler oder Warnungen; abschließendes Ergebnis siehe Validierungsnachtrag. Ein vorhandener Informationshinweis im unveränderten `tutorial_service.dart` wird nicht als Fehler ausgegeben.
- `git diff --check`: erfolgreich. Vier JSON-Kataloge, Apple default-off Plists und Xcode-Verweise auf Sprachressourcen strukturell geprüft.
- Das vorhandene per-Datei-Parallelscript wurde ebenfalls ausgeführt: ein Flutter-Compiler-Cache-Dateikonflikt führte zum Timeout, und der ältere Kalender-Test hatte keine Lokalisierungsdelegates. Der Test verwendet jetzt das reale lokalisierte App-Setup; die gesamte Suite bestand anschließend im einzelnen Flutter-Prozess. Keine Kernfunktion künstlich für Tests verändert.
- Neue Tests: Consent-vor-Collection/Werbedenials und Widerrufsreihenfolge, einmaliger Initialisierungsfehlschlag, Windows-No-op, zusätzliche Schul-ID-Grenze, Katalog-/Platzhaltergleichheit, Netzwerk-Redaktion/Limit, strikter Stack-Filter. Bestehende Consent-/Migration-/Alter-/Demo-/Dedup-/Logout-/SDK-Fehler-/UI-/Kernfunktionstests erhalten.

## L. Offene manuelle Aufgaben

1. Firebase-iOS-App mit tatsächlicher Bundle-ID registrieren, echte Konfiguration einbinden und Xcode/CocoaPods/Symbolupload prüfen; keine dieser externen Aufgaben ist erledigt.
2. Reale Android/iOS-Tests für Fresh Install, v3-Migration, unter14/unknown, Einzelzustimmung, Widerruf/Restart/Offline und Accountwechsel; Netzwerkverkehr/DebugView/Crashlytics-Auslieferung beobachten.
3. BigQuery-TTL tatsächlich konfigurieren und überprüfen, inklusive vorhandener Tabellen/Kopien/Backups; alle vier Retention-Texte an bestätigte Ist-Frist anpassen.
4. Google Play Data Safety und Apple App Privacy nach finaler SDK-/Artefaktprüfung ausfüllen; erforderliche öffentliche Datenschutzerklärungs-URL veröffentlichen/prüfen.
5. Datenschutzanfragen über den bestätigten Kontakt operativ bearbeiten und serverseitige Löschmöglichkeiten prüfen. Kein automatisches Backend-Verfahren existiert.
6. Ladinische Formulierungen, besonders Rechtstexte, durch sprachkundige Person prüfen lassen.

## M. Offene rechtliche Prüfung

**Legal review required:** Rechtsgrundlage/Rollen von Schule, Registeranbieter und App für notwendige Registerverarbeitung; gesundheitsbezogene Absenzgründe; lokale Speicherung und Kalender-/Datei-/Linkverarbeitung; konkrete Google-Verträge, Unterauftragnehmer und internationale Übermittlungsgarantien; actual retention/deletion obligations; Store-Angaben und Datenschutzerklärung vor Veröffentlichung. Verantwortlicher/Kontakt für den App-Fork sind bestätigt, die fremden Rollen wurden nicht erfunden.

## N. Risiken / Grenzen

Native SDK-Crashreports enthalten automatische Plattformmetadaten außerhalb des Dart-Filters. Bereits laufende SDK-Uploads lassen sich nicht rückwirkend abbrechen; lokale Löschung/Widerruf löscht keine GA4-/BigQuery-/Crashlytics-Serverhistorie. Native Sticky-Override-Reset greift auf isolierte SDK-Speichernamen zurück und muss bei SDK-Upgrades geprüft werden. Datenwiederherstellung/OS-Sicherungen und Cloud-Kalender-/Dateikopien können lokale App-Löschung überleben. UUIDs zählen Installationen/Accounts, keine verifizierten Personen. Die Kernfunktionen und Builds sind getestet, Firebase-Netzwerk-/Console-/Apple-Geräteverhalten bleibt extern zu verifizieren.

## Validierungsnachtrag

**Android:** `flutter build apk --release --no-pub` erfolgreich (168,4 Sekunden); `build/app/outputs/flutter-apk/app-release.apk`, 77,2 MB.

**Statische Analyse:** `flutter analyze --no-pub`: 0 Fehler, 0 Warnungen; ein bestehender Informationshinweis `unnecessary_getters_setters` in `lib/tutorial/tutorial_service.dart:246`. Flutter meldet wegen dieses Info-Lints einen nicht erfolgreichen Analyse-Exit; keine neuen Diagnosen.

**Abschließende Tests:** 310 erfolgreich. **Windows-Debug-Build:** erfolgreich. **Diff-Prüfung:** erfolgreich. iOS/macOS wurden strukturell geprüft, nicht kompiliert.

## Anhang: vollständige Dateiliste

- `README.md`
- `assets/locales/de.json`
- `assets/locales/en.json`
- `assets/locales/it.json`
- `assets/locales/lld.json`
- `docs/ANALYTICS_BIGQUERY_EXAMPLES.md`
- `docs/ANALYTICS_IMPLEMENTATION.md`
- `docs/BIGQUERY_RETENTION.md`
- `docs/FIREBASE_ANALYTICS_CONSOLE_CONFIGURATION.md`
- `docs/FIREBASE_ANALYTICS_SETUP.md`
- `docs/IOS_FIREBASE_SETUP.md`
- `docs/PRIVACY_AUDIT_V4.md`
- `docs/PRIVACY_DATA_INVENTORY.md`
- `docs/PRIVACY_IMPLEMENTATION.md`
- `docs/STORE_PRIVACY_CHECKLIST.md`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/de.lproj/InfoPlist.strings`
- `ios/Runner/en.lproj/InfoPlist.strings`
- `ios/Runner/it.lproj/InfoPlist.strings`
- `ios/Runner/lld.lproj/InfoPlist.strings`
- `lib/analytics_service.dart`
- `lib/calendar_sync_service.dart`
- `lib/container/exam_calendar_container.dart`
- `lib/container/grades_forecast_container.dart`
- `lib/container/grades_history_container.dart`
- `lib/container/grades_statistics_container.dart`
- `lib/diagnostics_service.dart`
- `lib/i18n/app_localizations.dart`
- `lib/middleware/absences.dart`
- `lib/middleware/dashboard.dart`
- `lib/middleware/login.dart`
- `lib/middleware/middleware.dart`
- `lib/middleware/profile.dart`
- `lib/privacy_log.dart`
- `lib/product_analytics.dart`
- `lib/reducer/dashboard.dart`
- `lib/reducer/network_protocol.dart`
- `lib/settings_persistence_service.dart`
- `lib/telemetry_capabilities.dart`
- `lib/ui/absences_page.dart`
- `lib/ui/calendar.dart`
- `lib/ui/calendar_detail.dart`
- `lib/ui/class_register_page.dart`
- `lib/ui/course_materials_page.dart`
- `lib/ui/days.dart`
- `lib/ui/debug_page.dart`
- `lib/ui/donations.dart`
- `lib/ui/exam_calendar_page.dart`
- `lib/ui/grades_chart.dart`
- `lib/ui/grades_chart_legend.dart`
- `lib/ui/grades_chart_page.dart`
- `lib/ui/homework_summary_page.dart`
- `lib/ui/login_page_content.dart`
- `lib/ui/messages.dart`
- `lib/ui/network_protocol.dart`
- `lib/ui/network_protocol_page.dart`
- `lib/ui/privacy_data_details_page.dart`
- `lib/ui/school_countdown_overview.dart`
- `lib/ui/settings_page_widget.dart`
- `lib/ui/sorted_grades_widget.dart`
- `lib/util.dart`
- `lib/wrapper.dart`
- `macos/Runner/MainFlutterWindow.swift`
- `test/diagnostics_service_test.dart`
- `test/localization_catalog_test.dart`
- `test/network_protocol_privacy_test.dart`
- `test/product_analytics_test.dart`
- `test/telemetry_capabilities_test.dart`
- `test/ui/exam_calendar_page_test.dart`
