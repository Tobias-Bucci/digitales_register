# Hintergrundbenachrichtigungen: Übernahme der Referenzarchitektur

Stand: 25.10.2026. Änderungen lokal auf dem bestehenden Branch; keine Commits,
Pushes, Branchwechsel oder Änderungen an GitHub-Issues. Der Ordner
`digitales_register/` wurde ausschließlich gelesen.

## Auftrag und Issue-Zuordnung

Die eingefügte Aufgabenbeschreibung nennt Issue #81. Die aktuelle GitHub-Abfrage
ergab jedoch: [#81](https://github.com/Tobias-Bucci/digitales_register/issues/81)
behandelt orange Noten und ist bereits geschlossen.
[#82](https://github.com/Tobias-Bucci/digitales_register/issues/82) behandelt
Benachrichtigungen über Noten und Schulmitteilungen und ist offen. Die Umsetzung
folgt dem Inhalt des Auftrags. Beide Issues wurden unverändert gelassen.

Die früheren Ansätze sind in `SCHOOL_NOTIFICATIONS.md`,
`SCHOOL_NOTIFICATIONS_OPT_IN.md` und
`SCHOOL_NOTIFICATIONS_DEVICE_TESTS.md` dokumentiert. Frühere Build-/Testnachweise
sind keine Nachweise für die Zustellung mit dieser neuen Version.

## 1. Was die Referenz tatsächlich verwendet

Der vollständige relevante Weg wurde anhand folgender Dateien untersucht:

- `digitales_register/lib/background_check.dart`: Dispatcher, Planung,
  gespeicherte Konten, Vordergrundmarkierung, Abruf, Baselines und Speicherung.
- `digitales_register/lib/system_notifications.dart`: Plugininitialisierung,
  Systemberechtigung, Anzeigen, Kontogruppen, Rücknahme und Tap-Payloads.
- `digitales_register/lib/services/system_notification_service.dart`: Verbindung
  mit Einstellungen, Berechtigungen, Appstart und Navigation nach einem Tap.
- `digitales_register/lib/notification_type.dart`: tatsächlich unterstützte
  Portaltypen einschließlich `messageShared` und Normalisierung der Schreibweise.
- `digitales_register/lib/providers/notifications_provider.dart`,
  `lib/middleware/login.dart` und `lib/middleware/middleware.dart`: im Vordergrund
  bekannte IDs sowie Setzen/Entfernen des verwendeten Kontos beim Lifecyclewechsel.
- `digitales_register/lib/ui/settings/pages/notification_settings_page.dart`,
  `lib/providers/settings_provider.dart`, `pubspec.yaml`, Android-Manifest und
  `lib/wrapper.dart`: Einstellungen, Abhängigkeiten, Plattform und Authentifizierung.

Die Referenz registriert unter Android einen eindeutigen periodischen
WorkManager-Auftrag mit Netzwerkbedingung und `ExistingPeriodicWorkPolicy.update`.
Der einstellbare Abstand wird auf mindestens 15 Minuten begrenzt. Es gibt keinen
dauerhaften Foreground Service und keinen eigenen AlarmManager-Pollingdienst.

Ein Lauf startet eine separate Flutter-Engine. Der Dispatcher stellt die
Dart-Pluginregistrierung ausdrücklich sicher. Der Worker liest Einstellungen und
gespeicherte Zugangsdaten neu ein, verarbeitet Konten nacheinander, meldet sich
jeweils mit einer eigenen Sitzung an und ruft `api/notification/unread` ab.
Für Hausaufgaben fragt die Referenz zusätzlich zwei Kalenderwochen ab.

Das aktuell in der sichtbaren App verwendete Konto wird ausgelassen. Seine
Markierung enthält die Prozess-ID, damit eine hinterlassene Markierung aus
einem beendeten Prozess nicht eine neu gestartete Hintergrund-Engine blockiert.
Das ist auch für Schulserver relevant, die eine Sitzung beim erneuten Login
beenden können. Die Vordergrund-App merkt sich selbst geladene IDs.

Beim ersten Abruf wird der vorhandene ungelesene Bestand still als bekannt
gespeichert. Spätere unbekannte und aktivierte Einträge werden über
`flutter_local_notifications` angezeigt und nach Konto gruppiert. Nicht mehr
ungelesene Einträge werden zurückgenommen. Ein Tap führt über das gespeicherte
Konto zur passenden Ansicht. Fehler eines Laufs werden in der Referenz abgefangen;
der nächste periodische Lauf ist ihr Wiederholungsmechanismus.

Die Referenz hält keinen Dart-Prozess ständig am Leben. Android verwaltet den
persistierten Arbeitsauftrag und startet die Engine bei einer erlaubten
Ausführung erneut. WorkManager plant Arbeit auch nach Prozessende und Neustart
neu; Doze wird dabei respektiert. Das erklärt die Eignung dieser Architektur,
garantiert aber keine minutengenaue oder sofortige Zustellung.
Siehe [Android: persistente Hintergrundarbeit](https://developer.android.com/develop/background-work/background-tasks/persistent).

Die praktische Zuverlässigkeit der Referenz wurde vom Auftraggeber berichtet.
In dieser Sitzung wurde auch die Referenz nicht auf einem Gerät getestet.

## 2. Unterschiede und nachvollziehbare Ausfallpfade

| Bereich | Vorher in unserer App | Referenz / neue Umsetzung |
| --- | --- | --- |
| Hintergrund-Plugin | Binding initialisiert; keine ausdrückliche Registrierung der Dart-Notification-Implementierung im Dispatcher | Plattform-Plugin vor dem Erzeugen des Services registrieren |
| Periodischer Auftrag | `keep`, zusätzlich 15 Minuten Startverzögerung | Unter Android `update`, keine zusätzliche Startverzögerung |
| Kontowechsel | Auftrag bei Deaktivierung auch für einen Wechsel abbrechen | Auftrag während des Wechsels erhalten; neue Aktivierung aktualisiert ihn |
| Sichtbare App | Dauerhafter Zeitstempel; native Prüfung teilweise Prozesspriorität bzw. konstant `true` | Prozessgebundener Lifecyclezustand, vor Login und Commit neu prüfen |
| Mitteilungstypen | Nur exakt `message` und `grade` | Groß-/Kleinschreibung normalisieren; `messageShared` der vorhandenen Mitteilungskategorie zuordnen |
| Mehrere Schulen | Alle zusammen höchstens 20 Sekunden Netzbudget | Android bis zwei Minuten pro Runde, höchstens 20 Sekunden je Konto; iOS bleibt bei 20 Sekunden insgesamt |
| Verspäteter Worker | Sitzungs-/Kontoprüfung, aber keine Prüfung seines eigenen Lease-Werts vor Commit | Zusätzlich prüfen, ob die Verarbeitungssperre noch dem zurückkehrenden Worker gehört |

Die eingesetzte Version `flutter_local_notifications 22.3.2` wählt die mobile
Dart-Implementierung nicht mehr im Plugin-Konstruktor selbst aus. Fehlt die
Registrierung in einer Engine, kann die Auflösung des Android-Plugins `null`
liefern; dann erreicht ein Initialisierungs-/Anzeigeaufruf keine native Seite.
Der neue Regressionstest stellt genau diesen Zustand mit dem echten
Plugin-Frontend her und weist nach der Registrierung echte Methodenaufrufe
auf dem simulierten nativen Kanal nach. Er verwendet keinen gemockten
`FlutterLocalNotificationsPlugin` für diesen Nachweis.

Das ist ein nachgewiesener Ausfallpfad bei fehlender Registrierung, aber kein
Gerätenachweis dafür, dass genau dieser Pfad jeden bisherigen Ausfall verursacht
hat. Automatische Registrierung hängt auch vom Engine-/Flutter-Startpfad ab.
Die explizite Registrierung beseitigt diese Abhängigkeit für das Anzeigeplugin.

Weitere plausible Ursachen waren die wiederholte Verschiebung des ersten Jobs
nach Kontowechseln, falsche Vordergrundklassifizierung und das vollständige
Übersehen geteilter Mitteilungen. Frühere Probleme mit langen Netzoperationen
innerhalb der SQLite-Sperre waren bereits behoben. Dieser Schutz bleibt bestehen.

## 3. Neue technische Aufteilung

```text
Bestehende Einstellungen / Kontenaktivierung
    -> SchoolNotificationScheduler
    -> eindeutiger WorkManager-Auftrag (Android) / BGAppRefresh (iOS)
    -> schoolNotificationDispatcher + mobile Dart-Pluginregistrierung
    -> Konten-/Berechtigungs-/Lifecycleprüfung unter kurzer Speichersperre
    -> SchoolNotificationFeedClient: eigenes HTTPS-Login + Ungelesen-Feed
    -> erneute Sitzungs-/Konten-/Lease-/Lifecycleprüfung
    -> bestehende Engine und verschlüsselte Ereignishistorie
    -> generische, nach Konto/Kategorie gruppierte Systembenachrichtigung
```

`lib/school_notification_background.dart` enthält nun den eigenständigen
Scheduler, den Pluginstart, die prozessgebundene Markierung und einen von der
Oberfläche unabhängigen API-Client. Dieser verwendet die vorhandenen Endpunkte
aus `school_api_endpoints.dart`, eine eigene Cookie-Sitzung je Konto und Lauf,
begrenzte Requests und einen abbrechbaren Gesamtzeitrahmen. Danach werden Client
und Cookies freigegeben. Der UI-Wrapper wird nicht instanziiert: Seine
Vordergrundsperren, Dialoge und Sitzungstimer passen nicht in eine headless Engine.

Die Referenz nutzt `DartPluginRegistrant.ensureInitialized()`. Hier werden die
Android-/iOS-Notification-Implementierungen gezielt mit `registerWith()` gesetzt.
Das übernimmt den erforderlichen Effekt für das Anzeigeplugin, ohne die für
Nebenisolates vorgesehene API auf dem Root-Isolate einer eigenen Engine aufzurufen.
Die übrige native Pluginregistrierung der Flutter-Engine bleibt erhalten.
Siehe [Flutter: Registrant-API](https://api.flutter.dev/flutter/dart-ui/DartPluginRegistrant/ensureInitialized.html).

`SchoolNotificationVisibility` registriert Activity-Lifecyclecallbacks in der
Application. UI- und Worker-Engine lesen denselben flüchtigen Zustand. Der
Notification-Wrapper prüft ihn noch einmal unmittelbar beim nativen `show`.
Die Worker-spezifische Kanalregistrierung gehört jetzt zur App und wird über den
vorhandenen `BackgroundEngineConfigurator` installiert, statt im allgemeinen
WorkManager-Paket eine App-spezifische Prozessprioritätsprüfung einzubauen.

## 4. Bewusste Anpassungen an unsere App

Die Oberfläche, Navigation, bestehenden Schalter, vier Sprachen, freiwillige
Zustimmung und Datenschutzdarstellung wurden nicht verändert. Noten- und
Mitteilungsschalter gelten auch für die normalisierten Portaltypen.

Aus der Referenz wurden keine Zugangsdaten, Schlüssel, Paketkennungen oder
projektspezifischen Konfigurationen übernommen. Neue Abhängigkeiten waren nicht
erforderlich. Die bestehenden WorkManager-Forks bleiben wegen der eigenen
Engine-/iOS-Lifecycleintegration und des passenden Plattform-Codecs erhalten.

Folgende vorhandenen Eigenschaften werden bewusst weiterverwendet:

- verschlüsselte, durch Kontohash getrennte Ereignishistorie;
- kurze SQLite-Transaktion als Sperre zwischen verschiedenen Engines;
- gespeicherte explizite Zustimmung je Konto sowie vorhandene Kategorieoptionen;
- stille erste Baseline und stille Baselines nach Wiederaktivierung;
- dauerhaft gespeicherte Ereignisidentitäten statt nur der zuletzt ungelesenen IDs;
- Speichern der Anzeigeansprüche vor dem Systemaufruf gegen doppelte Auslösung;
- generische Inhalte und Payloads ohne Namen, Schuladresse, Notenwerte oder Texte;
- Ablehnen verspäteter Antworten nach Logout, Kontowechsel, geänderten
  Zugangsdaten, Berechtigungen oder zwischenzeitlichem Vordergrundabruf.

Die Referenz zeigt detailliertere Inhalte und bietet mehr Ereigniskategorien.
Ihre zusätzlichen Kalenderabfragen, Hausaufgabenanzeigen und Testbedienelemente
wurden nicht übernommen, weil unsere vorhandenen Optionen Noten und Mitteilungen
abdecken und die Oberfläche unverändert bleiben soll.

Bei Netzwerkfehlern verwenden wir weiterhin exponentielle Android-Wiederholungen
ab einer Minute. Ein Konto mit erforderlicher interaktiver Authentifizierung
wird bis zu einer neuen App-Sitzung pausiert. Andere Konten werden unabhängig
weiter geprüft. Fehlerdiagnosen enthalten feste Kategorien, keine Requestdaten.

Die Duplikatstrategie bleibt „höchstens einmal angefordert“: Ein Prozessabbruch
zwischen gespeicherter Beanspruchung und Systemaufruf kann eine Anzeige verlieren.
Eine atomare Transaktion über verschlüsselten Speicher und Androids
NotificationManager existiert nicht. Eine erfolgreiche Systemanforderung beweist
auch weiterhin keine sichtbare Anzeige.

## 5. Android: Berechtigungen, Dienste und Verhalten

Der gebaute Debug-Manifest wurde zusätzlich geprüft. Für den Ablauf relevant sind
`INTERNET`, `POST_NOTIFICATIONS`, `ACCESS_NETWORK_STATE`, `WAKE_LOCK`,
`RECEIVE_BOOT_COMPLETED` und `VIBRATE`. Die bestehenden App-Berechtigungen für
Biometrie, Kalender usw. bleiben davon unabhängig.

Der zusammengeführte Manifest enthält
`androidx.work.impl.background.systemjob.SystemJobService`, geschützt durch
`BIND_JOB_SERVICE`, und WorkManagers `RescheduleReceiver` für `BOOT_COMPLETED`.
Der Receiver ist in der Bibliotheksdeklaration zunächst deaktiviert; WorkManager
verwaltet seine Aktivierung, sobald Arbeit eingeplant wird. Es wurde kein
zusätzlicher eigener Bootreceiver eingeführt.

Die WorkManager-Bibliothek bringt außerdem `FOREGROUND_SERVICE` und den nicht
exportierten `SystemForegroundService` im zusammengeführten Manifest mit.
Unser Polling ruft weder `setForeground()` noch einen dauerhaften Dienst auf.
Die bloße Deklaration dieses Bibliotheksdiensts ist kein dauerhaft laufender
Foreground Service. Es werden keine direkten Batterieausnahmen angefordert.

| Gerätezustand | Implementiertes Verhalten | Aktueller Nachweis |
| --- | --- | --- |
| App sichtbar | Vor Anmeldung überspringen; Vordergrunddaten still verarbeiten; letzte native Anzeigesperre | Automatisierte Dart-/Kanaltests; nativer Code kompiliert |
| App im Hintergrund | Vorhandenen eindeutigen Auftrag ausführen, wenn Android Zeit und Netz erlaubt | Ablauf automatisiert mit API-Fixtures; keine Geräteanzeige |
| Bildschirm gesperrt | Derselbe Workerpfad, sofern Lifecycle, Netz und geschützter Speicher zugänglich sind | Gerätetest offen |
| Aus letzter-App-Liste entfernt / normaler Prozess beendet | Arbeitsauftrag bleibt persistent; neue Engine kann ohne UI starten | Architektur und Build geprüft; Gerätetest offen |
| Geräteneustart | WorkManager plant persistierte Arbeit nach Boot neu; Speicherzugriff ggf. erst nach Entsperren | Manifest geprüft; echter Neustart offen |
| Lange Inaktivität / Doze / OEM-Energiesparen | Ausführung kann stark verzögert werden; Identitäten bleiben gespeichert | Automatisierte Historientests; Langzeitgerätetest offen |
| „Stopp erzwingen“ | Keine Zustellzusage; Nutzer muss App gewöhnlich wieder öffnen | Negativtest auf Gerät offen |

Die geplante Frequenz beträgt 15 Minuten; die erste Android-Ausführung bekommt
keine zusätzliche Verzögerung. Android entscheidet über die tatsächliche Zeit.
`update` erhält den bisherigen Einplanungszeitpunkt und unterbricht einen
laufenden Job nicht. Siehe [Android: UPDATE](https://developer.android.com/reference/androidx/work/ExistingPeriodicWorkPolicy)
und [periodische Requests](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work).

## 6. iOS

BGAppRefresh-Registrierung vor Ende des Appstarts, `fetch`-Modus, erlaubte
Taskkennung, native Pluginregistrierung, Expiration-Behandlung und
Keychain-Konfiguration nach erstem Entsperren bleiben bestehen. Der gemeinsame
API-Client, die Kontoprüfungen und Ereignishistorie werden wiederverwendet.
Auch iOS registriert sein Dart-Notification-Plugin jetzt ausdrücklich und prüft
den nativen Vordergrundzustand vor der Hintergrundanmeldung.

Das Gesamtzeitfenster bleibt dort bei 20 Sekunden. Die 15 Minuten sind nur eine
früheste Planungsabsicht, keine zugesicherte Pollingfrequenz. iOS kann Zeitfenster
verweigern, verschieben oder beenden. Ohne Hintergrundaktualisierung, vor der
ersten Entsperrung oder nach Force-quit kann Arbeit ausbleiben.

Die Referenz aktiviert ihren untersuchten Systembenachrichtigungsweg nur unter
Android; aus ihr ergibt sich kein zusätzlicher iOS-Zuverlässigkeitsnachweis.
Ein Xcode-/iOS-Build und reale iPhone-Zustellung sind in dieser Windows-Sitzung
nicht möglich und werden nicht als geprüft ausgewiesen.

## 7. Geänderte Dateien

| Datei | Änderung |
| --- | --- |
| `lib/school_notification_background.dart` | Neuer Scheduler, Pluginstart, Prozessmarkierung und eigener Feedclient |
| `lib/school_notification_service.dart` | Integration, Auftrag beim Wechsel erhalten, native Lifecycleprüfung, Budgets, Lease- und Diagnoseabsicherung |
| `lib/school_notification_engine.dart` | Gemeinsame Erkennung von `messageShared` und normalisierten Typen |
| `android/app/src/main/kotlin/it/bucci/digitalesregister/SchoolNotificationVisibility.kt` | Flüchtige native Activity-Sichtbarkeit |
| `android/app/src/main/kotlin/it/bucci/digitalesregister/PrivacyApplication.kt` | Lifecyclecallbacks und Kanal für Worker-Engines |
| `android/app/src/main/kotlin/it/bucci/digitalesregister/MainActivity.kt` | Sichtbarkeit statt konstantem Vordergrundwert |
| `android/app/src/main/kotlin/it/bucci/digitalesregister/SchoolLocalNotificationsPlugin.kt` | Letzte Anzeigesperre nach tatsächlicher Activity-Sichtbarkeit |
| `packages/workmanager_android/android/src/main/kotlin/dev/fluttercommunity/workmanager/BackgroundWorker.kt` | App-spezifischen Kanal in den App-Configurator verlagert |
| `test/school_notification_background_test.dart` | Echte Dart-Pluginaufrufe, Scheduler, Cookies, Prozessmarkierung und Fehlerbereinigung |
| `test/school_notification_service_test.dart` | Zusätzliche Lifecycle-, Kontowechsel-, Budget-, Feed- und Lease-Regressionen |
| `test/school_notification_engine_test.dart` | Geteilte Mitteilungen und Kategorie-/Duplikatverhalten |
| `tool/check_school_notification_config.py` | Taskkennung aus neuem Modul; optionale Prüfung des gebauten Manifests |
| `analysis_options.yaml` | Referenzcheckout von der Analyse unseres Pakets ausgeschlossen |
| `docs/SCHOOL_NOTIFICATIONS.md` | Architekturstand aktualisiert |
| `docs/SCHOOL_NOTIFICATIONS_DEVICE_TESTS.md` | Geräteszenarien für die neue Architektur ergänzt |
| `docs/SCHOOL_NOTIFICATIONS_REFERENCE_REBUILD.md` | Dieser Vergleichs- und Abschlussbericht |

Weder App-Manifest noch Pubspec mussten neue Dienste oder Abhängigkeiten erhalten:
Die erforderlichen Standarddienste werden bereits durch WorkManager eingebunden.
Die Buildprüfung kontrolliert deren tatsächliches Vorhandensein im Ergebnis.

## 8. Verifikation und noch offene Qualifikation

Die lokalen Test-/Buildresultate sind unten festgehalten. Die neuen Tests prüfen
unter anderem fehlende Dart-Registrierung,
Methodenaufrufe bis `show`, Netzwerkbedingungen und Updatepolitik, isolierte
Cookie-Sitzungen, alte Prozessmarkierungen, Kontowechsel ohne Jobabbruch,
Weiterarbeit anderer Schulen bei Timeout sowie Ablehnen überholter Worker.

API- und Lifecycle-Kanaltests verwenden kontrollierte Fixtures bzw. simulierte
native Antworten. Sie bestätigen weder eine Anmeldung an einem echten
Schulserver noch native OS-Ausführung oder eine sichtbare Benachrichtigung.

`adb devices -l` zeigte kein verbundenes Gerät. Es war auch kein Android-AVD
eingerichtet. Erforderlich bleiben echte neue Noten und direkte/geteilte
Mitteilungen nach der Baseline: im Hintergrund, bei gesperrtem Bildschirm, nach
Wegwischen, normalem Prozessende, Reboot/Entsperrung und über längere Doze-/OEM-
Inaktivität. Dazu gehören Kontowechsel, Logout, verweigerte Rechte, blockierte
Kanäle, Offlinephasen und die signierte Release-Version einschließlich R8.

| Plattform | Implementiert | Lokal automatisiert geprüft | Auf Gerät nachgewiesen |
| --- | --- | --- | --- |
| Android | Referenzmechanismus mit persistentem WorkManager, separater Engine, eigenem Login und lokaler Anzeige; vorhandene Datenschutz-/Kontoschutzregeln integriert | Dart-/Kanaltests, komplette Suite, Analyse, Debug-/Release-APK und Manifestprüfung; Einzelresultate unten | Nein; alle tatsächlichen Zustellszenarien offen |
| iOS | Bestehendes BGAppRefresh erhalten; gemeinsame Client-/Plugin-/Kontoverarbeitung angepasst | Gemeinsame Dart-Tests, iOS-Dart-Pluginregistrierung und statische Konfigurationsprüfung | Nein; zusätzlich Xcode-/Signierungsbuild offen |

Die Umsetzung ist damit lokal implementiert und prüfbar. Eine zuverlässige
Hintergrundzustellung auf konkreten Geräten ist noch nicht qualifiziert.

### Ergebnisse des Abschlusslaufs

- `flutter test --no-pub --reporter expanded`: **1.312 Tests bestanden**, zwei
  bestehende Tests übersprungen. Protokoll: `build/notification_full_tests.log`.
- `flutter analyze --no-pub`: **keine Befunde**.
  Protokoll: `build/notification_reference_analyze.log`.
- `flutter build apk --debug --no-pub`: **erfolgreich**.
  APK: `build/app/outputs/flutter-apk/app-debug.apk`.
  Protokoll: `build/notification_reference_android_build.log`.
- `flutter build apk --release --no-pub`: **erfolgreich**, einschließlich
  AOT-/Releaseverarbeitung und Codeverkleinerung.
  APK: `build/app/outputs/flutter-apk/app-release.apk` (87,1 MB laut Flutter).
  Protokoll: `build/notification_reference_android_release.log`.
- `python tool/check_school_notification_config.py --merged-manifest
  build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml`:
  **alle Prüfungen bestanden**. Protokoll: `build/notification_reference_config.log`.
- Dieselbe Konfigurationsprüfung mit dem zusammengeführten **Release-Manifest**:
  **alle Prüfungen bestanden**.
  Protokoll: `build/notification_reference_release_config.log`.
- Androids `apksigner verify --verbose` für die neue Release-APK:
  **erfolgreich**. Protokoll: `build/notification_reference_signature.log`.
- `git diff --check`: **erfolgreich**.

Die lokal erzeugten APKs wurden mangels Gerät nicht installiert. Die genannten
Protokolle und APKs liegen im ignorierten Buildverzeichnis und gehören nicht zu
den Quellcodeänderungen.
