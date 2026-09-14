DateTime addMonths(DateTime from, int months) {
  final int year = from.year + ((from.month - 1 + months) ~/ 12);
  final int month = ((from.month - 1 + months) % 12) + 1;

  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final day = from.day > lastDayOfMonth ? lastDayOfMonth : from.day;

  return DateTime(
    year,
    month,
    day,
    from.hour,
    from.minute,
    from.second,
  );
}
