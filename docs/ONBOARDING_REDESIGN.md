# Onboarding: Kurze Einführung

Die frühere Spotlight-Tour (sieben interaktive Schritte, die echte Bedienelemente
markierten und Aktionen verlangten) wurde durch eine kurze, ganzseitige
Einführung ersetzt (`lib/tutorial/intro_tour.dart`).

## Inhalt

Sechs Seiten mit je einer Illustration aus Paletten-Formen, einer Überschrift und
höchstens zwei kurzen Sätzen:

1. **Willkommen** – inklusive Sprachauswahl (Deutsch, Italiano, Ladin, English).
2. **Dashboard** – Hausaufgaben, Tests und anpassbare Karten.
3. **Noten** – Durchschnitte und Notenrechner.
4. **Kalender & Absenzen** – Stundenplan, Prüfungen, Voraus-Absenzen.
5. **Einstellungen** – Hell/Dunkel/AMOLED, Benachrichtigungen, Tutorial.
6. **Design** – Auswahl zwischen neuem Design (empfohlen) und Legacy, mit
   gezeichneter Vorschau beider Designs statt einer Illustration (#108).

## Bedienung

- Fortschrittsanzeige („Schritt n von 6“) und animierte Seitenpunkte.
- Überspringen oben rechts, Zurück/Weiter unten, Wischen zwischen Seiten.
- Tastatur: ← / → blättern, Esc überspringt.
- Bei reduzierten Animationen wird ohne Übergänge geblättert.

## Anzeige

`TutorialService` bietet die Einführung einmalig nach dem ersten Login an
(`tutorial.v3.seen`). Wer die alte Tour bereits gesehen hatte (`tutorial.v2.*`),
bekommt die neue nicht automatisch angezeigt; die alten Schlüssel werden
entfernt. In den Einstellungen startet „Einführung ansehen“ sie jederzeit erneut.

## Design-Auswahl (#108)

Gefragt wird genau einmal pro Installation. `designChoiceMade` in den
SharedPreferences merkt sich, dass gewählt wurde; das Design selbst bleibt
`legacyDesign` in den Einstellungen. Das Flag hängt an keiner Version und an
keinem Konto, spätere Updates, Logout und Login fragen also nicht erneut.

- **Neue Installation:** letzte Seite der Einführung, „Neu“ vorausgewählt.
  „Überspringen“ springt zu dieser Seite, statt die Einführung zu schließen.
- **Update von einer Version ohne Auswahl:** die Einführung ist schon gesehen,
  daher erscheint nur `DesignChoiceScreen`, mit dem bisherigen Design
  vorausgewählt.
- **Abgebrochen** (App beendet, Zurück, Esc): kein Flag, beim nächsten Start
  erscheint `DesignChoiceScreen`. Innerhalb desselben Starts wird nicht erneut
  gefragt.
- **Neuinstallation** löscht die SharedPreferences und zählt als neue
  Installation. Das Gleiche gilt nach dem Löschen der App-Daten.
- Alles ist lokal und funktioniert offline. Beim erneuten Ansehen der
  Einführung aus den Einstellungen ist die Seite mit dem aktuellen Design
  vorausgewählt und lässt sich überspringen.
