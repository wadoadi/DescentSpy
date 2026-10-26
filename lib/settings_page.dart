import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'calculations.dart';
import 'gps_position_service.dart';
import 'points_page.dart';

const _metersToFeet = 3.28084;
const _metersPerSecondToKnots = 1.943844;

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.verticalPathProfile,
    required this.onVerticalPathProfileChanged,
    required this.onOpenPoints,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VerticalPathProfile verticalPathProfile;
  final ValueChanged<VerticalPathProfile> onVerticalPathProfileChanged;
  final VoidCallback onOpenPoints;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _requestingPermission = false;
  bool _loadingKeyboardMode = true;
  PointSearchKeyboardMode _keyboardMode = PointSearchKeyboardMode.large;
  String? _keyboardModeError;

  @override
  void initState() {
    super.initState();
    GpsPositionService.instance.addListener(_onGpsChanged);
    unawaited(_loadKeyboardMode());
    unawaited(GpsPositionService.instance.refreshSatelliteStatus());
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
                            : '${(position.speed * _metersPerSecondToKnots).toStringAsFixed(1)} kt',
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
          const SizedBox(height: 10),
          Text(
            'DescentSpy is a planning aid. Verify navigation, weather, and aircraft performance using approved sources.',
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
