# Dashboard-Redesign – Issue #100

Grundlage sind Skizze und Sprachnachricht des Beta-Testers vom 20.10.2026.

## Entscheidungen zu den offenen Fragen

| Frage | Entscheidung |
| --- | --- |
| Standard-Design | „Neu“. „Legacy“ bleibt unter Einstellungen → Darstellung wählbar. Gespeicherte Einstellungen ohne das Feld öffnen ebenfalls „Neu“. |
| Kopfzeile | App-Logo, Schulname, „Digitales Register“. Der Name kommt aus `schools` über die Adresse des Kontos, bei fremden Adressen wird der Host gezeigt. |
| Striche im Banner | Kompaktes Banner in der Dichte der Karten. Am Rand läuft beim Erscheinen zweimal ein Lichtpunkt; bei „Bewegung reduzieren“ steht er still. |
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
nicht über ihr, sein Blur bleibt also bezahlbar. In der Liste gibt es keinen Blur,
weil er dort beim Scrollen am teuersten wäre. `GlassPerformance` misst die
Raster-Zeit: Verpassen über 25 % von 120 Frames das Budget, bleibt die Oberfläche
für die Sitzung einfarbig. Das gilt auch im Hochkontrastmodus.

Der Rest des Glases ist Licht, nicht Blur, und kostet deshalb fast nichts:
`GlassEdge` malt einen feinen Rand und einen weichen Schein, beides statische
Verläufe aus den Rollen des Themes (`GlassLight`). Das darf auch in der Liste
stehen: Übersichtsbox, Filter, Vergangenheit und „+“. Fällt der Blur weg, bleibt
das Licht; im Hochkontrastmodus entfällt es ganz.

Die Linse der Navigationsleiste gleitet auf einer Feder zum gewählten Eintrag,
streckt sich dabei mit ihrer Geschwindigkeit, und Symbole unter ihr wachsen leicht.
Das ersetzt Brechung, die einen zweiten Backdrop bräuchte. Bei „Bewegung
reduzieren“ springt sie. Die Leiste am Rand breiter Fenster zeigt dieselbe Füllung
und denselben Rand, ohne zu gleiten.

Die Deckkraft ist so gewählt, dass Text über dem ungünstigsten Hintergrund AA
erreicht; die Tests rechnen das für jede Akzentfarbe nach. Auf hellen Sheets
reicht `primary` dafür nicht, weil darunter der dunkle Scrim liegt. `GlassSheet`
setzt deshalb dort `onPrimaryContainer` als `primary`.

Bewusst nicht verwendet:

- Schein auf den Bannern: Im hellen Design wirkte er glänzend und schwächte die
  Farben, die dort eine Bedeutung haben.
- Blur oder Lupe in der Linse: Ein zweiter Backdrop in der Leiste bringt über dem
  schon verschwommenen Hintergrund sichtbar nichts.
- Sättigung im Backdrop-Filter: kaum sichtbar bei dieser Deckkraft, aber ein
  zusätzlicher Filterdurchgang.
- Fragment-Shader für Brechung: Shader in `ImageFilter` gibt es nur mit Impeller,
  Linux und Windows wären außen vor.
- Dialoge: Ihr Theme gilt auch für Legacy.

## Beta-Rollout

Die Veröffentlichung erfolgt manuell und zuerst im Beta-Kanal.

- [ ] Beta-Build verteilen und Rückmeldung des Testers einholen
- [ ] Offene Punkte aus „Herkunft der Banner-Daten“ mit einem echten Konto prüfen
- [ ] Ladinische Texte (`lld.json`) von einer Muttersprachlerin oder einem
      Muttersprachler prüfen lassen
- [ ] Nach der Freigabe `screenshots/01-dashboard.png` bis
      `05-pruefungskalender.png` für Store und Flathub neu aufnehmen
