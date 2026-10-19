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

Die umrandete Hauptkarte und Kontenkarte entfallen. Ein maximal 448 logische
Pixel breites Formular bildet die gemeinsame Mitte aller Auth-Seiten. Auf großen
Fenstern ist der Inhalt zentriert; bei wenig Platz kann die ganze Seite scrollen.
SafeArea und Scaffold-Tastaturanpassung halten die Aktionen erreichbar. Unter
360 Pixel Breite sinkt der seitliche Abstand von 24 auf 16 Pixel. Feld- und
Abschnittsabstände folgen einem 16/24-Pixel-Rhythmus.

Das bestehende Logo ergänzt die kompakte Markenkennung. Seitenüberschriften
stehen im scrollbaren Inhalt und können bei großer Schrift umbrechen. Bestehende
Typografie und Theme-Palette bleiben erhalten. Tonale Felder ersetzen permanente
Umrandungen; Fokus und Fehler erhalten sichtbare Konturen. 14-Pixel-Radien
verbinden Felder, Hauptaktion und Kontenzeilen. Der lokale Dialogradius beträgt
24 Pixel. Suchvorschläge übernehmen optional die Auth-Geometrie.

Die Anmeldung bleibt die dominante Aktion, mindestens 52 Pixel hoch. Recovery
und Feedback erscheinen als Textaktionen. „Angemeldet bleiben“ steht vor dem
Absenden. Konten sind unmittelbar auswählbar, mit separater Löschaktion und
unverändertem Bestätigungsdialog. Vorhandene Benutzernamen bleiben vollständig
sichtbar und dürfen umbrechen.

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
| `assets/locales/{de,it,en,lld}.json` | Drei neue Texte pro Sprache |
| `test/ui/auth_redesign_test.dart` | Interaktions-, Layout-, Accessibility- und Preview-Prüfungen |

Keine neuen Abhängigkeiten. Auth-Dienste, Container, Middleware, Credentials-/
Token-Persistenz, Backend-Verträge und globales Theme wurden nicht verändert.
Automatische Sitzungswiederherstellung bleibt Aufgabe der bestehenden Infrastruktur.

## Verifikation

Umgebung: Windows, Flutter 3.47.7 / Dart 3.13.5.

| Prüfung | Ergebnis |
| --- | --- |
| `flutter test` | **963 bestanden, 1 bestehender Test übersprungen**, keine Fehler |
| `flutter analyze lib` | **Keine Befunde** |
| `flutter analyze` | **166 bestehende Befunde ausschließlich in `AUDIT_REPORT/`**, insbesondere Repro-Dateien mit nicht auflösbaren relativen Test-Imports; dieser Ordner wurde nicht verändert |
| `git diff --check` | Erfolgreich |
| Zusätzlicher Preview-Export | Erfolgreich, 18 PNG-Ansichten gerendert |

Die vollständige Suite enthält die bestehenden Auth-, Persistenz-, Session-,
Demo- und Kontoentfernungstests. Neue Interaktionstests prüfen unveränderte
Credentials und Session-Präferenz, leere Eingaben, Demo-URL, Schulsuche mit
Tastaturauswahl, eigene Serveradresse, Recovery-URL, Passwortsichtbarkeit,
Tab-Reihenfolge, Kontenauswahl und bestätigte Löschung einschließlich Abbruch,
Ladesperre, Netzwerkfehler/Retry, erzwungenen Passwortwechsel, Link-Reset und
freiwillige Zurücknavigation.

128 Layoutkombinationen prüfen Deutsch/Italienisch/Englisch/Ladinisch ×
hell/dunkel × Login/Passwortwechsel/Recovery/Link-Reset × vier Formate:
320×640, 390×844, 740×360 mit 1,6-facher Schrift und 140 Pixel simuliertem
Tastatureinzug, 1440×1000 mit zweifacher Schrift. Ergebnis: keine Flutter-
Layoutfehler; Hauptaktionen durch Scrollen erreichbar und mindestens 48 Pixel hoch.

Flutter-Guidelines für Android-/iOS-Touchziele, beschriftete Aktionen und
Textkontrast bestehen für Login in beiden Themes. Fehler-Live-Region und
Tastaturbedienung sind separat geprüft.

18 PNG-Ansichten mit Roboto-/Material-Schriften wurden gerendert. Visuell geprüft:
beide Login-Themes, Konten, Fehler, Laden, Passwortwechsel, Recovery,
Link-Reset/Erfolg und Desktop-Komposition. Ausgewählte Ansichten liegen in
`screenshots/login-redesign-76/`. Logs und vollständige Preview-Ausgabe liegen
unter `build/`: `login_full_tests.log`, `login_full_analyze.log`,
`login_scoped_analyze.log`, `auth_accessibility_tests.log`, `auth_previews/`.

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
