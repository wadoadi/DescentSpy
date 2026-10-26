import 'dart:math' as math;

enum PointCategory { airfield, town, port, vrp }

class NavigationPoint {
  const NavigationPoint({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.icao = '',
    this.isCustom = false,
    this.details = '',
  });

  final String id;
  final String name;
  final PointCategory category;
  final double latitude;
  final double longitude;
  final String icao;
  final bool isCustom;
  final String details;

  String get categoryLabel => switch (category) {
    PointCategory.airfield => 'Airfield',
    PointCategory.town => 'Town',
    PointCategory.port => 'Port',
    PointCategory.vrp => 'VRP',
  };

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'latitude': latitude,
    'longitude': longitude,
    'icao': icao,
    'isCustom': isCustom,
    'details': details,
  };

  factory NavigationPoint.fromJson(Map<String, dynamic> json) {
    final categoryName = json['category'] as String;
    return NavigationPoint(
      id: json['id'] as String,
      name: json['name'] as String,
      category: PointCategory.values.firstWhere(
        (category) => category.name == categoryName,
      ),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      icao: json['icao'] as String? ?? '',
      isCustom: json['isCustom'] as bool? ?? false,
      details: json['details'] as String? ?? '',
    );
  }
}

NavigationPoint parseUKPostcodePoint(
  String requestedPostcode,
  Map<String, dynamic> result,
) {
  final latitude = result['latitude'];
  final longitude = result['longitude'];
  final postcode = result['postcode'];
  if (latitude is! num ||
      longitude is! num ||
      postcode is! String ||
      !latitude.toDouble().isFinite ||
      !longitude.toDouble().isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    throw const FormatException(
      'Postcode lookup returned invalid coordinates.',
    );
  }
  final normalizedPostcode = postcode.trim().toUpperCase();
  return NavigationPoint(
    id: 'postcode:${normalizedPostcode.replaceAll(' ', '')}',
    name: normalizedPostcode,
    category: PointCategory.town,
    latitude: latitude.toDouble(),
    longitude: longitude.toDouble(),
    details:
        'UK postcode${requestedPostcode == normalizedPostcode ? '' : ' · $requestedPostcode'}',
  );
}

List<NavigationPoint> deduplicateNavigationPoints(
  Iterable<NavigationPoint> points,
) {
  final unique = <NavigationPoint>[];
  final seenIcaos = <String>{};
  final seenCoordinates = <String>{};
  String coordinateKey(double value) {
    if (!value.isFinite) return value.toString();
    final rounded = (value * 100000).round() / 100000;
    return (rounded == 0 ? 0 : rounded).toStringAsFixed(5);
  }

  for (final point in points) {
    final icao = point.category == PointCategory.airfield
        ? point.icao.trim().toUpperCase()
        : '';
    final coordinates =
        '${coordinateKey(point.latitude)}:${coordinateKey(point.longitude)}';
    if ((icao.isNotEmpty && seenIcaos.contains(icao)) ||
        seenCoordinates.contains(coordinates)) {
      continue;
    }
    unique.add(point);
    if (icao.isNotEmpty) seenIcaos.add(icao);
    seenCoordinates.add(coordinates);
  }
  return unique;
}

List<NavigationPoint> sortNavigationPoints({
  required Iterable<NavigationPoint> points,
  String query = '',
  double? fromLatitude,
  double? fromLongitude,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  int matchRank(NavigationPoint point) {
    if (normalizedQuery.isEmpty) return 0;
    final name = point.name.toLowerCase();
    if (name.startsWith(normalizedQuery)) return 0;
    if (name.contains(normalizedQuery)) return 1;
    if (point.icao.toLowerCase().startsWith(normalizedQuery)) return 2;
    return 3;
  }

  final sorted = points.toList();
  sorted.sort((a, b) {
    final byMatch = matchRank(a).compareTo(matchRank(b));
    if (byMatch != 0) return byMatch;
    if (fromLatitude != null && fromLongitude != null) {
      final aDistance = calculatePointRange(
        fromLatitude: fromLatitude,
        fromLongitude: fromLongitude,
        toLatitude: a.latitude,
        toLongitude: a.longitude,
      ).distanceNm;
      final bDistance = calculatePointRange(
        fromLatitude: fromLatitude,
        fromLongitude: fromLongitude,
        toLatitude: b.latitude,
        toLongitude: b.longitude,
      ).distanceNm;
      final byDistance = aDistance.compareTo(bDistance);
      if (byDistance != 0) return byDistance;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

List<NavigationPoint> searchNavigationPoints({
  required Iterable<NavigationPoint> points,
  required String query,
  double? fromLatitude,
  double? fromLongitude,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final matches = points.where((point) {
    return normalizedQuery.isEmpty ||
        point.name.toLowerCase().contains(normalizedQuery) ||
        point.icao.toLowerCase().contains(normalizedQuery) ||
        point.details.toLowerCase().contains(normalizedQuery);
  });
  if (normalizedQuery.isEmpty) return matches.toList();
  return sortNavigationPoints(
    points: matches,
    query: normalizedQuery,
    fromLatitude: fromLatitude,
    fromLongitude: fromLongitude,
  );
}

class PointRange {
  const PointRange({required this.distanceNm, required this.bearingDeg});

  final double distanceNm;
  final double bearingDeg;
}

class PointSelection {
  const PointSelection({required this.point, required this.range});

  final NavigationPoint point;
  final PointRange range;
}

PointRange calculatePointRange({
  required double fromLatitude,
  required double fromLongitude,
  required double toLatitude,
  required double toLongitude,
}) {
  final lat1 = _radians(fromLatitude);
  final lat2 = _radians(toLatitude);
  final deltaLat = lat2 - lat1;
  final deltaLon = _radians(toLongitude - fromLongitude);
  final sinHalfLat = math.sin(deltaLat / 2);
  final sinHalfLon = math.sin(deltaLon / 2);
  final haversine =
      sinHalfLat * sinHalfLat +
      math.cos(lat1) * math.cos(lat2) * sinHalfLon * sinHalfLon;
  final centralAngle =
      2 *
      math.atan2(
        math.sqrt(haversine.clamp(0, 1)),
        math.sqrt(1 - haversine.clamp(0, 1)),
      );
  final distanceNm = 3440.065 * centralAngle;

  final y = math.sin(deltaLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
  final bearing = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  return PointRange(distanceNm: distanceNm, bearingDeg: bearing);
}

double _radians(double degrees) => degrees * math.pi / 180;
