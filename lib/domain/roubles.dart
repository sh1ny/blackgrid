/// Formats a rouble [value] for display, or "Unavailable" when it is null.
///
/// Whole amounts show no decimals; others show two.
String rub(num? value) => value == null
    ? 'Unavailable'
    : '₽${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
