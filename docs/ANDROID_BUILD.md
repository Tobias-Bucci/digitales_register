# Android build setup

The Android build compiles Java and Kotlin for JVM 17 (`android/app/build.gradle`)
and needs **JDK 17 or newer** to run Gradle; Android Studio's bundled JBR 21
works as well. The project does not pin a JDK location:
`android/gradle.properties` is shared by every machine, CI and packaging
environment, so it must not contain an absolute path.

## Choosing the JDK

Gradle uses the first of these that is set:

1. `org.gradle.java.home` in your user-wide `~/.gradle/gradle.properties`
   (on Windows `%USERPROFILE%\.gradle\gradle.properties`), for example
   `org.gradle.java.home=C:/Program Files/Eclipse Adoptium/jdk-17.0.19.10-hotspot`
2. The JDK Flutter passes to Gradle: `flutter config --jdk-dir <path>`, or the
   JBR bundled with Android Studio when no directory is configured
3. `JAVA_HOME`, then `java` on `PATH`

`flutter doctor -v` shows which Java binary Flutter uses for Android builds.
Any JDK 17+ distribution works (Temurin, Android Studio's JBR, OpenJDK).

## Checking the setup

```bash
flutter build apk --debug
```

If Gradle reports an invalid Java home, remove the stale
`org.gradle.java.home` override from the user-wide file above or point it to
an installed JDK 17 or newer. Do not add machine-specific values to
`android/gradle.properties` or other tracked files; `android/local.properties`
and `android/key.properties` stay untracked (`.gitignore`).
