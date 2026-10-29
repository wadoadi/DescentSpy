import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:descent_spy/barometer_service.dart';
import 'package:descent_spy/calculations.dart';
import 'package:descent_spy/gps_position_service.dart';
import 'package:descent_spy/main.dart';
import 'package:descent_spy/point_data.dart';
import 'package:descent_spy/points_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });

  group('live descent calculations', () {
    test(
      'does not report zero satellites as an active satellite fix',
      () async {
        const channel = MethodChannel('com.example.descent_spy/gps_status');
        Map<String, Object?> satelliteData = {'visible': 0, 'used': 0};
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => satelliteData);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );

        final service = GpsPositionService.instance;
        await service.refreshSatelliteStatus();
        expect(service.satelliteStatus, isNull);
        expect(service.satelliteError, 'Waiting for satellite status.');

        satelliteData = {'visible': 12, 'used': 5, 'is2d': true, 'is3d': false};
        await service.refreshSatelliteStatus();
        expect(service.satelliteStatus?.visibleSatellites, 12);
        expect(service.satelliteStatus?.usedSatellites, 5);
        expect(service.satelliteStatus?.fixLevel, GpsFixLevel.twoDimensional);

        satelliteData = {'visible': 12, 'used': 8, 'is2d': true, 'is3d': true};
        await service.refreshSatelliteStatus();
        expect(service.satelliteStatus?.has3dFix, isTrue);
        expect(service.satelliteStatus?.fixLevel, GpsFixLevel.threeDimensional);
        expect(service.satelliteError, isNull);
      },
    );

    test('fills current altitude from GPS unless the pilot overrides it', () {
      expect(
        gpsAltitudeEntry(altitudeMeters: 1000, manuallyOverridden: false),
        '3281',
      );
      expect(
        gpsAltitudeEntry(altitudeMeters: 1000, manuallyOverridden: true),
        isNull,
      );
      expect(
        gpsAltitudeEntry(
          altitudeMeters: double.infinity,
          manuallyOverridden: false,
        ),
        isNull,
      );
      expect(
        gpsAltitudeEntry(altitudeMeters: 20000, manuallyOverridden: false),
        isNull,
      );
    });

    test('fills ground speed from GPS unless the pilot overrides it', () {
      expect(
        gpsGroundSpeedEntry(
          speedMetersPerSecond: 10,
          manuallyOverridden: false,
        ),
        '19',
      );
      expect(
        gpsGroundSpeedEntry(speedMetersPerSecond: 10, manuallyOverridden: true),
        isNull,
      );
      expect(
        gpsGroundSpeedEntry(
          speedMetersPerSecond: 0.2,
          manuallyOverridden: false,
        ),
        '0',
      );
      expect(
        gpsGroundSpeedEntry(speedMetersPerSecond: 0, manuallyOverridden: false),
        '0',
      );
    });

    test('estimates signed VSI from a smoothed altitude trend', () {
      final start = DateTime.utc(2026, 1, 1);
      final result = estimateVerticalSpeedFpm([
        AltitudeSample(timestamp: start, altitudeFt: 5000),
        AltitudeSample(
          timestamp: start.add(const Duration(seconds: 10)),
          altitudeFt: 4900,
        ),
        AltitudeSample(
          timestamp: start.add(const Duration(seconds: 20)),
          altitudeFt: 4800,
        ),
      ]);

      expect(result, closeTo(-600, 0.01));
    });

    test('treats a repeated GPS fix as not newer than the last one', () {
      final start = DateTime.utc(2026, 1, 1);

      expect(isNewerFix(previousTimestamp: null, timestamp: start), isTrue);
      expect(
        isNewerFix(
          previousTimestamp: start,
          timestamp: start.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(isNewerFix(previousTimestamp: start, timestamp: start), isFalse);
      expect(
        isNewerFix(
          previousTimestamp: start.add(const Duration(seconds: 1)),
          timestamp: start,
        ),
        isFalse,
      );
    });

    test('waits for enough time-spaced GPS samples before showing VSI', () {
      final start = DateTime.utc(2026, 1, 1);
      final result = estimateVerticalSpeedFpm([
        AltitudeSample(timestamp: start, altitudeFt: 5000),
        AltitudeSample(
          timestamp: start.add(const Duration(seconds: 2)),
          altitudeFt: 4980,
        ),
      ]);

      expect(result, isNull);
    });

    test(
      'recalculates required descent rate from current altitude and time',
      () {
        expect(
          calculateLiveRequiredRateFpm(
            startAltitudeFt: 10000,
            currentAltitudeFt: 5000,
            targetAltitudeFt: 2000,
            remainingTimeMinutes: 10,
          ),
          -300,
        );
        expect(
          calculateLiveRequiredRateFpm(
            startAltitudeFt: 10000,
            currentAltitudeFt: 5000,
            targetAltitudeFt: 2000,
            remainingTimeMinutes: 0,
          ),
          isNull,
        );
        expect(
          calculateLiveRequiredRateFpm(
            startAltitudeFt: 1000,
            currentAltitudeFt: 1800,
            targetAltitudeFt: 2000,
            remainingTimeMinutes: 5,
          ),
          40,
        );
      },
    );

    test('calculates required climb rate and stops after reaching target', () {
      expect(
        calculateLiveRequiredRateFpm(
          startAltitudeFt: 1000,
          currentAltitudeFt: 2000,
          targetAltitudeFt: 5000,
          remainingTimeMinutes: 10,
        ),
        300,
      );
      expect(
        calculateLiveRequiredRateFpm(
          startAltitudeFt: 1000,
          currentAltitudeFt: 5100,
          targetAltitudeFt: 5000,
          remainingTimeMinutes: 10,
        ),
        0,
      );
    });

    test('projects remaining distance using entered target ground speed', () {
      expect(
        calculateTimeForDistanceMinutes(distanceNm: 20, groundspeedKt: 100),
        12,
      );
      expect(
        calculateTimeForDistanceMinutes(distanceNm: 20, groundspeedKt: 0),
        isNull,
      );
    });
  });

  group('calculateAltitudePlan', () {
    test('uses entered distance to calculate rate and time', () {
      final result = calculateAltitudePlan(
        startAltitudeFt: 10000,
        targetAltitudeFt: 3000,
        groundspeedKt: 120,
        distanceNm: 20,
      );

      expect(result.timeMinutes, 10);
      expect(result.rateFpm, 700);
      expect(result.distanceNm, 20);
    });

    test('uses entered time to calculate required distance', () {
      final result = calculateAltitudePlan(
        startAltitudeFt: 10000,
        targetAltitudeFt: 3000,
        groundspeedKt: 120,
        timeMinutes: 15,
      );

      expect(result.distanceNm, 30);
      expect(result.rateFpm, closeTo(466.67, 0.01));
    });

    test('uses a three-degree profile when neither constraint is supplied', () {
      final result = calculateAltitudePlan(
        startAltitudeFt: 10000,
        targetAltitudeFt: 3000,
        groundspeedKt: 120,
      );

      expect(result.usesProfile, isTrue);
      expect(result.profileDegrees, 3);
      expect(result.distanceNm, closeTo(7000 / 318, 0.001));
      expect(result.rateFpm, closeTo(636, 1));
    });

    test('uses the selected five-degree profile', () {
      final result = calculateAltitudePlan(
        startAltitudeFt: 10000,
        targetAltitudeFt: 3000,
        groundspeedKt: 120,
        profile: VerticalPathProfile.fiveDegree,
      );

      expect(result.usesProfile, isTrue);
      expect(result.profileDegrees, 5);
      expect(result.distanceNm, closeTo(7000 / 531, 0.001));
      expect(result.rateFpm, closeTo(1062, 0.01));
    });

    test('plans an ascent using the absolute altitude change', () {
      final result = calculateAltitudePlan(
        startAltitudeFt: 3000,
        targetAltitudeFt: 8000,
        groundspeedKt: 120,
        timeMinutes: 10,
      );

      expect(result.isClimb, isTrue);
      expect(result.rateFpm, 500);
      expect(result.distanceNm, 20);
    });

    test('rejects a target altitude at or above current altitude', () {
      expect(
        () => calculateAltitudePlan(
          startAltitudeFt: 3000,
          targetAltitudeFt: 3000,
          groundspeedKt: 100,
          distanceNm: 10,
        ),
        throwsArgumentError,
      );
    });

    test('rejects values outside the planning input ranges', () {
      expect(
        () => calculateAltitudePlan(
          startAltitudeFt: 10000,
          targetAltitudeFt: 3000,
          groundspeedKt: 1000,
          distanceNm: 10,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculateAltitudePlan(
          startAltitudeFt: 61000,
          targetAltitudeFt: 3000,
          groundspeedKt: 100,
          distanceNm: 10,
        ),
        throwsArgumentError,
      );
      expect(
        () => calculateAltitudePlan(
          startAltitudeFt: 10000,
          targetAltitudeFt: 3000,
          groundspeedKt: 100,
          distanceNm: double.infinity,
        ),
        throwsArgumentError,
      );
    });
  });

  group('calculateWind', () {
    test('calculates runway components and reciprocal recommendation', () {
      final result = calculateWind(
        windDirectionDeg: 180,
        windSpeedKt: 20,
        runwayNumber: 7,
      );

      expect(result.reciprocalRunwayNumber, 25);
      expect(result.intendedRunway.headwindKt, lessThan(0));
      expect(result.intendedRunway.tailwindKt, greaterThan(0));
      expect(result.reciprocalRunway.headwindKt, greaterThan(0));
      expect(result.recommendReciprocal, isTrue);
    });

    test('calculates direct point range and bearing', () {
      final result = calculatePointRange(
        fromLatitude: 0,
        fromLongitude: 0,
        toLatitude: 0,
        toLongitude: 1,
      );

      expect(result.distanceNm, closeTo(60.04, 0.02));
      expect(result.bearingDeg, closeTo(90, 0.01));

      final updated = calculatePointRange(
        fromLatitude: 1,
        fromLongitude: 0,
        toLatitude: 0,
        toLongitude: 0,
      );
      expect(updated.distanceNm, closeTo(60.04, 0.02));
      expect(updated.bearingDeg, closeTo(180, 0.01));
    });

    test('accepts runway 36 and calculates runway 18 reciprocal', () {
      final result = calculateWind(
        windDirectionDeg: 360,
        windSpeedKt: 10,
        runwayNumber: 36,
      );

      expect(result.reciprocalRunwayNumber, 18);
      expect(result.intendedRunway.headwindKt, closeTo(10, 0.001));
    });

    test('rejects an invalid runway number', () {
      expect(
        () =>
            calculateWind(windDirectionDeg: 0, windSpeedKt: 5, runwayNumber: 0),
        throwsArgumentError,
      );
    });

    test('rejects wind direction and speed outside supported ranges', () {
      for (final direction in [-1.0, 361.0, double.nan]) {
        expect(
          () => calculateWind(
            windDirectionDeg: direction,
            windSpeedKt: 10,
            runwayNumber: 7,
          ),
          throwsArgumentError,
        );
      }

      expect(
        () => calculateWind(
          windDirectionDeg: 180,
          windSpeedKt: double.infinity,
          runwayNumber: 7,
        ),
        throwsArgumentError,
      );
    });
  });

  test(
    'pressure altitude is zero at standard pressure and about 988 m at 900 hPa',
    () {
      expect(pressureAltitudeMeters(1013.25), closeTo(0, 0.01));
      expect(pressureAltitudeMeters(900), closeTo(988.6, 0.5));
      expect(
        pressureAltitudeMeters(1000),
        greaterThan(pressureAltitudeMeters(1010)),
      );
    },
  );

  test('sensor sample time is placed by its age on the since-boot clock', () {
    final now = DateTime(2026, 10, 27, 12);
    expect(
      sensorSampleTime(now: now, nowElapsedMs: 10000, sampleElapsedMs: 9000),
      DateTime(2026, 10, 27, 11, 59, 59),
    );
    expect(
      sensorSampleTime(now: now, nowElapsedMs: 10000, sampleElapsedMs: 10000),
      now,
    );
  });

  test('point bearing: due east is 90, due south 180, due west 270', () {
    const lat = 52.74;
    const lon = 0.55;
    double bearingTo(double toLat, double toLon) => calculatePointRange(
      fromLatitude: lat,
      fromLongitude: lon,
      toLatitude: toLat,
      toLongitude: toLon,
    ).bearingDeg;

    expect(bearingTo(lat + 0.05, lon), closeTo(0, 0.1));
    expect(bearingTo(lat, lon + 0.05), closeTo(90, 0.1));
    expect(bearingTo(lat - 0.05, lon), closeTo(180, 0.1));
    expect(bearingTo(lat, lon - 0.05), closeTo(270, 0.1));
  });

  test('accuracy label shows GPS ±N m, or NO FIX without a fresh fix', () {
    expect(gpsAccuracyLabel(fresh: true, horizontalAccuracyM: 4), 'GPS ±4 m');
    expect(gpsAccuracyLabel(fresh: false, horizontalAccuracyM: 4), 'NO FIX');
    expect(gpsAccuracyLabel(fresh: true, horizontalAccuracyM: null), 'NO FIX');
  });

  test('accuracy colour band: green at or below 10 m, orange above, none without a fix', () {
    expect(
      gpsAccuracyFixLevel(fresh: true, horizontalAccuracyM: 10),
      GpsFixLevel.threeDimensional,
    );
    expect(
      gpsAccuracyFixLevel(fresh: true, horizontalAccuracyM: 11),
      GpsFixLevel.twoDimensional,
    );
    expect(
      gpsAccuracyFixLevel(fresh: false, horizontalAccuracyM: 4),
      GpsFixLevel.none,
    );
  });

  test('deduplicates same-category points at the same coordinates', () {
    const first = NavigationPoint(
      id: 'one',
      name: 'Field One',
      category: PointCategory.airfield,
      latitude: 51.123456,
      longitude: -1.123456,
    );
    const duplicate = NavigationPoint(
      id: 'two',
      name: 'Field Alias',
      category: PointCategory.airfield,
      latitude: 51.123456,
      longitude: -1.123456,
    );
    const distinct = NavigationPoint(
      id: 'three',
      name: 'Field One',
      category: PointCategory.airfield,
      latitude: 51.124,
      longitude: -1.124,
    );

    expect(deduplicateNavigationPoints([first, duplicate, distinct]), [
      first,
      distinct,
    ]);
  });

  test('deduplicates across categories and by ICAO without merging names', () {
    const airfield = NavigationPoint(
      id: 'airfield:one',
      name: 'Field One',
      category: PointCategory.airfield,
      latitude: 51.123456,
      longitude: -1.123456,
      icao: 'EGAA',
    );
    const sameLocation = NavigationPoint(
      id: 'vrp:one',
      name: 'Field One VRP',
      category: PointCategory.vrp,
      latitude: 51.123456,
      longitude: -1.123456,
    );
    const sameIcao = NavigationPoint(
      id: 'airfield:icao',
      name: 'Different name',
      category: PointCategory.airfield,
      latitude: 52,
      longitude: -1,
      icao: 'egaa',
    );
    const associatedVrp = NavigationPoint(
      id: 'vrp:associated',
      name: 'Associated reporting point',
      category: PointCategory.vrp,
      latitude: 53,
      longitude: -1,
      icao: 'EGAA',
    );
    const sameNameDifferentPlace = NavigationPoint(
      id: 'town:two',
      name: 'Field One',
      category: PointCategory.town,
      latitude: 52,
      longitude: -1,
    );

    expect(
      deduplicateNavigationPoints([
        airfield,
        sameLocation,
        sameIcao,
        associatedVrp,
        sameNameDifferentPlace,
      ]),
      [airfield, associatedVrp, sameNameDifferentPlace],
    );
  });

  testWidgets('shows descent and wind tabs with large primary actions', (
    tester,
  ) async {
    await tester.pumpWidget(const DescentSpyApp());

    expect(find.text('CLIMB / DESCENT PLAN'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('CALCULATE PLAN'), findsOneWidget);
    expect(find.text('WIND & RUNWAY'), findsOneWidget);

    await tester.tap(find.text('WIND & RUNWAY'));
    await tester.pumpAndSettle();

    expect(find.text('INTENDED RUNWAY'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('CHECK WIND'), findsOneWidget);
  });

  testWidgets('tabs and section headings fit a 360 px phone width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DescentSpyApp());
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('WIND & RUNWAY'));
    await tester.pumpAndSettle();
    expect(find.text('INTENDED RUNWAY'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('COLOUR SCHEME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings changes theme and opens the points screen', (
    tester,
  ) async {
    await tester.pumpWidget(const DescentSpyApp());
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('COLOUR SCHEME'), findsOneWidget);
    await tester.tap(find.text('LIGHT'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('app_theme_mode'),
      'light',
    );
    expect(find.text('VERTICAL PATH PROFILE'), findsOneWidget);
    await tester.ensureVisible(find.text('5°'));
    await tester.tap(find.text('5°'));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        verticalPathProfilePreferenceKey,
      ),
      VerticalPathProfile.fiveDegree.name,
    );
    expect(find.text('POINT SEARCH KEYBOARD'), findsOneWidget);
    await tester.ensureVisible(find.text('SYSTEM'));
    await tester.tap(find.text('SYSTEM'));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        pointSearchKeyboardPreferenceKey,
      ),
      PointSearchKeyboardMode.system.name,
    );
    await tester.tapAt(tester.getCenter(find.widgetWithText(Tab, 'ALTITUDE')));
    await tester.pumpAndSettle();
    expect(find.text('5° PATH'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('3°'));
    await tester.tap(find.text('3°'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('REQUEST GPS PERMISSION'), findsOneWidget);
    expect(find.text('GPS STATUS'), findsOneWidget);
    expect(find.text('SATELLITES'), findsOneWidget);
    expect(find.text('HORIZONTAL ACCURACY'), findsOneWidget);
    expect(find.text('ALTITUDE ACCURACY'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPEN DESTINATION POINTS'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(find.text('DESTINATION POINTS'), findsOneWidget);
    expect(find.text('ADD POINT'), findsOneWidget);
  });

  testWidgets('live tracking puts EDIT PLAN below the live status card', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('descent_start', '5000');
    await preferences.setString('descent_target', '1000');
    await preferences.setString('descent_ground_speed', '90');
    await preferences.setBool('descent_ground_speed_manual', true);
    await preferences.setString('descent_constraint', '10');

    await tester.pumpWidget(const DescentSpyApp());
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calculate-plan')));
    await tester.pumpAndSettle();

    final editButton = find.byKey(const ValueKey('edit-plan'));
    final livePanel = find.byKey(
      const ValueKey('live-vertical-rate-gps-heading'),
    );
    final gpsLabel = find.descendant(of: livePanel, matching: find.text('GPS'));
    expect(
      tester.widget<Text>(gpsLabel).style!.color,
      Theme.of(tester.element(gpsLabel)).colorScheme.error,
    );
    expect(find.text('NO LOCK'), findsOneWidget);
    expect(find.text('H —'), findsOneWidget);
    expect(find.text('ALT —'), findsOneWidget);
    expect(find.byKey(const ValueKey('gps-3d-fix-indicator')), findsNothing);
    expect(find.text('EDIT DESCENT INPUTS'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(editButton, findsOneWidget);
    expect(
      tester.getTopLeft(editButton).dy,
      greaterThan(tester.getTopLeft(livePanel).dy),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    final verticalPlanToggle = find.byKey(
      const ValueKey('vertical-plan-toggle'),
    );
    expect(verticalPlanToggle, findsOneWidget);
    expect(find.byKey(const ValueKey('vertical-plan-metrics')), findsNothing);
    await tester.tap(verticalPlanToggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vertical-plan-metrics')), findsOneWidget);
    await tester.tap(verticalPlanToggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vertical-plan-metrics')), findsNothing);
  });

  testWidgets('wind-direction keypad blocks values above 360', (tester) async {
    await tester.pumpWidget(const DescentSpyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('WIND & RUNWAY'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    for (final digit in ['3', '6', '1']) {
      await tester.tap(find.widgetWithText(FilledButton, digit));
    }
    await tester.ensureVisible(find.text('DONE'));
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '36',
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '0'));
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '360',
    );
  });

  test('sorts prefix matches before substring matches and by GPS range', () {
    const nearbyPrefix = NavigationPoint(
      id: 'near',
      name: 'Lent',
      category: PointCategory.town,
      latitude: 0,
      longitude: 0.1,
    );
    const fartherPrefix = NavigationPoint(
      id: 'far',
      name: 'Lenwade',
      category: PointCategory.town,
      latitude: 0,
      longitude: 2,
    );
    const substring = NavigationPoint(
      id: 'substring',
      name: 'Glen',
      category: PointCategory.town,
      latitude: 0,
      longitude: 0.01,
    );

    expect(
      sortNavigationPoints(
        points: [substring, fartherPrefix, nearbyPrefix],
        query: 'Len',
        fromLatitude: 0,
        fromLongitude: 0,
      ),
      [nearbyPrefix, fartherPrefix, substring],
    );
  });

  test('filters point search results as the query changes', () {
    const londonCity = NavigationPoint(
      id: 'london-city',
      name: 'London City',
      category: PointCategory.airfield,
      latitude: 51.505,
      longitude: 0.055,
      icao: 'EGLC',
    );
    const bristol = NavigationPoint(
      id: 'bristol',
      name: 'Bristol',
      category: PointCategory.airfield,
      latitude: 51.383,
      longitude: -2.719,
      icao: 'EGGD',
    );

    expect(
      searchNavigationPoints(points: [londonCity, bristol], query: 'LON'),
      [londonCity],
    );
    expect(
      searchNavigationPoints(points: [londonCity, bristol], query: 'EGLC'),
      [londonCity],
    );
    expect(
      searchNavigationPoints(points: [londonCity, bristol], query: 'not found'),
      isEmpty,
    );
  });

  test('parses postcode coordinates into a destination point', () {
    final point = parseUKPostcodePoint('SW1A1AA', {
      'postcode': 'SW1A 1AA',
      'latitude': 51.501,
      'longitude': -0.142,
    });

    expect(point.name, 'SW1A 1AA');
    expect(point.category, PointCategory.town);
    expect(point.latitude, 51.501);
    expect(point.longitude, -0.142);
    expect(point.id, 'postcode:SW1A1AA');
  });

  testWidgets('opens point selection in a material page', (tester) async {
    await tester.pumpWidget(const DescentSpyApp());
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ADD BY LOCATION'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('DESTINATION POINTS'), findsOneWidget);
    expect(
      find.text('Tap a destination to use its direct GPS distance.'),
      findsOneWidget,
    );
    expect(find.text('ADD POINT'), findsNothing);
    expect(
      find.byTooltip('Clear all custom points and favourites'),
      findsNothing,
    );
    await tester.ensureVisible(find.text('VRPs').first);
    await tester.tap(find.text('VRPs').first);
    await tester.pump();
    expect(find.text('ADD VRP'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back without selecting a point'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('CLIMB / DESCENT PLAN'), findsOneWidget);
  });

  testWidgets('uses large keypad and remembers descent values until cleared', (
    tester,
  ) async {
    await tester.pumpWidget(const DescentSpyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('CURRENT ALTITUDE'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '1'));
    await tester.tap(find.widgetWithText(FilledButton, '0'));
    await tester.tap(find.widgetWithText(FilledButton, '0'));
    await tester.tap(find.widgetWithText(FilledButton, '0'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('DONE'));
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();

    final startField = tester.widget<TextField>(find.byType(TextField).first);
    expect(startField.controller!.text, '1000');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('descent_start'), '1000');
    expect(preferences.getBool('descent_start_manual'), isTrue);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('1000'), findsWidgets);
    await tester.tap(find.text('CLEAR'));
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(startField.controller!.text, isEmpty);
    expect(preferences.getBool('descent_start_manual'), isFalse);

    final groundSpeedField = tester.widget<TextField>(
      find.byType(TextField).at(2),
    );
    await tester.tap(find.byType(TextField).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '9'));
    await tester.tap(find.widgetWithText(FilledButton, '0'));
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(groundSpeedField.controller!.text, '90');
    expect(preferences.getBool('descent_ground_speed_manual'), isTrue);
    await tester.tap(find.byType(TextField).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLEAR'));
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(groundSpeedField.controller!.text, isEmpty);
    expect(preferences.getBool('descent_ground_speed_manual'), isFalse);

    await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLEAR ALL'));
    await tester.pumpAndSettle();
    expect(startField.controller!.text, isEmpty);
    expect(preferences.getString('descent_start'), isNull);
    expect(preferences.getBool('descent_start_manual'), isNull);
  });

  testWidgets('loads bundled airfields in the point finder', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      pointSearchKeyboardPreferenceKey,
      PointSearchKeyboardMode.system.name,
    );
    await tester.pumpWidget(_testPointFinderApp());
    await tester.pump();
    expect(find.text('DESTINATION POINTS'), findsOneWidget);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(find.text('AIRFIELDS'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'Aberdeen');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Aberdeen'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Aberdeen',
    );

    await tester.ensureVisible(find.text('VRPs'));
    await tester.tap(find.text('VRPs'));
    await tester.pump();
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'A1(M) JUNCTION 4');
    await tester.pump();
    expect(find.text('A1(M) JUNCTION 4'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens large QWERTY keyboard for point search', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_testPointFinderApp());
    await tester.pump();
    await tester.pump();
    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    expect(find.text('LARGE SEARCH KEYBOARD'), findsOneWidget);
    expect(find.text('Q'), findsOneWidget);
    expect(find.text('SPACE'), findsOneWidget);
    expect(find.text('SEARCH'), findsOneWidget);
    expect(find.text('LOOK UP POSTCODE'), findsNothing);
    final keyboardPanel = find.byKey(
      const ValueKey('large-search-keyboard-panel'),
    );
    expect(
      tester.getBottomLeft(keyboardPanel).dy,
      closeTo(tester.view.physicalSize.height - 10, 1),
    );
    expect(
      tester.getSize(keyboardPanel).height,
      lessThan(tester.view.physicalSize.height * 0.4),
    );
    expect(
      tester.getTopLeft(find.byType(TextField).first).dy,
      lessThan(tester.getTopLeft(find.text('LARGE SEARCH KEYBOARD')).dy),
    );
    for (final key in ['A', 'B', 'E', 'R', 'D', 'E', 'E', 'N']) {
      final keyButton = find.widgetWithText(
        key == 'SPACE' ? OutlinedButton : FilledButton,
        key,
      );
      await tester.tap(keyButton);
      await tester.pump();
    }
    expect(searchField.controller!.text, 'ABERDEEN');
    expect(find.text('Aberdeen'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Aberdeen')).dy,
      lessThan(tester.getTopLeft(find.text('LARGE SEARCH KEYBOARD')).dy),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'X'));
    await tester.pump();
    expect(find.text('No points match this filter.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '⌫'));
    await tester.pump();
    expect(find.text('Aberdeen'), findsOneWidget);

    await tester.tap(find.text('SEARCH'));
    await tester.pump();
    expect(searchField.controller!.text, 'ABERDEEN');
    expect(tester.takeException(), isNull);
  });

  testWidgets('system keyboard filters and keeps point results above it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      pointSearchKeyboardPreferenceKey,
      PointSearchKeyboardMode.system.name,
    );

    await tester.pumpWidget(_testPointFinderApp());
    await tester.pump();
    await tester.pump();
    final searchFieldFinder = find.byType(TextField).first;
    final searchField = tester.widget<TextField>(searchFieldFinder);
    expect(searchField.readOnly, isFalse);
    await tester.tap(searchFieldFinder);
    tester.view.viewInsets = const FakeViewPadding(bottom: 420);
    await tester.pump();

    expect(find.text('LARGE SEARCH KEYBOARD'), findsNothing);
    expect(find.text('Open large QWERTY search keyboard'), findsNothing);
    for (final query in ['A', 'AB', 'ABE', 'ABERDEEN']) {
      await tester.enterText(searchFieldFinder, query);
      await tester.pump();
      expect(find.textContaining('Aberdeen'), findsWidgets);
    }
    expect(
      tester.getBottomLeft(find.text('Aberdeen')).dy,
      lessThan(1200 - 420),
    );
    await tester.enterText(searchFieldFinder, 'ZZZZ');
    await tester.pump();
    expect(find.text('No points match this filter.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ADD BY LOCATION shares the distance field line, split 50/50', (
    tester,
  ) async {
    await tester.pumpWidget(const DescentSpyApp());
    await tester.pumpAndSettle();

    final distanceRect = tester.getRect(find.byType(TextField).at(3));
    final locationRect = tester.getRect(
      find.byKey(const ValueKey('add-by-location')),
    );
    expect(locationRect.center.dy, closeTo(distanceRect.center.dy, 40));
    expect(locationRect.left, closeTo(distanceRect.right + 10, 1));
    expect(locationRect.width, closeTo(distanceRect.width, 1));

    await tester.tap(find.text('3° PATH'));
    await tester.pump();
    expect(
      find.text('Standard 3° path estimates time and distance.'),
      findsOneWidget,
    );
  });
}

Widget _testPointFinderApp() => MaterialApp(
  home: DefaultAssetBundle(
    bundle: _TestNavigationAssetBundle(),
    child: const Scaffold(body: PointFinderPage()),
  ),
);

class _TestNavigationAssetBundle extends CachingAssetBundle {
  static const _assets = {
    'assets/airfields_uk.json': '[{"name":"Aberdeen International","lat":57.2,"lon":-2.2,"icao":"EGPD"}]',
    'assets/places_uk.json': '[{"name":"Aberdeen","kind":"city","lat":57.1437,"lon":-2.0981},{"name":"Dundee","kind":"city","lat":56.4691,"lon":-2.9749}]',
    'assets/UK-VRPs.csv': 'VRP name,Latitude,Longitude,Valid From\n',
  };

  @override
  Future<ByteData> load(String key) async {
    final asset = _assets[key];
    if (asset == null) throw FlutterError('Missing test asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(asset)));
  }
}
