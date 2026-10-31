# Issue #82 — Einmaliger Opt-in

Stand: 25.10.2026. Dieser Nachtrag beschreibt die Erweiterung nach dem
ursprünglichen Abschlussbericht (außerhalb des Repos geführt); dessen Testzahlen beziehen sich
auf den vorherigen Implementierungsstand.

## Verhalten

- Ohne ausdrückliche Accountentscheidung bleiben persönliche Benachrichtigungen
  deaktiviert. Noten und Mitteilungen sind nur im Erklärdialog vorausgewählt.
- Nach erfolgreicher Anmeldung wird der Dialog einmal pro noch unentschiedenem
  Account angeboten — auch nach einem Update. Bestehende Starthinweise, andere
  Dialoge und App-Entsperrung gehen vor. Das Tutorial folgt anschließend.
- Zustimmung speichert die ausgewählten Kategorien und stille Baselines vor dem
  möglichen nativen Berechtigungsaufruf. Ablehnung speichert einen deaktivierten
  Zustand, ohne eine Systemberechtigung anzufragen.
- Ein Systemgrant, eine frühere Feed-Historie oder vorausgewählte Kategorien
  ersetzen keine App-Zustimmung. Bereits ausdrücklich gespeicherte Einstellungen
  bleiben erhalten. Alte globale Einstellungen werden den vor der Anmeldung
  gespeicherten Accounts zugeordnet; später neue Accounts werden dadurch nicht
  positiv angemeldet. Vorherige globale Deaktivierung wird nicht aufgehoben.
- Account- und Sitzungsschutz verhindern, dass ein alter Dialog eine Auswahl
  auf einen anderen Account überträgt. Nach Accountwechsel wird die alte Frage
  geschlossen. Ein abgebrochener Speichervorgang bleibt erneut versuchbar.
- Der Hauptschalter in den Einstellungen kann die Entscheidung jederzeit ändern.
  Kategorien und Datenschutzeinstellung bleiben getrennt erhalten.

## Speicherung und Berechtigungen

`school-notification-preferences-v1-<Account-Hash>` enthält nun zusätzlich
`decision: unknown | accepted | declined`. Die gespeicherte Appentscheidung ist
unabhängig von der geräteweiten Systemberechtigung. Keine Credentials, Inhalte
oder Einwilligungsdaten werden dafür an ein eigenes Backend übertragen.

Die geräteweite Markierung `school-notification-permission-requested-v1` wird
vor dem nativen Aufruf gespeichert. Eine OS-Ablehnung führt weder beim nächsten
Start noch bei einem anderen Account oder Hauptschalterwechsel zu einer erneuten
Systemfrage. Die Einstellungen bieten stattdessen einen freiwilligen Systemlink.
iOS prüft `authorizationStatus == .notDetermined`; Android berücksichtigt die
öffentliche Rationale-API und die OS-eigene Sperre nach dauerhafter Ablehnung.
Eine auf alten Android-Versionen nicht eindeutig erkennbare historische Ablehnung
kann höchstens einen vom OS ohne erneuten Dialog abgelehnten Aufruf erzeugen.

Die einmalige Migration verwendet nur den beim Start gespeicherten Accountbestand.
`school-notification-consent-migrated-v1` verhindert, dass spätere neue Accounts
eine alte globale positive Auswahl erben. Lokale Verlaufs-/Schulabfragen verwenden
weiterhin dieselbe Engine und denselben Hintergrunddienst.

## Dateien

- `lib/ui/school_notification_opt_in.dart`: Dialog, Modal-/Lifecycle-/Lock-Schutz,
  Anzeige nach Starthinweisen und anschließendes Tutorial.
- `lib/container/home_page.dart`, `lib/ui/home_page_content.dart`: Accountbezug
  und Integration in die sichtbare Startansicht.
- `lib/school_notification_service.dart`: persistente Entscheidung, Migration,
  stille Baselines, einmaliger Permission-Aufruf und sichere Accountübergänge.
- `lib/school_notification_engine.dart`: Zustimmung als zusätzliche Zustellbedingung.
- `lib/middleware/middleware.dart`: Snapshot der alten Accounts und Abschluss der
  vorgelagerten Starthinweise; Login wartet nicht auf die optionale Auswahl.
- `lib/ui/school_notification_settings.dart`: Wechsel zwischen einmaliger
  Berechtigungsfrage und freiwilligem Systemeinstellungslink.
- Android `MainActivity.kt`, iOS `AppDelegate.swift`: unterstützte native
  Abfragen vor einem Berechtigungsversuch.
- Vier Sprachkataloge: Deutsch, Italienisch, Englisch und Ladinisch.

## Verifikation

Abschließend ausgeführt:

- `flutter test --no-pub --reporter expanded`: **1.296 bestanden, 2 bestehende
  Tests übersprungen, keine Fehler**.
- Gezielter Lauf mit Opt-in-, Engine-, Service-, Settings-, Login-/Tutorial- und
  Katalogtests: **145 bestanden**; Teilmenge des Gesamtlaufs.
- `flutter analyze --no-pub`: **keine Probleme**.
- `flutter build apk --debug --no-pub`: **erfolgreich**.
- Statische Konfigurationsprüfung und `git diff --check`: **erfolgreich**.

Die neuen Testdateien sind `test/school_notification_opt_in_test.dart` und
`test/ui/school_notification_opt_in_test.dart`. Zusätzlich prüfen die Engine-Tests,
dass aktivierte Kategorien allein keine Zustellung autorisieren. Bestehende
Delivery-Fixtures sind ausdrücklich als bereits zugestimmte Accounts eingerichtet;
der Login-/Kalendertest verwendet die tatsächliche Home-Integration.

Abgedeckt sind Neuinstallation, Update ohne Entscheidung, Zustimmung/Ablehnung,
Neustart, alte globale und accountbezogene Einstellungen, verschiedene Schulen,
zwei Benutzer derselben Schule, einmalige Systemfrage, vorhandene Ablehnung,
Speicherfehler, stale Dialoge, stille Baseline, App-Sperre, konkurrierende Modals,
große Schrift sowie alle vier Sprachen in Hell/Dunkel. UI-Vorschauen wurden mit
App-Schriften erzeugt und ausgewählte Ansichten visuell geprüft.

Logs liegen unter `build/issue82_optin_*.log`, Vorschauen unter
`build/notification_optin_previews/`. Die nativen Dialoge auf physischen Geräten
und der iOS-Build sind in dieser Windows-Umgebung nicht verifiziert; die bestehende
Geräteanleitung wurde um Opt-in-Szenarien ergänzt. Die bereits dokumentierten
Android-/iOS-Hintergrundgrenzen bestehen weiter.
