// Speed display unit selected in Settings. Calculations always work in knots;
// this enum converts at the edges (inputs and displayed values).
const speedUnitPreferenceKey = 'speed_unit';

enum SpeedUnit {
  knots(label: 'kt', unitsPerKnot: 1),
  kilometresPerHour(label: 'km/h', unitsPerKnot: 1.852),
  milesPerHour(label: 'mph', unitsPerKnot: 1.15078);

  const SpeedUnit({required this.label, required this.unitsPerKnot});

  final String label;

  /// How many of this unit make one knot (1 kt = 1.852 km/h = 1.15078 mph).
  final double unitsPerKnot;

  double fromKnots(double knots) => knots * unitsPerKnot;

  double toKnots(double value) => value / unitsPerKnot;

  /// Whole numbers stay whole; otherwise one decimal place.
  static String formatValue(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  static SpeedUnit fromName(String? name) => SpeedUnit.values.firstWhere(
    (unit) => unit.name == name,
    orElse: () => SpeedUnit.knots,
  );
}

/// Converts a text field value typed in [unit] to the knots text stored in
/// preferences. Text that is not a number is returned unchanged.
String speedTextToKnots(String text, SpeedUnit unit) {
  final value = double.tryParse(text.trim());
  if (value == null) return text;
  return unit.toKnots(value).toString();
}

/// Converts knots text from preferences to a text field value in [unit].
/// Text that is not a number is returned unchanged.
String speedTextFromKnots(String text, SpeedUnit unit) {
  final knots = double.tryParse(text.trim());
  if (knots == null) return text;
  return SpeedUnit.formatValue(unit.fromKnots(knots));
}
