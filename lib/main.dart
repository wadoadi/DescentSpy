import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_theme.dart';
import 'barometer_service.dart';
import 'calculations.dart';
import 'gps_position_service.dart';
import 'point_data.dart';
import 'points_page.dart';
import 'settings_page.dart';

void main() {
  runApp(const DescentSpyApp());
}

class DescentSpyApp extends StatefulWidget {
  const DescentSpyApp({super.key});

  @override
  State<DescentSpyApp> createState() => _DescentSpyAppState();
}

class _DescentSpyAppState extends State<DescentSpyApp>
    with WidgetsBindingObserver {
  static const _themePreferenceKey = 'app_theme_mode';
  ThemeMode _themeMode = ThemeMode.dark;
  VerticalPathProfile _verticalPathProfile = VerticalPathProfile.threeDegree;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(WakelockPlus.enable());
    unawaited(GpsPositionService.instance.start());
    unawaited(_loadThemeMode());
    unawaited(BarometerService.instance.restorePreference());
  }

  Future<void> _loadThemeMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedMode = preferences.getString(_themePreferenceKey);
      final savedProfile = preferences.getString(
        verticalPathProfilePreferenceKey,
      );
      if (!mounted) return;
      setState(() {
        if (savedMode != null) {
          _themeMode = savedMode == 'light' ? ThemeMode.light : ThemeMode.dark;
        }
        _verticalPathProfile = VerticalPathProfile.values.firstWhere(
          (profile) => profile.name == savedProfile,
          orElse: () => VerticalPathProfile.threeDegree,
        );
      });
    } catch (error) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'DescentSpy settings',
          context: ErrorDescription('while loading the color scheme'),
        ),
      );
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _themePreferenceKey,
        mode == ThemeMode.light ? 'light' : 'dark',
      );
    } catch (error) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'DescentSpy settings',
          context: ErrorDescription('while saving the color scheme'),
        ),
      );
    }
  }

  Future<void> _setVerticalPathProfile(VerticalPathProfile profile) async {
    setState(() => _verticalPathProfile = profile);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        verticalPathProfilePreferenceKey,
        profile.name,
      );
    } catch (error) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'DescentSpy settings',
          context: ErrorDescription('while saving the vertical path profile'),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    GpsPositionService.instance.logDebugEvent('lifecycle ${state.name}');
    if (state == AppLifecycleState.resumed) {
      unawaited(WakelockPlus.enable());
      unawaited(GpsPositionService.instance.start());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(WakelockPlus.disable());
      unawaited(GpsPositionService.instance.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(WakelockPlus.disable());
    unawaited(GpsPositionService.instance.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DescentSpy',
      debugShowCheckedModeBanner: false,
      theme: DescentSpyTheme.light,
      darkTheme: DescentSpyTheme.dark,
      themeMode: _themeMode,
      home: FlightToolsPage(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        verticalPathProfile: _verticalPathProfile,
        onVerticalPathProfileChanged: _setVerticalPathProfile,
      ),
    );
  }
}

class FlightToolsPage extends StatelessWidget {
  const FlightToolsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.verticalPathProfile,
    required this.onVerticalPathProfileChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VerticalPathProfile verticalPathProfile;
  final ValueChanged<VerticalPathProfile> onVerticalPathProfileChanged;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'DescentSpy',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          bottom: TabBar(
            indicatorColor: context.appAccent,
            indicatorWeight: 4,
            tabs: const [
              Tab(
                height: 56,
                icon: Icon(Icons.trending_up),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'ALTITUDE',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Tab(
                height: 56,
                icon: Icon(Icons.air),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'WIND & RUNWAY',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Tab(
                height: 56,
                icon: Icon(Icons.settings, semanticLabel: 'Settings'),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AltitudePlanner(profile: verticalPathProfile),
            const WindPlanner(),
            SettingsPage(
              themeMode: themeMode,
              onThemeModeChanged: onThemeModeChanged,
              verticalPathProfile: verticalPathProfile,
              onVerticalPathProfileChanged: onVerticalPathProfileChanged,
              onOpenPoints: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: const Text('POINTS')),
                      body: const PointFinderPage(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AltitudePlanner extends StatefulWidget {
  const AltitudePlanner({super.key, required this.profile});

  final VerticalPathProfile profile;

  @override
  State<AltitudePlanner> createState() => _AltitudePlannerState();
}

enum _PlanMode { distance, time, profile }

class _AltitudePlannerState extends State<AltitudePlanner> {
  final _start = TextEditingController();
  final _target = TextEditingController();
  final _groundspeed = TextEditingController();
  final _constraint = TextEditingController();
  _PlanMode _mode = _PlanMode.distance;
  AltitudePlan? _plan;
  String? _error;
  final List<AltitudeSample> _altitudeSamples = [];
  Position? _lastPosition;
  double _gpsTravelledNm = 0;
  double? _verticalSpeedFpm;
  final List<AltitudeSample> _barometerSamples = [];
  double? _barometerVerticalSpeedFpm;
  StreamSubscription<BarometerReading>? _barometerSubscription;
  String? _gpsMessage;
  Stopwatch? _planClock;
  Timer? _refreshTimer;
  bool _showTracking = false;
  bool _restoring = true;
  bool _groundspeedManuallyOverridden = false;
  bool _startAltitudeManuallyOverridden = false;
  bool _startAltitudeLockedForPlan = false;
  bool _groundspeedLockedForPlan = false;
  String? _constraintPointName;
  NavigationPoint? _constraintPoint;
  static const _preferenceKeys = [
    'descent_start',
    'descent_target',
    'descent_ground_speed',
    'descent_constraint',
    'descent_mode',
  ];
  static const _startAltitudeManualPreference = 'descent_start_manual';

  @override
  void initState() {
    super.initState();
    GpsPositionService.instance.addListener(_onGpsServiceChanged);
    _barometerSubscription = BarometerService.instance.readings.listen(
      _onBarometerReading,
    );
    unawaited(_restoreFields().then((_) => _onGpsServiceChanged()));
  }

  void _onBarometerReading(BarometerReading reading) {
    if (!mounted ||
        _plan == null ||
        !BarometerService.instance.useForVerticalSpeed) {
      return;
    }
    _barometerSamples.add(
      AltitudeSample(
        timestamp: reading.time,
        altitudeFt: reading.altitudeMeters * metersToFeet,
      ),
    );
    final cutoff = reading.time.subtract(const Duration(seconds: 30));
    _barometerSamples.removeWhere(
      (sample) => sample.timestamp.isBefore(cutoff),
    );
    setState(() {
      _barometerVerticalSpeedFpm = estimateVerticalSpeedFpm(_barometerSamples);
    });
  }

  Future<void> _restoreFields() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final savedStartAltitude = preferences.getString('descent_start') ?? '';
      _startAltitudeManuallyOverridden =
          preferences.getBool(_startAltitudeManualPreference) ??
          savedStartAltitude.isNotEmpty;
      _start.text = _startAltitudeManuallyOverridden ? savedStartAltitude : '';
      _target.text = preferences.getString('descent_target') ?? '';
      _groundspeedManuallyOverridden =
          preferences.getBool('descent_ground_speed_manual') ?? false;
      _groundspeed.text = _groundspeedManuallyOverridden
          ? preferences.getString('descent_ground_speed') ?? ''
          : '';
      _constraint.text = preferences.getString('descent_constraint') ?? '';
      final savedMode = preferences.getString('descent_mode');
      _mode = _PlanMode.values.firstWhere(
        (mode) => mode.name == savedMode,
        orElse: () => _PlanMode.distance,
      );
      _restoring = false;
    });
  }

  void _saveField(String key, String value) {
    if (_restoring) return;
    unawaited(
      SharedPreferences.getInstance().then(
        (preferences) => preferences.setString(key, value),
      ),
    );
  }

  @override
  void dispose() {
    GpsPositionService.instance.removeListener(_onGpsServiceChanged);
    _barometerSubscription?.cancel();
    _refreshTimer?.cancel();
    _start.dispose();
    _target.dispose();
    _groundspeed.dispose();
    _constraint.dispose();
    super.dispose();
  }

  Widget _groundSpeedField() => _NumberField(
    controller: _groundspeed,
    label: 'GROUND SPEED',
    unit: 'kt',
    hint: 'Leave blank for GPS',
    clearValueOnOpen:
        !_groundspeedManuallyOverridden && _groundspeed.text.isNotEmpty,
    maxIntegerDigits: 3,
    minimumValue: 1,
    maximumValue: 999,
    onChanged: (value) {
      _groundspeedManuallyOverridden = value.isNotEmpty;
      if (!_restoring) {
        unawaited(
          SharedPreferences.getInstance().then(
            (preferences) => preferences.setBool(
              'descent_ground_speed_manual',
              _groundspeedManuallyOverridden,
            ),
          ),
        );
      }
      _saveField('descent_ground_speed', value);
      _clearResult();
    },
  );

  Widget _currentAltitudeField() => _NumberField(
    controller: _start,
    label: 'CURRENT ALTITUDE',
    unit: 'ft',
    hint: 'Leave blank for GPS',
    clearValueOnOpen:
        !_startAltitudeManuallyOverridden && _start.text.isNotEmpty,
    maxIntegerDigits: 6,
    minimumValue: 0,
    maximumValue: 60000,
    onChanged: (value) {
      _startAltitudeManuallyOverridden = value.isNotEmpty;
      if (!_restoring) {
        unawaited(
          SharedPreferences.getInstance().then(
            (preferences) => preferences.setBool(
              _startAltitudeManualPreference,
              _startAltitudeManuallyOverridden,
            ),
          ),
        );
      }
      _saveField('descent_start', value);
      _clearResult();
    },
  );

  Widget _constraintField() => _NumberField(
    controller: _constraint,
    label: _mode == _PlanMode.distance
        ? _constraintPointName == null
              ? 'DISTANCE AVAILABLE'
              : 'DISTANCE · ${_shortLocationName(_constraintPointName!)}'
        : 'TIME AVAILABLE',
    unit: _mode == _PlanMode.distance ? 'NM' : 'min',
    hint: _mode == _PlanMode.distance ? 'e.g. 25.0' : 'e.g. 12',
    maxIntegerDigits: _mode == _PlanMode.distance ? 3 : 4,
    decimalPlaces: _mode == _PlanMode.distance ? 1 : 0,
    minimumValue: 0.1,
    maximumValue: _mode == _PlanMode.distance ? 999.9 : 9999,
    onChanged: (value) {
      _constraintPointName = null;
      _constraintPoint = null;
      _saveField('descent_constraint', value);
      _clearResult();
    },
  );

  Widget _groundSpeedStatus() => Text(
    'Leave blank for GPS; type a value for manual input.',
    style: TextStyle(color: context.appMutedText, fontSize: 13),
  );

  void _calculate() {
    final start = double.tryParse(_start.text.trim());
    final target = double.tryParse(_target.text.trim());
    final speed = double.tryParse(_groundspeed.text.trim());
    final constraint = _mode == _PlanMode.profile
        ? null
        : double.tryParse(_constraint.text.trim());
    if (start == null ||
        target == null ||
        speed == null ||
        (_mode != _PlanMode.profile && constraint == null)) {
      setState(() {
        _error =
            'Enter current altitude, target altitude, ground speed'
            '${_mode == _PlanMode.profile ? '' : ', and ${_mode == _PlanMode.distance ? 'distance' : 'time'}'}.';
        _plan = null;
      });
      return;
    }

    try {
      final plan = calculateAltitudePlan(
        startAltitudeFt: start,
        targetAltitudeFt: target,
        groundspeedKt: speed,
        distanceNm: _mode == _PlanMode.distance ? constraint : null,
        timeMinutes: _mode == _PlanMode.time ? constraint : null,
        profile: widget.profile,
      );
      setState(() {
        _plan = plan;
        _error = null;
        _showTracking = true;
        _gpsMessage = GpsPositionService.instance.errorMessage;
        _gpsTravelledNm = 0;
        _startAltitudeLockedForPlan = true;
        _groundspeedLockedForPlan = true;
        _altitudeSamples.clear();
        _verticalSpeedFpm = null;
        _barometerSamples.clear();
        _barometerVerticalSpeedFpm = null;
        _planClock = Stopwatch()..start();
      });
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } on ArgumentError catch (error) {
      setState(() {
        _plan = null;
        _error = error.message.toString();
      });
    }
  }

  void _onGpsServiceChanged() {
    if (!mounted || _restoring) return;
    final position = GpsPositionService.instance.position;
    if (position != null) _onPosition(position);
    final message = GpsPositionService.instance.errorMessage;
    if (message != null && mounted) {
      setState(() => _gpsMessage = message);
    }
  }

  void _onPosition(Position position) {
    if (!mounted || position.isMocked) return;
    final altitudeEntry =
        position.hasAltitude &&
            DateTime.now().difference(position.timestamp) <=
                const Duration(seconds: 10)
        ? gpsAltitudeEntry(
            altitudeMeters: position.altitude,
            manuallyOverridden:
                _startAltitudeManuallyOverridden || _startAltitudeLockedForPlan,
          )
        : null;
    if (altitudeEntry != null && altitudeEntry != _start.text && !_restoring) {
      _start.text = altitudeEntry;
      _saveField('descent_start', altitudeEntry);
      unawaited(
        SharedPreferences.getInstance().then(
          (preferences) =>
              preferences.setBool(_startAltitudeManualPreference, false),
        ),
      );
    }
    final groundspeedEntry = gpsGroundSpeedEntry(
      speedMetersPerSecond: position.speed,
      manuallyOverridden:
          _groundspeedManuallyOverridden || _groundspeedLockedForPlan,
    );
    if (groundspeedEntry != null &&
        groundspeedEntry != _groundspeed.text &&
        !_restoring) {
      _groundspeed.text = groundspeedEntry;
      _saveField('descent_ground_speed', groundspeedEntry);
    }
    final timestamp = position.timestamp;
    final previous = _lastPosition;
    if (_plan != null &&
        previous != null &&
        timestamp.isAfter(previous.timestamp)) {
      final segmentMeters = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      if (segmentMeters.isFinite && segmentMeters > 0) {
        _gpsTravelledNm += segmentMeters / 1852;
      }
    }
    _lastPosition = position;
    if (_plan != null &&
        isNewerFix(
          previousTimestamp: previous?.timestamp,
          timestamp: timestamp,
        )) {
      final altitudeFt = position.altitude * metersToFeet;
      _altitudeSamples.add(
        AltitudeSample(timestamp: timestamp, altitudeFt: altitudeFt),
      );
      final cutoff = timestamp.subtract(const Duration(seconds: 30));
      _altitudeSamples.removeWhere(
        (sample) => sample.timestamp.isBefore(cutoff),
      );
      _verticalSpeedFpm = estimateVerticalSpeedFpm(_altitudeSamples);
    }
    setState(() => _gpsMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    final gpsPosition = _lastPosition;
    final useBarometerSpeed =
        BarometerService.instance.useForVerticalSpeed &&
        _barometerVerticalSpeedFpm != null;
    final currentAltitudeFt = gpsPosition == null
        ? null
        : gpsPosition.altitude * metersToFeet;
    final elapsedMinutes = (_planClock?.elapsed.inMilliseconds ?? 0) / 60000;
    final selectedTimeMinutes = _mode == _PlanMode.time
        ? double.tryParse(_constraint.text.trim())
        : _mode == _PlanMode.profile
        ? _plan?.timeMinutes
        : null;
    final selectedDistanceNm = _mode == _PlanMode.distance
        ? double.tryParse(_constraint.text.trim())
        : _mode == _PlanMode.profile
        ? _plan?.distanceNm
        : null;
    final remainingDistanceNm = selectedDistanceNm == null
        ? null
        : math.max(0.0, selectedDistanceNm - _gpsTravelledNm).toDouble();
    final gpsIsStale =
        gpsPosition == null ||
        DateTime.now().difference(gpsPosition.timestamp) >
            const Duration(seconds: 10);
    final targetGroundSpeedKt = double.tryParse(_groundspeed.text.trim());
    final currentGroundSpeedKt = gpsPosition == null || gpsIsStale
        ? null
        : gpsPosition.speed * metersPerSecondToKnots;
    final remainingTimeMinutes = selectedTimeMinutes != null
        ? selectedTimeMinutes - elapsedMinutes
        : remainingDistanceNm != null && targetGroundSpeedKt != null
        ? calculateTimeForDistanceMinutes(
            distanceNm: remainingDistanceNm,
            groundspeedKt: targetGroundSpeedKt,
          )
        : null;
    final liveRequiredRate =
        currentAltitudeFt == null || gpsIsStale || remainingTimeMinutes == null
        ? null
        : calculateLiveRequiredRateFpm(
            startAltitudeFt: double.tryParse(_start.text.trim()) ?? 0,
            currentAltitudeFt: currentAltitudeFt,
            targetAltitudeFt: double.tryParse(_target.text.trim()) ?? 0,
            remainingTimeMinutes: remainingTimeMinutes,
          );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          if (!_showTracking) ...[
            const _SectionHeading(
              title: 'CLIMB / DESCENT PLAN',
              subtitle: 'Set a target above or below current altitude. Enter altitude in ft and ground speed in kt.',
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _currentAltitudeField()),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    controller: _target,
                    label: 'TARGET ALTITUDE',
                    unit: 'ft',
                    hint: 'e.g. 3000',
                    maxIntegerDigits: 6,
                    minimumValue: 0,
                    maximumValue: 60000,
                    onChanged: (value) {
                      _saveField('descent_target', value);
                      _clearResult();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Leave blank for GPS; type a value for manual input.',
              style: TextStyle(color: context.appMutedText, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Text(
              'WHAT DO YOU KNOW?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: context.appSecondaryText,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<_PlanMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
              ),
              segments: [
                ButtonSegment(
                  value: _PlanMode.distance,
                  label: Text('DISTANCE'),
                ),
                ButtonSegment(value: _PlanMode.time, label: Text('TIME')),
                ButtonSegment(
                  value: _PlanMode.profile,
                  label: Text('${widget.profile.degrees}° PATH'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.first;
                  _constraint.clear();
                  _constraintPointName = null;
                  _constraintPoint = null;
                  _plan = null;
                  _error = null;
                  _showTracking = false;
                });
                _saveField('descent_mode', selection.first.name);
                _saveField('descent_constraint', '');
              },
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final fields = <Widget>[
                  _groundSpeedField(),
                  if (_mode != _PlanMode.profile) _constraintField(),
                  if (_mode == _PlanMode.profile)
                    _InfoCard(
                      text:
                          'Standard ${widget.profile.degrees}° path estimates time and distance.',
                      icon: Icons.info_outline,
                    ),
                ];
                if (constraints.maxWidth < 480) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < fields.length; index++) ...[
                        if (index > 0) const SizedBox(height: 8),
                        fields[index],
                      ],
                      const SizedBox(height: 6),
                      _groundSpeedStatus(),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < fields.length; index++) ...[
                          if (index > 0) const SizedBox(width: 10),
                          Expanded(child: fields[index]),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    _groundSpeedStatus(),
                  ],
                );
              },
            ),
            if (_mode == _PlanMode.distance) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 62,
                child: FilledButton.icon(
                  key: const ValueKey('add-by-location'),
                  onPressed: _chooseDistancePoint,
                  icon: const Icon(Icons.add_location_alt, size: 26),
                  label: const Text(
                    'ADD BY LOCATION',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.appAccent,
                    foregroundColor: context.appBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 62,
              child: FilledButton.icon(
                key: const ValueKey('calculate-plan'),
                onPressed: _calculate,
                icon: const Icon(Icons.calculate, size: 26),
                label: const Text(
                  'CALCULATE PLAN',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: context.appAccent,
                  foregroundColor: context.appBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _AlertCard(text: _error!, warning: false),
            ],
          ],
          if (_plan != null && _showTracking) ...[
            _AltitudeResults(
              plan: _plan!,
              groundspeedKt: targetGroundSpeedKt ?? 0,
            ),
            const SizedBox(height: 14),
            _LiveVerticalRateCard(
              gpsMessage: _gpsMessage,
              position: gpsPosition,
              isStale: gpsIsStale,
              gpsFixLevel: gpsIsStale
                  ? GpsFixLevel.none
                  : GpsPositionService.instance.satelliteStatus?.fixLevel ??
                        GpsFixLevel.none,
              targetGroundSpeedKt: targetGroundSpeedKt,
              currentGroundSpeedKt: currentGroundSpeedKt,
              currentAltitudeFt: currentAltitudeFt,
              targetAltitudeFt: double.tryParse(_target.text.trim()),
              verticalSpeedFpm: useBarometerSpeed
                  ? _barometerVerticalSpeedFpm
                  : _verticalSpeedFpm,
              verticalSpeedSource: useBarometerSpeed ? 'BARO' : 'GPS',
              requiredRateFpm: liveRequiredRate,
              remainingTimeMinutes: remainingTimeMinutes,
              remainingDistanceNm: remainingDistanceNm,
              trackedDistanceNm: _gpsTravelledNm,
              point: _constraintPoint,
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 14),
              const _GpsDebugPanel(),
            ],
          ],
          if (_plan != null && !_showTracking) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 62,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showTracking = true),
                icon: const Icon(Icons.sensors, size: 25),
                label: const Text(
                  'SHOW LIVE TRACKING',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
          if (!_showTracking) ...[
            const SizedBox(height: 14),
            _ClearAllButton(onPressed: _clearAll),
            const SizedBox(height: 22),
          ],
          Text(
            'Planning aid only. Confirm against aircraft performance, current conditions, and approved procedures.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.appFaintText,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (_plan != null && _showTracking) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 62,
              child: FilledButton.icon(
                key: const ValueKey('edit-plan'),
                onPressed: () => setState(() => _showTracking = false),
                icon: const Icon(Icons.edit, size: 25),
                label: const Text(
                  'EDIT PLAN',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: context.appPanel,
                  foregroundColor: context.appAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _clearResult() {
    if (_plan != null || _error != null) {
      final hadPlan = _plan != null;
      _showTracking = false;
      if (hadPlan) {
        _startAltitudeLockedForPlan = false;
        _groundspeedLockedForPlan = false;
        _refreshTimer?.cancel();
      }
      setState(() {
        _plan = null;
        _error = null;
        _planClock = null;
        _gpsTravelledNm = 0;
        _altitudeSamples.clear();
        _verticalSpeedFpm = null;
      });
    }
  }

  Future<void> _chooseDistancePoint() async {
    final selection = await Navigator.of(context).push<PointSelection>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: context.appBackground,
          appBar: AppBar(
            title: Text('SELECT DESTINATION'),
            leading: IconButton(
              tooltip: 'Back without selecting a point',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: PointFinderPage(selectForDistance: true),
        ),
      ),
    );
    if (selection == null || !mounted) return;
    final distance = selection.range.distanceNm;
    if (distance <= 0 || distance > 999.9) {
      setState(() {
        _error = 'The selected point is outside the distance field range (0.1–999.9 NM).';
      });
      return;
    }
    final value = distance.toStringAsFixed(1);
    setState(() {
      _constraint.text = value;
      _constraintPointName = selection.point.name;
      _constraintPoint = selection.point;
    });
    _saveField('descent_constraint', value);
    _clearResult();
  }

  void _clearAll() {
    _refreshTimer?.cancel();
    for (final controller in [_start, _target, _groundspeed, _constraint]) {
      controller.clear();
    }
    setState(() {
      _plan = null;
      _error = null;
      _gpsMessage = null;
      _planClock = null;
      _gpsTravelledNm = 0;
      _altitudeSamples.clear();
      _verticalSpeedFpm = null;
      _showTracking = false;
      _groundspeedLockedForPlan = false;
      _startAltitudeLockedForPlan = false;
      _startAltitudeManuallyOverridden = false;
      _groundspeedManuallyOverridden = false;
      _mode = _PlanMode.distance;
      _constraintPointName = null;
      _constraintPoint = null;
    });
    unawaited(
      SharedPreferences.getInstance().then((preferences) async {
        for (final key in _preferenceKeys) {
          await preferences.remove(key);
        }
        await preferences.remove('descent_ground_speed_manual');
        await preferences.remove(_startAltitudeManualPreference);
      }),
    );
  }
}

class _GpsAccuracyIndicator extends StatelessWidget {
  const _GpsAccuracyIndicator({
    required this.icon,
    required this.tooltip,
    required this.value,
  });

  final IconData icon;
  final String tooltip;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: '$tooltip: $value',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: context.appMutedText),
            const SizedBox(width: 3),
            Text(
              value,
              style: TextStyle(
                color: context.appMutedText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GpsDebugPanel extends StatelessWidget {
  const _GpsDebugPanel();

  @override
  Widget build(BuildContext context) {
    final service = GpsPositionService.instance;
    final lastFix = service.position?.timestamp;
    final ageMs = lastFix == null
        ? null
        : DateTime.now().difference(lastFix).inMilliseconds;
    final gaps = service.debugRecentGapsMs;
    final style = TextStyle(
      color: context.appSecondaryText,
      fontFamily: 'monospace',
      fontSize: 12,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GPS DEBUG', style: style.copyWith(fontWeight: FontWeight.w900)),
        Text('fixes: ${service.debugFixCount}', style: style),
        Text('last fix: ${lastFix?.toIso8601String() ?? 'none'}', style: style),
        Text('age: ${ageMs == null ? 'none' : '$ageMs ms'}', style: style),
        Text(
          'gaps ms: ${gaps.isEmpty ? 'none' : gaps.join(' ')}',
          style: style,
        ),
      ],
    );
  }
}

class _LiveVerticalRateCard extends StatelessWidget {
  const _LiveVerticalRateCard({
    required this.gpsMessage,
    required this.position,
    required this.isStale,
    required this.gpsFixLevel,
    required this.targetGroundSpeedKt,
    required this.currentGroundSpeedKt,
    required this.currentAltitudeFt,
    required this.targetAltitudeFt,
    required this.verticalSpeedFpm,
    required this.verticalSpeedSource,
    required this.requiredRateFpm,
    required this.remainingTimeMinutes,
    required this.remainingDistanceNm,
    required this.trackedDistanceNm,
    required this.point,
  });

  final String? gpsMessage;
  final Position? position;
  final bool isStale;
  final GpsFixLevel gpsFixLevel;
  final double? targetGroundSpeedKt;
  final double? currentGroundSpeedKt;
  final double? currentAltitudeFt;
  final double? targetAltitudeFt;
  final double? verticalSpeedFpm;
  final String verticalSpeedSource;
  final double? requiredRateFpm;
  final double? remainingTimeMinutes;
  final double? remainingDistanceNm;
  final double trackedDistanceNm;
  final NavigationPoint? point;

  @override
  Widget build(BuildContext context) {
    final actual = isStale ? null : verticalSpeedFpm;
    final required = requiredRateFpm;
    final deviation = actual == null || required == null
        ? null
        : actual - required;
    final accuracyMeters = position?.altitudeAccuracy;
    final horizontalAccuracyMeters = position?.hasAccuracy == true
        ? position!.accuracy
        : null;
    final altitudeAccuracyFeet = position?.hasAltitudeAccuracy == true
        ? position!.altitudeAccuracy * metersToFeet
        : null;
    final targetAltitude = targetAltitudeFt;
    final altitudeDelta = currentAltitudeFt == null || targetAltitude == null
        ? null
        : targetAltitude - currentAltitudeFt!;
    final speedDelta =
        currentGroundSpeedKt == null || targetGroundSpeedKt == null
        ? null
        : currentGroundSpeedKt! - targetGroundSpeedKt!;
    final gpsIndicatorColor = switch (gpsFixLevel) {
      GpsFixLevel.none => Theme.of(context).colorScheme.error,
      GpsFixLevel.twoDimensional => context.appWarning,
      GpsFixLevel.threeDimensional =>
        context.isDarkPalette
            ? const Color(0xFF8BE28B)
            : const Color(0xFF1B5E20),
    };
    final pointRange = !isStale && position != null && point != null
        ? calculatePointRange(
            fromLatitude: position!.latitude,
            fromLongitude: position!.longitude,
            toLatitude: point!.latitude,
            toLongitude: point!.longitude,
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.appWarning.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label:
                'LIVE VERTICAL RATE · GPS · ${switch (gpsFixLevel) {
                  GpsFixLevel.none => 'NO LOCK',
                  GpsFixLevel.twoDimensional => '2D',
                  GpsFixLevel.threeDimensional => '3D',
                }}',
            child: Wrap(
              key: const ValueKey('live-vertical-rate-gps-heading'),
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'LIVE VERTICAL RATE ·',
                      style: TextStyle(
                        color: context.appWarning,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'GPS',
                      style: TextStyle(
                        color: gpsIndicatorColor,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      switch (gpsFixLevel) {
                        GpsFixLevel.none => 'NO LOCK',
                        GpsFixLevel.twoDimensional => '2D',
                        GpsFixLevel.threeDimensional => '3D',
                      },
                      key: const ValueKey('gps-fix-level-label'),
                      style: TextStyle(
                        color: gpsIndicatorColor,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (gpsFixLevel == GpsFixLevel.threeDimensional) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: '3D satellite fix',
                        child: Icon(
                          Icons.satellite_alt,
                          key: const ValueKey('gps-3d-fix-indicator'),
                          size: 16,
                          color: gpsIndicatorColor,
                        ),
                      ),
                    ],
                  ],
                ),
                _GpsAccuracyIndicator(
                  icon: Icons.gps_fixed,
                  tooltip: 'Horizontal accuracy',
                  value: horizontalAccuracyMeters == null
                      ? 'H —'
                      : 'H ±${horizontalAccuracyMeters.round()} m',
                ),
                _GpsAccuracyIndicator(
                  icon: Icons.height,
                  tooltip: 'Altitude accuracy',
                  value: altitudeAccuracyFeet == null
                      ? 'ALT —'
                      : 'ALT ±${altitudeAccuracyFeet.round()} ft',
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'GPS altitude is approximate; compare with the aircraft altimeter.',
            style: TextStyle(color: context.appMutedText, fontSize: 13),
          ),
          if (gpsMessage != null || isStale) ...[
            const SizedBox(height: 12),
            _AlertCard(
              warning: false,
              text: isStale && gpsMessage == null
                  ? 'GPS fix is stale. Waiting for a fresh location.'
                  : gpsMessage ?? '',
            ),
          ],
          const SizedBox(height: 10),
          _TrackingPanel(
            title: 'GROUND SPEED',
            unit: 'kt',
            metrics: [
              _TrackingMetric(
                label: 'TARGET',
                value: targetGroundSpeedKt?.round().toString() ?? '—',
              ),
              _TrackingMetric(
                label: 'CURRENT',
                value: currentGroundSpeedKt?.toStringAsFixed(1) ?? '—',
              ),
              _TrackingMetric(
                label: 'DELTA',
                value: speedDelta == null ? '—' : _signed(speedDelta, 1),
                alert: speedDelta != null && speedDelta.abs() >= 5,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TrackingPanel(
            title: 'VERTICAL SPEED · $verticalSpeedSource',
            unit: 'ft/min',
            metrics: [
              _TrackingMetric(
                label: 'TARGET',
                value: required == null ? '—' : _signedFpm(required),
              ),
              _TrackingMetric(
                label: 'CURRENT',
                value: actual == null ? '—' : _signedFpm(actual),
                alert: actual != null && actual > 0,
              ),
              _TrackingMetric(
                label: 'DELTA',
                value: deviation == null ? '—' : _signedFpm(deviation),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TrackingPanel(
            title: 'ALTITUDE',
            unit: 'ft',
            metrics: [
              _TrackingMetric(
                label: 'TARGET',
                value: targetAltitude?.round().toString() ?? '—',
              ),
              _TrackingMetric(
                label: 'CURRENT',
                value: currentAltitudeFt?.round().toString() ?? '—',
              ),
              _TrackingMetric(
                label: 'DELTA',
                value: altitudeDelta == null ? '—' : _signed(altitudeDelta, 0),
              ),
            ],
          ),
          if (actual == null)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Collecting GPS altitude trend…',
                style: TextStyle(color: context.appSecondaryText, fontSize: 14),
              ),
            )
          else if (required == null)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Required rate unavailable: waiting for a fresh GPS fix or remaining constraint.',
                style: TextStyle(
                  color: context.appSecondaryText,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ),
          if (accuracyMeters != null && accuracyMeters > 0) ...[
            const SizedBox(height: 6),
            Text(
              'GPS vertical accuracy ±${(accuracyMeters * metersToFeet).round()} ft',
              style: TextStyle(color: context.appMutedText, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          _TrackingPanel(
            title: point == null ? 'REMAINING' : 'REMAINING - ${point!.name}',
            unit: '',
            metrics: [
              _TrackingMetric(
                label: 'TIME',
                value:
                    remainingTimeMinutes != null &&
                        remainingTimeMinutes!.isFinite
                    ? math.max(0, remainingTimeMinutes!).toStringAsFixed(1)
                    : '—',
                unit: 'min',
              ),
              _TrackingMetric(
                label: 'DISTANCE',
                value: remainingDistanceNm?.toStringAsFixed(1) ?? '—',
                unit: 'NM',
              ),
              _TrackingMetric(
                label: point == null ? 'POINT' : 'TO POINT',
                value: pointRange == null
                    ? '—'
                    : (pointRange.bearingDeg.round() % 360).toString().padLeft(
                        3,
                        '0',
                      ),
                unit: pointRange == null ? '' : '°T',
                bearingDegrees: pointRange?.bearingDeg,
              ),
            ],
          ),
          if (remainingDistanceNm != null) ...[
            const SizedBox(height: 8),
            Text(
              '${trackedDistanceNm.toStringAsFixed(1)} NM tracked since calculation',
              style: TextStyle(color: context.appMutedText, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'GPS-derived values are approximate. DELTA shows current minus target, except altitude (target minus current).',
            style: TextStyle(
              color: context.appMutedText,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          if (point != null) ...[
            const SizedBox(height: 4),
            Text(
              'Point arrow shows true bearing, not a wind-corrected heading.',
              style: TextStyle(color: context.appMutedText, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String _signedFpm(double value) => '${value > 0 ? '+' : ''}${value.round()}';

  String _signed(double value, int decimals) =>
      '${value > 0 ? '+' : ''}${value.toStringAsFixed(decimals)}';
}

class _AltitudeResults extends StatefulWidget {
  const _AltitudeResults({required this.plan, required this.groundspeedKt});

  final AltitudePlan plan;
  final double groundspeedKt;

  @override
  State<_AltitudeResults> createState() => _AltitudeResultsState();
}

class _AltitudeResultsState extends State<_AltitudeResults> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.appAccent.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('vertical-plan-toggle'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'VERTICAL PLAN',
                      style: TextStyle(
                        color: context.appAccent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: context.appAccent,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 180),
            child: _expanded
                ? Padding(
                    key: const ValueKey('vertical-plan-metrics'),
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _Metric(
                                label: widget.plan.isClimb
                                    ? 'CLIMB RATE'
                                    : 'DESCENT RATE',
                                value: '${widget.plan.rateFpm.round()}',
                                unit: 'ft/min',
                              ),
                            ),
                            Expanded(
                              child: _Metric(
                                label: 'TIME',
                                value: _formatTime(widget.plan.timeMinutes),
                                unit: '',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _Metric(
                                label: 'GROUND SPEED',
                                value: widget.groundspeedKt.round().toString(),
                                unit: 'kt',
                              ),
                            ),
                            Expanded(
                              child: _Metric(
                                label: 'DISTANCE',
                                value: widget.plan.distanceNm.toStringAsFixed(
                                  1,
                                ),
                                unit: 'NM',
                              ),
                            ),
                          ],
                        ),
                        if (widget.plan.usesProfile) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Based on approximately ${widget.plan.profileDegrees == 3 ? 318 : 531} ft per nautical mile (${widget.plan.profileDegrees}° vertical path).',
                            style: TextStyle(
                              color: context.appMutedText,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _formatTime(double minutes) {
    final wholeMinutes = minutes.round();
    final hours = wholeMinutes ~/ 60;
    final remainder = wholeMinutes % 60;
    if (hours == 0) return '$remainder min';
    return '$hours h ${remainder.toString().padLeft(2, '0')} min';
  }
}

class _TrackingPanel extends StatelessWidget {
  const _TrackingPanel({
    required this.title,
    required this.unit,
    required this.metrics,
  });

  final String title;
  final String unit;
  final List<_TrackingMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.appBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.appWarning,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final metric in metrics)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.label,
                        style: TextStyle(
                          color: context.appMutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          if (metric.bearingDegrees != null) ...[
                            Transform.rotate(
                              angle: metric.bearingDegrees! * math.pi / 180,
                              child: Icon(
                                Icons.navigation,
                                color: context.appAccent,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${metric.value} ${metric.unit ?? unit}',
                                style: TextStyle(
                                  color: metric.alert
                                      ? const Color(0xFFFF6B6B)
                                      : context.appText,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _shortLocationName(String name, {int maxLength = 9}) {
  final trimmedName = name.trim();
  if (trimmedName.length <= maxLength) return trimmedName;
  return '${trimmedName.substring(0, maxLength - 1).trimRight()}…';
}

class _TrackingMetric {
  const _TrackingMetric({
    required this.label,
    required this.value,
    this.alert = false,
    this.unit,
    this.bearingDegrees,
  });

  final String label;
  final String value;
  final bool alert;
  final String? unit;
  final double? bearingDegrees;
}

class WindPlanner extends StatefulWidget {
  const WindPlanner({super.key});

  @override
  State<WindPlanner> createState() => _WindPlannerState();
}

class _WindPlannerState extends State<WindPlanner> {
  final _windDirection = TextEditingController();
  final _windSpeed = TextEditingController();
  final _runway = TextEditingController();
  WindAssessment? _assessment;
  String? _error;
  bool _restoring = true;
  static const _preferenceKeys = [
    'wind_direction',
    'wind_speed',
    'wind_runway',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_restoreFields());
  }

  Future<void> _restoreFields() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _windDirection.text = preferences.getString('wind_direction') ?? '';
      _windSpeed.text = preferences.getString('wind_speed') ?? '';
      _runway.text = preferences.getString('wind_runway') ?? '';
      _restoring = false;
    });
  }

  void _saveField(String key, String value) {
    if (_restoring) return;
    unawaited(
      SharedPreferences.getInstance().then(
        (preferences) => preferences.setString(key, value),
      ),
    );
  }

  @override
  void dispose() {
    _windDirection.dispose();
    _windSpeed.dispose();
    _runway.dispose();
    super.dispose();
  }

  void _calculate() {
    final direction = double.tryParse(_windDirection.text.trim());
    final speed = double.tryParse(_windSpeed.text.trim());
    final runway = int.tryParse(_runway.text.trim());
    if (direction == null || speed == null || runway == null) {
      setState(() {
        _assessment = null;
        _error = 'Enter wind direction, wind speed, and runway number.';
      });
      return;
    }
    try {
      final result = calculateWind(
        windDirectionDeg: direction,
        windSpeedKt: speed,
        runwayNumber: runway,
      );
      setState(() {
        _assessment = result;
        _error = null;
      });
    } on ArgumentError catch (error) {
      setState(() {
        _assessment = null;
        _error = error.message.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          const _SectionHeading(
            title: 'WIND & RUNWAY',
            subtitle: 'Wind direction is where the wind comes FROM. Enter runway number, e.g. 07.',
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _NumberField(
                  controller: _windDirection,
                  label: 'WIND DIRECTION',
                  unit: '°',
                  hint: '180',
                  onChanged: (value) {
                    _saveField('wind_direction', value);
                    _clearResult();
                  },
                  maxIntegerDigits: 3,
                  minimumValue: 0,
                  maximumValue: 360,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  controller: _windSpeed,
                  label: 'WIND SPEED',
                  unit: 'kt',
                  hint: '20',
                  onChanged: (value) {
                    _saveField('wind_speed', value);
                    _clearResult();
                  },
                  maxIntegerDigits: 3,
                  minimumValue: 0,
                  maximumValue: 999,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _NumberField(
            controller: _runway,
            label: 'INTENDED RUNWAY',
            unit: 'RWY',
            hint: '07',
            onChanged: (value) {
              _saveField('wind_runway', value);
              _clearResult();
            },
            maxIntegerDigits: 2,
            minimumValue: 1,
            maximumValue: 36,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 62,
            child: FilledButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.air, size: 26),
              label: const Text(
                'CHECK WIND',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: context.appAccent,
                foregroundColor: context.appBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _AlertCard(text: _error!, warning: false),
          ],
          if (_assessment != null) ...[
            const SizedBox(height: 18),
            _WindResults(assessment: _assessment!),
          ],
          const SizedBox(height: 14),
          _ClearAllButton(onPressed: _clearAll),
          const SizedBox(height: 22),
          Text(
            'Planning aid only. Verify reported winds, runway conditions, aircraft limits, and operational decisions independently.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.appFaintText,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _clearResult() {
    if (_assessment != null || _error != null) {
      setState(() {
        _assessment = null;
        _error = null;
      });
    }
  }

  void _clearAll() {
    for (final controller in [_windDirection, _windSpeed, _runway]) {
      controller.clear();
    }
    setState(() {
      _assessment = null;
      _error = null;
    });
    unawaited(
      SharedPreferences.getInstance().then((preferences) async {
        for (final key in _preferenceKeys) {
          await preferences.remove(key);
        }
      }),
    );
  }
}

class _WindResults extends StatelessWidget {
  const _WindResults({required this.assessment});

  final WindAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final current = assessment.intendedRunway;
    final reciprocal = assessment.reciprocalRunway;
    final showWarning =
        current.tailwindKt > 0.5 || assessment.recommendReciprocal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showWarning)
          _AlertCard(
            warning: true,
            text: current.tailwindKt > 0.5
                ? 'TAILWIND on runway ${assessment.runwayLabel}.'
                      '${assessment.recommendReciprocal ? ' Consider runway ${assessment.reciprocalLabel}: it has a headwind and lower crosswind.' : ''}'
                : 'Runway ${assessment.reciprocalLabel} has a headwind and lower crosswind. Consider it if operationally suitable.',
          ),
        if (showWarning) const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.appPanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: context.appAccent.withValues(alpha: 0.65),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RUNWAY ${assessment.runwayLabel}',
                style: TextStyle(
                  color: context.appAccent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: current.headwindKt >= 0 ? 'HEADWIND' : 'TAILWIND',
                      value: (current.headwindKt.abs()).toStringAsFixed(1),
                      unit: 'kt',
                      alert: current.tailwindKt > 0.5,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'CROSSWIND',
                      value: current.crosswindKt.toStringAsFixed(1),
                      unit: 'kt',
                    ),
                  ),
                ],
              ),
              Divider(
                height: 30,
                color: context.appFaintText.withValues(alpha: 0.35),
              ),
              Text(
                'RECIPROCAL ${assessment.reciprocalLabel}',
                style: TextStyle(
                  color: context.appSecondaryText,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: reciprocal.headwindKt >= 0
                          ? 'HEADWIND'
                          : 'TAILWIND',
                      value: reciprocal.headwindKt.abs().toStringAsFixed(1),
                      unit: 'kt',
                      alert: reciprocal.tailwindKt > 0.5,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'CROSSWIND',
                      value: reciprocal.crosswindKt.toStringAsFixed(1),
                      unit: 'kt',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            color: context.appSecondaryText,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.unit,
    required this.hint,
    required this.onChanged,
    this.maxIntegerDigits = 6,
    this.decimalPlaces = 0,
    this.minimumValue,
    this.maximumValue,
    this.clearValueOnOpen = false,
  });

  final TextEditingController controller;
  final String label;
  final String unit;
  final String hint;
  final ValueChanged<String> onChanged;
  final int maxIntegerDigits;
  final int decimalPlaces;
  final double? minimumValue;
  final double? maximumValue;
  final bool clearValueOnOpen;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      showCursor: false,
      onTap: () async {
        final result = await showDialog<String>(
          context: context,
          builder: (context) => _LargeNumberPad(
            initialValue: clearValueOnOpen ? '' : controller.text,
            maxIntegerDigits: maxIntegerDigits,
            decimalPlaces: decimalPlaces,
            title: label,
            minimumValue: minimumValue,
            maximumValue: maximumValue,
          ),
        );
        if (result != null) {
          controller.text = result;
          onChanged(result);
        }
      },
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: unit,
        suffixStyle: TextStyle(
          color: context.appWarning,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _LargeNumberPad extends StatefulWidget {
  const _LargeNumberPad({
    required this.initialValue,
    required this.maxIntegerDigits,
    required this.decimalPlaces,
    required this.title,
    this.minimumValue,
    this.maximumValue,
  });

  final String initialValue;
  final int maxIntegerDigits;
  final int decimalPlaces;
  final String title;
  final double? minimumValue;
  final double? maximumValue;

  @override
  State<_LargeNumberPad> createState() => _LargeNumberPadState();
}

class _LargeNumberPadState extends State<_LargeNumberPad> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  void _append(String key) {
    if (key == '⌫') {
      if (_value.isNotEmpty) {
        setState(() => _value = _value.substring(0, _value.length - 1));
      }
      return;
    }
    if (key == '.' && (widget.decimalPlaces == 0 || _value.contains('.'))) {
      return;
    }
    final candidate = key == '.' && _value.isEmpty ? '0.' : '$_value$key';
    final parts = candidate.split('.');
    if (parts.first.length > widget.maxIntegerDigits ||
        (parts.length > 1 && parts.last.length > widget.decimalPlaces)) {
      return;
    }
    final value = double.tryParse(candidate);
    if (value != null &&
        widget.maximumValue != null &&
        value > widget.maximumValue!) {
      return;
    }
    setState(() => _value = candidate);
  }

  bool get _isWithinRange {
    if (_value.isEmpty) return true;
    final value = double.tryParse(_value);
    return value != null &&
        (widget.minimumValue == null || value >= widget.minimumValue!) &&
        (widget.maximumValue == null || value <= widget.maximumValue!);
  }

  @override
  Widget build(BuildContext context) {
    final keys = <String>[
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      if (widget.decimalPlaces > 0) '.',
      '0',
      '⌫',
    ];
    return Dialog(
      backgroundColor: context.appBackground,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: context.appPanel,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _value.isEmpty ? ' ' : _value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (!_isWithinRange) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Enter a value between ${widget.minimumValue ?? 'any'} and ${widget.maximumValue ?? 'any'}.',
                    style: const TextStyle(color: Color(0xFFFF6B6B)),
                  ),
                ],
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: keys.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.1,
                  ),
                  itemBuilder: (context, index) {
                    final key = keys[index];
                    return FilledButton(
                      onPressed: () => _append(key),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.appPanel,
                        foregroundColor: context.appText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        key,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 58,
                        child: OutlinedButton(
                          onPressed: () => setState(() => _value = ''),
                          child: const Text(
                            'CLEAR',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 58,
                        child: FilledButton(
                          onPressed: _isWithinRange
                              ? () => Navigator.of(context).pop(_value)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: context.appAccent,
                            foregroundColor: context.appBackground,
                          ),
                          child: const Text(
                            'DONE',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearAllButton extends StatelessWidget {
  const _ClearAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.delete_sweep_outlined),
        label: const Text(
          'CLEAR ALL',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.appSecondaryText,
          side: BorderSide(color: context.appFaintText),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    this.alert = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.appMutedText,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                color: alert ? const Color(0xFFFF6B6B) : context.appText,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                unit,
                style: TextStyle(
                  color: context.appSecondaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.text, required this.warning});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? const Color(0xFFFF4D4D) : context.appWarning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.warning_amber_rounded : Icons.info_outline,
            color: color,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.appPanel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.appAccent, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: context.appSecondaryText, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
