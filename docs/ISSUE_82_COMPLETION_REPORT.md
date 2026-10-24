# Digitales Register — Abschlussbericht zu Issue #82

**Stand:** 25.10.2026 (Bearbeitung 24.–25.10.2026). **Arbeitsbranch:** bestehender `main`.
Keine Branch-Erstellung, keine Commits, kein Push, kein Pull Request und keine
Änderung des Issue-Status. Alle Änderungen liegen lokal zur Prüfung vor.

## A. Zusammenfassung

Die vorhandene Implementierung wurde untersucht und erweitert. Der konkrete
App-Start-Fehler ist behoben: Vordergrundabrufe speichern neue Ereignisse und
aktualisieren den In-App-Feed, ohne daraus Systembenachrichtigungen zu erzeugen.
Hintergrundabrufe dürfen nach erfolgreicher Authentifizierung und Prüfung des
aktuellen Account-/App-Zustands lokale Benachrichtigungen anfordern.

Die Umsetzung bleibt vollständig clientseitig und verwendet die vorhandenen
Schulendpunkte. Die bestehende Ereignis-Engine, verschlüsselte Hive-Historie,
SQLite-Sperre und WorkManager-Infrastruktur wurden weiterverwendet. Ergänzt
wurden insbesondere Account-spezifische Optionen, mehrere gespeicherte Accounts,
ein dauerhaftes Worker-Lease, gebündelte Benachrichtigungen, native Schutzpfade
gegen Vordergrundanzeigen und eine verständliche Hintergrunddiagnose.

**Ergebnis:** lokal implementiert und automatisiert geprüft. Android und Windows
kompilieren. Der iOS-Code und seine Task-Konfiguration sind implementiert, aber
hier nicht mit Xcode kompiliert oder auf einem iPhone ausgeführt. Eine belegte
Produktionsfreigabe der Hintergrundzustellung ist damit noch nicht erreicht.

## B. Tatsächlich gefundene Probleme

1. **Startabruf konnte Systembenachrichtigungen auslösen.**
   `middleware/notifications.dart` übergab den beim Login/Öffnen geladenen Feed an
   `SchoolNotificationService.ingest`. Dieser Pfad benutzte dieselbe Zustelllogik
   wie ein Hintergrundabruf. Es gab keinen eindeutigen Ausführungskontext, der
   Systemanzeigen beim Öffnen ausschloss. Ein erstmalig auf dem Gerät erkanntes,
   ausreichend neues Schulereignis konnte dadurch gerade beim Start erscheinen.
2. **Heartbeat allein verhinderte dieses Verhalten nicht.** Er wurde vom Worker
   zum Überspringen aktiver UI-Sitzungen verwendet, nicht vom Vordergrundabruf
   selbst. Außerdem blieb zwischen Dart-Prüfung und nativem `show` eine Lücke.
3. **Keine Begrenzung auf sinnvolle Gruppen.** Der Zustellpfad zeigte jedes neue
   Ereignis einzeln. Große Batches konnten viele einzelne Anzeigen erzeugen.
4. **Unzureichend getrennte Diagnose.** Ein gemeinsamer letzter Abgleich sagte
   nicht aus, ob ein Hintergrundlauf gestartet, erfolgreich abgeschlossen oder
   eine Systemanzeige lediglich angefordert worden war.
5. **Grobe Bereinigung mit `cancelAll`.** Einstellungen und Accountübergänge
   entfernten sämtliche über das Plugin verwalteten App-Benachrichtigungen.
   Ein eigener, auf persönliche Schulereignisse begrenzter Filter fehlte.
   Jetzt werden zusätzlich ausschließlich selbst eingereichte persönliche IDs
   zur gezielten Bereinigung festgehalten, falls ein Desktop-Plugin keine
   verwertbaren Payloads aus der Liste aktiver Anzeigen zurückliefert.
6. **Nur der aktive primäre Account wurde im Hintergrund geprüft.** Andere
   gespeicherte, bereits verwendete Schulaccounts wurden nicht mitverarbeitet;
   die Kategorien-Einstellungen waren global.
7. **Netzwerkabrufe konnten sich zwischen Engines überschneiden.** Die bestehende
   SQLite-Sperre schützte Commit/Historie, aber nicht das gesamte ausgelagerte
   Netzwerkfenster. Ein dauerhaftes Lease für denselben Account fehlte.
8. **iOS-Abbruchpfad der verwendeten Abhängigkeit war unvollständig.**
   `BackgroundTaskOperation.main` wartete auf ein Semaphor. Das normale Cancel
   entblockte dieses Warten und die laufende Engine nicht zuverlässig. Zudem
   meldete der BGTask-Abschluss Erfolg anhand von `!isCancelled`, statt den
   Dart-Ausgang zu berücksichtigen. Fehlende Callback-Konfiguration konnte ohne
   `setTaskCompleted` zurückkehren.
9. **iOS-Scheduling verschluckte Fehler.** Der Dart-Aufrufer konnte Erfolg sehen,
   obwohl das native Submit fehlgeschlagen war. Wiederholtes Einplanen konnte
   außerdem einen bereits ausstehenden frühesten Start verschieben.
10. **Die Notenübersicht setzte einen zu groben lokalen Angesehen-Zustand.**
    Bereits das Öffnen der Übersicht unterdrückte alle bekannten Notenereignisse
    als angesehen. Dieser Aufruf wurde entfernt; konkrete Detail-/Leseaktionen
    bleiben die dafür vorgesehenen Pfade.

Die Hintergrundarchitektur war vor dieser Überarbeitung bereits vorhanden.
Es wäre falsch zu behaupten, dass grundsätzlich kein Worker registriert gewesen
sei. Die konkrete Ursache einer unterbliebenen Ausführung auf einem bestimmten
Gerät — etwa OS-Aufschub, Berechtigung oder Anmeldung — kann ohne dieses Gerät
nicht bewiesen werden. Die neue Diagnose macht diese Fälle unterscheidbarer.

## C. Technische Änderungen und Dateien

| Datei/Bereich | Funktion und wesentliche Änderung |
|---|---|
| `lib/school_notification_engine.dart` | Ruhiger Vordergrundkontext, Batch-Übergabe, zusätzliche Zustandsmetadaten; bestehende Baselines, Hash-Identitäten und vorab persistierte Claims bleiben erhalten. |
| `lib/school_notification_service.dart` | Gemeinsame Verarbeitung, Lifecycle-Schutz, accountbezogene Optionen, gespeicherte Accounts, Lease, Budget/Fairness, feste Fehlerkategorien, Diagnose, Filterbereinigung, gruppierte Anzeige und sichere Zielauflösung. |
| `lib/school_api_endpoints.dart` | Gemeinsamer Vertrag für `/v2/`, Login und vorhandenen Unread-Feed. |
| `lib/wrapper.dart`, `lib/middleware/notifications.dart` | Dieselben gemeinsamen Endpunktdefinitionen; UI-Feed wird weiterhin über vorhandenes Middleware-/Cache-System geladen. |
| `lib/middleware/middleware.dart` | Import der gemeinsamen Endpunkte für die Middleware-Teile. |
| `lib/middleware/login.dart` | Accountwechsel erhält die Einrichtung anderer Accounts; Accountlöschung entfernt Notification-Daten und widerruft späte Antworten. |
| `lib/middleware/routing.dart` | Öffnen der Notenübersicht bedeutet nicht mehr automatisch „alle Notenereignisse angesehen“. |
| `lib/main.dart` | Kalte/warme Ziele weiter validieren; fremden gespeicherten Account über normalen Anmeldeweg auswählen; manuelle Folgewechsel überschreiben das Ziel. |
| `lib/ui/school_notification_settings.dart` | Hauptschalter, Kategorien, Account-/Schulbezug, Zähloption; aufklappbarer Bereich für Hintergrundstatus, Zeitpunkte und Systemeinstellungen. |
| `assets/locales/{de,en,it,lld}.json` | Überarbeitete Einzel-/Mehrzahltexte, Datenschutz, Accountbezug, Diagnose und Fehlerzustände in allen vier Sprachen. |
| `android/.../MainActivity.kt` | Native Bereinigung persönlicher Alerts beim Resume; echte WorkManager-Abfrage, Energie-/Kanaldiagnose und freiwillige Systemeinstellungen. |
| `android/.../SchoolLocalNotificationsPlugin.kt` | Unterklasse des vorhandenen Plugins; persönliche Anzeigen werden unmittelbar im nativen `show` bei Vordergrundprozess unterdrückt. Sonstige Plugin-Funktionen werden delegiert. |
| `android/.../PrivacyApplication.kt` | Installiert denselben Plugin-Schutz auch in der headless Engine. Bestehende Datenschutzinitialisierung bleibt bestehen. |
| `packages/workmanager_android/.../BackgroundEngineConfigurator.kt` | Kleiner App-Hook nach automatischer Plugin-Registrierung im Worker. |
| `packages/workmanager_android/.../BackgroundWorker.kt` | Headless-Hook, native Sichtbarkeitsabfrage, Schutz gegen doppelte/späte Abschlüsse und saubere Engine-Freigabe bei Fehler/Stop. |
| `android/app/build.gradle` | Bereits verwendetes WorkManager `2.11.0` zusätzlich direkt für die native Diagnose verfügbar machen; keine neue Hintergrundtechnik. |
| `ios/Runner/AppDelegate.swift` | Lifecycle-Kanal auch headless, Filterbereinigung, Unterdrückung persönlicher Vordergrundanzeigen/-töne, native Refresh-/Schedulingdiagnose. |
| `packages/workmanager_apple/` | Lokale, lizenzierte Kopie der bereits verwendeten Version `0.9.1+2` mit korrigiertem Ablauf/Abbruch/Scheduling; Dart-API und Pigeon-Code unverändert. |
| `pubspec.yaml`, `pubspec.lock` | Lokaler Apple-Pfad; matching Platform Interface `0.9.1+1` bleibt fixiert. Keine unabhängige inkompatible Codec-Aktualisierung. |
| `test/school_notification_*`, `test/ui/school_notification_settings_test.dart` | Tests für neue Zustände, Hintergrund-/Vordergrundtrennung, Gruppen, Accountschutz, Fehler und Einstellungen. |
| `test/support/test_harness.dart` | Sicherer Speicher in Widget-Tests ist ebenfalls lokal ersetzt; kein Zugriff auf echten OS-Speicher beim frühen Lifecycle-Schutz. |
| `tool/check_school_notification_config.py` | Statische Konsistenzprüfung von Task-ID, nativer Registrierung, Background Mode, Berechtigungen, Fork-Auswahl und Sprachkatalogen. |

`AndroidManifest.xml` und `Info.plist` enthielten die benötigten grundlegenden
Einträge bereits. Sie wurden geprüft, nicht unnötig um weitere Berechtigungen
erweitert. Die im Debug-APK zusammengeführte Manifest-Konfiguration wurde
zusätzlich kontrolliert.

## D. Android

Ein eindeutig benannter WorkManager-Auftrag wird mit Netzwerkanforderung,
15 Minuten Intervall und anfänglicher Verzögerung registriert. Die Keep-Strategie
verhindert ständiges Ersetzen. Transiente Fehler geben Misserfolg an den Worker
zurück; dieser fordert einen Retry mit exponentiellem Backoff ab einer Minute an.
Der Scheduler entscheidet über den tatsächlichen Zeitpunkt.

Der Worker startet eine eigene Flutter-Engine mit registrierten Plugins und liest
Accountdaten aus dem vorhandenen sicheren Speicher. Keine sichtbare Activity,
kein Redux-Store und keine UI-Anmeldung sind für diesen Pfad erforderlich. Diese
Unabhängigkeit ist im Code und in Fixture-Tests geprüft; eine echte headless
Ausführung auf einem Telefon wurde hier nicht beobachtet.

Persistierte Arbeit überlebt normale Prozessbeendigung und Geräte-Neustart,
soweit Android sie ausführen darf. Doze, eingeschränkte Hintergrundaktivität,
Herstellerregeln, fehlendes Netz, Force-stop oder fehlender Zugang zu sicherem
Speicher können Prüfungen verzögern oder verhindern. Eine 15-Minuten-Garantie
wird ausdrücklich nicht gegeben. Die App fordert keine direkte Akku-Ausnahme
an, verändert keine Systemeinstellung und verwendet keinen dauerhaft laufenden
Foreground Service. Details entsprechen den offiziellen
[WorkManager-Intervallgrenzen](https://developer.android.com/reference/androidx/work/PeriodicWorkRequest)
und [Doze-Regeln](https://developer.android.com/training/monitoring-device-state/doze-standby).

Die native Plugin-Unterklasse schließt das Anzeige-Rennen auf der Main Queue:
Ist die App bereits im Vordergrund, wird ein persönliches `show` nicht an den
NotificationManager weitergegeben. Eine zuvor rechtmäßig im Hintergrund
angeforderte Anzeige wird beim nativen Resume bereinigt. Der OS-Wechsel selbst
kann keine allgemeine Exactly-once- oder Sichtbarkeitsgarantie ermöglichen;
dieser Übergang ist ausdrücklich Teil der Gerätetests.

## E. iOS

`BGAppRefreshTask` bleibt der gewählte Mechanismus. Task-ID, `fetch`, Registrierung
vor Ende des App-Starts und Callback zur Pluginregistrierung sind vorhanden.
Der native Lifecycle-Kanal wird im UI- und Hintergrundkontext eingerichtet.
Der Notification-Delegate unterdrückt persönliche Vordergrundanzeigen und deren
Ton; normale Hintergrundbenachrichtigungen behalten die OS-konforme Darstellung.

Der lokale Apple-Fork beendet bei Expiration die headless Flutter-Engine auf der
Main Queue, entblockt die Operation und ignoriert verspätete Callbacks. Der
Abschluss berücksichtigt Dart-Erfolg bzw. Cancel; fehlende Callback-Konfiguration
meldet Misserfolg. Ausstehende Tasks werden beim erneuten Einrichten beibehalten,
und anfängliche Submit-Fehler gelangen bis zur Dart-Diagnose.
Das Deaktivieren hebt ausstehende Arbeit auch dann auf, wenn Background App
Refresh gerade gesperrt ist; die Verfügbarkeitsprüfung blockiert keine Abmeldung.

Der Earliest-begin-Hinweis von 15 Minuten ist kein Ausführungstakt.
[Apple überlässt den Laufzeitpunkt dem System](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app).
Force-quit, deaktiviertes Background App Refresh und Energiesparen können die
Verarbeitung unterbinden. Ein eigenes Backend ohne Schulereignisse behebt diese
Grenze nicht. Apple-Komponenten wurden hier statisch auf Konsistenz geprüft;
**Swift-Kompilierung, Task-Expiration und Gerätezustellung bleiben unbestätigt**.

## F. Ereigniserkennung, Zustände und Deduplication

1. Die Server-/Benutzerkombination erzeugt einen eigenen SHA-256-Namensraum.
2. Der vorhandene Feed liefert `grade` oder `message`, möglichst mit Objekt-ID.
   Feed-IDs werden als Aliase berücksichtigt. Ohne stabile ID bleibt der
   konservative Typ-/Zeitstempel-Fallback.
3. Der erste gültige Abgleich legt den Ausgangsbestand ohne Anzeige fest.
   Wiederaktivieren und neue Berechtigung stellen passende Baselines neu auf.
4. Identitäten werden gegen die dauerhafte Historie geprüft. Reihenfolge,
   Formatierung, Titeländerung und neue Feed-ID desselben Objekts erzeugen kein
   neues Schulereignis.
5. Neue Beobachtungen speichern serverseitig gemeldete Sendezeit,
   erste Geräteerkennung, Speicherzeit und Präsentationsentscheidung.
   Die Sendezeit ist nicht als bewiesene Erstellungszeit der Note zu verstehen.
6. Lokales Ansehen/Bestätigen wird separat mit `locallyViewedAt` erfasst.
   Ein gemeldeter Server-Lesestatus ist ebenfalls ein anderer Zustand.
7. Für zulässige Hintergrundereignisse werden Claims gemeinsam geschrieben und
   geflusht, bevor der erste native Anzeigeversuch erfolgen kann.
8. Je Account/Kategorie wird der neue Batch als eine Benachrichtigung angefordert.
   Request-Zeit und erfolgreicher nativer Rückgabepunkt sind getrennte Diagnose-
   Informationen, keine bestätigte Zustellung.

SQLite schützt Änderungen zwischen Engines, ein Dart-Mutex innerhalb des Isolates.
Ein 45-Sekunden-Lease verhindert parallele Hintergrundauthentifizierung desselben
Accounts. Das Netzwerk hält die History-Sperre nicht. Späte Antworten müssen
Session, Account-Einrichtung, gespeicherte Anmeldung, Berechtigung, Vordergrund-
Heartbeat und letzten Abgleich erneut erfüllen. Gelöschte Accounts werden nicht
durch eine verspätete Antwort wiederangelegt.

**Bewusste Grenzen:** Identische Zeitstempel ohne IDs können Ereignisse
zusammenfassen. Änderungen bestehender Noten lösen ohne zuverlässige Server-
Versionssemantik keine neue Anzeige aus. Bereits anderswo gelesene/entfernte
Unread-Einträge sind nicht mehr erkennbar. Ein Absturz zwischen persistiertem
Claim und nativem Aufruf kann eine Anzeige verlieren; die Gegenentscheidung,
nachträglich zu claimen, könnte bereits angezeigte Meldungen wiederholen.
Exactly-once-Zustellung wird daher nicht behauptet.

## G. Benachrichtigungstexte und Datenschutzoption

| Fall | Vorher | Jetzt |
|---|---|---|
| Note, DE | „Neue Note“ / „Eine neue Note ist im Schulregister verfügbar.“ | „Neue Note“ / „Eine neue Bewertung wurde veröffentlicht.“ |
| Mitteilung, DE | „Neue Schulnachricht“ / „Du hast eine neue Nachricht von deiner Schule erhalten.“ | „Neue Schulmitteilung“ / „Du hast eine neue Mitteilung erhalten.“ |
| Mehrere Noten | Ein eigener Einzelaufruf pro Note | Standard: „Neue Noten“ / „Neue Bewertungen sind im Register verfügbar.“; optional z. B. „3 neue Noten“. |
| Mehrere Mitteilungen | Ein eigener Einzelaufruf pro Mitteilung | Standard: „Neue Schulmitteilungen“; optional z. B. „3 neue Schulmitteilungen“. |

Englisch, Italienisch und Ladinisch besitzen passende Einzel-/Mehrzahl- und
Diagnosetexte. Plural-Platzhalter werden katalogübergreifend geprüft; echte
Notification-Aufrufe werden in allen vier Sprachen getestet. Notenwerte, Fächer,
Absender und Mitteilungstexte bleiben verborgen. Nur die optionale Anzahl wird
zusätzlich gezeigt. Android verwendet private Sperrbildschirm-Sichtbarkeit und
normale Priorität. Eine muttersprachliche Ladinisch-Prüfung ist noch erforderlich.

## H. App-Lifecycle und Navigation

| Zustand | Implementiertes Verhalten |
|---|---|
| App-Start/Resume | Frühe Vordergrundbarriere; persönliche Alerts bereinigen; normalen Feed still aktualisieren. Kein automatisches Lesen durch App-Öffnung. |
| Aktiv im Vordergrund | Bestehender Feed/Glockenindikator aktualisiert sich; keine zusätzliche Systemanzeige. Der Timer prüft bei aktivierten Kategorien auch ohne Systemanzeige-Berechtigung. |
| Hintergrund | Berechtigter, wirklich ausgeführter Task darf neue Ereignisse gebündelt als Systembenachrichtigung anfordern. |
| OS beendet Prozess | Daten/Claims bleiben erhalten; spätere zulässige Taskausführung kann fortsetzen. Zeitpunkt ist OS-abhängig. |
| Force-stop/Force-quit | Keine Hintergrundgarantie und keine Umgehung. Bei Wiederöffnung stiller Abgleich und erneute Schedulingprüfung. |
| Neustart | Android persistierte Jobs/Boot-Empfänger; sichere Daten und iOS-Laufzeit erst verfügbar, wenn OS/Entsperrung dies erlauben. |
| Tap auf Einzelereignis | Account validieren; normale Anmeldung/Biometrie; Mitteilungs-ID oder Notenübersicht öffnen. |
| Tap auf Gruppe | Richtigen Account und zugehörige Kategorie-Liste öffnen. |
| Fehlender Account/Ereignis | Fehlender Account erhält lokalisierte Erklärung; gelöschte Mitteilungen fallen auf die bestehende Liste zurück. |
| Manueller Accountwechsel während Zielauflösung | Accountprüfung verhindert falsche Ansicht; ein weiterer Wechsel widerruft das noch wartende Notification-Ziel. |

Ein bereits laufender HTTP-Aufruf kann beim App-Wechsel nicht rückwirkend
ungeschehen gemacht werden. Alte Ergebnisse dürfen aber nicht in den neuen
Account übernommen werden; Anzeigeentscheidungen werden zusätzlich nativ geprüft.
Die konkrete Schulserver-Sessionsemantik bleibt ein Live-Testpunkt.

## I. Sicherheit und Datenfluss

Der Hintergrundpfad sendet ausschließlich den vorhandenen Login und den
Unread-Abruf direkt an den jeweils gespeicherten HTTPS-Schulserver. Redirects und
URLs mit eingebetteten Credentials/Query/Fragment werden abgelehnt. Es gibt in
diesem Pfad keinen Aufruf eines eigenen Backends und keinen Versand von Schul-
Credentials oder persönlichen Schulereignissen dorthin. Auch Firebase wird dafür
nicht initialisiert/verwendet.

Credentials liegen ausschließlich im vorhandenen sicheren Anmeldespeicher.
Keine Kopie wird in Work-Payloads, Notification-Payloads oder Diagnoseprotokollen
abgelegt. Das lokale Verlaufssystem speichert verschlüsselte Hashes und Zustände,
keine vollständigen Noten oder Nachrichtentexte. Payloads enthalten Version,
Account-Hash, Kategorie und gegebenenfalls Objekt-ID. Schul-/Accountnamen stehen
nicht in Systemanzeigen. Fehlermeldungen verwenden feste Kategorien.

Netzwerkfehler werden begrenzt behandelt. Abgelaufene Anmeldung/2FA/401/403
erfordern die App; dieselbe abgewiesene Sitzung wird nicht endlos neu angemeldet.
Ein neuer App-Login ermöglicht einen weiteren Versuch. Accountentfernung und
Logout wirken als Widerrufsbarrieren. Testdaten und Testspeicher sind lokal;
es wurden keine realen Schulzugangsdaten für Tests verwendet.

## J. Ausgeführte Prüfungen und Ergebnisse

| Befehl/Prüfung | Ergebnis |
|---|---|
| `flutter pub get --offline` | Erfolgreich, bestehende Dependencies aufgelöst; lokaler Apple-Fork ausgewählt. |
| `flutter test --no-pub --reporter expanded` | **1.262 bestanden, 2 übersprungen, 0 fehlgeschlagen.** |
| `flutter test --no-pub test/school_notification_engine_test.dart test/school_notification_service_test.dart test/ui/school_notification_settings_test.dart --reporter expanded` | **90 bestanden, 0 fehlgeschlagen.** Teilmenge des Gesamtlaufs, nicht hinzuzählen. |
| `flutter test --no-pub packages/workmanager_apple/test --reporter expanded` | **22 Dart-Tests bestanden.** Separater Abhängigkeitstest, kein Swift-Nachweis. |
| `flutter analyze --no-pub` | **Keine Probleme.** Plattformquellen werden nicht durch den Dart-Analyzer kompiliert. |
| `flutter build apk --debug --no-pub` | **Erfolgreich.** Native Android-Unterklasse, Worker und Diagnose kompilieren. |
| `android/gradlew.bat :workmanager_android:testDebugUnitTest --console=plain` | **7 Tests, 0 Fehler, 0 übersprungen.** Vorhandene native SharedPreferences-Helper-Tests. |
| `flutter build windows --debug --no-pub` | **Erfolgreich.** Desktop-Kompilierung, kein Nachweis mobilen Hintergrundverhaltens. |
| `python tool/check_school_notification_config.py` | **11 statische Konsistenzprüfungen bestanden.** |
| APK-Badging und gemergtes Manifest | Debug-Paket, `POST_NOTIFICATIONS`, Boot-Berechtigung, `SystemJobService`, `RescheduleReceiver` und Boot-Action bestätigt. |
| `git diff --check` | Erfolgreich. |
| UI-Vorschauen | Hell/Dunkel in vier Sprachen erzeugt; ausgewählte Vorschauen visuell geprüft. Große Schrift und Aufklapp-Diagnose automatisiert geprüft. |
| Angeschlossene Android-Geräte | `adb devices -l`: keine Geräte verbunden. |
| iOS/macOS/Linux-Builds, signierte Releases | Hier nicht durchgeführt; Windows bietet kein Xcode/iPhone. |

Die beiden übersprungenen Tests sind bestehende, nicht benachrichtigungsbezogene
Prüfungen: der native Linux-Dateiöffnungsdispatch auf Windows und die optionale
private Export-Vorschau ohne `EXPORT_REVIEW_INPUT`. Die bestehende Sprachkatalog-
Prüfung für alle Schlüssel/Platzhalter ist Teil des Gesamtlaufs.

Die neuen Tests behandeln unter anderem Vordergrund-Stille ohne falsches Lesen,
gezielte Alert-Bereinigung, große Batches, optionale Anzahl, Hauptschalter,
ungültige Feed-Einträge, unabhängige Diagnosezeiten, Offline/Timeout, Native-
Fehler, Authentifizierungspause, zwei Engines, Lease-Ablauf, mehrere Schulen,
Credential-Isolation, gelöschte Accounts während Abruf, Migration und Permission-
Neubaselines aller Accounts. Persistenz, umsortierte Daten, fehlende IDs,
Schreibfehler, Corruption, Cold-/Warm-Payloads und große Historien sind abgedeckt.

Während der Umsetzung gefundene und behobene Prüfprobleme: vier Widget-Timeouts
durch unersetzten sicheren Speicher in der Testumgebung; zunächst fehlender
direkter WorkManager-Kompilierzugriff für die neue native Diagnose; kleinere
Analyzer-Hinweise. Die oben genannten Resultate beziehen sich auf die bereinigten
abschließenden Läufe. Gradle meldet zusätzlich bestehende Deprecation-Hinweise
zur künftigen Gradle-10-Kompatibilität; der Build/Test endet erfolgreich.

Nachweisdateien unter `build/`:

- `issue82_full_tests_final.log`, `issue82_personal_final.log`
- `issue82_apple_dart.log`, `issue82_android_unit.log`
- `issue82_analyze_final.log`, `issue82_android_debug_final.log`
- `issue82_windows_debug_final.log`, `issue82_configuration.log`
- `issue82_android_manifest.log`, `notification_previews/`

Die Logs sind lokale, ignorierte Build-Artefakte; Quelltext und Testanleitung
bleiben versionierbar im Repository.

## K. Verifikationsstand und verbleibende Grenzen

| Einordnung | Stand |
|---|---|
| Implementiert und lokal automatisiert geprüft | Ereignisverarbeitung, stille Vordergrundabrufe, persistente Deduplication, Account-/Serverisolation, Settings-Migration, Gruppierung/Texte, Fixture-Authentifizierung, Fehler-/Lease-/Löschrennen, Diagnose-UI. |
| Implementiert und kompiliert, nur teilweise verifiziert | Android headless Integration, native Vordergrundsperre, Boot-/Scheduler-Einrichtung; physisches Verhalten und echte Schul-API fehlen. |
| Implementiert, hier nicht nativ kompiliert | iOS-AppDelegate und korrigierte Apple-Task-Abhängigkeit. Statische Konsistenz und Dart-API-Tests ersetzen kein Xcode. |
| Implementiert, betriebssystemabhängig | WorkManager/BGAppRefresh-Ausführung, Berechtigungen, Kanäle, DND, Energiesparen, Zeitpunkt und sichtbare Systemanzeige. |
| Bewusst nicht implementiert | Hintergrund-2FA-Dialoge, künstlicher Dauerbetrieb, Akku-/OS-Umgehungen, Upload persönlicher Schuldaten an eigenes Backend, neue Push-Infrastruktur. |
| Durch vorhandenen API-Vertrag begrenzt | Erkennung bereits aus dem Unread-Feed verschwundener Ereignisse, sichere Änderungsbenachrichtigungen ohne Versionierung, verlustfreie Identifikation ohne stabile IDs. |
| Bestehende Produktgrenze | Kein einzelner Noten-ID-Detailpfad; Noten-Taps öffnen die zugehörige Übersicht. |
| Desktop-Sondergrenze | Windows benötigt eine paketierte App-Identität für native Bereinigung; Linux kann die Daemon-IDs eines früheren App-Prozesses nicht wiederherstellen. |

Weitere Grenzen sind das dokumentierte Claim/Show-Absturzfenster und ein
gemeinsames 20-Sekunden-Netzwerkbudget: bei vielen/langsamen Schulen werden
verbleibende Accounts erst in einem späteren zulässigen Lauf geprüft. Dies spart
Energie und respektiert kurze iOS-Zeitfenster, garantiert aber keine Maximal-
Latenz. Faire Sortierung verhindert dauerhafte Bevorzugung derselben Schule.

## L. Explizite Abschlussbewertung

1. **Werden neue Noten auf Android bei geschlossener App erkannt?** Der headless
   Worker mit sicherem Login und Feed-Abgleich ist implementiert, kompiliert und
   im Fixture-Test geprüft. Wenn WorkManager tatsächlich läuft, kann er Noten
   erkennen. Physische Zustellung/OS-Zuverlässigkeit wurde hier nicht bewiesen.
2. **Werden neue Mitteilungen im Android-Hintergrund erkannt?** Derselbe geprüfte
   Pfad verarbeitet `message` und erstellt lokale Mitteilungsrequests. Es gelten
   dieselben OS- und noch offenen Live-Qualifikationsgrenzen.
3. **Funktioniert die iOS-Hintergrundverarbeitung?** Die Architektur inklusive
   Abbruchkorrekturen ist implementiert. Statische Checks und 22 Dart-Tests
   bestehen; Xcode-/iPhone-Nachweis fehlen. Daher kein uneingeschränktes Ja.
4. **Erscheinen beim normalen Start weiterhin verspätete Popups?** Der normale
   Vordergrundpfad fordert sie nicht mehr an. Regressionstests bestätigen stille
   Erkennung. Zusätzlich sichern native Android-/iOS-Pfade den Übergang; deren
   tatsächliche Gerätausführung muss noch qualifiziert werden.
5. **Werden Duplikate verhindert?** Persistente Identitäten, Claims vor Request,
   Sperren und Lease sind automatisiert geprüft. Dies ist eine At-most-once-
   Entscheidung mit möglichem Verlust im Absturzfenster, keine Exactly-once-
   Zustellgarantie und kein Ersatz für stabile Schul-IDs.
6. **Mehrere Schulaccounts?** Bereits aktivierte gespeicherte Accounts werden
   getrennt, sequentiell und mit eigenen Einstellungen verarbeitet. Mehrere
   Server/gleiche IDs sind getestet. Der gesamte Tap-/Login-/2FA-Ablauf über
   Accountwechsel benötigt zusätzlich echte Gerätetests.
7. **Bleiben Schulzugangsdaten auf dem Gerät?** Speicherung ausschließlich im
   vorhandenen sicheren lokalen Anmeldesystem; Übertragung nur an den jeweiligen
   Schulserver zur Anmeldung. Kein eigenes Backend im Synchronisierungspfad.
8. **Sind Texte vollständig überarbeitet?** Ja, die persönlichen Systemtexte und
   dazugehörigen Einstellungen/Diagnosen liegen in allen vier App-Sprachen vor;
   Singular/Plural und Datenschutz sind getestet. Ladinisch-Muttersprachprüfung
   bleibt als sprachliche Release-Qualifikation offen.
9. **Welche Tests bestehen?** Abschließend 1.262 Flutter-Tests,
   darin 90 persönliche Notification-Tests; zusätzlich 22 Apple-Dart- und 7 native
   Android-Helper-Tests. Analyzer, Android-/Windows-Debug-Build und 11 statische
   Konfigurationschecks bestehen. Zwei bestehende Tests sind begründet übersprungen.
10. **Was fehlt auf echten Geräten?** Alle 15 Zustands-/Netz-/Ereignisszenarien,
    signierter Release, echte Schul-IDs/Zeitstempel/Auth, gesperrter Speicher,
    Task-Expiration, native Übergangssperre, Kaltstart, Biometrie/2FA und
    mehraccountbezogene Navigation gemäß Geräteanleitung.
11. **Welche OS-Grenzen sind unvermeidbar?** Keine feste Android-15-Minuten-
    Zusage; keine frei planbare iOS-Abfrage; mögliche Ausfälle bei Force-stop/
    Force-quit, Doze, Restriktionen, fehlendem Netz und fehlender Entsperrung.
12. **Kann Issue #82 technisch abgeschlossen werden?** Die direkt lokal
    realisierbaren Änderungen sind umgesetzt und geprüft. Für einen vollständig
    qualifizierten technischen Abschluss fehlen insbesondere Xcode-Build,
    physische Android-/iPhone-Tests und reale Schul-API-/Release-Verifikation.
    **Issue #82 sollte deshalb offen bleiben.**

Die konkrete Geräteanleitung steht in `SCHOOL_NOTIFICATIONS_DEVICE_TESTS.md`;
die laufende Architekturdokumentation in `SCHOOL_NOTIFICATIONS.md`.
