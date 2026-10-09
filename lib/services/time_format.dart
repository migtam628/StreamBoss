/// Clock time for the guide: "18:30" or "6:30 PM".
///
/// Guide times arrive in UTC, so [d] is shown in the device's own time zone.
String fmtTime(DateTime t, {required bool use24h}) {
  final d = t.toLocal();
  final m = d.minute.toString().padLeft(2, '0');
  if (use24h) return '${d.hour.toString().padLeft(2, '0')}:$m';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
