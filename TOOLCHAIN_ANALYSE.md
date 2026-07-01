# Toolchain- und Versionsanalyse

Stand: 2026-07-01, nach Modernisierung

Projekt: `digitales_register`

## Zusammenfassung

Dieses Projekt ist eine Flutter-App mit Android-, iOS-, macOS-, Windows-, Linux- und Web-Zielen.

Der aktuelle modernisierte Stand baut erfolgreich als Android-Debug-APK mit Android SDK 37.

| Bereich | Aktuell verwendet |
| --- | --- |
| App-Version | `1.10.5+34` |
| Flutter | `3.44.4 stable` |
| Dart SDK lokal | `3.12.2` |
| DevTools | `2.57.0` |
| Gradle Wrapper | `9.6.1` |
| Android Gradle Plugin | `9.2.0` |
| Kotlin Gradle Plugin | `2.3.21` |
| Google Services Gradle Plugin | `4.4.4` |
| JDK fuer Flutter/Gradle | Temurin `17.0.18+8` |
| Java Compile/Target | `17` |
| Kotlin JVM Target | `17` |
| Android compileSdk | `37` |
| Android targetSdk | `37` |
| Android minSdk | Flutter default `24` |
| Android NDK | `28.2.13676358` |
| Android SDK Pfad | `C:\Users\mainb\AppData\Local\Android\Sdk` |
| Flutter SDK Pfad | `C:\flutter` |
| Firebase BoM Android | `34.13.0` |
| iOS Deployment Target | `14.0` |
| macOS Deployment Target | `10.14` |
| Visual Studio | Community 2026 `18.7.3` |
| Windows SDK | `10.0.26100.0` |

## Verifikation

Ausgefuehrt und erfolgreich:

```powershell
flutter analyze
flutter build apk --debug
```

Der Android-Debug-Build erzeugt:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

Hinweis: `flutter test` wurde in diesem Durchlauf nicht final abgeschlossen, weil der vorherige Turn unterbrochen wurde.

## Flutter und Dart

Lokal installierte Version:

```text
Flutter 3.44.4 • channel stable
Framework revision ad70ec4617
Engine revision a10d8ac38d
Dart 3.12.2
DevTools 2.57.0
```

Flutter SDK Pfad:

```text
C:\flutter
```

Projekt-Constraint aus `pubspec.yaml`:

```yaml
environment:
  sdk: ">=3.3.0 <4.0.0"
```

Wichtig: Das Projekt selbst erlaubt noch Dart `>=3.3.0`, der aktuelle Lockfile-Stand wird aber praktisch mit der aktuellen Flutter/Dart-Toolchain gepflegt. Eine spaetere bewusste Anhebung des SDK-Constraints waere sinnvoll, ist aber fuer den aktuellen Build nicht zwingend.

## Android Toolchain

Flutter Doctor meldet:

```text
Android SDK version 37.0.0
Platform android-37.0
Build-tools 37.0.0
Java binary: C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot\bin\java
Java version: OpenJDK Runtime Environment Temurin-17.0.18+8
All Android licenses accepted.
```

Installierte Android SDK Platforms:

```text
android-28
android-30
android-31
android-33
android-34
android-35
android-36
android-37.0
```

Installierte Android Build Tools:

```text
29.0.2
30.0.3
33.0.3
34.0.0
35.0.0
36.0.0
37.0.0
```

Android App-Konfiguration aus `android/app/build.gradle`:

```groovy
android {
    namespace "it.bucci.digitalesregister"
    compileSdk 37
    ndkVersion "28.2.13676358"

    defaultConfig {
        applicationId "it.bucci.digitalesregister"
        minSdkVersion flutter.minSdkVersion
        targetSdk 37
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }
}
```

Damit gilt aktuell:

| Wert | Version |
| --- | --- |
| `compileSdk` | `37` |
| `targetSdk` | `37` |
| `minSdk` | `24` |
| `applicationId` | `it.bucci.digitalesregister` |
| `namespace` | `it.bucci.digitalesregister` |
| `ndkVersion` | `28.2.13676358` |

## Gradle

Gradle Wrapper aus `android/gradle/wrapper/gradle-wrapper.properties`:

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.6.1-all.zip
```

Tatsaechlich ausgefuehrte Wrapper-Version:

```text
Gradle 9.6.1
Kotlin: 2.3.21
Groovy: 4.0.32
Ant: 1.10.17
Daemon JVM: C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot
```

Hinweis: `java` im normalen Windows PATH zeigt weiterhin zuerst auf Java 8. Gradle verwendet in diesem Projekt trotzdem JDK 17, weil `org.gradle.java.home` explizit gesetzt ist.

## Gradle Plugins

Aus `android/settings.gradle`:

```groovy
plugins {
    id "dev.flutter.flutter-plugin-loader" version "1.0.0"
    id "com.android.application" version "9.2.0" apply false
    id "com.android.library" version "9.2.0" apply false
    id "org.jetbrains.kotlin.android" version "2.3.21" apply false
    id "com.google.gms.google-services" version "4.4.4" apply false
}
```

Aus `android/app/build.gradle`:

```groovy
plugins {
    id "com.android.application"
    id "org.jetbrains.kotlin.android"
    id "dev.flutter.flutter-gradle-plugin"
    id "com.google.gms.google-services"
}
```

## JDK und Java

Projektseitig fuer Gradle festgelegt in `android/gradle.properties`:

```properties
org.gradle.java.home=C:/Program Files/Eclipse Adoptium/jdk-17.0.18.8-hotspot
```

Diese JDK-Version:

```text
openjdk version "17.0.18" 2026-01-20
OpenJDK Runtime Environment Temurin-17.0.18+8
OpenJDK 64-Bit Server VM Temurin-17.0.18+8
```

Android Compile-Optionen:

```groovy
compileOptions {
    coreLibraryDesugaringEnabled true
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
}

kotlinOptions {
    jvmTarget = '17'
}
```

## Gradle Einstellungen

Aus `android/gradle.properties`:

```properties
org.gradle.jvmargs=-Xmx4096M -XX:MaxMetaspaceSize=1024m -Dkotlin.daemon.jvm.options=-Xmx2048M
android.useAndroidX=true
android.enableJetifier=false
org.gradle.java.home=C:/Program Files/Eclipse Adoptium/jdk-17.0.18.8-hotspot
android.builtInKotlin=false
android.newDsl=false
```

Bewertung:

- AndroidX ist aktiviert.
- Jetifier ist deaktiviert.
- Gradle nutzt explizit JDK 17.
- `android.builtInKotlin=false` und `android.newDsl=false` sind aktuell bewusst gesetzt, damit AGP 9.2.0 mit mehreren Flutter-Plugins funktioniert, die noch klassisch `kotlin-android` bzw. alte Android Gradle APIs verwenden.
- Flutter warnt deshalb beim Build, dass kuenftige Flutter-Versionen eine vollstaendige Built-in-Kotlin-Migration verlangen koennen.

## Android Dependencies

Aus `android/app/build.gradle`:

```groovy
dependencies {
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.5"
    implementation "com.google.errorprone:error_prone_annotations:2.28.0"
    implementation "com.google.code.findbugs:jsr305:3.0.2"
    implementation platform('com.google.firebase:firebase-bom:34.13.0')
    implementation 'com.google.firebase:firebase-analytics'
}
```

## Lokale Plugin-Patches

Zwei Pub-Pakete sind jetzt lokal vendort, weil sie fuer AGP 9.2.0 und SDK 37 angepasst werden mussten:

| Package | Version | Pfad | Grund |
| --- | --- | --- | --- |
| `biometric_storage` | `5.0.1` | `packages/biometric_storage` | Android `compileSdk 37`; AGP-9-kompatibles Kotlin-Plugin-Verhalten |
| `file_picker` | `11.0.2` | `packages/file_picker` | Klassisches KGP-Verhalten bei `android.builtInKotlin=false` unter AGP 9 |

Diese lokalen Packages sind in `analysis_options.yaml` ausgeschlossen, damit die Root-App-Analyse nicht deren Examples und eigene Analyzer-Konfigurationen mitprueft.

## Direkte Pub Dependencies

Die folgenden Versionen stammen aus `pubspec.lock`, also aus dem aktuell aufgeloesten Stand.

### Main Dependencies

| Paket | Version | Quelle |
| --- | --- | --- |
| `badges` | `3.2.0` | hosted |
| `biometric_storage` | `5.0.1` | local path: `packages/biometric_storage` |
| `built_collection` | `5.1.1` | hosted |
| `built_redux` | `7.5.11` | local path: `packages/built_redux` |
| `built_value` | `8.12.6` | hosted |
| `charts_flutter` | `0.11.0` | local path: `packages/charts_repo/charts_flutter` |
| `collapsible_sidebar` | `1.0.0` | local path: `packages/collapsible_sidebar` |
| `collection` | `1.19.1` | hosted |
| `cookie_jar` | `4.0.9` | hosted |
| `deleteable_tile` | `0.0.1-nullsafety.1` | hosted |
| `dio` | `5.10.0` | hosted |
| `dio_cookie_manager` | `3.4.0` | hosted |
| `file_picker` | `11.0.2` | local path: `packages/file_picker` |
| `firebase_analytics` | `12.4.3` | hosted |
| `firebase_core` | `4.11.0` | hosted |
| `firebase_crashlytics` | `5.2.4` | hosted |
| `flutter` | SDK | Flutter SDK |
| `flutter_built_redux` | `0.6.0` | local path: `packages/flutter_built_redux` |
| `flutter_colorpicker` | `1.1.0` | hosted |
| `flutter_local_notifications` | `22.0.1` | hosted |
| `flutter_localizations` | SDK | Flutter SDK |
| `flutter_secure_storage` | `10.3.1` | hosted |
| `flutter_svg` | `2.3.0` | hosted |
| `flutter_widget_from_html_core` | `0.17.2` | hosted |
| `fuzzy` | `0.5.1` | hosted |
| `hive` | `2.2.3` | hosted |
| `html` | `0.15.6` | hosted |
| `http` | `1.6.0` | hosted |
| `image` | `4.9.1` | hosted |
| `intl` | `0.20.2` | hosted |
| `mocktail` | `1.0.5` | hosted |
| `mutex` | `3.1.0` | hosted |
| `open_file` | `3.3.1` | local path: `packages/open_file` |
| `package_info_plus` | `9.0.1` | hosted |
| `path_provider` | `2.1.6` | hosted |
| `quill_delta` | `3.0.0-nullsafety.2` | hosted |
| `quill_delta_viewer` | `0.0.1` | local path: `packages/quill_delta_viewer` |
| `responsive_scaffold` | `0.0.1` | local path: `packages/responsive_scaffold` |
| `scroll_to_index` | `3.0.1` | hosted |
| `scrollable_positioned_list` | `0.3.8` | hosted |
| `shared_preferences` | `2.5.5` | hosted |
| `tuple` | `2.0.2` | hosted |
| `uni_links` | `0.5.0` | local path: `packages/uni_links` |
| `url_launcher` | `6.3.2` | hosted |
| `workmanager` | `0.9.0+3` | hosted |

### Dev Dependencies

| Paket | Version | Quelle |
| --- | --- | --- |
| `build_runner` | `2.15.0` | hosted |
| `built_value_generator` | `8.12.6` | hosted |
| `flutter_launcher_icons` | `0.14.4` | hosted |
| `flutter_test` | SDK | Flutter SDK |
| `golden_toolkit` | `0.15.0` | hosted, discontinued |
| `lint` | `2.8.0` | hosted |
| `matcher` | `0.12.19` | hosted |
| `msix` | `3.18.0` | hosted |
| `quiver` | `3.2.2` | hosted |

### Dependency Override

| Paket | Version | Quelle |
| --- | --- | --- |
| `file` | `6.1.4` | hosted |

## iOS und macOS

Diese Analyse hat iOS/macOS nicht neu gebaut. Die Projektkonfiguration bleibt:

| Bereich | Wert |
| --- | --- |
| iOS Deployment Target | `14.0` |
| macOS Deployment Target | `10.14` |
| CocoaPods iOS laut altem Lockfile | `1.16.2` |
| CocoaPods macOS laut altem Lockfile | `1.12.1` |

Nach den Pub-Upgrades sollten `pod install` bzw. Flutter-iOS/macOS-Builds auf einem macOS-System separat geprueft werden.

## Windows und Web

Flutter Doctor meldet:

```text
Visual Studio Community 2026 18.7.3
Windows 10 SDK version 10.0.26100.0
```

Chrome wird weiterhin nicht gefunden:

```text
[X] Chrome - develop for the web
Cannot find Chrome executable at .\Google\Chrome\Application\chrome.exe
```

Edge ist vorhanden:

```text
Edge (web) • web-javascript • Microsoft Edge 149.0.4022.98
```

## Verbundene Geraete

Flutter Doctor meldet:

```text
SM S926B (mobile) • android-arm64 • Android 16 (API 36)
Windows (desktop) • windows-x64
Edge (web) • web-javascript • Microsoft Edge 149.0.4022.98
```

## Auffaelligkeiten und Risiken

### 1. System-Java ist weiter Java 8

Der normale PATH findet zuerst Oracle Java 8. Gradle und Flutter verwenden aber JDK 17 durch Projekt-/Flutter-Konfiguration.

Empfehlung: Java 17 im PATH vor Java 8 setzen oder Java 8 entfernen, falls nicht mehr benoetigt.

### 2. AGP 9 laeuft mit klassischem KGP-Kompatibilitaetsmodus

Aktuell sind gesetzt:

```properties
android.builtInKotlin=false
android.newDsl=false
```

Das ist bewusst so, weil mehrere Flutter-Plugins noch nicht sauber auf AGP-9-Built-in-Kotlin bzw. neue Android Gradle APIs migriert sind. Der Build funktioniert damit, aber Flutter zeigt Zukunftswarnungen.

### 3. Lokale Plugin-Forks muessen gepflegt werden

`biometric_storage` und `file_picker` liegen jetzt lokal im Repo. Bei spaeteren Upstream-Releases sollte geprueft werden, ob diese lokalen Anpassungen wieder entfernt werden koennen.

### 4. Chrome fehlt fuer Flutter Web

Web-Entwicklung ueber Edge ist moeglich. Fuer Chrome-Debugging muss Chrome installiert oder `CHROME_EXECUTABLE` gesetzt werden.

## Quellen

Gepruefte Projektdateien:

```text
pubspec.yaml
pubspec.lock
.flutter-plugins-dependencies
analysis_options.yaml
android/gradle.properties
android/settings.gradle
android/build.gradle
android/app/build.gradle
android/gradle/wrapper/gradle-wrapper.properties
packages/biometric_storage/android/build.gradle
packages/file_picker/android/build.gradle
```

Ausgefuehrte Pruefkommandos:

```powershell
flutter --version
flutter doctor -v
flutter pub get
flutter analyze
flutter build apk --debug
.\gradlew.bat --version
```
