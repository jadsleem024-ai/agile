/// Weight display helpers.
///
/// Weights arrive as int, double, String or null depending on whether they came
/// from a set template, a trainee's typed entry, or nothing at all. Rendering
/// them with plain `toString()` produced the two bugs these fix: a bare `0.0`
/// wherever no weight was recorded, and trailing `.0` on every whole number.
library;

/// Parses whatever the DB or a text field handed us into a number, or null when
/// the value is absent/blank/unparseable. Zero is preserved — it is meaningful
/// for bodyweight movements.
double? parseWeight(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return double.tryParse(text.replaceAll(',', '.'));
}

/// The number alone, with no trailing zeros: 20.0 -> "20", 22.50 -> "22.5".
/// Returns '' when there is no value to show.
String formatWeight(dynamic value) {
  final w = parseWeight(value);
  if (w == null) return '';
  if (w == w.roundToDouble()) return w.toInt().toString();
  // Two decimals is as fine as any gym plate gets; drop the padding zeros.
  return w
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Weight for a label, with the unit. Zero and null both read as "Bodyweight"
/// rather than "0.0 kg".
String weightLabel(dynamic value, {String emptyLabel = 'Bodyweight'}) {
  final w = parseWeight(value);
  if (w == null || w == 0) return emptyLabel;
  return '${formatWeight(w)} kg';
}

/// Short form for dense rows: "22.5kg", or "BW" when there is no load.
String weightChip(dynamic value) {
  final w = parseWeight(value);
  if (w == null || w == 0) return 'BW';
  return '${formatWeight(w)}kg';
}

/// mm:ss for a duration in seconds.
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// One set of a plan, e.g. "22.5kg × 10" or "BW × 45s".
String setLine(dynamic weight, {int? reps, int? duration, required bool isTime}) {
  final load = weightChip(weight);
  if (isTime) return '$load × ${duration ?? 0}s';
  return '$load × ${reps ?? 0}';
}
