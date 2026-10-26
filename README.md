# DescentSpy

DescentSpy is a Flutter app for Android and iOS that helps pilots plan climbs
and descents, review wind components for a runway, and find UK destination
points. Its interface uses large, touch-friendly controls intended for quick
use.

> **Important:** DescentSpy is a planning aid, not approved navigation,
> performance, or operational guidance. GPS-derived altitude, speed, range,
> and bearing are approximate. Verify calculations and decisions against
> approved aircraft data, procedures, and current official charts and AIP.
> Direct point bearings are true great-circle bearings, not wind-corrected
> headings or routes.

## Features

- **Altitude planning:** Calculate a climb or descent using available distance,
  available time, or a configurable 3°/5° path profile. The planner shows the
  planned rate, time, groundspeed, and distance.
- **Live tracking:** Use GPS groundspeed and altitude when available, with
  manual overrides for groundspeed and starting altitude. The live view shows
  vertical speed, required-rate deviation, and remaining time or distance.
- **Wind and runway:** Enter wind direction, wind speed, and runway number to
  calculate headwind/tailwind and crosswind components, including the
  reciprocal runway.
- **Destination points:** Search bundled UK airfields, places and VRPs, as well
  as custom points. View direct range and true bearing when a fresh GPS fix is
  available; add a selected point's direct range to an altitude plan.
- **Settings:** Choose light or dark appearance, the point-search keyboard,
  and the vertical path profile. GPS diagnostics are available in Settings.
- **Local preferences:** Planner inputs, settings, favourites, and custom
  points are stored on the device.

## Requirements

- Flutter SDK with Dart SDK `^3.13.5` (see `environment` in
  [`pubspec.yaml`](pubspec.yaml)).
- Android development: Android SDK and a configured Flutter Android toolchain.
- iOS development: macOS, Xcode, and a configured Flutter iOS toolchain.
- A connected device or emulator for running the app. GPS features require
  device location services and location permission.

Check your local toolchain with:

```shell
flutter doctor -v
```

## Get started

From the project directory:

```shell
flutter pub get
flutter run
```

To select a device explicitly, first list available devices and then pass its
ID:

```shell
flutter devices
flutter run -d <device-id>
```

The app requests location permission when GPS features need it. On Android,
satellite lock details may be available; iOS does not expose satellite counts
through the location APIs used by the app.

## Tests and builds

Format, analyze, and run the test suite with:

```shell
dart format lib test
flutter analyze
flutter test
```

Build a release APK for Android:

```shell
flutter build apk --release
```

Build the iOS app on macOS with Xcode installed and signing configured:

```shell
flutter build ios --release
```

The Android release build currently uses the default debug signing
configuration. Configure a production signing key before distributing a
release build. iOS distribution also requires appropriate Apple signing and
provisioning.

## Data and safety

The point catalogue combines OurAirports data, GeoNames data, and the
user-supplied `assets/UK-VRPs.csv` file. The point finder is offline; it does
not perform postcode lookups or automatically update the VRP catalogue. VRP
data can become outdated. Check the current official charts and AIP before
using any point or coordinate.

See [`assets/POINT_DATA_SOURCES.txt`](assets/POINT_DATA_SOURCES.txt) for data
attribution and limitations.

## Project documentation

[`AGENTS.md`](AGENTS.md) is the maintained project guide for implementation
work. It describes app behavior, architecture, persisted preferences,
development checks, and safety constraints for contributors and AI coding
assistants.
