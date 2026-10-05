/// Clock time for the guide: "18:30" or "6:30 PM".
String fmtTime(DateTime d, {required bool use24h}) {
  final m = d.minute.toString().padLeft(2, '0');
  if (use24h) return '${d.hour.toString().padLeft(2, '0')}:$m';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
