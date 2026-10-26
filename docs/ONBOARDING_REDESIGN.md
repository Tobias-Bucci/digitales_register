# Onboarding: Kurze Einführung

Die frühere Spotlight-Tour (sieben interaktive Schritte, die echte Bedienelemente
markierten und Aktionen verlangten) wurde durch eine kurze, ganzseitige
Einführung ersetzt (`lib/tutorial/intro_tour.dart`).

## Inhalt

Fünf Seiten mit je einer Illustration aus Paletten-Formen, einer Überschrift und
höchstens zwei kurzen Sätzen:

1. **Willkommen** – inklusive Sprachauswahl (Deutsch, Italiano, Ladin, English).
2. **Dashboard** – Hausaufgaben, Tests und anpassbare Karten.
3. **Noten** – Durchschnitte und Notenrechner.
4. **Kalender & Absenzen** – Stundenplan, Prüfungen, Voraus-Absenzen.
5. **Einstellungen** – Hell/Dunkel/AMOLED, Benachrichtigungen, Tutorial.

## Bedienung

- Fortschrittsanzeige („Schritt n von 5“) und animierte Seitenpunkte.
- Überspringen oben rechts, Zurück/Weiter unten, Wischen zwischen Seiten.
- Tastatur: ← / → blättern, Esc überspringt.
- Bei reduzierten Animationen wird ohne Übergänge geblättert.

## Anzeige

`TutorialService` bietet die Einführung einmalig nach dem ersten Login an
(`tutorial.v3.seen`). Wer die alte Tour bereits gesehen hatte (`tutorial.v2.*`),
bekommt die neue nicht automatisch angezeigt; die alten Schlüssel werden
entfernt. In den Einstellungen startet „Einführung ansehen“ sie jederzeit erneut.
