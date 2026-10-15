# iOS 1.17.3+50: Untersuchung des abgelehnten Build 49

## Nachweis am tatsächlichen IPA

Untersucht am 16.10.2026: `C:/Users/mainb/Downloads/Digitales_Register.ipa`.
Der zuerst angegebene Name `Digitales Register.ipa` mit Leerzeichen existiert
nicht. Es wurde ausschließlich das anschließend genannte Artefakt untersucht;
dessen finale `Payload/Runner.app/Info.plist` bestätigt:

- Bundle-ID `it.bucci.digitalesregister`
- Marketing-Version `1.17.3`, Build `49`
- `NSCameraUsageDescription` und `NSLocationWhenInUseUsageDescription` fehlen.
- IPA-SHA256: `7881e2cfdade2b9f7d11560d1cc9777ded38e9f67d71c1d79e110e9394a53dbc`

Im **Mach-O-Hauptprogramm Runner** wurden folgende Byte-/Symbolnamen gefunden:

| Referenz | Vorkommen |
| --- | ---: |
| UIImagePickerController | 12 |
| AVCaptureDevice / AVCaptureSession | 7 / 5 |
| requestAccessForMediaType | 1 |
| CLLocation / requestWhenInUseAuthorization | 35 / 1 |
| startUpdatingLocation | 1 |
| DKCamera / DKAsset | 52 / 103 |
| DKImagePickerController / DKPhotoGallery | 148 / 134 |

Zusätzlich sind die Klassenbezeichnungen `DKCameraLocationManager` und
`DKCameraPhotoCapturer` vorhanden. Runner bindet über Mach-O-Load-Commands
`CoreLocation.framework`, `AVFoundation.framework` und `libswiftCoreLocation.dylib`
ein. Die zehn separat eingebetteten Mach-O-Frameworks (u.a. Flutter, App,
FirebaseAnalytics, GoogleAppMeasurement, biometric_storage, open_file, uni_links)
enthielten keine der gezielt gesuchten Kamera-/Standortreferenzen.

Dies weist den mitgelieferten SDK-Code nach, keine vom Nutzer aufgerufene
Kamerafunktion. Der Flutter-Code verwendet bestehende Bilder als Profilbilder
und Dokumente als Anhänge; Kameraaufnahme und Geräteortung sind dort nicht
implementiert. Ein SDK kann Berechtigungs-APIs enthalten, obwohl die App diese
Funktion nicht nutzt. Apple beanstandet hier bereits das ausgelieferte Artefakt.

## Warum der vorherige Versuch nicht genügte

Die bisherige Einstellung `Pod::PICKER_LEGACY_MEDIA = false` betrifft CocoaPods.
Der ebenfalls vorhandene Swift-Package-Pfad aktivierte dagegen weiterhin
`PICKER_LEGACY_MEDIA` und zog DKImagePickerController ein. Dessen
[Package.swift 4.3.9](https://github.com/zhangao0086/DKImagePickerController/blob/4.3.9/Package.swift)
bindet **DKCamera**, DKPhotoGallery und TOCropViewController zusätzlich ein.
Die inzwischen entfernte lokale `Package.resolved` enthielt diese Abhängigkeiten.
Der [DKCamera-Stand aus dieser Auflösung](https://github.com/zhangao0086/DKCamera/blob/5c691d11014b910aff69f960475d70e65d9dcc96/DKCamera/DKCameraLocationManager.swift)
enthält selbst `requestWhenInUseAuthorization()`; die Standortreferenzen beschränken
sich deshalb nicht auf DKAssets Standort-Metadaten.

Das IPA enthält Swift-Package-Ressourcen mit folgenden Kennungen:

- `file-picker.file-picker.resources`
- `dkimagepickercontroller.DKImagePickerController.resources`
- `dkphotogallery.DKPhotoGallery.resources`

Zusammen mit dem statisch eingebundenen DKCamera-Code belegt das den
Swift-Package-Abhängigkeitspfad im Artefakt. Der bisherige CocoaPods-Lock enthält
DKCamera gerade nicht und erklärt diese zusätzliche Komponente nicht. Die lokale
Flutter-Metadatei meldet zwar SPM deaktiviert; sie beweist nicht die Einstellung
des entfernten Codemagic-Runners. Ob dort SPM aktiviert war oder entsprechende
generierte Dateien aus einem Cache übernommen wurden, lässt sich ohne Build-Logs
nicht unterscheiden. Eine pauschale Behauptung, CocoaPods habe die Konstante
ignoriert, ist durch diese Untersuchung nicht belegt.

Weitere Lücken: Die eingecheckte `ios/Podfile.lock` enthält noch die alten
DK-Pods. Die Plugin-Registrierung registriert file_picker regulär, entscheidet
aber nicht über dessen transitive SDKs. Das bisherige Build-Skript prüfte nur
Versionswerte im Archiv, keine nativen Referenzen und nicht das exportierte IPA.
Eine Liste der eingebetteten Frameworks allein übersieht statisch in Runner
eingebundene Bibliotheken.

## Änderungen für Build 50

- `pubspec.yaml`: **1.17.3+50**. Runner-Info.plist und alle drei Xcode-Konfigurationen
  verwenden weiterhin die Flutter-Versionsvariablen und die bestehende Bundle-ID.
- `packages/file_picker/ios/file_picker.podspec`: keine DK-Abhängigkeit mehr,
  unabhängig von Podfile-Konstanten; PHPicker-Mindestversion iOS 14.
- `packages/file_picker/ios/file_picker/Package.swift`: ebenfalls ohne DK-Pakete
  und Legacy-Definition; Mindestversion iOS 14. Alte `Package.resolved` entfernt.
- `FilePickerPlugin.m` und zugehöriger Header: alte UIImagePicker-/DK-Pfade
  physisch entfernt. Die bisherige PHPicker-Auswahl und Dokumentauswahl bleiben
  erhalten. Die App unterstützt ohnehin erst iOS 15.
- `ios/Podfile`: unnötige Opt-out-Konstante entfernt; Installation bricht ab,
  wenn unerwartet doch DK-Pod-Targets aufgelöst werden.
- `tool/check_ios_release.py`: statische Prüfung beider Plugin-Manifeste und
  nativer Quellen gegen die alten APIs/Abhängigkeiten.
- `tool/inspect_ios_artifact.py`: prüft die finale Info.plist, Bundle-ID,
  Version/Build, alle Mach-O-Dateien einschließlich Runner, native
  Load-Commands, sensible API-Namen und alte Ressourcen. Gibt Framework-Versionen,
  SHA256-Werte und Diagnose-JSON aus. Unerwartete Referenzen oder falsche
  Release-Werte führen zum Abbruch, auch wenn Purpose-Strings vorhanden wären.
- `tool/test_inspect_ios_artifact.py`: sechs Tests mit synthetischen Binärdaten
  für die Artefaktprüfung.
- `tool/build_ios_release.sh`: bereinigt Flutter-Ausgaben, lokale Pods,
  Plugin-Symlinks und generierte SPM-Dateien; prüft den lokalen file_picker-Pfad;
  erzeugt die iOS-Konfiguration und löst Pods neu auf. Prüft anschließend sowohl
  das Archiv als auch das tatsächlich exportierte IPA. Der frühere Bericht
  `docs/IOS_UPLOAD_FIX_49.md` verweist nun auf diese Untersuchung.

Keine neuen Purpose-Strings oder Laufzeit-Berechtigungsanfragen: Für eine nicht
implementierte Kamera-/Ortungsfunktion wäre eine entsprechende Zweckbehauptung
unwahr. Stattdessen wird der ungenutzte SDK-Code aus beiden Build-Pfaden entfernt.
Die bestehende Info.plist und ihre Foto-/Face-ID-Texte bleiben unverändert.
Signierungszertifikate, Provisioning und Zugangsdaten wurden nicht geändert.

## Codemagic

Es gibt weiterhin keine Codemagic-YAML im Repository und keinen Zugriff auf die
externe Workflow-Konfiguration. Im vorhandenen macOS-Workflow muss der
iOS-Build-Schritt dieses Skript verwenden:

```sh
bash tool/build_ios_release.sh
```

Es leitet `--build-name=1.17.3` und `--build-number=50` explizit aus pubspec ab,
unabhängig vom Codemagic-Zähler `BUILD_NUMBER`, und prüft die tatsächlichen Werte
in Archiv **und IPA**. Bestehende Exportoptionen können mit
`IOS_EXPORT_OPTIONS_PLIST` übergeben werden. Bestehende Signierungsvorbereitung
bleibt vor dem Skript; Veröffentlichung darf erst nach seinem erfolgreichen
Abschluss erfolgen. Keinen späteren Build/Versionspatch und keine spätere
Wiederherstellung von Build-Caches ausführen. Nur das frisch geprüfte IPA unter
`build/ios/ipa/` veröffentlichen. Bei einem Gate-Fehler darf der Workflow nicht
mit Upload fortfahren.

Diagnosen als zusätzliche CI-Artefakte sichern: `build/ios/diagnostics/*`.
Sie enthalten die tatsächliche CocoaPods-Auflösung und den Binärbefund.
Die alte Podfile.lock wurde nicht von Hand umgeschrieben: `pod install
--repo-update` muss sie auf macOS anhand der aktuellen Podspecs regenerieren.
Den tatsächlichen neuen Lock anschließend prüfen und übernehmen. Globale Caches
und Signierungsdateien werden vom Skript nicht gelöscht.

## Prüfung und verbleibende Grenzen

Lokal unter Windows:

| Prüfung | Ergebnis |
| --- | --- |
| `flutter analyze` einschließlich Dependency-Auflösung | Erfolgreich, keine Befunde |
| `flutter test --reporter expanded` | 490 bestanden, 1 übersprungen |
| `python tool/check_ios_release.py` | Erfolgreich, 1.17.3 / 50, konsistente Runner-Konfiguration |
| Alle iOS-Plists mit plistlib | Erfolgreich |
| Native Präprozessor-Blöcke, Python- und Shell-Syntax | Erfolgreich |
| 6 Tests der Artefaktprüfung | Erfolgreich |
| Neuer Gate gegen das echte Build-49-IPA | Erwartet abgelehnt, Exit 1, beide fehlenden Beschreibungen und DK-Code erkannt |
| `git diff --check` | Erfolgreich |

Der vollständige lokale Build-49-Befund liegt unter
`build/ios/diagnostics/build49.json`; Log: `build/ios_build49_inspection.log`.
Das Eingabe-IPA wurde nicht verändert. Reproduktion:

```sh
python tool/inspect_ios_artifact.py /path/to/Digitales_Register.ipa \
  --expected-version 1.17.3+49 --report build/ios/diagnostics/build49.json
```

Der neue Prüfbuild kann auf Codemagic mit dem angepassten Skript gestartet werden.
Ein Build-50-IPA liegt lokal noch nicht vor. CocoaPods-/SPM-Auflösung,
Objective-C-/Swift-Kompilierung, Export und Bildauswahl auf einem Gerät sind erst
unter macOS prüfbar. Die API-Suche ist eine konservative Prüfung bekannter
Referenzen, kein vollständiger Ersatz für Apples Validierung. Sie erkennt auch
statische SDK-Reste, beweist aber weder die Ausführung einer API noch die
Abwesenheit jeder denkbaren indirekten Referenz. Erfolgreiche Apple-Validierung
wird erst durch eine neue Rückmeldung von Apple nachgewiesen.
