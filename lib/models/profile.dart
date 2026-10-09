/// One person (or one shared screen) using the app: its own My List, history and resume positions.
class Profile {
  final String id;
  final String name;

  /// Shows only categories that look made for children and needs the PIN to leave.
  final bool kids;

  /// Needs the PIN to switch into it.
  final bool locked;

  /// Has its own layout, text size, languages, subtitles and filters instead of the device's.
  final bool ownSettings;

  const Profile({
    required this.id,
    required this.name,
    this.kids = false,
    this.locked = false,
    this.ownSettings = false,
  });

  /// The profile everyone starts with. It keeps the storage keys used before profiles existed.
  static const main = Profile(id: 'main', name: 'Main');

  Profile copyWith({String? name, bool? kids, bool? locked, bool? ownSettings}) => Profile(
        id: id,
        name: name ?? this.name,
        kids: kids ?? this.kids,
        locked: locked ?? this.locked,
        ownSettings: ownSettings ?? this.ownSettings,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kids': kids, 'locked': locked, 'own': ownSettings};

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        kids: (j['kids'] as bool?) ?? false,
        locked: (j['locked'] as bool?) ?? false,
        ownSettings: (j['own'] as bool?) ?? false,
      );
}
