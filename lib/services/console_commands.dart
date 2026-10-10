/// A slash command typed into Console's prompt.
class ConsoleCommand {
  final String name;
  final String help;

  /// The shell tab it opens (see kDests), or null for a command that fills the list instead.
  final int? tab;
  const ConsoleCommand(this.name, this.help, {this.tab});
}

const consoleCommands = <ConsoleCommand>[
  ConsoleCommand('/live', 'live channels', tab: 1),
  ConsoleCommand('/guide', 'what is on', tab: 2),
  ConsoleCommand('/movies', 'movies', tab: 3),
  ConsoleCommand('/series', 'series', tab: 4),
  ConsoleCommand('/search', 'the full search screen', tab: 5),
  ConsoleCommand('/settings', 'settings, sources and profiles', tab: 6),
  ConsoleCommand('/list', 'my list'),
  ConsoleCommand('/recent', 'watched lately'),
];

/// The commands that [input] could be the start of ("/mo" gives /movies). Empty unless it starts with a slash.
List<ConsoleCommand> matchCommands(String input) {
  final t = input.trim().toLowerCase();
  if (!t.startsWith('/')) return const [];
  final word = t.split(RegExp(r'\s+')).first;
  return [
    for (final c in consoleCommands)
      if (c.name.startsWith(word)) c
  ];
}

/// The command [input] names exactly (or the only one it could be), else null.
ConsoleCommand? exactCommand(String input) {
  final m = matchCommands(input);
  final word = input.trim().toLowerCase().split(RegExp(r'\s+')).first;
  for (final c in m) {
    if (c.name == word) return c;
  }
  return m.length == 1 ? m.first : null;
}
