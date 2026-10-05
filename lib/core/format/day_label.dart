/// "Good morning" from the phone’s clock.
String greetingLabel([DateTime? date]) {
  final hour = (date ?? DateTime.now()).hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// "Friday, October 2" from the phone’s clock.
String dayLabel([DateTime? date]) {
  final day = date ?? DateTime.now();
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[day.weekday - 1]}, ${months[day.month - 1]} ${day.day}';
}

/// "7:58" from the phone’s clock.
String clockLabel([DateTime? date]) {
  final day = date ?? DateTime.now();
  final hour = day.hour % 12 == 0 ? 12 : day.hour % 12;
  final minute = day.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
