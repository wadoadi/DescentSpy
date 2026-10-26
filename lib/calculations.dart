import 'dart:math' as math;

const double _feetPerNmAtThreeDegrees = 318;
const double metersToFeet = 3.28084;
const double metersPerSecondToKnots = 1.943844;

enum VerticalPathProfile {
  threeDegree(degrees: 3, feetPerNm: 318),
  fiveDegree(degrees: 5, feetPerNm: 531);

  const VerticalPathProfile({required this.degrees, required this.feetPerNm});

  final int degrees;
  final double feetPerNm;
}

const verticalPathProfilePreferenceKey = 'descent_vertical_path_profile';

String? gpsGroundSpeedEntry({
  required double speedMetersPerSecond,
  required bool manuallyOverridden,
}) {
  if (manuallyOverridden ||
      !speedMetersPerSecond.isFinite ||
      speedMetersPerSecond < 0) {
    return null;
  }
  if (speedMetersPerSecond <= 0.5) return '0';
  final speedKt = speedMetersPerSecond * metersPerSecondToKnots;
  if (speedKt >= 1000) return null;
  return speedKt.round().toString();
}

String? gpsAltitudeEntry({
  required double altitudeMeters,
  required bool manuallyOverridden,
}) {
  if (manuallyOverridden || !altitudeMeters.isFinite) return null;
  final altitudeFt = altitudeMeters * metersToFeet;
  if (altitudeFt < 0 || altitudeFt > 60000) return null;
  return altitudeFt.round().toString();
}

class AltitudeSample {
  const AltitudeSample({required this.timestamp, required this.altitudeFt});

  final DateTime timestamp;
  final double altitudeFt;
}

double? estimateVerticalSpeedFpm(List<AltitudeSample> samples) {
  if (samples.length < 3) return null;

  final ordered = [...samples]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final first = ordered.first.timestamp;
  final last = ordered.last.timestamp;
  final spanSeconds = last.difference(first).inMilliseconds / 1000;
  if (spanSeconds < 8) return null;

  final elapsedSeconds = ordered
      .map((sample) => sample.timestamp.difference(first).inMilliseconds / 1000)
      .toList();
  final meanTime =
      elapsedSeconds.reduce((sum, value) => sum + value) /
      elapsedSeconds.length;
  final meanAltitude =
      ordered
          .map((sample) => sample.altitudeFt)
          .reduce((sum, value) => sum + value) /
      ordered.length;
  var covariance = 0.0;
  var variance = 0.0;
  for (var index = 0; index < ordered.length; index++) {
    final timeOffset = elapsedSeconds[index] - meanTime;
    covariance += timeOffset * (ordered[index].altitudeFt - meanAltitude);
    variance += timeOffset * timeOffset;
  }
  if (variance == 0) return null;
  return covariance / variance * 60;
}

double? calculateLiveRequiredRateFpm({
  required double startAltitudeFt,
  required double currentAltitudeFt,
  required double targetAltitudeFt,
  required double remainingTimeMinutes,
}) {
  final isClimb = targetAltitudeFt > startAltitudeFt;
  if ((isClimb && currentAltitudeFt >= targetAltitudeFt) ||
      (!isClimb && currentAltitudeFt <= targetAltitudeFt)) {
    return 0;
  }
  final altitudeToGainFt = targetAltitudeFt - currentAltitudeFt;
  if (remainingTimeMinutes <= 0) return null;
  return altitudeToGainFt / remainingTimeMinutes;
}

double? calculateTimeForDistanceMinutes({
  required double distanceNm,
  required double groundspeedKt,
}) {
  if (distanceNm < 0 || groundspeedKt <= 0) return null;
  return distanceNm / groundspeedKt * 60;
}

class AltitudePlan {
  const AltitudePlan({
    required this.rateFpm,
    required this.timeMinutes,
    required this.distanceNm,
    required this.profileDegrees,
    required this.isClimb,
  });

  final double rateFpm;
  final double timeMinutes;
  final double distanceNm;
  final int? profileDegrees;
  final bool isClimb;

  bool get usesProfile => profileDegrees != null;
}

AltitudePlan calculateAltitudePlan({
  required double startAltitudeFt,
  required double targetAltitudeFt,
  required double groundspeedKt,
  double? distanceNm,
  double? timeMinutes,
  VerticalPathProfile profile = VerticalPathProfile.threeDegree,
}) {
  if (!startAltitudeFt.isFinite ||
      !targetAltitudeFt.isFinite ||
      startAltitudeFt < 0 ||
      targetAltitudeFt < 0 ||
      startAltitudeFt > 60000 ||
      targetAltitudeFt > 60000) {
    throw ArgumentError('Altitudes must be between 0 and 60000 ft.');
  }
  if (startAltitudeFt == targetAltitudeFt) {
    throw ArgumentError('Current and target altitude must be different.');
  }
  if (!groundspeedKt.isFinite || groundspeedKt < 1 || groundspeedKt > 999) {
    throw ArgumentError('Ground speed must be between 1 and 999 kt.');
  }
  if (distanceNm != null &&
      (!distanceNm.isFinite || distanceNm <= 0 || distanceNm > 999.9)) {
    throw ArgumentError('Distance must be between 0 and 999.9 NM.');
  }
  if (timeMinutes != null &&
      (!timeMinutes.isFinite || timeMinutes <= 0 || timeMinutes > 9999)) {
    throw ArgumentError('Time must be between 0 and 9999 minutes.');
  }
  if (distanceNm != null && timeMinutes != null) {
    throw ArgumentError('Enter either distance or time, not both.');
  }

  final altitudeChangeFt = (startAltitudeFt - targetAltitudeFt).abs();
  final isClimb = targetAltitudeFt > startAltitudeFt;
  if (distanceNm != null) {
    if (distanceNm <= 0) {
      throw ArgumentError('Distance must be greater than zero.');
    }
    final time = distanceNm / groundspeedKt * 60;
    return AltitudePlan(
      rateFpm: altitudeChangeFt / time,
      timeMinutes: time,
      distanceNm: distanceNm,
      profileDegrees: null,
      isClimb: isClimb,
    );
  }
  if (timeMinutes != null) {
    if (timeMinutes <= 0) {
      throw ArgumentError('Time must be greater than zero.');
    }
    return AltitudePlan(
      rateFpm: altitudeChangeFt / timeMinutes,
      timeMinutes: timeMinutes,
      distanceNm: groundspeedKt * timeMinutes / 60,
      profileDegrees: null,
      isClimb: isClimb,
    );
  }

  final feetPerNm = profile == VerticalPathProfile.threeDegree
      ? _feetPerNmAtThreeDegrees
      : profile.feetPerNm;
  final profileDistance = altitudeChangeFt / feetPerNm;
  final profileTime = profileDistance / groundspeedKt * 60;
  return AltitudePlan(
    rateFpm: altitudeChangeFt / profileTime,
    timeMinutes: profileTime,
    distanceNm: profileDistance,
    profileDegrees: profile.degrees,
    isClimb: isClimb,
  );
}

class RunwayWind {
  const RunwayWind({required this.headwindKt, required this.crosswindKt});

  final double headwindKt;
  final double crosswindKt;

  double get tailwindKt => math.max(0, -headwindKt);
}

class WindAssessment {
  const WindAssessment({
    required this.runwayNumber,
    required this.reciprocalRunwayNumber,
    required this.intendedRunway,
    required this.reciprocalRunway,
    required this.recommendReciprocal,
  });

  final int runwayNumber;
  final int reciprocalRunwayNumber;
  final RunwayWind intendedRunway;
  final RunwayWind reciprocalRunway;
  final bool recommendReciprocal;

  String get runwayLabel => runwayNumber.toString().padLeft(2, '0');
  String get reciprocalLabel =>
      reciprocalRunwayNumber.toString().padLeft(2, '0');
}

WindAssessment calculateWind({
  required double windDirectionDeg,
  required double windSpeedKt,
  required int runwayNumber,
}) {
  if (!windDirectionDeg.isFinite ||
      windDirectionDeg < 0 ||
      windDirectionDeg > 360) {
    throw ArgumentError('Wind direction must be between 0 and 360 degrees.');
  }
  if (!windSpeedKt.isFinite || windSpeedKt < 0 || windSpeedKt > 999) {
    throw ArgumentError('Wind speed must be between 0 and 999 kt.');
  }
  if (runwayNumber < 1 || runwayNumber > 36) {
    throw ArgumentError('Runway number must be between 01 and 36.');
  }

  final reciprocalNumber = ((runwayNumber + 17) % 36) + 1;
  final runwayHeading = runwayNumber * 10.0;
  final reciprocalHeading = reciprocalNumber * 10.0;
  final intended = _components(windDirectionDeg, windSpeedKt, runwayHeading);
  final reciprocal = _components(
    windDirectionDeg,
    windSpeedKt,
    reciprocalHeading,
  );
  return WindAssessment(
    runwayNumber: runwayNumber,
    reciprocalRunwayNumber: reciprocalNumber,
    intendedRunway: intended,
    reciprocalRunway: reciprocal,
    recommendReciprocal:
        reciprocal.headwindKt >= -0.5 &&
        (reciprocal.crosswindKt + 0.1 < intended.crosswindKt ||
            intended.tailwindKt > 0.5),
  );
}

RunwayWind _components(
  double windDirection,
  double windSpeed,
  double runwayHeading,
) {
  final angle = (windDirection - runwayHeading) * math.pi / 180;
  return RunwayWind(
    headwindKt: windSpeed * math.cos(angle),
    crosswindKt: windSpeed * math.sin(angle).abs(),
  );
}
