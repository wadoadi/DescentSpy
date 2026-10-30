import 'package:flutter_test/flutter_test.dart';

import 'package:descent_spy/calculations.dart';
import 'package:descent_spy/speed_unit.dart';

void main() {
  group('SpeedUnit', () {
    test('converts knots using 1 kt = 1.852 km/h = 1.15078 mph', () {
      expect(SpeedUnit.knots.fromKnots(10), 10);
      expect(SpeedUnit.kilometresPerHour.fromKnots(10), closeTo(18.52, 1e-9));
      expect(SpeedUnit.milesPerHour.fromKnots(10), closeTo(11.5078, 1e-9));
    });

    test('converts back to knots', () {
      expect(SpeedUnit.kilometresPerHour.toKnots(18.52), closeTo(10, 1e-9));
      expect(SpeedUnit.milesPerHour.toKnots(11.5078), closeTo(10, 1e-9));
    });

    test('falls back to knots for unknown or missing names', () {
      expect(SpeedUnit.fromName(null), SpeedUnit.knots);
      expect(SpeedUnit.fromName('furlongs'), SpeedUnit.knots);
      expect(SpeedUnit.fromName('milesPerHour'), SpeedUnit.milesPerHour);
    });

    test('field text converts between knots storage and the chosen unit', () {
      expect(speedTextFromKnots('100', SpeedUnit.kilometresPerHour), '185.2');
      expect(speedTextFromKnots('100', SpeedUnit.knots), '100');
      expect(speedTextFromKnots('', SpeedUnit.milesPerHour), '');
      expect(speedTextToKnots('185.2', SpeedUnit.kilometresPerHour),
          closeTo(100, 1e-6));
      expect(speedTextToKnots('abc', SpeedUnit.knots), 'abc');
    });

    test('GPS ground speed entry is shown in the chosen unit', () {
      // 10 m/s is 19.43844 kt, which is exactly 36 km/h.
      expect(
        gpsGroundSpeedEntry(
          speedMetersPerSecond: 10,
          manuallyOverridden: false,
          unit: SpeedUnit.kilometresPerHour,
        ),
        '36',
      );
      expect(
        gpsGroundSpeedEntry(
          speedMetersPerSecond: 10,
          manuallyOverridden: false,
          unit: SpeedUnit.milesPerHour,
        ),
        '22',
      );
      expect(
        gpsGroundSpeedEntry(speedMetersPerSecond: 10, manuallyOverridden: false),
        '19',
      );
    });
  });
}
