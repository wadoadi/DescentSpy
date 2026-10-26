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

  Position? get position => _position;
  GpsSatelliteStatus? get satelliteStatus => _satelliteStatus;
  String? get satelliteError => _satelliteError;
  String? get errorMessage => _errorMessage;

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
                  _setError('GPS error: $error');
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
    _position = position;
    notifyListeners();
  }

  void _setError(String? message) {
    if (_errorMessage == message) return;
    _errorMessage = message;
    notifyListeners();
  }
}
