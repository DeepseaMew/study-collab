class DateFormatter {
  DateFormatter._();

  static String relativeDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return '${_pad(date.day)}/${_pad(date.month)}/${date.year}';
  }

  static String time(DateTime date) =>
      '${_pad(date.hour)}:${_pad(date.minute)}';

  static String timeRange(DateTime start, DateTime end) =>
      '${time(start)} - ${time(end)}';

  static String dayMonth(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  static String relative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? "minute" : "minutes"} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? "hour" : "hours"} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return dayMonth(date);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}