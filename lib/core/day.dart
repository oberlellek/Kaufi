/// A calendar day without time or time zone.
///
/// Stored as the number of days since 1970-01-01, which makes arithmetic and
/// comparisons trivial and keeps persisted data independent of time zones.
class Day implements Comparable<Day> {
  const Day(this.epochDay);

  factory Day.fromDate(DateTime d) =>
      Day(DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay);

  factory Day.today([DateTime? now]) => Day.fromDate(now ?? DateTime.now());

  /// Parses `YYYY-MM-DD`. Returns null for anything else.
  static Day? tryParse(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^\s*(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final date = DateTime.utc(y, mo, d);
    // Reject dates like 2026-02-31 that DateTime silently rolls over.
    if (date.month != mo) return null;
    return Day.fromDate(date);
  }

  final int epochDay;

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(
      epochDay * Duration.millisecondsPerDay,
      isUtc: true);

  /// 1 = Monday ... 7 = Sunday.
  int get weekday => date.weekday;

  String get iso {
    final d = date;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Day operator +(int days) => Day(epochDay + days);
  Day operator -(int days) => Day(epochDay - days);
  int difference(Day other) => epochDay - other.epochDay;

  bool operator <(Day o) => epochDay < o.epochDay;
  bool operator <=(Day o) => epochDay <= o.epochDay;
  bool operator >(Day o) => epochDay > o.epochDay;
  bool operator >=(Day o) => epochDay >= o.epochDay;

  @override
  int compareTo(Day other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) => other is Day && other.epochDay == epochDay;

  @override
  int get hashCode => epochDay.hashCode;

  @override
  String toString() => iso;
}

const _weekdaysShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _weekdaysLong = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

String formatDayShort(Day day) {
  final d = day.date;
  return '${_weekdaysShort[d.weekday - 1]} ${d.day}.${d.month}.';
}

/// "Heute", "Morgen" or e.g. "Donnerstag, 5.11.".
String formatDayRelative(Day day, Day today) {
  final diff = day.difference(today);
  final d = day.date;
  final base = '${_weekdaysLong[d.weekday - 1]}, ${d.day}.${d.month}.';
  if (diff == 0) return 'Heute · $base';
  if (diff == 1) return 'Morgen · $base';
  if (diff == -1) return 'Gestern · $base';
  return base;
}
