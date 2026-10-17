# Dynamische Sternbewertungen

Stand: 17. Oktober 2026.

1. **Ursache**

   `CompetenceWidget` erzeugte mit `List.generate(5, ...)` immer fünf Symbole. Werte oberhalb fünf wurden dadurch visuell abgeschnitten. Das Model dokumentierte ebenfalls fest „0 bis 5“. Der Parser begrenzte den Wert zwar nicht auf fünf, wandelte ihn aber mit `double.parse(...).toInt()` um: Nachkommastellen gingen verloren; ungültige Werte konnten Parsefehler auslösen. `tryParse` im Projekt verpackt Fehler und wirft sie erneut, es liefert keinen neutralen Ersatz.

2. **Bisherige Verarbeitung und betroffene Ansichten**

   `api/student/all_subjects` liefert die numerischen Basisnoten. `api/student/subject_detail` liefert die Detailnoten mit `competences`, deren Einträge im vorhandenen Fixture `typeName` und `grade` enthalten. `_parseGrade` und `_parseCompetence` im Noten-Reducer bauen daraus `GradeDetail` und `Competence`. Die Kompetenzbewertungen erscheinen ausschließlich unter Detailnoten in `sorted_grades_widget.dart`, sowohl bei chronologischer Sortierung als auch innerhalb von Notentyp-Gruppen. Numerische Noten, Durchschnitte, Diagramme und Notenrechner verwenden andere Felder.

3. **Belegte Metadaten und Grenzen der API-Analyse**

   Das vorhandene Webseiten-Fixture `source` in `test/parse_webpage_test.dart` enthält im JavaScript-Objekt `config` die Felder `competence_stars_enabled: true`, `competence_stars_scale: 5` und `competence_grade_decimals: false`. `Wrapper.parseConfig` las bisher keines dieser drei Felder ein. Das vorhandene Detailnoten-Fixture in `test/parse_test.dart` enthält keinen kompetenzspezifischen Maximalwert. Die Änderung nutzt ausschließlich das belegte Feld `competence_stars_scale`. Sie erfindet weder neue API-Felder noch Endpunkte. Die Varianten mit anderen Skalen sind gezielt veränderte Fixtures, keine aufgezeichneten Antworten entsprechender Schulen.

4. **Lösung und Fallback**

   `Wrapper.parseConfig` liest die optionale Skala neu ein und validiert sie als positive ganze Zahl. Fehlende, ungültige oder mehrfach vorkommende Angaben bleiben unbekannt. `Config.competenceStarsScale` wird mit dem bestehenden Config-Serializer gespeichert; ältere gespeicherte Konfigurationen ohne dieses Feld bleiben lesbar.

   `SortedGradesViewModel.from` übernimmt die Skala aus der aktuellen Konfiguration. `SortedGradesWidget`, `SubjectWidget`, `GradeTypeWidget` und `GradeWidget` reichen sie bis `CompetenceWidget` weiter. Es gibt keinen globalen Maximalwert und keine Ermittlung aus der höchsten bisher gesehenen Bewertung. Jede neue Konfiguration ersetzt die alte Skala, auch wenn die neue Skala unbekannt ist.

   Bei gültigem Wert und bekannter Skala erscheinen genau so viele Sterne wie vorgesehen. Sterne brechen bei Platzmangel um. Bei unbekanntem Maximum erscheint beispielsweise `4 ★ / ?`, bei einem Widerspruch `8 / 6 ?`, bei ungültigem Wert `—`. Widersprüchliche Werte werden weder gekappt noch zu einer anderen Note umgerechnet. Oberhalb von 100 Symbolen wird die Skala ressourcenschonend exakt als Zahlenpaar dargestellt, etwa `777 / 1000 ★`. Diese Schwelle begrenzt die Widget-Anzahl, nicht die Bewertungsskala.

5. **Geänderte Dateien und Funktionen**

   - `lib/app_state.dart`: optionales `Config.competenceStarsScale`.
   - `lib/wrapper.dart`: `parseConfig`, neue Funktion `_readCompetenceStarsScale`.
   - `lib/star_rating.dart`: `parseStarCount`, `parseStarScale`, `parseCompetenceList`, `parseCompetenceMap`.
   - `lib/data.dart`: `Competence.grade` ist optional; veraltete Fünf-Sterne-Dokumentation entfernt.
   - `lib/reducer/grades.dart`: `_parseGrade` und `_parseCompetence` behandeln fehlerhafte Kompetenzdaten kontrolliert.
   - `lib/container/sorted_grades_container.dart`: `SortedGradesViewModel` übernimmt die aktuelle Skala.
   - `lib/ui/sorted_grades_widget.dart`: Weitergabe in beiden Sortierungen und dynamische Darstellung mit `_rating`.
   - `test/star_rating_test.dart`: neue Parser-, Reducer-, Serialisierungs-, Schulwechsel- und Widget-Tests.
   - `test/ui/grades/grades_test.dart`: bestehender Fünf-Sterne-Test erhält explizit die belegte Schulkonfiguration.

   Die betroffenen `built_value`-Dateien wurden mit `dart run build_runner build` neu erzeugt. Generierte `.g.dart`-Dateien werden laut Projektkonfiguration nicht versioniert.

6. **Crash-Sicherheit**

   Kompetenzwerte akzeptieren ganze Zahlen als Zahl oder String, einschließlich Formen wie `6.00`. Fehlende Werte, boolesche Werte, Objekte, negative Werte, echte Bruchteile, NaN und Unendlich ergeben einen unbekannten Wert. Es wird nicht mehr abgeschnitten oder gerundet. Werte oberhalb der plattformübergreifend exakt darstellbaren Ganzzahlgrenze 9007199254740991 werden ebenfalls neutral behandelt.

   Fehlende oder fehlerhafte Kompetenzlisten ergeben eine leere Liste. Fehlerhafte einzelne Einträge bleiben als neutrale Kompetenz sichtbar und verhindern nicht das Laden der übrigen Detailnote. JSON-kodierte Listen und einzelne JSON-kodierte Kompetenzobjekte bleiben unterstützt. Ein fehlender oder falsch typisierter Kompetenzname erhält `—`. Die Absicherung betrifft die Kompetenzdaten; sie ersetzt keine allgemeine Validierung sämtlicher anderer API-Felder.

7. **Tests und Ergebnisse**

   Tests verwenden die vorhandenen Webseiten- und Notenantworten als Grundlage. Abgedeckt sind Skalen 5, 6, 7, 12 und 1000; Null- und Vollbewertungen; fehlerhafte und widersprüchliche Metadaten; ungültige Datentypen und Zahlen; fehlende, leere und JSON-kodierte Kompetenzlisten; Schulwechsel einschließlich unbekannter Skala; Serialisierung; die unveränderte numerische Detailnote 7,50; Sternanzahl und Umbruch auf schmalen Ansichten sowie beide Gruppierungen.

   - Gezielter Lauf vor der abschließenden Ergänzung zur Kompatibilität einzelner JSON-Objekte: 61 Tests bestanden.
   - Abschließender vollständiger Lauf `flutter test`: 515 Tests bestanden, ein Test übersprungen.
   - `flutter analyze`: keine Probleme gefunden.
   - `git diff --check`: keine Fehler.

8. **Verbleibende Einschränkungen**

   Es wurde kein echter Schulaccount und keine Live-Antwort einer Schule mit sechs oder mehr Sternen verwendet. Das belegte Metadatenfeld genügt für die implementierte Dynamik; seine Verfügbarkeit bei jeder Schule ist jedoch nicht nachgewiesen. Das Verhalten bei abweichenden zukünftigen API-Strukturen oder kompetenzspezifischen Skalen innerhalb einer Schule kann ohne entsprechende Daten nicht abschließend verifiziert werden. Es werden keine solchen Skalen geraten. Alte Offline-Konfigurationen ohne gespeicherte Skala zeigen das unbekannte Maximum, bis neue Metadaten geladen wurden. Dezimale Kompetenzbewertungen werden neutral dargestellt; eine fachliche Interpretation als Teilsterne ist anhand der vorhandenen Daten nicht belegt.
