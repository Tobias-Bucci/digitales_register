# Onboarding: Kurze Einführung

Die frühere Spotlight-Tour (sieben interaktive Schritte, die echte Bedienelemente
markierten und Aktionen verlangten) wurde durch eine kurze, ganzseitige
Einführung ersetzt (`lib/tutorial/intro_tour.dart`).

## Inhalt

Sieben Seiten (#109), jede mit einer Überschrift, höchstens zwei kurzen Sätzen
und einer Illustration. Die Illustrationen (`lib/tutorial/intro_illustrations.dart`)
zeigen das neue Design im Kleinen und sind aus denselben Bausteinen gezeichnet
wie die App: `GlassCard`, `GlassEdge`, `GlassLens`, `navigationBarTint`, die
Ziele aus `AppDestination` und die Fächerpaletten aus `AppPalette`. Sie liegen
auf einer festen Fläche (320 × 210), die auf den verfügbaren Platz skaliert
wird, haben keinen Blur und keine Bilder und werden von Screenreadern
übersprungen, weil der Text der Seite sagt, was sie zeigen.

1. **Willkommen!** – mit Sprachauswahl (Deutsch, Italiano, Ladin, English).
2. **Alles auf einen Blick** – die kompakte Liste, farbige Hinweise, welche
   Karten oben stehen, legt man in den Einstellungen fest.
3. **Immer in Reichweite** – Leiste unten auf dem Handy, Leiste am Rand im
   breiten Fenster; Absenzen, Klassenbuch und Materialien unter Extras, die
   Einstellungen unter Profil.
4. **Nichts verpassen** – die Glocke, die Filter Alle / Schule / App und
   „Nur ungelesene“.
5. **Fächerfarben** – Farben je Fach, gewählt aus vier Paletten unter
   Einstellungen › Aussehen › Fächerfarben.
6. **Ganz nach deinem Geschmack** – Sprache, Design, Hell/Dunkel und
   Erinnerungen unter Profil › Einstellungen, dort auch diese Einführung.
7. **Wähle dein Design** – neues Design (empfohlen) oder Legacy, mit
   gezeichneter Vorschau beider Designs statt einer Illustration (#108).

Ab 720 px Breite steht die Illustration neben dem Text. Bei großer Schrift
wird die Illustration kleiner, und jede Seite scrollt; „Überspringen“ wird
eher verkleinert als getrennt.

## Bedienung

- Fortschrittsanzeige („Schritt n von 7“), die Screenreader bei jedem
  Seitenwechsel ansagen (Live-Region), und animierte Seitenpunkte.
- Überschriften sind als Überschrift ausgezeichnet. Ausgeblendete Knöpfe
  (Zurück auf der ersten, Überspringen auf der letzten Seite) sind auch für
  Screenreader weg.
- Überspringen oben rechts, Zurück/Weiter unten, Wischen zwischen Seiten.
- Tastatur: ← / → blättern, Enter geht weiter, solange kein Knopf den Fokus
  hat, Esc überspringt.
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
