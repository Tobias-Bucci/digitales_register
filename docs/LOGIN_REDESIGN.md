# Login-Redesign – Issue #76

## Bestandsaufnahme vor der Implementierung

Untersucht: `login_page_content.dart`, Login-Container, Login-Middleware,
Passwort-Container/-Widgets, Theme, Lokalisierung und bestehende Tests.

| Bestehende Fähigkeit | Zu erhaltendes Verhalten |
| --- | --- |
| Schulauswahl | Fuzzy-Suche ab drei Zeichen, maximal 15 Treffer, Tastaturauswahl, „Andere Schule“, lokalisierte Fehlermeldung bei unbekannter Schule |
| Serveradresse | Immer editierbares Adressfeld; vorausgewählte Schule setzt die Adresse; gespeicherte URL/Benutzername werden vorbelegt |
| Anmeldung | Benutzername und unverändertes Passwort an vorhandenen Callback; Validierung und HTTPS-Prüfung bleiben in der Middleware |
| Demo | Leere Schule und `demo`/`demo` übergeben weiterhin eine leere URL |
| Sitzung | „Angemeldet bleiben“ invertiert weiterhin `safeMode`; Speicherung erfolgt beim Absenden über `setSaveNoPass` |
| Gespeicherte Konten | Vorhandene Benutzernamen, unmittelbare Auswahl per Index, Entfernen ausschließlich nach Bestätigungsdialog |
| Weiteres Konto | Bestehendes Formular erlaubt neue Zugangsdaten; Speicherung und Umsortierung bleiben Aufgabe der Middleware |
| Passwort ändern | Freiwilliger/erzwungener Wechsel, alter/neuer/wiederholter Wert, Passwortregeln und Gleichheitsprüfung; Absenden nur bei übereinstimmenden Passwörtern |
| Passwort vergessen | Übergabe der aktuellen URL an die Navigation; Anfrage mit Benutzername und E-Mail; Servermeldung übersetzt anzeigen |
| Passwort zurücksetzen | Zwei neue Passwörter, Gleichheitsprüfung; Erfolg blendet Absenden aus und zeigt „Fertig“; Close-Callback und Back-Verhalten erhalten |
| Laden/Fehler | Oberer Fortschrittsbalken, deaktivierte Eingaben und Absenden, Auth-/Netzwerkfehler samt URL-Hinweis; erneutes Absenden nach Fehler möglich |
| Feedback | Bestehendes externes Formular mit App-Version erreichbar |
| Navigation | Anmeldung beendet App über System-Back; freiwilliger Passwortwechsel erlaubt Zurück, erzwungener Wechsel nicht |
| Autofill/Sprachen | Autofill-Gruppe und Benutzer-/Passwort-Hinweise; Deutsch, Italienisch, Englisch und Ladinisch |

Nicht vorhanden: SSO/alternative Anbieter, dedizierter Konto-hinzufügen-Dialog,
Passwort-Sichtbarkeitsschalter. `onReload` wird bereits im Bestand nicht durch
ein UI-Element aufgerufen. Automatische Wiederanmeldung, sichere Speicherung,
Session-Erneuerung und Konto-Persistenz liegen außerhalb der UI und bleiben unverändert.

## Ausgangslage und Umsetzung

Die Ausgangsoberfläche kombiniert eine umrandete Hauptkarte mit umrandeten
Feldern und einer zweiten Kontenkarte. Wiederholte Branding-Blöcke, gleich stark
betonte Aktionen und blau statt semantisch dargestellte Fehler schwächen die
Hierarchie. Die Link-Reset-Seite verwendet noch eine andere Geometrie.

Plan: gemeinsamer ausschließlich lokal verwendeter Auth-Rahmen mit begrenzter
Breite, scrollbarem Inhalt, kompakter Markenkennung und konsistenten Feldern/
Aktionen. Formular ohne äußere Karte, ruhige Kontenzeilen, Meldungen nahe der
Aktion, einheitliche Recovery-/Wechselseiten. Bestehende Callback-Verträge,
Middleware, Persistenz und Navigation erhalten. Regressionen über Widgettests,
bestehende Auth-Tests und Layout-Matrix absichern; gerenderte Ansichten prüfen.

## Ergebnis und Designentscheidungen

Wiederhergestellt ist die Variante aus den gezeigten Tablet-Ansichten: dauerhaft
sichtbares Adressfeld, zentrierte Begrüßung und weichere Konturen. Mobil und auf
Tablets im Hochformat steht das maximal 448 logische Pixel breite Formular frei
auf der Seite. Ab 1000 Pixel Breite stehen Markenbereich und Anmeldefläche
nebeneinander. Die Desktop-/Tablet-Fläche erhält eine weiche 36-Pixel-Kontur und
einen dezenten Schatten. Bei starker Textvergrößerung bleibt das Layout einspaltig.
Alle Inhalte können scrollen; SafeArea und Scaffold-Tastaturanpassung halten die
Aktionen erreichbar. Mobil beträgt der seitliche Abstand 28 Pixel, unter 360 Pixel
Breite 20 Pixel. Felder und Abschnitte verwenden 18/28 Pixel Abstand.

Das bestehende Logo ergänzt die kompakte Markenkennung. Seitenüberschriften
stehen im scrollbaren Inhalt und können bei großer Schrift umbrechen. Bestehende
Typografie und Akzentpalette bleiben erhalten. Helle Auth-Seiten verwenden einen
neutralen weißen Untergrund. Eingaben besitzen dezente Umrisse, dauerhaft
sichtbare Beschriftungen und Such-/Benutzerhinweise. 20-Pixel-Radien ersetzen die
kleineren Rundungen; Button, Logo und Desktop-Fläche verwenden Flutter-
Superellipsen für weich auslaufende Konturen. Der lokale Dialogradius beträgt
28 Pixel. Suchvorschläge übernehmen optional die Auth-Geometrie.

Die Anmeldung bleibt die dominante Aktion, mindestens 56 Pixel hoch. Recovery
und Feedback erscheinen als Textaktionen. „Angemeldet bleiben“ steht vor dem
Absenden. Konten sind unmittelbar auswählbar, mit separater Löschaktion und
unverändertem Bestätigungsdialog. Vorhandene Benutzernamen bleiben vollständig
sichtbar und dürfen umbrechen. Kontenzeilen verwenden runde Profilzeichen und
keine eigenen Hintergrundblöcke. Demo-Hinweis und Feedback bilden einen ruhigen
Footer. Feedback führt weiterhin zum gleichen Formular wie in den Einstellungen.

Fehler stehen unmittelbar vor der Hauptaktion, mit Fehlerfarbpaar, Icon und
Live-Region. Erfolgsmeldungen haben ein Bestätigungssymbol. Ladende Anmeldungen
zeigen Fortschrittsbalken und Spinner sowie „Bitte warten …“ im deaktivierten
Button. Es gibt keine zusätzlichen Übergangsanimationen oder Verzögerungen.

Alle Passwortfelder haben lokalisierte Sichtbarkeitsschalter. Benutzername,
Adresse und Passwort verwenden passende Tastaturaktionen; Enter im letzten Feld
ruft denselben Submit-Pfad wie der Button auf. Der Passwortabgleich sperrt auch
diesen Pfad. Unveränderte Passwörter, Session-Präferenz und URL gehen weiterhin
an die bisherigen Callbacks. Neue Texte für Sichtbarkeit und Laden sind in
Deutsch, Italienisch, Englisch und Ladinisch ergänzt.

## Technische Änderungen

| Datei | Zweck |
| --- | --- |
| `lib/ui/auth_layout.dart` | Lokaler Auth-Rahmen, Feld-/Button-Theme, Meldungen und Passwortfeld |
| `lib/ui/login_page_content.dart` | Neue Komposition, extrahierte Submit-/Kontenaktionen; Schulsuche und Navigation erhalten |
| `lib/ui/request_pass_reset.dart` | Einheitliches Recovery-Formular, Ergebnisdarstellung und Tastatur-Submit |
| `lib/ui/pass_reset.dart` | Einheitliches Link-Reset-Formular mit Passwortabgleich und Abschlussaktion |
| `lib/ui/autocomplete_options.dart` | Optionaler Radius, Standard weiterhin ohne Rundung |
| `assets/locales/{de,it,en,lld}.json` | Texte für Sichtbarkeit, Laden, Begrüßung, Markenbereich und Eingabehinweise; Demo-Hinweis ohne sichtbare Markdown-Zeichen |
| `test/ui/auth_redesign_test.dart` | Interaktions-, Layout-, Accessibility- und Preview-Prüfungen |

Keine neuen Abhängigkeiten. Auth-Dienste, Container, Middleware, Credentials-/
Token-Persistenz, Backend-Verträge und globales Theme wurden nicht verändert.
Automatische Sitzungswiederherstellung bleibt Aufgabe der bestehenden Infrastruktur.

## Verifikation

Umgebung: Windows, Flutter 3.47.7 / Dart 3.13.5.

| Prüfung | Ergebnis |
| --- | --- |
| `flutter test` | **1027 bestanden, 1 bestehender Test übersprungen**, keine Fehler |
| `flutter analyze lib` | **Keine Befunde** |
| `flutter analyze` | **166 bestehende Befunde ausschließlich in `AUDIT_REPORT/`**, insbesondere Repro-Dateien mit nicht auflösbaren relativen Test-Imports; dieser Ordner wurde nicht verändert |
| `git diff --check` | Erfolgreich |
| Zusätzlicher Preview-Export | Erfolgreich, 22 PNG-Ansichten gerendert, einschließlich Tablet im Hoch- und Querformat |

Die vollständige Suite enthält die bestehenden Auth-, Persistenz-, Session-,
Demo- und Kontoentfernungstests. Neue Interaktionstests prüfen unveränderte
Credentials und Session-Präferenz, leere Eingaben, Demo-URL, Schulsuche mit
Tastaturauswahl, eigene Serveradresse, Recovery-URL, Passwortsichtbarkeit,
Tab-Reihenfolge, Kontenauswahl und bestätigte Löschung einschließlich Abbruch,
Ladesperre, Netzwerkfehler/Retry, erzwungenen Passwortwechsel, Link-Reset und
freiwillige Zurücknavigation.

192 Layoutkombinationen prüfen Deutsch/Italienisch/Englisch/Ladinisch ×
hell/dunkel × Login/Passwortwechsel/Recovery/Link-Reset × sechs Formate:
320×640, 390×844, 768×1024, 1440×1000, 740×360 mit 1,6-facher Schrift und 140 Pixel
simuliertem Tastatureinzug, 1440×1000 mit zweifacher Schrift. Ergebnis: keine Flutter-
Layoutfehler; Hauptaktionen durch Scrollen erreichbar und mindestens 48 Pixel hoch.

Flutter-Guidelines für Android-/iOS-Touchziele, beschriftete Aktionen und
Textkontrast bestehen für Login in beiden Themes. Fehler-Live-Region und
Tastaturbedienung sind separat geprüft.

22 PNG-Ansichten mit Roboto-/Material-Schriften wurden gerendert. Visuell geprüft:
beide Login-Themes, Konten, Fehler, Laden, Passwortwechsel, Recovery,
Link-Reset/Erfolg und Desktop-Komposition. Ausgewählte Ansichten liegen in
`screenshots/login-redesign-76/`. Logs und vollständige Preview-Ausgabe liegen
unter `build/`: `auth_restored_full_tests.log`, `login_full_analyze.log`,
`auth_restore_analyze.log`, `auth_restore_tests.log`, `auth_previews/`.

Preview-Export reproduzieren (PowerShell; SDK-Pfad anpassen):

```powershell
$env:UPDATE_AUTH_PREVIEWS='1'
$env:FLUTTER_ROOT='C:\flutter'
flutter test test/ui/auth_redesign_test.dart --plain-name 'export representative rendered previews when requested'
```

## Prüfgrenzen und optionale Weiterentwicklung

Die Ansichten sind Flutter-Widget-Renderings, keine nativen Gerätescreenshots.
In diesem Durchlauf erfolgten keine native Geräte-/Screenreader-Prüfung und
keine Anmeldung mit realen Schulzugangsdaten. Tests sichern UI-Callbacks und
die vorhandene Testsuite ab; sie belegen keine Erreichbarkeit produktiver
Schulserver. Manuelle TalkBack-/VoiceOver-Prüfung und ein nativer Smoke-Test
wären zusätzliche Release-Prüfungen.

Optional können weitere App-Seiten die weichere Gestaltung übernehmen (Issue #27).
Neue Auth-Anbieter, zusätzliche Kontometadaten oder Änderungen an der
Sitzungssicherheit gehören nicht zu diesem Issue.
