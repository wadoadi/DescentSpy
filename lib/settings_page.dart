import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'app_version.dart';
import 'barometer_service.dart';
import 'calculations.dart';
import 'gps_debug_page.dart';
import 'gps_position_service.dart';
import 'points_page.dart';
import 'speed_unit.dart';

const _metersToFeet = 3.28084;
const _metersPerSecondToKnots = 1.943844;

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.verticalPathProfile,
    required this.onVerticalPathProfileChanged,
    required this.speedUnit,
    required this.onSpeedUnitChanged,
    required this.rateSmoothingSeconds,
    required this.onRateSmoothingChanged,
    required this.showLiveDeltas,
    required this.onShowLiveDeltasChanged,
    required this.onOpenPoints,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VerticalPathProfile verticalPathProfile;
  final ValueChanged<VerticalPathProfile> onVerticalPathProfileChanged;
  final SpeedUnit speedUnit;
  final ValueChanged<SpeedUnit> onSpeedUnitChanged;
  final int rateSmoothingSeconds;
  final ValueChanged<int> onRateSmoothingChanged;
  final bool showLiveDeltas;
  final ValueChanged<bool> onShowLiveDeltasChanged;
  final VoidCallback onOpenPoints;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _requestingPermission = false;
  bool _barometerAvailable = false;
  bool _useBarometer = false;
  bool _loadingKeyboardMode = true;
  PointSearchKeyboardMode _keyboardMode = PointSearchKeyboardMode.large;
  String? _keyboardModeError;

  @override
  void initState() {
    super.initState();
    GpsPositionService.instance.addListener(_onGpsChanged);
    unawaited(_loadKeyboardMode());
    unawaited(_loadBarometer());
    unawaited(GpsPositionService.instance.refreshSatelliteStatus());
  }

  Future<void> _loadBarometer() async {
    final available = await BarometerService.instance.checkAvailable();
    if (!mounted) return;
    setState(() {
      _barometerAvailable = available;
      _useBarometer = BarometerService.instance.useForVerticalSpeed;
    });
  }

  Future<void> _setUseBarometer(bool value) async {
    setState(() => _useBarometer = value);
    await BarometerService.instance.setUseForVerticalSpeed(value);
  }

  @override
  void dispose() {
    GpsPositionService.instance.removeListener(_onGpsChanged);
    super.dispose();
  }

  void _onGpsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadKeyboardMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _keyboardMode =
            preferences.getString(pointSearchKeyboardPreferenceKey) ==
                PointSearchKeyboardMode.system.name
            ? PointSearchKeyboardMode.system
            : PointSearchKeyboardMode.large;
        _loadingKeyboardMode = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _keyboardModeError = 'Could not load keyboard preference: $error';
        _loadingKeyboardMode = false;
      });
    }
  }

  Future<void> _setKeyboardMode(PointSearchKeyboardMode mode) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(pointSearchKeyboardPreferenceKey, mode.name);
      if (!mounted) return;
      setState(() {
        _keyboardMode = mode;
        _keyboardModeError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _keyboardModeError = 'Could not save keyboard preference: $error';
        });
      }
    }
  }

  Future<void> _requestGpsPermission() async {
    setState(() => _requestingPermission = true);
    await GpsPositionService.instance.requestPermissionAgain();
    if (mounted) setState(() => _requestingPermission = false);
  }

  @override
  Widget build(BuildContext context) {
    final gps = GpsPositionService.instance;
    final position = gps.position;
    final age = position == null
        ? null
        : DateTime.now().difference(position.timestamp);
    final fixIsFresh = age != null && age <= const Duration(seconds: 10);
    final satelliteStatus = gps.satelliteStatus;
    final gpsStatus =
        gps.errorMessage ??
        (gps.position == null
            ? 'Waiting for GPS location.'
            : 'GPS permission and location are available.');

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'SETTINGS',
            style: TextStyle(
              color: context.appText,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          Card(
            color: context.appPanel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'COLOUR SCHEME',
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('DARK'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('LIGHT'),
                      ),
                    ],
                    selected: {widget.themeMode},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        widget.onThemeModeChanged(selection.first);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_barometerAvailable) ...[
            Card(
              color: context.appPanel,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'USE BAROMETER FOR VERTICAL SPEED',
                        style: TextStyle(
                          color: context.appText,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      value: _useBarometer,
                      onChanged: _setUseBarometer,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Barometric altitude can be wrong in some aircraft because of static port and ventilation effects. Check the aircraft altimeter. GPS altitude remains the altitude source.',
                      style: TextStyle(color: context.appSecondaryText),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Card(
            color: context.appPanel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'VERTICAL PATH PROFILE',
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sets the slope used when the altitude planner uses a path profile.',
                    style: TextStyle(color: context.appSecondaryText),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<VerticalPathProfile>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: VerticalPathProfile.threeDegree,
                        label: Text('3°'),
                      ),
                      ButtonSegment(
                        value: VerticalPathProfile.fiveDegree,
                        label: Text('5°'),
                      ),
                    ],
                    selected: {widget.verticalPathProfile},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        widget.onVerticalPathProfileChanged(selection.first);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: context.appPanel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'SPEED UNIT',
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sets the unit for ground speed and wind speed entry and display.',
                    style: TextStyle(color: context.appSecondaryText),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<SpeedUnit>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: SpeedUnit.knots,
                        label: Text('kt'),
                      ),
                      ButtonSegment(
                        value: SpeedUnit.kilometresPerHour,
                        label: Text('km/h'),
                      ),
                      ButtonSegment(
                        value: SpeedUnit.milesPerHour,
                        label: Text('mph'),
                      ),
                    ],
                    selected: {widget.speedUnit},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        widget.onSpeedUnitChanged(selection.first);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: context.appPanel,
            child: SwitchListTile(
              value: widget.showLiveDeltas,
              onChanged: widget.onShowLiveDeltasChanged,
              title: Text(
                'SHOW LIVE DELTAS',
                style: TextStyle(
                  color: context.appText,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              subtitle: Text(
                'Shows the DELTA readings on the live panels (speed, vertical speed and altitude).',
                style: TextStyle(color: context.appSecondaryText),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: context.appPanel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'LIVE SMOOTHING',
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Averages GPS altitude, ground speed, remaining distance, bearing to the point, and the TARGET and CURRENT vertical rates over this many seconds. Clock time, typed targets and GPS status are not smoothed.',
                    style: TextStyle(color: context.appSecondaryText),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${widget.rateSmoothingSeconds} s',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  Slider(
                    min: minVerticalRateSmoothingSeconds.toDouble(),
                    max: maxVerticalRateSmoothingSeconds.toDouble(),
                    divisions:
                        maxVerticalRateSmoothingSeconds -
                        minVerticalRateSmoothingSeconds,
                    label: '${widget.rateSmoothingSeconds} s',
                    value: widget.rateSmoothingSeconds.toDouble(),
                    onChanged: (value) =>
                        widget.onRateSmoothingChanged(value.round()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: context.appPanel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'POINT SEARCH KEYBOARD',
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose which keyboard opens when you tap point search. Results update as you type.',
                    style: TextStyle(color: context.appSecondaryText),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<PointSearchKeyboardMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: PointSearchKeyboardMode.large,
                        icon: Icon(Icons.keyboard_alt_outlined),
                        label: Text('LARGE'),
                      ),
                      ButtonSegment(
                        value: PointSearchKeyboardMode.system,
                        icon: Icon(Icons.keyboard_outlined),
                        label: Text('SYSTEM'),
                      ),
                    ],
                    selected: {_keyboardMode},
                    onSelectionChanged: _loadingKeyboardMode
                        ? null
                        : (selection) {
                            if (selection.isNotEmpty) {
                              unawaited(_setKeyboardMode(selection.first));
                            }
                          },
                  ),
                  if (_keyboardModeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _keyboardModeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: context.appPanel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'GPS STATUS',
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _GpsStatusMetric(
                        label: 'FIX',
                        value: position == null
                            ? 'NO FIX'
                            : fixIsFresh
                            ? 'CURRENT'
                            : 'STALE',
                      ),
                      _GpsStatusMetric(
                        label: 'FIX AGE',
                        value: age == null
                            ? '—'
                            : '${math.max(0, age.inSeconds)} s',
                      ),
                      _GpsStatusMetric(
                        label: 'SATELLITES',
                        value: satelliteStatus == null
                            ? '—'
                            : '${satelliteStatus.usedSatellites} used / ${satelliteStatus.visibleSatellites} visible',
                      ),
                      _GpsStatusMetric(
                        label: 'HORIZONTAL ACCURACY',
                        value: position == null || !position.hasAccuracy
                            ? '—'
                            : '±${position.accuracy.toStringAsFixed(0)} m',
                      ),
                      _GpsStatusMetric(
                        label: 'ALTITUDE',
                        value: position == null || !position.hasAltitude
                            ? '—'
                            : '${(position.altitude * _metersToFeet).round()} ft',
                      ),
                      _GpsStatusMetric(
                        label: 'ALTITUDE ACCURACY',
                        value: position == null || !position.hasAltitudeAccuracy
                            ? '—'
                            : '±${(position.altitudeAccuracy * _metersToFeet).round()} ft',
                      ),
                      _GpsStatusMetric(
                        label: 'GROUND SPEED',
                        value: position == null || !position.hasSpeed
                            ? '—'
                            : '${widget.speedUnit.fromKnots(position.speed * _metersPerSecondToKnots).toStringAsFixed(1)} ${widget.speedUnit.label}',
                      ),
                      _GpsStatusMetric(
                        label: 'TRACK / COURSE',
                        value: position == null || !position.hasHeading
                            ? '—'
                            : '${position.heading.round()}°',
                      ),
                    ],
                  ),
                  if (position != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Position ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} · updated ${TimeOfDay.fromDateTime(position.timestamp.toLocal()).format(context)}',
                      style: TextStyle(
                        color: context.appMutedText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (gps.satelliteError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      gps.satelliteError!,
                      style: TextStyle(
                        color: context.appFaintText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (!fixIsFresh && position != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'This GPS fix is stale and should not be treated as current.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: context.appPanel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'GPS PERMISSION',
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    gpsStatus,
                    style: TextStyle(color: context.appSecondaryText),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _requestingPermission
                          ? null
                          : _requestGpsPermission,
                      icon: _requestingPermission
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.location_searching),
                      label: Text(
                        _requestingPermission
                            ? 'REQUESTING…'
                            : 'REQUEST GPS PERMISSION',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'If permission was permanently denied, app settings will open so it can be enabled there.',
                    style: TextStyle(color: context.appFaintText, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 60,
            child: FilledButton.icon(
              onPressed: widget.onOpenPoints,
              icon: const Icon(Icons.place, size: 24),
              label: const Text(
                'OPEN DESTINATION POINTS',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 60,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GpsDebugPage()),
              ),
              icon: const Icon(Icons.bug_report, size: 24),
              label: const Text(
                'GPS DEBUG PAGE',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'DescentSpy is a planning aid. Verify navigation, weather, and aircraft performance using approved sources.',
            style: TextStyle(color: context.appFaintText, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            'Version $appVersion · build $appBuild',
            style: TextStyle(color: context.appFaintText, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _GpsStatusMetric extends StatelessWidget {
  const _GpsStatusMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.appMutedText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: context.appText,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
