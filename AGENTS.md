# DescentSpy project guide for AI assistants

This file is the maintained project overview for AI coding assistants. Read it
before making changes. Keep it current whenever app behavior, screens, data
sources, dependencies, permissions, or build/test workflows change.

## App overview

**DescentSpy** is a Flutter app for Android and iOS that provides touch-friendly
flight-planning calculations. The UI is designed for quick operation with large
controls. It is a planning aid, not approved navigation, performance, or
operational guidance. GPS-derived altitude and bearings are approximate; pilots
must verify calculations and navigation against approved aircraft data,
procedures, and current official charts/AIP.

The app has three tabs:

### Altitude

- Plans a climb or descent from entered current and target altitude in `ft`.
- Ground speed is required, in the unit chosen under **SPEED UNIT** (`kt` by default). It starts GPS tracking on app start and
  fills the field with the latest GPS groundspeed (including `0` when
  stationary). Leave the field blank to use GPS or enter a value for manual
  input. Clearing a manual value returns to GPS readings. The altitude and
  points screens share one app-wide GPS position service and the same cached
  live fix.
- Tapping a GPS-filled altitude or groundspeed field opens its keypad empty so
  the pilot can enter a replacement immediately; a committed manual value is
  preserved when edited again. Clearing a manual value returns the field to
  GPS autofill.
- Current altitude in `ft` is filled from a fresh GPS altitude by default.
  Editing it saves a manual override across app restarts; clearing the manual
  entry returns it to GPS autofill. During an active plan the starting-altitude
  input remains fixed while live GPS altitude continues to drive tracking.
- The plan accepts one constraint: available distance in `NM`, available time
  in minutes, or the selected 3- or 5-degree path estimate when neither is
  selected.
- **ADD BY LOCATION** opens the destination picker and uses direct GPS
  great-circle distance to the selected point.
- Barometer (optional): if the device has a pressure sensor, Settings shows
  **USE BAROMETER FOR VERTICAL SPEED** (off by default, with a warning that
  barometric altitude can be wrong in some aircraft). When on, the live
  vertical-speed panel uses barometer altitude over the same 30 s window and
  is labelled **BARO**; otherwise it is labelled **GPS**. GPS remains the
  altitude source. Platform channels: `com.example.descent_spy/barometer` and
  `.../barometer_pressure` (Android uses SENSOR_DELAY_NORMAL; iOS uses
  CMAltimeter, which is not built or tested here). Preference key:
  `vertical_speed_barometer`. Readings are stamped with the sensor's own time
  (converted with the since-boot clock), not with arrival time. A stream error
  is logged as a GPS debug event and the stream restarts after 2 s, up to 5
  retries in a row; a reading resets the count.
- After calculation, the live view shows target/current/delta panels for ground
  speed, GPS vertical speed, and altitude. A separate **REMAINING** panel
  shows remaining time, remaining distance, and (when a point was selected) a
  live arrow and true bearing to the point. When a point is selected, its name
  appears in the distance field label and the live panel title is
  **REMAINING - [point name]**, truncated to fit.
- The **VERTICAL PLAN** summary is collapsible from its header; it starts
  collapsed and retains the climb/descent rate, time, groundspeed, and distance
  metrics while expanded.
- GPS is also used to estimate vertical speed, track distance, update remaining
  calculations, and calculate point range/bearing. A stale fix is visibly
  treated as unavailable.
- The live vertical-rate heading shows red GPS text without a current satellite
  lock, orange with a 2D satellite lock, and green with a 3D satellite lock.
  It labels the state **NO LOCK**, **2D**, or **3D** and shows horizontal and
  altitude accuracy beside it using GPS/height icons. The satellite icon
  appears only for the 3D lock. Accuracy is shown as horizontal `H ±… m` and
  altitude `ALT ±… ft`. Android determines lock state from a fresh GPS-provider
  fix and satellites used in the fix: at least three for 2D, and at least four
  plus a fresh GPS altitude for 3D. Fused/network altitude or speed alone does
  not indicate a satellite lock. Platforms without satellite counts (iOS) show
  **GPS ±N m** from horizontal accuracy, or **NO FIX** without a fresh fix or
  accuracy value. The colours follow accuracy: red without a fix, orange above
  10 m, green at or below 10 m. No satellite icon is shown on those platforms.
- Inputs are saved using `shared_preferences`; clear actions remove saved
  values. The live tracking view intentionally has no clear-all button.

### Wind & Runway

- Accepts wind direction in degrees (where the wind comes from), wind speed in
  the **SPEED UNIT** (`kt` by default), and intended runway number.
- Validates ranges and calculates headwind/tailwind and crosswind components
  for the intended runway and reciprocal.
- Displays a warning and reciprocal-runway suggestion when the reciprocal has
  no meaningful tailwind and has a better crosswind or avoids a tailwind.
- Wind entries are persisted locally and can be cleared.

### Points

- Searches bundled UK airfields, towns/places, user-supplied VRPs, and locally
  saved custom points. Filters include all, favourites, airfields, towns,
  ports, and VRPs.
- Point search uses the keyboard selected in **SETTINGS**: the large QWERTY
  keyboard (default) or the platform system keyboard. Both filter and order
  suggestions immediately as the query changes. The large keyboard is compact,
  scrolls on short displays, and is docked 10 px above the bottom with results
  visible above it; the system keyboard resizes the
  screen, and a compact search header keeps some sorted results visible. The
  large keyboard's **SEARCH** button closes it and keeps the query. Search does
  not perform an online postcode lookup.
- Results are ordered by text match and then by distance when a fresh GPS
  position is available. The point finder immediately reuses the shared GPS
  fix rather than opening a second location stream. Bundled and custom points
  are deduplicated across categories by matching coordinates, and airfields
  are additionally deduplicated by ICAO. VRP aerodrome codes are not treated as
  unique VRP identifiers. Repeated names at different coordinates are
  retained. Point rows show direct range and true bearing when
  available; the point screen recalculates/repaints arrows every second using
  the latest GPS fix and updates immediately when a new fix arrives.
- Selecting a point shows its range and true bearing. Custom points can be
  added with a name, category, and coordinates. Favourites and custom points
  are stored locally.
- **ADD BY LOCATION** uses the selected point's direct great-circle range.
  Bearings are true bearings, not wind-corrected headings; ranges are not
  routes.
- Points are opened from the **SETTINGS** tab's cog button or from **ADD BY
  LOCATION** in the altitude planner. In distance-selection mode, point creation
  and the destructive clear-saved-points/favourites control are hidden.

### Settings

- The cog tab provides persistent **LIGHT** and **DARK** colour schemes.
  The light scheme uses a darker cool-grey background with brighter panels for
  stronger surface separation and readable text contrast. The dark scheme uses
  a near-black background behind clearly lighter panels.
- **SPEED UNIT** chooses `kt` (default), `km/h`, or `mph` for ground speed and
  wind speed entry, the live ground-speed panel, the altitude results, the wind
  results, and the GPS ground-speed diagnostic. Speeds are stored in knots, so
  `descent_ground_speed` and `wind_speed` keep their meaning; the choice is saved
  under `speed_unit`. Conversions use 1 kt = 1.852 km/h = 1.15078 mph
  (`lib/speed_unit.dart`). Live speed-deviation alerts stay at 5 kt.
- **POINT SEARCH KEYBOARD** chooses the large QWERTY keyboard (default) or the
  device system keyboard; the selection persists across launches.
- **VERTICAL PATH PROFILE** selects the persistent 3° or 5° path used by the
  altitude planner when **[degree] PATH** is selected.
- **REQUEST GPS PERMISSION** retries the permission prompt; if the permission
  has been permanently denied, it opens the platform app settings.
- **OPEN DESTINATION POINTS** opens the full point manager.
- **GPS DEBUG PAGE** (all builds, for on-device testing) opens
  `lib/gps_debug_page.dart`, with START/STOP RECORDING of GPS fixes (last 500),
  CLEAR, a COPY ALL export of records, the last 100 lifecycle and GPS
  start/stop/stream events, and barometer readings. Only the `debugPrint` lines
  are debug-only. The live-card debug panel in the altitude planner stays
  debug-only (`kDebugMode`).
- Shows GPS fix age/state, satellite counts when available, horizontal accuracy,
  altitude/vertical accuracy, groundspeed, track/course, coordinates, and last
  update time. On Android, the shared GPS service requests GPS-provider updates
  while gathering GNSS status and derives 2D/3D lock from fresh GPS fixes and
  satellites used. Until GNSS status arrives, the count is shown as unavailable
  rather than a misleading zero. iOS location APIs do not provide satellite
  counts, so this field is unavailable.
- The live altitude tracking screen ends with an **EDIT PLAN** button below
  the live status panel.
- The app requests location permission when GPS features need it. Location
  must be enabled on the device. Stale or unavailable GPS values must not be
  represented as current.

## Screen behavior and aviation safety

- The display is kept awake while the app is in the foreground; the wake lock
  is released when the app is backgrounded.
- Keep controls large, high-contrast, and compact enough to avoid overflow on
  phone and tablet displays.
- Preserve input validation, manual GPS override behavior, stale-fix handling,
  and clear aviation caveats when changing calculations or UI.
- Do not describe direct point bearing as a heading to fly: it is a true
  great-circle bearing and does not account for wind, routing, airspace, or
  obstacles.
- VRP data may be out of date. The bundled CSV has a “Valid From” date, but the
  app does not update it automatically. Advise checking current official
  charts/AIP. See [assets/POINT_DATA_SOURCES.txt](assets/POINT_DATA_SOURCES.txt)
  for data provenance and caveats.
- The point finder currently has no postcode network lookup. Do not restore
  automatic or implicit online searches without an explicit product request.

## Code map

- `lib/main.dart` — app shell, altitude and wind tabs, altitude planner,
  live tracking panels, wind/runway UI, large numeric keypad, persistence, and
  foreground screen-awake behavior.
- `lib/gps_position_service.dart` — shared location permission handling,
  cached position, the single foreground GPS stream, and periodic satellite
  status refresh.
- `lib/app_theme.dart` — persisted light/dark palettes and shared adaptive
  colors.
- `assets/descentspy_app_icon.png` and platform icon catalogs — custom
  DescentSpy launcher icon for Android and iOS.
- `lib/settings_page.dart` — appearance and point-search keyboard selection,
  vertical path profile selection, GPS permission retry, GPS fix diagnostics,
  and navigation to the point manager.
- `lib/speed_unit.dart` — the speed unit setting (kt, km/h, mph) and conversions
  between the displayed unit and the knots used by calculations.
- `lib/calculations.dart` — pure altitude planning, live rate, GPS groundspeed,
  selectable 3°/5° path profiles, and runway wind calculations. Prefer
  extending/test-driving calculations here rather than embedding formulas in
  widgets.
- `lib/point_data.dart` — navigation point model, deduplication, search/range
  sorting, great-circle distance and true bearing.
- `lib/points_page.dart` — point data loading, shared GPS consumer, search and
  selectable keyboard, point list/details, favourites, and custom point editor.
- `assets/airfields_uk.json` and `assets/places_uk.json` — bundled catalogue
  assets, declared in `pubspec.yaml`.
- `assets/UK-VRPs.csv` — user-provided VRP catalogue, declared in
  `pubspec.yaml`.
- `assets/POINT_DATA_SOURCES.txt` — data source attribution and limitations.
- `README.md` — user-facing project overview, setup, development, and build
  instructions.
- `test/widget_test.dart` — calculation and widget regression tests.
- `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` —
  platform location permissions and user-facing disclosure.
- `android/app/src/main/kotlin/com/example/descent_spy/MainActivity.kt` —
  Android GNSS monitoring and fresh GPS-provider fixes used to distinguish 2D
  and 3D locks.

Important persisted preference keys include `app_theme_mode`, `descent_*`,
`descent_ground_speed_manual`, `descent_start_manual`,
`descent_vertical_path_profile`, `speed_unit`, `point_search_keyboard_mode`,
`navigation_custom_points`, and
`navigation_favourite_ids`. Preserve compatibility when changing these keys.

## Development and verification

From the project root:

```text
flutter pub get
dart format lib test
flutter analyze
flutter test
```

For a connected Android device:

```text
flutter devices
flutter run -d <device-id> --debug
```

Build release binaries with `flutter build apk --release` on Android or
`flutter build ios --release` on macOS with Xcode and signing configured. The
current Android release build uses debug signing; configure production signing
before distributing it.

The Android Gradle JVM args include
`--enable-native-access=ALL-UNNAMED` in `android/gradle.properties`.

The user-facing setup, safety, data-source, test, and build overview is in
`README.md`; keep it aligned with this guide when those details change.

## Versioning

Version: the Settings page shows `appVersion` and `appBuild` from
`lib/app_version.dart`. Keep pubspec.yaml's version in step. Increment
`appBuild` (and the pubspec build number after the +) with every build.
Increment the V number (`appVersion`) only when the owner asks. Current: 0.7,
build 10. After each build, push the build to main.
Owner preference: push to main after each build without asking for re-confirmation.

## Keeping this guide current

When implementing a feature or changing behavior:

1. Read this guide and the relevant existing code/tests first.
2. Make the code and regression tests authoritative; update this file in the
   same change if user-visible behavior, data, dependencies, permissions,
   architecture, or commands differ from its description.
3. Remove or revise obsolete descriptions rather than accumulating conflicting
   notes.
4. Run the narrowest relevant tests, then `flutter analyze` and `flutter test`
   when practical. Report any validation that could not be run.
