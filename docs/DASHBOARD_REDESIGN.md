# Dashboard-Redesign – Issue #100

Grundlage sind Skizze und Sprachnachricht des Beta-Testers vom 20.10.2026.

## Entscheidungen zu den offenen Fragen

| Frage | Entscheidung |
| --- | --- |
| Standard-Design | „Neu“. „Legacy“ bleibt unter Einstellungen → Darstellung wählbar. Gespeicherte Einstellungen ohne das Feld öffnen ebenfalls „Neu“. |
| Kopfzeile | App-Logo, Schulname, „Digitales Register“. Der Name kommt aus `schools` über die Adresse des Kontos, bei fremden Adressen wird der Host gezeigt. |
| Striche im Banner | Kompaktes Banner in der Dichte der Karten. Am Rand fällt beim Erscheinen zweimal ein Lichtband von oben nach unten; bei „Bewegung reduzieren“ steht es still. |
| Farbe der Beobachtungen | Violett (`observationContainer`). |
| Oranger Bereich | `gradeCategory()` bleibt unverändert: 5,50–5,75 orange, 6 grün (siehe #81). Der Tester hatte auch die 6 als orange genannt. |
| Absenzen, Materialien | Auf der Seite „Extras“, zusammen mit Klassenbuch, Hausaufgaben und Zeugnis. |
| Dauer eines Banners | Bis zum Öffnen oder Ausblenden, ohne Zeitlimit. |

## Farben

Mitteilungen (blau), Absenzen (gelb) und Beobachtungen (violett) sind Rollen in
`AppStatusColors`. Sie werden aus den Fach-Swatches abgeleitet und hängen daher
nicht von der Akzentfarbe ab.

Noten-Banner sind im neuen Design immer farbig, auch wenn „Noten farbig“ nie
angefasst wurde. Neutral werden sie nur, wenn der Schalter ausdrücklich
ausgeschaltet wurde. Der gespeicherte Wert `colorGrades` kann das nicht zeigen,
weil er in beiden Fällen `false` ist. Deshalb merkt sich `gradeColorsTurnedOff`
diese Entscheidung; nur der Schalter setzt das Feld. `colorGrades` selbst, sein
Standardwert und alles, was davon abhängt, bleiben unverändert, also auch Legacy.

Zwei Folgen davon:

- Wer den Schalter früher ein- und wieder ausgeschaltet hat, ist nicht von
  jemandem zu unterscheiden, der ihn nie benutzt hat, und sieht zunächst farbige
  Banner.
- Bei unberührtem Schalter steht er auf „aus“, die Banner sind aber farbig. Um sie
  neutral zu machen, muss er einmal ein- und wieder ausgeschaltet werden.

## Prozentwert

`gradePercentOf()` rechnet jede Note als Anteil an der Zehnerskala um: 6 → 60 %,
7/8 → 75 %, 8 → 80 %. Das Issue nannte für 7/8 den Wert 87,5 %. Im Register
bedeutet 7/8 aber 7,50, und als Bruch gelesen stünde 7/8 über einer 8. Deshalb
wurde bewusst davon abgewichen.

## Herkunft der Banner-Daten

Die Banner entstehen in `dashboardEvents()` nur aus bereits geladenen Daten, es
gibt keine neuen Anfragen. Note, Durchschnitt und Beschreibung werden über
`objectId` gesucht, zuerst in den Notendetails, dann unter den Noten des
Dashboards. Ohne Treffer zeigt das Banner neutral den Text der Benachrichtigung.

Noch mit echten Daten zu prüfen:

- ob `objectId` einer Noten-Benachrichtigung mit der ID der Note übereinstimmt,
- ob das Portal die Typen `absence` und `observation` überhaupt liefert. Neue
  Beobachtungen werden zusätzlich aus den Dashboard-Einträgen erkannt; Absenzen
  erscheinen nur, wenn der Feed sie meldet.

## Glas und Leistung

Echten Blur haben nur Kopfzeile, Navigationsleiste (in einer gemeinsamen
`BackdropGroup`) und die modalen Sheets. Ein Sheet deckt die Seite ab und scrollt
nicht über ihr, sein Blur bleibt also bezahlbar. Solange die Route es bewegt, auch
unter dem Finger, ist es einfarbig. Erst wenn es ruht, kommt der Blur unter dem noch
deckenden Ton dazu, und der Ton klart in 140 ms zum Glas auf. Sein Inhalt liegt auf
einer eigenen Ebene und wird einmal gemalt, nicht in jedem Frame der Bewegung. In
der Liste gibt es keinen Blur,
weil er dort beim Scrollen am teuersten wäre. `GlassPerformance` misst die
Raster-Zeit: Verpassen über 25 % von 120 Frames das Budget, bleibt die Oberfläche
für die Sitzung einfarbig. Das gilt auch im Hochkontrastmodus.

Der Rest des Glases ist Licht, nicht Blur, und kostet deshalb fast nichts:
`GlassEdge` malt einen feinen Rand und einen weichen Schein, beides statische
Verläufe aus den Rollen des Themes (`GlassLight`). Das darf auch in der Liste
stehen. Fällt der Blur weg, bleibt das Licht; im Hochkontrastmodus entfällt es
ganz.

Das Licht kommt für alle Oberflächen gleich von direkt oben und von nah: Es
erreicht den ganzen Umriss fast gleich, oben nur ganz leicht stärker als unten
(höchstens 1,2 : 1), links und rechts identisch. Der Verlauf läuft über die ganze
Höhe, damit „+“ und ein hohes Sheet gleich betont sind. Schatten haben keinen
horizontalen und nur wenig vertikalen Versatz. Auf hellen Seiten würde ein
Lichtrand allein verschwinden, er liegt dort deshalb innen an einer weichen,
gleichmäßigen Kontur. Das Rezept steht nur in `GlassLight`, `GlassRimPainter` und
`GlassSheenPainter`. Zeilen bekommen nur den Rand, weil ihr
Text auf kräftigen Farben steht. Dialoge, einfache Sheets, Menüs und die
Datums- und Zeitauswahl erben den Rand über `NewDesignTheme` vom Ort, an dem sie
geöffnet werden, und bleiben dadurch in Legacy unberührt. Ein Sheet liegt am
Bildschirmrand an; sein Rand läuft trotzdem an beiden Seiten und unten weiter, damit
der Umriss nicht an den Ecken aufhört. Die
Tests spiegeln gerenderte Flächen pixelgenau.

Die Bindung links am Notizblock-Kästchen gehört zum App-Logo und ist kein Licht.

Zeilen sind so breit wie die Leiste und laufen unter ihr durch. Eine rote Zeile
stand deshalb an den runden Enden der Leiste über und schien durch ihr Glas, was
wie ein rötlicher Rand aussah; Rand, Akzent und Linse sind neutral. Die Seite läuft
deshalb im Abstand über der Leiste kurz aus (`app-navigation-fade`), reicht aber
nicht in diesen Abstand hinein weiter nach oben, damit die letzte Zeile unberührt
bleibt.

Die Linse der Navigationsleiste gleitet auf einer kritisch gedämpften Feder zum
gewählten Eintrag, ohne über ihn hinauszuschwingen, und streckt sich dabei nur
leicht. Sie ist die einzige Antwort auf einen Tipp: Einträge sind deshalb keine
`IconButton`, haben weder Ink noch einen Pressed-Zustand, und Symbole bleiben
gleich groß. Maus und Tastatur sehen trotzdem, wo sie sind (`navigationHoverTint`,
Ring von `GlassFocusRingPainter`), und die Hand bleibt. Bei „Bewegung reduzieren“
springt die Linse.

`GlassLensPainter` malt die Linse: eine durchscheinende Füllung, ein Schein von
genau oben, das Licht, das ihr unterer Rand zurückwirft, und ein Schatten, der nur
außerhalb fällt, weil er sonst durch die Füllung schmutzig wirkt. Das ersetzt
Brechung, die einen zweiten Backdrop bräuchte.

Die Deckkraft ist so gewählt, dass Text über dem ungünstigsten Hintergrund AA
erreicht; die Tests rechnen das für jede Akzentfarbe nach. Auf hellen Sheets
reicht `primary` dafür nicht, weil darunter der dunkle Scrim liegt. `GlassSheet`
setzt deshalb dort `onPrimaryContainer` als `primary`.

Bewusst nicht verwendet:

- Blur oder Lupe in der Linse: Ein zweiter Backdrop in der Leiste bringt über dem
  schon verschwommenen Hintergrund sichtbar nichts.
- Sättigung im Backdrop-Filter: kaum sichtbar bei dieser Deckkraft, aber ein
  zusätzlicher Filterdurchgang.
- Eine schwebende Leiste unten auf dem Desktop: 16:9-Fenster haben Breite übrig,
  aber wenig Höhe.
- Fragment-Shader für Brechung: Shader in `ImageFilter` gibt es nur mit Impeller,
  Linux und Windows wären außen vor.

## Profilbild

Der Avatar in der Leiste lebt so lange wie die App, anders als der in der alten
Seitenleiste, der bei jedem Öffnen neu entstand und dadurch nebenbei neu lud.
`ProfileAvatar` findet deshalb selbst zum Bild:

- Solange kein Bild gezeigt werden kann, stehen die Initialen, nie eine leere
  Fläche. Gilt für fehlend, ladend, fehlgeschlagen und nicht dekodierbar. Leiste und
  Profilmenü zeigen dabei keinen Spinner. Das Bild blendet über ihnen ein; nur das
  Bild bewegt sich, sonst schiene die Seite mitten in der Blende durch.
- Initialen sind die des ersten und letzten Worts des Namens, bei nur einem Wort
  die seiner Teile (`max.muster` → MM). Ohne Buchstaben im Namen steht die Figur.
  Legacy behält die Figur.
- Die Farbe ist ein ruhiger Ton einer der Akzentfarben. Sie hängt am Benutzernamen und
  nicht am Namen, der erst nach dem Laden kommt, und ist dadurch in Leiste, Menü und
  Kontenliste dieselbe.
- Gespeichert und gezeigt wird nur, was sich dekodieren lässt. Eine abgelaufene
  Sitzung antwortet mit Status 200 und der Anmeldeseite; `fetchAuthenticatedBytes`
  meldet sich dann einmal neu an und liefert sonst einen Fehler, statt die Seite
  als Bild weiterzureichen. Ohne Sitzung geht keine Anfrage hinaus.
- Nach einem Fehler versucht es der Avatar nach 2, 5, 15, 30 und 60 Sekunden noch
  einmal und wartet danach. `retryProfilePictures()` weckt es sofort, wenn der
  Grund weg sein kann: nach der Anmeldung und wenn die App wieder online ist.
  Das deckt auch den Neustart ab, bei dem die gespeicherte Adresse vor der Sitzung
  da ist.
- Bilder gehören zur Sitzung: `_clearRuntimeCaches()` vergisst sie, und bei einer
  neuen Adresse verschwindet das alte Bild sofort. Nach einem Upload wird neu
  geladen, auch wenn die Adresse gleich bleibt.

Bilder liegen nur im Speicher. Nach einem Neustart ohne Netz stehen deshalb die
Initialen, bis die App wieder online ist.

## Breite Fenster

Ab 720 px ist die Navigation dieselbe Leiste wie auf dem Handy, nur hochkant: am
linken Rand, schwebend, mit derselben Linse. Beide teilen sich `_LensTrack`. Die
Kopfzeile schwebt ebenfalls und richtet sich an der Spalte aus, Sheets werden zu
zentrierten Panels aus demselben Glas (`showGlassSheet`).

Ab 1080 px teilt `DashboardColumns` das Dashboard: Übersicht und Banner behalten
ihre Handybreite und bleiben stehen, daneben scrollt die Tagesliste. Beide Spalten
zusammen werden nicht breiter als 1220 px, mehr Platz wird zu Rand. Die Liste
selbst reicht bis zum Fensterrand, damit dort auch ihre Scrollleiste liegt.

Flutter zeigt in nativen Desktop-Apps auf Buttons den normalen Pfeil. Das neue
Design setzt über `NewDesignTheme` die Hand, die Tastatur bekommt auf Glas einen
deutlichen Ring (`GlassFocusRing`). Seiten, die Legacy mitbenutzt, begrenzen ihre
Breite nur im neuen Design (`NewDesignReadable`).

## Notenseite

Die Notenseite bekommt im neuen Design eine eigene Darstellung. Daten, Zustand und
Aktionen bleiben dieselben, Legacy bleibt unverändert.

### Ausgangslage

`GradesPage` im neuen Design, aus dem Code und aus Renderings bei 412 × 900:

- Normale `AppBar` mit Titel, Verlauf und Semester-Dropdown, ohne Glas.
- Karte mit dem Diagramm, 220 px hoch, und einem Knopf zum Vollbild.
- Drei Zeilen für Durchschnitt (Zahnrad), Zeugnisdurchschnitt (Info) und Prognose
  (Info).
- Drei Schalter über die volle Breite: nach Art sortieren, gelöschte Noten, farbig.
- Ein Filter für Lieblingsfächer, wenn welche gesetzt sind.
- Fächer als `ExpansionTile`, 58 px pro Zeile. Vom Bildschirm bleibt Platz für vier
  Fächer, die Schalter und Durchschnitte nehmen mehr Höhe ein als die Fächerliste.
- Eine Note hat drei bis fünf Textzeilen, darunter Kompetenzen mit 24-px-Sternen.
  Beobachtungen stehen als `ListTile` dazwischen. Nach Art sortiert kommen
  aufklappbare Gruppen dazu.
- Unten Hinweis auf ausgeschlossene Fächer, Rechner, Statistik (Dialog).
- Offline eine schwarze Pille unten rechts, ohne Daten `NoInternet`, beim Laden ein
  Spinner. Pull-to-Refresh gibt es nicht: `load` holt ohnehin nur veraltete Daten.

### Aufbau

```text
Handy                                 Breites Fenster ab 1080 px
┌──────────────────────────────┐      ┌─────────────────────────────────────────┐
│ Noten      [1|2|Alle]    (⟲) │ Glas │ (Noten            [1. | 2. | Beide] (⟲))│
├──────────────────────────────┤      ├───────────────┬─────────────────────────┤
│ ┌ 1. Semester ─────────────┐ │      │ Übersicht     │ Fächer 12          (⚙) │
│ │ 7,64       7,73 ⓘ        │ │      │ Diagramm      │ (D) Deutsch      7,50 ⌄ │
│ │ ↗ Prognose ca. 7,6     ⓘ │ │      │ Statistik     │ (E) Englisch     8,63 ⌄ │
│ └──────────────────────────┘ │      │ Rechner       │ (M) Mathematik   5,40 ⌄ │
│ ┌ Notenverlauf ──────── ⤢ ─┐ │      │ bleibt stehen │ scrollt für sich        │
│ │ Diagramm, Legende        │ │      └───────────────┴─────────────────────────┘
│ └──────────────────────────┘ │
│ [Statistik]      [Rechner]   │
│ Fächer 12               (⚙)  │
│ (D) Deutsch  ②   7,50     ⌄  │
│ (E) Englisch     8,63     ⌄  │
│     02.10. Test  Vokabeln  8 │
└──────────────────────────────┘
```

Die Wahl trifft `GradesPageContainer` mit `ResponsiveNavigationScope.isActive`, wie
die anderen geteilten Seiten. Einen zweiten Schalter gibt es nicht. Die Navigation
verschwindet beim Wechsel aus dem Baum, die Seite baut sich dadurch sofort als die
andere auf, ohne Neustart.

### Umsetzung

| Datei | Inhalt |
| --- | --- |
| `grades_page_new_container.dart` | Dieselben View-Models wie Legacy, dazu die Farbregel. |
| `grades_page_new.dart` | Kopfzeile, Aufteilung, Zustände. |
| `grades_overview.dart` | Durchschnitte, Prognose, Diagramm, Kacheln. |
| `grades_subject_list.dart` | Fächer und Notenzeilen. |
| `grades_panels.dart` | Alles, was die Seite als Sheet oder Panel öffnet. |
| `grades_format.dart` | Zahlen und Daten nach Sprache, gesprochene Kategorie. |
| `glass_segmented_control.dart` | Der Semesterschalter mit der Linse der Navigation. |

Das Glas ist das des Dashboards: `GlassHeaderShell` ist die Hülle von
`DashboardAppHeader`, `GlassCard` die Box oben auf dem Dashboard, die Linse ist
`GlassLens`. Blur hat nur die Kopfzeile; alles in der Liste hat bloß Licht. Fächer
und Notenzeilen stehen auf deckenden Farben. Jedes Fach liegt auf einer eigenen
Ebene: Öffnet sich eines, rücken die darunter nur, ohne neu gemalt zu werden. Was
zu ist, wird nicht gebaut. Die Fächer stehen trotzdem in einer `Column`, nicht in
einer Lazy-Liste, weil der Sprung vom Banner das Ziel sonst nicht fände.

Bewusste Abweichungen von Legacy:

- Farben folgen `gradeColorsTurnedOff` wie die Banner: Noten sind farbig, bis der
  Schalter ausgeschaltet wird. Der Schalter im Anzeige-Panel zeigt deshalb diesen
  Wert. Das Diagramm liest weiter `colorGrades`, seine Punkte bleiben also, wie sie
  in Legacy sind.
- Die drei Schalter und „Durchschnitt anpassen“ (früher das Zahnrad) liegen im Panel
  „Anzeige“ hinter dem Knopf neben „Fächer“.
- Null Absenzen zeigen kein Abzeichen mehr. In einer Liste, in der fast alle Fächer
  null haben, ist das nur Rauschen.
- Jahr, Beschreibung, Eintragung und Löschgrund einer Note stehen erst im Panel einer
  Note. Die Zeile bleibt so einzeilig. Kompetenzen und Beobachtungen bleiben im Fach.
- Nach Art sortiert wiederholt die Zeile die Art nicht, sie steht in der Überschrift.
- Zahlen und Daten folgen der Sprache, also 7.64 auf Englisch. Der Zustand speichert
  weiterhin die deutsche Schreibweise, und Legacy zeigt sie.

Über 130 % Textgröße rutschen Datum und Gewichtung unter den Titel der Zeile, sonst
reicht ein Handy mit 320 px nicht. Die Seite begrenzt die Textgröße bei 200 %.

Unverändert und für beide Designs gleich bleiben die Vollbildseite des Diagramms
und die beiden Rechner. Sie liegen auf dem Root-Navigator, also außerhalb von
`NewDesignTheme`.

Die Texte `grades.*` in `lld.json` sind neu und noch ungeprüft, siehe Beta-Rollout.

### Leistung

Gemessen am 06.11.2026 mit einem Profile-Build unter Windows (Impeller), 22 Fächern
und isolierten Daten. Je zwei abwechselnde Läufe pro Variante, nach einem
Aufwärmdurchgang, in Millisekunden pro Frame:

| Vorgang | Breite | Design | Raster Ø | Raster p99 | Build Ø | Frames über 16,7 ms |
| --- | --- | --- | --- | --- | --- | --- |
| Scrollen | 412 | Neu | 5,9–6,2 | 10,8 | 0,2 | 2 von 5929 |
| Scrollen | 412 | Legacy | 1,1 | 1,8 | 0,5 | 0 von 7088 |
| Scrollen | 1280 | Neu | 5,9–6,1 | 9,2–10,2 | 0,2 | 0 von 6025 |
| Scrollen | 1280 | Legacy | 2,1 | 3,5 | 0,5 | 0 von 7052 |
| Auf- und Zuklappen | 412 | Neu | 4,3–4,6 | 7,0 | 0,9 | 0 von 5131 |
| Auf- und Zuklappen | 412 | Legacy | 1,1–1,3 | 2,1 | 1,1–1,5 | 0 von 4613 |
| Auf- und Zuklappen | 1280 | Neu | 4,8 | 7,1 | 0,6 | 0 von 4965 |
| Auf- und Zuklappen | 1280 | Legacy | 2,0 | 3,5 | 1,3 | 0 von 4684 |

Der höhere Rasterwert ist der Preis des Blurs von Kopfzeile und Leiste, den Legacy
nicht hat. Der Build ist niedriger als in Legacy. Die Liste ist in Neu kürzer, die
Wege beim Scrollen sind also nicht gleich lang. Geräte mit schwacher GPU fängt
`GlassPerformance` ab; auf einem Handy gemessen wurde das nicht.

## Beta-Rollout

Die Veröffentlichung erfolgt manuell und zuerst im Beta-Kanal.

- [ ] Beta-Build verteilen und Rückmeldung des Testers einholen
- [ ] Offene Punkte aus „Herkunft der Banner-Daten“ mit einem echten Konto prüfen
- [ ] Ladinische Texte (`lld.json`, auch die neuen `grades.*`) von einer Muttersprachlerin oder einem
      Muttersprachler prüfen lassen
- [ ] Nach der Freigabe `screenshots/01-dashboard.png` bis
      `05-pruefungskalender.png` für Store und Flathub neu aufnehmen
