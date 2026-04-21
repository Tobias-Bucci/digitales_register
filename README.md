# Digitales Register (App)

Unofficial application for the Digital Register platform  
(http://xxxxxx.digitalesregister.it)

This repository is a fork of the original project:  
https://github.com/miDeb/digitales_register

It builds upon the original implementation and may include modifications, improvements, or adaptations specific to this version.

---

## Overview

Digitales Register (App) provides a mobile-friendly interface to access the Digital Register system.  
The goal of this project is to improve usability, accessibility, and convenience compared to the web version by offering a native mobile experience.

The application is developed using Flutter and currently targets Android devices.

---

## Features

- Native mobile interface for the Digital Register
- Authentication with existing user accounts
- Background notification system for unread updates
- Demo mode for testing without a real account
- Aggregated notifications to reduce noise
- Configurable settings within the app

---

## Installation

### Android (Google Play)

Download the app from the Play Store:

https://play.google.com/store/apps/details?id=it.bucci.digitalesregister

---

## Development

### Requirements

- Flutter SDK (latest stable recommended)
- Dart SDK (bundled with Flutter)
- Java 11 (required for Android builds)
- Android SDK / Android Studio

### Setup

Clone the repository:

git clone https://github.com/Tobias-Bucci/digitales_register
cd digitales_register

Install dependencies and generate code:

flutter packages run build_runner build

Run the app in debug mode:

flutter run

Run in release mode:

flutter run --release

---

## Build (Android)

The project is configured for a stable Android toolchain using Java 11.

### Release Build Configuration

By default, release builds expect a valid keystore configuration:

android/key.properties

### Local Development (Debug Signing)

For local testing without a production keystore, debug signing can be enabled.

Option 1 – local.properties:

allowDebugSigningForRelease=true

Option 2 – Environment Variable:

ALLOW_DEBUG_SIGNING_FOR_RELEASE=true

### Build APK

flutter build apk --release

---

## Demo Mode

The application includes a demo mode for testing purposes without requiring a real account.

Credentials:

- School: Blank
- Username: demo
- Password: demo

Notes:

- The demo environment uses mock data
- All UI-visible demo actions run locally without real backend requests
- Local demo changes stay on the device until the app data is deleted

---

## Background Notifications

The application supports background polling for unread notifications and displays them as local push notifications.

### Behavior

- Notifications must be enabled in app settings
- Unread notifications are repeatedly reminded until marked as read
- While the app is open: polling every 10 minutes
- In background (Android): handled via WorkManager (typically ~15 minutes minimum interval enforced by OS)
- Multiple notifications are grouped into a single summary notification

---

## Testing (Without Backend Access)

### 1. Mock API

- Provide a local endpoint for: api/notification/unread
- Return static and evolving datasets across polling cycles
- Expected behavior:
  - New IDs trigger immediate notifications
  - Existing unread IDs trigger repeated reminders

### 2. Static Test Data

- Use predefined JSON responses
- Simulate:
  - unchanged lists
  - new entries
  - updated content for existing IDs

### 3. Debug Endpoints

- Optionally implement server-side debug endpoints
- Allow controlled creation of notification objects
- Enables reproducible test scenarios

### 4. Logging

Verify:

- polling intervals
- detected unread IDs
- retry/reminder logic
- grouping of notifications

---

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0).

You are free to use, modify, and distribute this software under the terms of the license.  
Any derivative work must also be distributed under the same license.

For full details, see the LICENSE file or:  
https://www.gnu.org/licenses/gpl-3.0.en.html

---

## Contributing

Contributions are welcome.

- Fork the repository
- Create a feature branch
- Submit a pull request

For significant changes, please open an issue first to discuss the proposed modifications.
