# Start-Animation

Beim Kaltstart spielt `AppLaunchAnimation` (`lib/ui/launch/`) eine Logo-Animation
über der App und deckt danach Login oder Dashboard mit einem kreisförmigen
Reveal von der Häkchenspitze auf. Das erste Bild ist identisch mit dem nativen
Splash, das Overlay liegt über `MaterialApp` und wird am Ende aus dem Baum
entfernt.

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `lib/ui/launch/launch_tokens.dart` | Alle Timings, Kurven, Bewegungsgrößen, Farben (hell/dunkel) und die Logo-Geometrie (aus `assets/index.png` vermessen) |
| `lib/ui/launch/launch_logo_painter.dart` | `CustomPainter` für Hintergrund, Logo, Lichtreflex und Reveal |
| `lib/ui/launch/app_launch_animation.dart` | Widget, Choreografie, Warteschleife, Skip, Reduced Motion, `appLaunchGate` |
| `tool/launch_assets/generate_test.dart` | Erzeugt die nativen Splash-Assets aus denselben Tokens |

Ablauf: `main.dart` übergibt `RegisterApp` das Future `_launchTargetReady()`.
Es wird erfüllt, sobald die Start-Middleware (`_loadAccounts`) Login oder
Dashboard gewählt hat (`appLaunchGate.open()`) und die Routen-Transition
abgeschlossen ist. Bei einem gespeicherten Login ist das der Moment, in dem
die gespeicherten Daten offline angemeldet sind; die Online-Anmeldung und das
erste Laden laufen danach sichtbar im Dashboard weiter
(`docs/performance/startup-loading.md`). Ist es nach 1,3 s noch offen, „atmet“ das Häkchen, bis es
erfüllt ist. Fehler beim Start öffnen das Gate ebenfalls.

## Anpassen

- Timings, Kurven und Bewegungsgrößen: `LaunchTimings`, `LaunchCurves`,
  `LaunchMotion` in `launch_tokens.dart`.
- Logo-Größe: `LaunchLayout`. Mobil ist sie fest (160 dp), weil sie dem
  nativen Splash entsprechen muss.
- Farben oder Geometrie geändert? Native Assets neu erzeugen:

  ```bash
  flutter test tool/launch_assets/generate_test.dart
  ```

  Die Hintergrundfarben in `windows/runner/win32_window.cpp` und
  `linux/my_application.cc` werden von Hand gepflegt;
  `test/ui/launch_animation_test.dart` prüft, dass sie zu den Tokens passen.

## Testen und Abschalten

- `--dart-define=DR_LAUNCH_ANIMATION=full|reduced|off` erzwingt eine Variante
  (ohne Angabe entscheidet die Systemeinstellung „Animationen entfernen“).
- `--dart-define=DR_LAUNCH_EXTRA_WAIT_MS=3000` simuliert eine langsame
  Anmeldung (Warteschleife).
- Tippen, Klicken oder eine Taste spult die Animation kurz vor; der Reveal
  läuft trotzdem, aber nie vor dem Ziel-Screen.

## Plattformen

- **Android 12+**: `windowSplashScreenAnimatedIcon` zeigt
  `launch_logo_splash_icon` (288 dp, Logo als 160-dp-Kern im Viewport; ein
  `InsetDrawable` wird vom System nicht mitskaliert). `MainActivity` entfernt
  den Splash ohne System-Überblendung, weil das erste Flutter-Bild identisch ist.
  `values-night-v31` ist nötig, weil der Nacht-Qualifier vor dem API-Level greift.
- **Android < 12**: `drawable/launch_background.xml` (Farbe + Vector-Logo).
- **iOS**: `LaunchScreen.storyboard` mit `LaunchImage` (160 pt, hell/dunkel) und
  `LaunchBackground`. iOS cached Launch-Screens; nach Änderungen die App
  löschen und neu installieren.
- **Windows**: Das Fenster wird erst nach dem ersten Flutter-Frame gezeigt;
  der Fensterhintergrund folgt dem System-Theme.
- **Linux**: Ebenso über das `first-frame`-Signal von `FlView`; die
  Hintergrundfarbe ist eine Schätzung aus den GTK-Einstellungen.

Nach dem Ändern oder Löschen von Android-Ressourcen kann der inkrementelle
Gradle-Build veraltete Referenzen melden; dann hilft `flutter clean`.
