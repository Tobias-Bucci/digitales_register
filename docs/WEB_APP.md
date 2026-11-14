# Web app (app.digitalesregister.com)

The same Flutter code base, built with `flutter build web`. There is no fork:
everything web-specific sits behind `kIsWeb` or in a few small files, and the
native apps (Android, iOS, Windows, Linux/Flatpak, macOS) behave as before.

## How it reaches the schools

The school servers send no CORS headers, so a browser cannot call them from
another origin. The web app therefore talks to them through a same-origin
proxy on its own host (a Cloudflare Worker):

```
https://<school>.digitalesregister.it/v2/...
  → https://app.digitalesregister.com/proxy/<school>.digitalesregister.it/<slot>/v2/...
```

- `lib/school_proxy.dart` rewrites every dio request to a school this way
  (`SchoolProxyInterceptor`), and only in the web build.
- Only `*.digitalesregister.it` works. Other addresses are refused at login
  with a hint to use the app (`login.webSchoolUnsupported`).
- `<slot>` is a random id per session. The browser keeps the school's cookies
  under `/proxy/<school>/<slot>/`, so every session has its own cookie jar,
  like the in-memory `DefaultCookieJar` of each native `Wrapper`. Where the
  native app clears its jar, the web app starts a new slot and asks the proxy
  to delete the old slot's cookies (they are `HttpOnly`, so the app cannot).
- When the proxy's free daily quota is used up, Cloudflare answers instead of
  the proxy (no `x-dr-proxy` header). The app then shows
  `error.webProxyUnavailable` ("temporarily unavailable, try later or use the
  app") instead of "no internet".
- The proxy stores and logs nothing; it streams bodies through unchanged.

## What differs on the web

| Area | Native | Web |
|---|---|---|
| `Platform.isX` | `dart:io` | `HostPlatform` (`lib/host_platform.dart`): all false in the browser |
| HTTP to the school | dio + `IOHttpClientAdapter`, cookie jar | dio over XHR, browser cookies, proxy |
| Firebase Analytics, Crashlytics, school & grade statistics | optional, with consent | not used; no consent dialog, settings hidden |
| School notifications, reminders, calendar sync, home widgets, biometric lock | per platform | not offered (no background work in a browser) |
| Downloads, attachments, export | saved in the app folder, opened with the system | handed to the browser's downloads (`lib/web_app/browser_download.dart`) |
| Demo account | stored in a file | in memory, a reload starts it fresh |
| Design | new or legacy, user's choice | new design only |
| Logout | removes the password; data only with "delete data on logout" | always also deletes the account's saved register data |

## Storage in the browser

Only what the app needs to work; no tracking, no analytics, no third-party
requests (CanvasKit, fonts and assets are served by the web app itself).

| What | Where | Why |
|---|---|---|
| School session cookie (`PHPSESSID`) | Cookie, `HttpOnly; Secure; SameSite=Strict`, path of the session's slot | Signed-in session with the school (set by the school, via the proxy) |
| Settings, caches of register data, read state of announcements | `localStorage` (shared_preferences) | Same as the app's local storage |
| Saved login, saved register data | `localStorage`, encrypted by flutter_secure_storage (WebCrypto AES-GCM) | "Stay signed in" and offline start |

Signing out deletes the account's saved data and password and the session's
cookies. Clearing the site data in the browser removes everything.

### Credentials: the trade-off

The native app keeps the school password in the platform's secure storage
(Keychain, Keystore, Credential Manager, Secret Service) for automatic
sign-in. A browser has no equivalent: flutter_secure_storage encrypts the data
with WebCrypto, but the key lives in the same browser profile. Anyone with
access to that profile, or a script running on the page, could read it.

So the web app is stricter than the native app:

- With **"Stay signed in" on** (the default) it keeps the password, encrypted
  as above, and signs in automatically after a reload or a new tab, like the
  app.
- With **"Stay signed in" off** it keeps no password at all, only the account
  names; every new tab asks for the password again.
- Scripts on the page are limited by a strict Content Security Policy
  (`script-src 'self'`, no inline scripts, no third-party code), which is the
  main protection for anything stored in a browser.

On a shared or public computer: turn "Stay signed in" off, or sign out.

## Addresses and navigation

Readable paths (`usePathUrlStrategy`): `/`, `/grades`, `/absences`,
`/calendar`, `/exams`, `/class-register`, `/course-materials`, `/homework`,
`/certificate`, `/messages`, `/settings`, `/extras`, `/profile`
(`lib/web_app/web_routing.dart`).

- The address follows the open page.
- Opening or reloading an address signs in as usual and then opens that page
  (an after-login callback, like a link from a widget).
- The browser's back button goes back inside the app, like Android's back
  button. Flutter's Navigator 1.0 keeps a single browser history entry, so
  there is nothing to go *forward* to after going back.

## Build and run locally

```bash
flutter build web --release --no-web-resources-cdn
```

`web/flutter_bootstrap.js` is the loader template. The deployment moves
`main.dart.js`, `canvaskit/` and `assets/` into content-hashed folders under
`/static/` and rewrites the three addresses in the template, so those files
can be cached for a year while `index.html` and the bootstrap are revalidated
on every load. `web/fonts/Roboto-Regular.ttf` (Apache 2.0, from the Flutter
SDK) is served where the engine looks for its default font, so nothing is
loaded from Google.

`flutter run -d chrome` works for UI work; signing in to a real school needs
the proxy, so use the demo account (school empty, `demo` / `demo`) there.
