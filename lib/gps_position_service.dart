import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

enum GpsFixLevel { none, twoDimensional, threeDimensional }

class GpsSatelliteStatus {
  const GpsSatelliteStatus({
    required this.visibleSatellites,
    required this.usedSatellites,
    required this.has2dFix,
    required this.has3dFix,
  });

  final int visibleSatellites;
  final int usedSatellites;
  final bool has2dFix;
  final bool has3dFix;

  GpsFixLevel get fixLevel => has3dFix
      ? GpsFixLevel.threeDimensional
      : has2dFix
      ? GpsFixLevel.twoDimensional
      : GpsFixLevel.none;
}

/// Debug-only record of one GPS fix and when it arrived in the app.
class GpsDebugFix {
  const GpsDebugFix({
    required this.arrival,
    required this.fixTimestamp,
    required this.ageMs,
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.hasAltitude,
    required this.speedMetersPerSecond,
    required this.horizontalAccuracyMeters,
  });

  final DateTime arrival;
  final DateTime fixTimestamp;
  final int ageMs;
  final double latitude;
  final double longitude;
  final double altitudeMeters;
  final bool hasAltitude;
  final double speedMetersPerSecond;
  final double horizontalAccuracyMeters;
}

/// Debug-only lifecycle or GPS control event.
class GpsDebugEvent {
  const GpsDebugEvent({
    required this.time,
    required this.message,
    required this.streamActive,
  });

  final DateTime time;
  final String message;
  final bool streamActive;
}

class GpsPositionService extends ChangeNotifier {
  GpsPositionService._();

  static final GpsPositionService instance = GpsPositionService._();
  static const _satelliteChannel = MethodChannel(
    'com.example.descent_spy/gps_status',
  );

  Position? _position;
  GpsSatelliteStatus? _satelliteStatus;
  String? _satelliteError;
  String? _errorMessage;
  StreamSubscription<Position>? _subscription;
  Timer? _satelliteTimer;
  bool _starting = false;
  bool _shouldRun = false;
  bool _refreshingSatelliteStatus = false;
  int _debugFixCount = 0;
  DateTime? _debugLastArrival;
  final List<int> _debugGapsMs = [];
  bool _debugRecording = false;
  final List<GpsDebugFix> _debugRecords = [];
  final List<GpsDebugEvent> _debugEvents = [];
  DateTime? _debugRecordingWindowStart;
  DateTime? _debugRecordingWindowEnd;

  static const _debugGapHistoryLength = 20;
  static const _debugRecordLimit = 500;
  static const _debugEventLimit = 100;

  Position? get position => _position;
  GpsSatelliteStatus? get satelliteStatus => _satelliteStatus;
  String? get satelliteError => _satelliteError;
  String? get errorMessage => _errorMessage;

  /// Debug-only diagnostics: fixes received since the service was created.
  int get debugFixCount => _debugFixCount;

  /// Debug-only diagnostics: local arrival time of the most recent fix.
  DateTime? get debugLastArrival => _debugLastArrival;

  /// Debug-only diagnostics: gaps in ms between the last fixes (oldest first).
  List<int> get debugRecentGapsMs => List.unmodifiable(_debugGapsMs);

  /// Debug-only: whether the shared position stream is currently listening.
  bool get debugStreamActive => _subscription != null;

  /// Debug-only: whether fixes are being stored as [debugRecords].
  bool get debugRecording => _debugRecording;

  /// Debug-only: stored fixes, oldest first, while recording.
  List<GpsDebugFix> get debugRecords => List.unmodifiable(_debugRecords);

  /// Debug-only: lifecycle and GPS control events, oldest first.
  List<GpsDebugEvent> get debugEvents => List.unmodifiable(_debugEvents);

  /// Start of the first recording since the last clear.
  DateTime? get debugRecordingWindowStart => _debugRecordingWindowStart;

  /// End of the last recording, or null while recording.
  DateTime? get debugRecordingWindowEnd => _debugRecordingWindowEnd;

  void startDebugRecording() {
    if (_debugRecording) return;
    _debugRecordingWindowStart ??= DateTime.now();
    _debugRecordingWindowEnd = null;
    _debugRecording = true;
    logDebugEvent('recording started');
    notifyListeners();
  }

  void stopDebugRecording() {
    if (!_debugRecording) return;
    _debugRecordingWindowEnd = DateTime.now();
    _debugRecording = false;
    logDebugEvent('recording stopped');
    notifyListeners();
  }

  /// Clears stored fixes and events. Does nothing while recording.
  void clearDebugRecords() {
    if (_debugRecording) return;
    _debugRecords.clear();
    _debugEvents.clear();
    _debugRecordingWindowStart = null;
    _debugRecordingWindowEnd = null;
    notifyListeners();
  }

  /// Appends a diagnostic event with the current stream state.
  void logDebugEvent(String message) {
    _debugEvents.add(
      GpsDebugEvent(
        time: DateTime.now(),
        message: message,
        streamActive: _subscription != null,
      ),
    );
    if (_debugEvents.length > _debugEventLimit) _debugEvents.removeAt(0);
  }

  Future<void> refreshSatelliteStatus() async {
    if (_refreshingSatelliteStatus) return;
    _refreshingSatelliteStatus = true;
    if (defaultTargetPlatform != TargetPlatform.android) {
      _satelliteStatus = null;
      _satelliteError = 'Satellite count is not available on this platform.';
      notifyListeners();
      _refreshingSatelliteStatus = false;
      return;
    }
    try {
      final result = await _satelliteChannel.invokeMapMethod<String, Object?>(
        'getSatelliteStatus',
      );
      final visible = result?['visible'] as int?;
      final used = result?['used'] as int?;
      _satelliteStatus = visible == null || visible <= 0 || used == null
          ? null
          : GpsSatelliteStatus(
              visibleSatellites: visible,
              usedSatellites: used,
              has2dFix: result?['is2d'] == true,
              has3dFix: result?['is3d'] == true,
            );
      _satelliteError = _satelliteStatus == null
          ? 'Waiting for satellite status.'
          : null;
      notifyListeners();
    } on MissingPluginException {
      _satelliteStatus = null;
      _satelliteError = 'Satellite count is unavailable on this device.';
      notifyListeners();
    } on PlatformException catch (error) {
      _satelliteStatus = null;
      _satelliteError =
          'Unable to read satellite status: ${error.message ?? error.code}';
      notifyListeners();
    } finally {
      _refreshingSatelliteStatus = false;
    }
  }

  Future<void> start() async {
    _shouldRun = true;
    logDebugEvent('start requested');
    if (_subscription != null) {
      _startSatelliteMonitoring();
      return;
    }
    if (_starting) return;
    _starting = true;
    _setError(null);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setError('Enable device location to use GPS.');
        return;
      }
      if (!_shouldRun) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!_shouldRun) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setError(
          permission == LocationPermission.deniedForever
              ? 'Location permission is blocked. Allow it in app settings.'
              : 'Location permission is needed for GPS.',
        );
        return;
      }
      if (!_shouldRun) return;

      _startSatelliteMonitoring();
      try {
        final lastKnownPosition = await Geolocator.getLastKnownPosition();
        if (lastKnownPosition != null && !lastKnownPosition.isMocked) {
          _setPosition(lastKnownPosition);
        }
      } on MissingPluginException {
        _setError('GPS is not available on this platform.');
      } on PlatformException catch (error) {
        _setError(
          'Unable to read the last GPS fix: ${error.message ?? error.code}',
        );
      }

      _subscription =
          Geolocator.getPositionStream(locationSettings: _locationSettings())
              .listen(
                (position) {
                  if (position.isMocked) return;
                  _setPosition(position);
                  _setError(null);
                },
                onError: (Object error) {
                  _subscription = null;
                  logDebugEvent('stream error: $error');
                  _setError('GPS error: $error');
                },
                onDone: () {
                  _subscription = null;
                  logDebugEvent('stream done');
                },
              );
    } on LocationServiceDisabledException {
      _setError('Enable device location to use GPS.');
    } on PermissionDeniedException {
      _setError('Location permission was denied.');
    } on MissingPluginException {
      _setError('GPS is not available on this platform.');
    } on PlatformException catch (error) {
      _setError('Unable to start GPS: ${error.message ?? error.code}');
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _shouldRun = false;
    _satelliteTimer?.cancel();
    _satelliteTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    logDebugEvent('stop requested');
    _setError('GPS paused while app is in background.');
  }

  void _startSatelliteMonitoring() {
    _satelliteTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refreshSatelliteStatus()),
    );
    unawaited(refreshSatelliteStatus());
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<LocationPermission> requestPermissionAgain() async {
    await stop();
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        permission = await Geolocator.checkPermission();
      } else {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        await start();
      } else {
        _setError(
          permission == LocationPermission.deniedForever
              ? 'Location permission is blocked. Allow it in app settings.'
              : 'Location permission was not granted.',
        );
      }
      return permission;
    } on LocationServiceDisabledException {
      _setError('Enable device location to use GPS.');
      return LocationPermission.denied;
    } on PermissionDeniedException {
      _setError('Location permission was denied.');
      return LocationPermission.denied;
    } on MissingPluginException {
      _setError('GPS is not available on this platform.');
      return LocationPermission.denied;
    } on PlatformException catch (error) {
      _setError(
        'Unable to request location permission: ${error.message ?? error.code}',
      );
      return LocationPermission.denied;
    }
  }

  LocationSettings _locationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  void _setPosition(Position position) {
    final arrived = DateTime.now();
    if (kDebugMode) {
      debugPrint(
        'GPS fix timestamp ${position.timestamp.toIso8601String()} '
        'arrived ${arrived.toIso8601String()} '
        'age ${arrived.difference(position.timestamp).inMilliseconds} ms',
      );
    }
    _recordDebugFix(arrived, position);
    _position = position;
    notifyListeners();
  }

  void _recordDebugFix(DateTime arrived, Position position) {
    _debugFixCount++;
    final previous = _debugLastArrival;
    if (previous != null) {
      _debugGapsMs.add(arrived.difference(previous).inMilliseconds);
      if (_debugGapsMs.length > _debugGapHistoryLength) {
        _debugGapsMs.removeAt(0);
      }
    }
    _debugLastArrival = arrived;
    if (!_debugRecording) return;
    _debugRecords.add(
      GpsDebugFix(
        arrival: arrived,
        fixTimestamp: position.timestamp,
        ageMs: arrived.difference(position.timestamp).inMilliseconds,
        latitude: position.latitude,
        longitude: position.longitude,
        altitudeMeters: position.altitude,
        hasAltitude: position.hasAltitude,
        speedMetersPerSecond: position.speed,
        horizontalAccuracyMeters: position.accuracy,
      ),
    );
    if (_debugRecords.length > _debugRecordLimit) _debugRecords.removeAt(0);
  }

  void _setError(String? message) {
    if (_errorMessage == message) return;
    _errorMessage = message;
    notifyListeners();
  }
}
