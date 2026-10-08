/// Zero-based position in a list of [count] channels for the digits a viewer typed on the remote
/// ("207" means the 207th channel), or null when there is no such channel.
int? channelIndexForDigits(String digits, int count) {
  final n = int.tryParse(digits);
  if (n == null || n < 1 || n > count) return null;
  return n - 1;
}
