# Upgrade Baseline

This file documents the target technical baseline for the Flutter modernization of
`digitales_register`.

## Toolchain

| Component | Target |
| --- | --- |
| Flutter | 3.41.6 stable |
| Dart | 3.11.4 |
| Java / JDK | 17.0.18 |
| Android SDK Platform | 36 |
| Android Build Tools | 36.0.0 |
| iOS Deployment Target | 14.0 |

## Android Build Stack

| Component | Target |
| --- | --- |
| Gradle Wrapper | 8.11.1 |
| Android Gradle Plugin | 8.9.1 |
| Kotlin Android Plugin | 2.1.0 |
| compileSdk | 36 |
| targetSdk | 36 |
| minSdk | 23 |

## App-Level Dependency Targets

| Package | Target Version |
| --- | --- |
| badges | ^3.1.1 |
| biometric_storage | ^5.0.1 |
| built_value | ^8.9.2 |
| collection | ^1.19.1 |
| cookie_jar | ^4.0.9 |
| dio | ^5.9.0 |
| dio_cookie_manager | ^3.4.0 |
| flutter_local_notifications | ^17.2.4 |
| flutter_secure_storage | ^8.1.0 |
| flutter_svg | ^2.2.0 |
| flutter_widget_from_html_core | ^0.17.0 |
| http | ^1.2.2 |
| intl | ^0.20.2 |
| package_info_plus | ^8.3.1 |
| path_provider | ^2.1.5 |
| shared_preferences | ^2.5.3 |
| url_launcher | ^6.3.2 |
| workmanager | ^0.9.0+3 |

## Local Path / Forked Packages Kept For Compatibility

| Package | Source |
| --- | --- |
| charts_flutter | path: `packages/charts_repo/charts_flutter` |
| built_redux | path: `packages/built_redux` |
| collapsible_sidebar | path: `packages/collapsible_sidebar` |
| flutter_built_redux | path: `packages/flutter_built_redux` |
| quill_delta_viewer | path: `packages/quill_delta_viewer` |
| responsive_scaffold | path: `packages/responsive_scaffold` |
| open_file | path: `packages/open_file` |
| uni_links | path: `packages/uni_links` |

## Implementation Notes

- `dynamic_theme` is removed from app code and replaced by an app-owned theme
  controller.
- Deprecated back-navigation patterns are migrated to `PopScope`.
- Android no longer stores a machine-specific JDK path in repo-tracked files.
- Local Flutter SDK remains machine-specific via `android/local.properties`.
- Legacy `built_redux` code generation is not part of the active upgraded dev
  toolchain; committed generated files remain the source of truth.
- Test failure images and Flutter test cache outputs are gitignored and should
  no longer be committed.
