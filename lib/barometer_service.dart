import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gps_position_service.dart';

const verticalSpeedBarometerPreferenceKey = 'vertical_speed_barometer';

/// Pressure altitude in metres from station pressure in hPa (ISA model).
/// Use differences between readings: the absolute value ignores the local QNH.
double pressureAltitudeMeters(double pressureHpa) {
  return 44330 * (1 - math.pow(pressureHpa / 1013.25, 1 / 5.255).toDouble());
}

/// Wall-clock time of a sensor sample. [sampleElapsedMs] and [nowElapsedMs]
/// are on the device's since-boot clock; [now] is the wall clock at
/// [nowElapsedMs]. Works for late-delivered samples too.
DateTime sensorSampleTime({
  required DateTime now,
  required int nowElapsedMs,
  required int sampleElapsedMs,
}) {
  return now.subtract(Duration(milliseconds: nowElapsedMs - sampleElapsedMs));
}

class BarometerReading {
  const BarometerReading({required this.time, required this.pressureHpa});

  final DateTime time;
  final double pressureHpa;

  double get altitudeMeters => pressureAltitudeMeters(pressureHpa);
}

/// Shared barometer access. The pressure stream runs only while the
/// vertical-speed option is on and the device reports a pressure sensor.
class BarometerService {
  BarometerService._();

  static final BarometerService instance = BarometerService._();
  static const _methodChannel = MethodChannel(
    'com.example.descent_spy/barometer',
  );
  static const _pressureChannel = EventChannel(
    'com.example.descent_spy/barometer_pressure',
  );

  static const _recentLimit = 500;
  static const _maxRetries = 5;
  static const _retryDelay = Duration(seconds: 2);

  final _readings = StreamController<BarometerReading>.broadcast();
  final List<BarometerReading> _recent = [];
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  bool? _available;
  bool _useForVerticalSpeed = false;
  int _sampleCount = 0;
  int _retries = 0;
  double? _referenceAltitudeMeters;
  String? _lastError;
  DateTime? _lastErrorAt;

  /// Whether the pressure stream is currently listening.
  bool get streaming => _subscription != null;

  /// The most recent stream error, or null if none this session.
  String? get lastError => _lastError;

  /// When [lastError] happened.
  DateTime? get lastErrorAt => _lastErrorAt;

  /// Restart attempts since the last reading.
  int get retryCount => _retries;

  /// Whether the device has a pressure sensor. Null until checked.
  bool? get available => _available;

  bool get useForVerticalSpeed => _useForVerticalSpeed;

  Stream<BarometerReading> get readings => _readings.stream;

  /// Debug: readings received since the app started, including ones dropped
  /// from [recentReadings].
  int get sampleCount => _sampleCount;

  /// Debug: the most recent readings, oldest first (up to 500).
  List<BarometerReading> get recentReadings => List.unmodifiable(_recent);

  /// Debug: altitude change from the first reading of this session, in metres.
  /// Only differences are meaningful; the absolute value ignores the local QNH.
  double? relativeAltitudeMeters(BarometerReading reading) {
    final reference = _referenceAltitudeMeters;
    return reference == null ? null : reading.altitudeMeters - reference;
  }

  /// Asks the platform once whether a pressure sensor exists.
  /// Returns false when the platform channel is missing.
  Future<bool> checkAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    var available = false;
    try {
      available =
          await _methodChannel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      available = false;
    } on PlatformException {
      available = false;
    }
    _available = available;
    return available;
  }

  /// Loads the saved choice and starts the pressure stream if it is on.
  Future<void> restorePreference() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _useForVerticalSpeed =
          preferences.getBool(verticalSpeedBarometerPreferenceKey) ?? false;
    } catch (_) {
      _useForVerticalSpeed = false;
    }
    if (_useForVerticalSpeed) await _startIfAvailable();
  }

  Future<void> setUseForVerticalSpeed(bool value) async {
    _useForVerticalSpeed = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(verticalSpeedBarometerPreferenceKey, value);
    _retryTimer?.cancel();
    _retryTimer = null;
    _retries = 0;
    if (value) {
      await _startIfAvailable();
    } else {
      _stop();
    }
  }

  Future<void> _startIfAvailable() async {
    if (_subscription != null) return;
    if (!await checkAvailable()) return;
    if (_subscription != null) return;
    _subscription = _pressureChannel.receiveBroadcastStream().listen(
      (event) {
        final map = event as Map<dynamic, dynamic>;
        final now = DateTime.now();
        final sampleElapsedMs = (map['elapsedMs'] as num?)?.toInt();
        final nowElapsedMs = (map['nowElapsedMs'] as num?)?.toInt();
        _recordReading(
          BarometerReading(
            time: sampleElapsedMs == null || nowElapsedMs == null
                ? now
                : sensorSampleTime(
                    now: now,
                    nowElapsedMs: nowElapsedMs,
                    sampleElapsedMs: sampleElapsedMs,
                  ),
            pressureHpa: (map['hPa'] as num).toDouble(),
          ),
        );
      },
      onError: (Object error) {
        _reportError('$error');
        _stop();
        _scheduleRetry();
      },
      onDone: () {
        _stop();
        _scheduleRetry();
      },
    );
  }

  void _reportError(String message) {
    _lastError = message;
    _lastErrorAt = DateTime.now();
    GpsPositionService.instance.logDebugEvent('barometer error: $message');
  }

  /// Restarts the stream after [_retryDelay], at most [_maxRetries] times in a
  /// row. A reading resets the count.
  void _scheduleRetry() {
    if (!_useForVerticalSpeed || _retryTimer != null) return;
    if (_retries >= _maxRetries) {
      GpsPositionService.instance.logDebugEvent(
        'barometer stopped after $_maxRetries retries',
      );
      return;
    }
    _retries++;
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      if (_useForVerticalSpeed) unawaited(_startIfAvailable());
    });
  }

  void _recordReading(BarometerReading reading) {
    _retries = 0;
    _sampleCount++;
    _referenceAltitudeMeters ??= reading.altitudeMeters;
    _recent.add(reading);
    if (_recent.length > _recentLimit) _recent.removeAt(0);
    _readings.add(reading);
  }

  void _stop() {
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
  }
}
