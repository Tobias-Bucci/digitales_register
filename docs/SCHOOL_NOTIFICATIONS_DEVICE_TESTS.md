# Issue #82 — Gerätequalifikation Android und iOS

Stand: 25.10.2026. Diese Anleitung ist vorbereitet; die nachfolgenden Gerätetests
wurden in der Windows-Entwicklungsumgebung **nicht durchgeführt**.

Die Referenzübernahme vom 25.10.2026 ist in
`SCHOOL_NOTIFICATIONS_REFERENCE_REBUILD.md` beschrieben. Für diese Version müssen
die untenstehenden Zustellszenarien neu geprüft werden; alte Builds qualifizieren
den neuen Pluginstart und Lifecyclepfad nicht.

## iOS-Keychain-Regression (26.10.2026)

Siehe `SCHOOL_NOTIFICATIONS_DEBUG_2026-10-26.md`. Auf einem iPhone mit einem
Build **vor** dieser Korrektur angemeldete Accounts verwenden, dann auf den neuen
Build aktualisieren:

- Nach dem Update ohne erneute Anmeldung: App einmal öffnen, gespeicherte Anmeldung
  muss weiterhin automatisch funktionieren (keine verlorenen Zugangsdaten).
- Einstellungen der Schulbenachrichtigungen: eingerichtete Accounts müssen wieder
  aufgelistet werden (vorher war die Liste unter iOS leer).
- Gerät sperren, BGAppRefresh mit Apples Entwicklungsverfahren auslösen: Die
  Diagnose darf nicht `credentialsUnavailable` zeigen; nach einer neuen Note muss
  eine Systembenachrichtigung angefordert werden.
- Neustart, **vor** der ersten Entsperrung Task auslösen: Fehlschlag ist zulässig,
  die gespeicherte Anmeldung darf danach nicht verloren sein.
- Accountwechsel, Abmelden/Anmelden und Passwortänderung: Die App muss die
  Anmeldung weiter lesen und speichern können; danach wieder gesperrter Hintergrundlauf.

## Zusätzliche Regressionen der Referenzübernahme

- Ohne sichtbare Activity eine natürliche WorkManager-Ausführung abwarten. Auch
  nach Prozessende muss die neue Engine das Anzeigeplugin initialisieren und
  eine tatsächlich neue Note/Mitteilung anzeigen können.
- App direkt nach einem Wechsel A → B → A schließen. Der eindeutige periodische
  Auftrag muss erhalten bleiben; Wechsel dürfen den nächsten Lauf nicht wieder
  um 15 Minuten verschieben. Expliziter Logout muss weitere Abrufe verhindern.
- Eine geteilte Mitteilung (`messageShared`) nach der stillen Baseline anlegen.
  Derselbe Mitteilungsschalter und dieselbe Duplikatvermeidung müssen gelten.
- Mit mehreren berechtigten Testkonten eine nicht erreichbare Schule und eine
  erreichbare Schule kombinieren. Der Timeout der ersten darf die zweite nicht
  aus jeder Runde verdrängen; keine fremden Zugangsdaten in Logs aufzeichnen.
- Die App während eines laufenden Hintergrundabrufs öffnen, auch mit Biometrie
  und in Split Screen. Keine nachträgliche Systemanzeige im sichtbaren Fenster;
  angemeldete Schul-Sitzung und Kontoansicht anschließend prüfen.
- Neuen Prozess nach verpasstem Pause-Callback, Reboot und manueller Uhränderung
  prüfen. Eine gespeicherte Markierung aus einem anderen Prozess darf den
  Android-Abruf nicht blockieren.

## Vorbereitung und Messverfahren

1. Signierten Release-Build sowie einen Debug-Build auf einem physischen Android-
   Gerät und einem iPhone bereitstellen. Zusätzlich mindestens einen Android-
   Hersteller mit eigener Energieverwaltung prüfen. Version, OS, Gerätemodell,
   App-Paketkennung und Energie-/Benachrichtigungseinstellungen protokollieren.
2. Nur berechtigte Schul-Testaccounts verwenden. Ereignisse durch einen
   autorisierten Testablauf anlegen lassen; keine Produktionsnoten manipulieren.
   Existiert dieser Zugang nicht, den entsprechenden Live-Test als offen führen.
3. Account A anmelden, Passwortspeicherung aktivieren, persönliche
   Benachrichtigungen und beide Kategorien aktivieren, Systemberechtigung erteilen.
   Im einmaligen Opt-in müssen beide Kategorien vorausgewählt, die persönlichen
   Benachrichtigungen vor dem Bestätigen aber noch deaktiviert sein. Ablehnung
   separat prüfen: nach Neustart kein Dialog, keine native Berechtigungsfrage.
   Feed einmal im Vordergrund laden lassen: Bestandsdaten müssen still bleiben.
4. Account B an einer anderen Schule, dann einen zweiten Account am selben Server
   anmelden. Alle einmal im Vordergrund abgleichen. Erst so sind sie für
   Hintergrundprüfungen eingerichtet. Anschließend zu A zurückkehren.
5. Datum/Uhrzeit auf dem Gerät korrekt einstellen. Schul-`timeSent` und stabile
   Objekt-/Feed-IDs ausschließlich im geschützten Testprotokoll kontrollieren.
   Zu Beginn ein Baseline-Ereignis notieren; danach neue Ereignisse erzeugen.
6. Folgende Zeitpunkte getrennt erfassen: serverseitige Veröffentlichung,
   „Hintergrundprüfung gestartet“, „Hintergrundprüfung erfolgreich“,
   „Ereignis erkannt“, „Systembenachrichtigung angefordert“, sichtbare Anzeige,
   App-Öffnung und tatsächliches Öffnen/Bestätigen des Ereignisses. Screenshots
   nur mit Testdaten und ohne Zugangsdaten speichern.

Eine geplante Aufgabe beweist keine Ausführung; ein erfolgreicher Plugin-Aufruf
beweist keine sichtbare Anzeige. Fehlende Hintergrundausführung nach 15 Minuten
ist für sich allein kein Implementierungsfehler. Für jeden Versuch ein vorher
festgelegtes Beobachtungsfenster dokumentieren, bei iOS auch längere reale
Nutzungsphasen. Das Öffnen der App zur Diagnose darf nicht als Hintergrundnachweis
gezählt werden: Es entfernt persönliche Systembenachrichtigungen und aktualisiert
den Feed absichtlich still.

## Gemeinsame Szenarien

| Nr. | Konkreter Ablauf | Erwartung Android | Erwartung iOS |
|---|---|---|---|
| 1 — App geöffnet | Neues Testereignis veröffentlichen; normalen Feed-Refresh ausführen bzw. den Vordergrundtimer abwarten. | Feed/Glockenindikator aktualisiert; kein System-Popup und kein Ton. Öffnen der App bedeutet nicht gelesen. | Gleiches Verhalten; native `willPresent` darf kein persönliches Banner/keinen Ton freigeben. |
| 2 — Hintergrund | App mit Home-Geste verlassen, nicht zwangsbeenden; danach Ereignis erstellen. | Bei tatsächlich ausgeführtem Worker erscheint eine lokale Benachrichtigung. Zeit ist nicht garantiert. | Bei tatsächlich gewährtem BGAppRefresh ist lokale Anzeige möglich; Ausführung nicht garantiert. |
| 3 — Display gesperrt | Nach erfolgreicher Baseline sperren, Ereignis erstellen, auf OS-Lauf warten. | Keine Note, kein Fach, kein Absender, kein Nachrichtentext auf dem Sperrbildschirm. | Gleiches Datenschutzverhalten; Keychain/Hive müssen nach erstem Entsperren erreichbar sein. |
| 4 — System beendet Prozess | Erst Hintergrund herstellen, dann Prozess ohne Force-stop beenden bzw. echte Speicherverdrängung beobachten. Neues Ereignis erstellen. | WorkManager kann neuen headless Flutter-Prozess starten; es darf keine sichtbare Activity nötig sein. | Bei OS-zugelassenem Neustart kann der headless Task laufen. Jetsam/Systemende ist von manuellem Wegwischen zu unterscheiden. |
| 5 — Manuell erzwungen beendet | Android „Beenden erzwingen“, iOS App aus App-Umschalter wegwischen; danach Ereignis erstellen. | Keine Hintergrundgarantie. Nach manueller Wiederöffnung stiller Abgleich, keine alte Popup-Flut; Scheduling danach wieder prüfen. | Nach Force-quit keine Hintergrundgarantie. Nächste Wiederöffnung gleicht still ab; kein Umgehungstrick. |
| 6 — Neustart | Gerät neu starten, zunächst gesperrt lassen; anschließend einmal entsperren, App weiterhin geschlossen lassen. Neues Ereignis erstellen. | Persistierte Arbeit/Boot-Reschedule prüfen; vor erstem Entsperren kann sicherer Speicher fehlen. Keine exakte Frist erwarten. | Verfügbarkeit nach erstem Entsperren und spätere OS-Ausführung prüfen; kein garantierter Lauf direkt nach Boot. |
| 7 — Energiesparen/Doze | Standard-Akkuoptimierung beibehalten, Energiesparen aktivieren; Android zusätzlich Doze testen. | Verzögerung ist zulässig; Diagnose muss Einschränkung verständlich zeigen, Erholung nach Aufhebung prüfen. Keine Ausnahme erzwingen. | Low Power Mode/Background App Refresh prüfen; Verzögerung bzw. Ausbleiben zulässig. Erholung danach prüfen. |
| 8 — Offline | Vor dem geplanten Lauf Flugmodus aktivieren; neues Ereignis serverseitig bereitstellen. | Netzwerkbedingung verhindert Lauf oder Anfrage schlägt begrenzt fehl. Kein falscher Erfolg, keine Baseline aus Fehlerantwort, kein Absturz. | Kein falscher Prüferfolg/keine neue Baseline; OS entscheidet über späteren Lauf. |
| 9 — Wieder online/Netzwechsel | WLAN wiederherstellen; zusätzlich zwischen WLAN und Mobilfunk wechseln. | Nächster zulässiger Lauf erkennt Ereignis einmal. Nach vorheriger Vordergrundöffnung kein nachträgliches Popup. | Dasselbe, sobald iOS wieder Laufzeit gewährt; kein Sofortstartversprechen. |
| 10 — Neue Note | Nach Baseline genau eine Note mit neuer stabiler ID veröffentlichen. | Eine generische „Neue Note“; Antippen öffnet Notenübersicht des richtigen Accounts. Kein eigenständiger Noten-ID-Dialog ist vorhanden. | Gleiches Produktverhalten, abhängig von BGAppRefresh. |
| 11 — Neue Mitteilung | Neue Mitteilung mit Objekt-ID nach Baseline veröffentlichen. | Eine generische Schulmitteilung; Tap lädt die Mitteilung, soweit sie noch existiert. | Gleiches Verhalten; warmen und kalten Start separat prüfen. |
| 12 — Mehrere Ereignisse | Mindestens zehn Noten und zehn Mitteilungen zwischen zwei erfolgreichen Läufen erzeugen. | Höchstens zwei persönliche Alerts je Account und Prüflauf. Gruppen-Tap öffnet die Liste. Ohne Zähloption keine Anzahl; mit Option korrekte Anzahl neuer Batch-Ereignisse. | Höchstens zwei Requests pro Account/Batch, gemeinsamer Account-Thread, gleiche Textregeln. |
| 13 — Lange Inaktivität | Viele Ereignisse während Abwesenheit erzeugen, App anschließend selbst öffnen, bevor eine erfolgreiche Hintergrundprüfung stattfand. | Kein System-Popup durch den Startabruf; vorhandene persönliche Alerts verschwinden; ungelesene Feedeinträge bleiben in der App. | Gleiches Verhalten; keine Nachholwarteschlange. |
| 14 — Mehrere Accounts | A/B mit gleichen Ereignis-IDs und verschiedenen Servern sowie zwei Benutzer am selben Server verwenden. B-Kategorien getrennt deaktivieren. Aus B-Alert bei aktivem A starten. | Getrennte IDs/Baselines/Einstellungen; B-Tap führt über vorhandene Anmeldung zu B. Kein A-Inhalt in B. Manuelles Umschalten während Login überschreibt den Tap. | Dasselbe einschließlich Biometrie/2FA. Keine fremde Ansicht unter dem noch aktiven Account anzeigen. |
| 15 — Anmeldung abgelaufen | Testpasswort ändern bzw. 2FA verlangen; Worker laufen lassen. | Keine Login-Dialoge im Hintergrund, keine unendliche Login-Schleife. Diagnose fordert Anmeldung an; erst neue App-Sitzung erlaubt weiteren Loginversuch. | Dasselbe; neuer Scheduler-Lauf allein löst keine 2FA-UI aus. |

Für jede Zeile Ergebnis, Beobachtungsdauer, Hintergrundstart/-ende und sichtbare
Anzeige getrennt protokollieren. Auch ein erwartetes OS-bedingtes Ausbleiben muss
mit Gerätezustand erfasst werden; es ist kein bestandener Zustellnachweis.

## Zusätzliche Pflichtprüfungen

- Neuinstallation und Update ohne ausdrückliche Auswahl: nach Anmeldung und
  bestehenden Starthinweisen genau ein Account-Opt-in, vor dem Tutorial und erst
  nach Entsperren der App. Keine Auswahl durch Zurücktippen/Antippen außerhalb.
- Frühere ausdrückliche Kategorie-/Hauptschalterwahl nach Update unverändert;
  globale Alt-Einstellungen nur den vorher gespeicherten Accounts zuordnen.
  Ein später neuer Account erhält keine übernommene positive Zustimmung.
- Systemberechtigung verweigern, dann anderen Account anmelden oder Hauptschalter
  aus-/einschalten: keine wiederholte Systemfrage. Freiwilligen Einstellungslink
  und anschließendes manuelles Freigeben der Systemberechtigung prüfen.
- Account wechseln oder abmelden, während die Erklärung bzw. Systemfrage offen
  ist: keine Zustimmung für den neuen/falschen Account und keine alte Zielansicht.

- Erster Opt-in, Kategorie-Wiedereinschalten, Hauptschalter-Wiedereinschalten und
  Wiedererteilen der Systemberechtigung: vorhandener Bestand bleibt still.
- Berechtigung verweigern; danach nur einen Android-Kanal ausschalten. Diagnose
  muss zwischen globaler Berechtigung und Kanalzustand unterscheiden.
- Drei-Minuten-Vordergrundprüfung bei deaktivierter Systemberechtigung: Der
  vorhandene In-App-Feed soll weiterhin aktualisiert werden, sofern Kategorien
  aktiviert sind. Keine Systemanzeige.
- Vordergrundstart während langsamer Login-/Feed-Antwort und unmittelbar vor
  `show`: alte Antwort darf keine verspätete sichtbare Schulbenachrichtigung
  auslösen. Native Android-Gate- und iOS-Delegate-Pfade tatsächlich ausführen.
- Hintergrundtask mitten im HTTP-Abruf und nach persistierter Erkennung abbrechen.
  Folgelauf darf keine Duplikate erzeugen; ein Verlust im dokumentierten
  Claim/Show-Absturzfenster ist als At-most-once-Grenze gesondert zu protokollieren.
- Ereignis umsortieren, Text ändern, Feed-ID bei stabiler Objekt-ID neu vergeben:
  keine neue Benachrichtigung. ID-lose gleichzeitige Ereignisse separat auf die
  dokumentierte konservative Zusammenfassung prüfen.
- Account während Abruf löschen; danach App neu starten. Keine erneute Anlage
  gelöschter Benachrichtigungshistorie, keine Anzeige oder Navigation zu dem Account.
- Mitteilung vor dem Tap löschen; Liste muss verständlich nutzbar bleiben.
- App öffnen und Alerts entfernen lassen, anschließend Lesestatus im Schulfeed
  vergleichen. Nur eine explizite Lese-/Bestätigungsaktion darf den dazugehörigen
  Lesepfad auslösen. Die Notenübersicht allein liest nicht alle Notenereignisse.
- Alle vier Sprachen (Deutsch, Englisch, Italienisch, Ladinisch), Singular,
  Mehrzahl, Zähloption, Hell/Dunkel und große Schrift auf dem Gerät prüfen.
  Ladinische Texte zusätzlich muttersprachlich prüfen lassen.
- Signierten Release getrennt vom Debug-Build prüfen: Icon, Pluginregistrierung,
  R8, Kaltstart-Tap, korrekte Paketkennung und Wiederherstellung nach Update.

## Android-Werkzeuge für berechtigte Testgeräte

Debug-Paket: `it.bucci.digitalesregister.debug`; Produktionspaket:
`it.bucci.digitalesregister` (jeweils tatsächlich installiertes APK prüfen).

```powershell
adb shell dumpsys jobscheduler
adb shell am kill it.bucci.digitalesregister.debug
adb shell am force-stop it.bucci.digitalesregister.debug
adb shell dumpsys deviceidle force-idle
adb shell dumpsys deviceidle unforce
adb shell dumpsys battery reset
```

`am kill` erst nach dem Wechsel in den Hintergrund verwenden. `force-stop` ist
ein anderer Zustand und gerade kein Nachweis normaler Prozessbeendigung. Keine
fremden Jobs oder appfremden Benachrichtigungen löschen. Entwicklerseitig
erzwungene Jobausführung prüft die Worker-Funktion, nicht die reale Taktung oder
Energiesparzuverlässigkeit. Doze-/Batterieänderungen nach dem Test zurücksetzen.

Referenz: [Androids Doze-Testverfahren](https://developer.android.com/training/monitoring-device-state/doze-standby).

## iOS-Build und Task-Ablauf auf macOS

```sh
flutter pub get
flutter build ios --no-codesign
```

Anschließend im Xcode-Workspace einen signierten Build auf einem physischen
iPhone ausführen. `BGTaskSchedulerPermittedIdentifiers`, `fetch`, Plugin-Callback,
Keychain-Zugriff nach erstem Entsperren sowie das erneute Einplanen kontrollieren.
Mit Apples dokumentiertem Entwicklungsverfahren einen Start und eine Expiration
des Tasks `it.bucci.digitalesregister.schoolRefresh` simulieren. Dabei muss die
headless Engine beendet, die Operation entblockt und der Task mit Misserfolg
abgeschlossen werden; verspätete Callback-Antworten dürfen keinen zweiten
Abschluss verursachen. Danach einen frischen Tasklauf ausführen.

Simulation ersetzt keine längere Beobachtung natürlicher OS-Ausführung. Die
Xcode-Simulation eines alten Background-Fetch-Callbacks allein qualifiziert den
BGAppRefreshTask-Pfad nicht.

Referenzen:
[Apple: Tasks während der Entwicklung starten und beenden](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development),
[Apple: Hintergrundstrategien](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app).

## Freigabekriterium

Issue #82 erst nach erfolgreichem iOS-Build, signierter Release-Qualifikation,
realer Schul-API-Validierung und physischen Android-/iPhone-Tests schließen.
Automatisierte Fixture-Tests, Konfigurationsprüfung und erfolgreiche Kompilierung
allein bestätigen keine zuverlässige Hintergrundzustellung.
