import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'barometer_service.dart';
import 'gps_position_service.dart';

/// Diagnostics page: records GPS fixes and shows lifecycle and barometer data.
/// Reachable from Settings in all builds, for on-device testing.
class GpsDebugPage extends StatefulWidget {
  const GpsDebugPage({super.key});

  @override
  State<GpsDebugPage> createState() => _GpsDebugPageState();
}

class _GpsDebugPageState extends State<GpsDebugPage> {
  static const _listLimit = 50;
  static const _recordHeader =
      'arrival\tfix_timestamp\tage_ms\tlatitude\tlongitude\taltitude_m'
      '\thas_altitude\tspeed_mps\thorizontal_accuracy_m';

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    GpsPositionService.instance.addListener(_refresh);
    unawaited(
      BarometerService.instance.checkAvailable().then((_) => _refresh()),
    );
    // Refreshes the age figures even when no new fix arrives.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    GpsPositionService.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _copyRecordsAndEvents() async {
    final service = GpsPositionService.instance;
    final records = service.debugRecords;
    final events = service.debugEvents;
    final buffer = StringBuffer('$_recordHeader\n');
    for (final record in records) {
      buffer.writeln(
        [
          record.arrival.toIso8601String(),
          record.fixTimestamp.toIso8601String(),
          record.ageMs,
          record.latitude,
          record.longitude,
          record.altitudeMeters,
          record.hasAltitude,
          record.speedMetersPerSecond,
          record.horizontalAccuracyMeters,
        ].join('\t'),
      );
    }
    buffer
      ..writeln()
      ..writeln('events');
    for (final event in events) {
      buffer.writeln(
        [
          event.time.toIso8601String(),
          event.message,
          event.streamActive ? 'stream on' : 'stream off',
        ].join('\t'),
      );
    }
    final barometer = BarometerService.instance;
    final baroReadings = _windowedBaroReadings();
    if (baroReadings.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('baro');
      for (final reading in baroReadings) {
        buffer.writeln(
          [
            reading.time.toIso8601String(),
            reading.pressureHpa,
            barometer.relativeAltitudeMeters(reading) ?? '',
          ].join('\t'),
        );
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied ${records.length} records and ${events.length} events.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = GpsPositionService.instance;
    final records = service.debugRecords;
    final events = service.debugEvents;
    final lastFix = service.position?.timestamp;
    final lastArrival = service.debugLastArrival;
    final ageNowMs = lastFix == null
        ? null
        : DateTime.now().difference(lastFix).inMilliseconds;
    final barometer = BarometerService.instance;
    final baroReadings = _windowedBaroReadings();
    final latestBaro = baroReadings.isEmpty ? null : baroReadings.last;
    final baroRelativeM = latestBaro == null
        ? null
        : barometer.relativeAltitudeMeters(latestBaro);
    final baroSinceMs = latestBaro == null
        ? null
        : DateTime.now().difference(latestBaro.time).inMilliseconds;
    final baroAvailability = switch (barometer.available) {
      null => 'checking',
      true => 'yes',
      false => 'no barometer on this device',
    };
    final recentRecords = records.reversed.take(_listLimit).toList();
    final recentEvents = events.reversed.take(_listLimit).toList();
    final style = TextStyle(
      color: context.appSecondaryText,
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.4,
    );

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text(
          'GPS DEBUG',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: context.appBackground,
        foregroundColor: context.appText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.appPanel,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'recording: ${service.debugRecording ? 'ON' : 'OFF'}'
                  '   records: ${records.length}/500',
                  style: style,
                ),
                Text(
                  'stream: ${service.debugStreamActive ? 'on' : 'off'}'
                  '   fixes received: ${service.debugFixCount}',
                  style: style,
                ),
                Text(
                  'last fix: ${lastFix?.toIso8601String() ?? 'none'}',
                  style: style,
                ),
                Text(
                  'age now: ${ageNowMs == null ? 'none' : '$ageNowMs ms'}',
                  style: style,
                ),
                Text(
                  'last arrival: ${lastArrival == null ? 'none' : _clock(lastArrival)}',
                  style: style,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.appPanel,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('barometer: $baroAvailability', style: style),
                Text(
                  'pressure: ${latestBaro == null ? 'none' : '${latestBaro.pressureHpa.toStringAsFixed(2)} hPa'}',
                  style: style,
                ),
                Text(
                  'relative altitude: ${baroRelativeM == null ? 'none' : '${baroRelativeM.toStringAsFixed(1)} m'}',
                  style: style,
                ),
                Text(
                  'samples in recording: ${baroReadings.length}',
                  style: style,
                ),
                Text(
                  'last sample: ${baroSinceMs == null ? 'none' : '$baroSinceMs ms ago'}',
                  style: style,
                ),
                if (barometer.available == true && barometer.sampleCount == 0)
                  Text(
                    'Turn on USE BAROMETER FOR VERTICAL SPEED in Settings to sample.',
                    style: style,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: service.debugRecording
                        ? null
                        : service.startDebugRecording,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text(
                      'START RECORDING',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: service.debugRecording
                        ? service.stopDebugRecording
                        : null,
                    icon: const Icon(Icons.stop),
                    label: const Text(
                      'STOP RECORDING',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: records.isEmpty && events.isEmpty
                        ? null
                        : _copyRecordsAndEvents,
                    icon: const Icon(Icons.copy),
                    label: const Text(
                      'COPY ALL',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: service.debugRecording
                        ? null
                        : service.clearDebugRecords,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text(
                      'CLEAR',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'LAST $_listLimit RECORDS (NEWEST FIRST)',
            style: TextStyle(
              color: context.appAccent,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          if (recentRecords.isEmpty)
            Text('No records. Press START RECORDING.', style: style),
          for (var i = 0; i < recentRecords.length; i++)
            Text(_recordLine(records, records.length - 1 - i), style: style),
          const SizedBox(height: 18),
          Text(
            'LAST $_listLimit EVENTS (NEWEST FIRST)',
            style: TextStyle(
              color: context.appAccent,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          if (recentEvents.isEmpty) Text('No events yet.', style: style),
          for (final event in recentEvents)
            Text(
              '${_clock(event.time)} ${event.message} '
              '(${event.streamActive ? 'stream on' : 'stream off'})',
              style: style,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Barometer readings inside the recording window. The window runs from the
  /// first recording start to the last recording stop, or to now while recording.
  List<BarometerReading> _windowedBaroReadings() {
    final service = GpsPositionService.instance;
    final start = service.debugRecordingWindowStart;
    if (start == null) return const [];
    final end = service.debugRecordingWindowEnd ?? DateTime.now();
    return BarometerService.instance.recentReadings
        .where(
          (reading) =>
              !reading.time.isBefore(start) && !reading.time.isAfter(end),
        )
        .toList();
  }

  /// One record line; [index] points into [records], oldest first.
  String _recordLine(List<GpsDebugFix> records, int index) {
    final record = records[index];
    final gapMs = index == 0
        ? null
        : record.arrival.difference(records[index - 1].arrival).inMilliseconds;
    final altitude = record.hasAltitude
        ? '${record.altitudeMeters.toStringAsFixed(0)} m'
        : '-';
    return '${_clock(record.arrival)} age ${record.ageMs} ms '
        'gap ${gapMs ?? '-'} ms  '
        '${record.latitude.toStringAsFixed(5)}, '
        '${record.longitude.toStringAsFixed(5)}  '
        'alt $altitude  '
        'spd ${record.speedMetersPerSecond.toStringAsFixed(1)} m/s  '
        'acc ${record.horizontalAccuracyMeters.toStringAsFixed(0)} m';
  }

  String _clock(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}
