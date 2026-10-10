import '../models/media.dart';

/// What the viewer changed about one live channel: a name of their own, or hidden. The original name is
/// kept so the TV guide (which can match by name) still finds it, and so the Edited channels screen can
/// say what a renamed or hidden channel was.
class ChannelEdit {
  final String? name;
  final String original;
  final bool hidden;
  const ChannelEdit({this.name, required this.original, this.hidden = false});

  bool get isEmpty => name == null && !hidden;

  ChannelEdit copyWith({Object? name = _keep, bool? hidden}) => ChannelEdit(
        name: identical(name, _keep) ? this.name : name as String?,
        original: original,
        hidden: hidden ?? this.hidden,
      );

  Map<String, dynamic> toJson() => {'o': original, if (name != null) 'n': name, if (hidden) 'h': 1};

  factory ChannelEdit.fromJson(Map<String, dynamic> j) => ChannelEdit(
        name: j['n'] as String?,
        original: '${j['o'] ?? ''}',
        hidden: j['h'] == 1 || j['h'] == true,
      );
}

const _keep = Object();

/// The renames, hidden channels and pinned channels of one profile.
class ChannelEdits {
  final Map<String, ChannelEdit> edits;

  /// Channel keys that come first in a list of channels, in this order.
  final List<String> pins;
  ChannelEdits([Map<String, ChannelEdit>? edits, List<String>? pins])
      : edits = edits ?? {},
        pins = pins ?? [];

  bool get isEmpty => edits.isEmpty && pins.isEmpty;

  Set<String> get hiddenKeys => {
        for (final e in edits.entries)
          if (e.value.hidden) e.key
      };

  void clear() {
    edits.clear();
    pins.clear();
  }
}

/// [live] with the edits applied: hidden channels dropped, renamed ones renamed, pinned ones first in
/// the order they were pinned. Returns [live] itself when there is nothing to do.
List<MediaItem> applyChannelEdits(List<MediaItem> live, ChannelEdits e) {
  if (e.isEmpty) return live;
  final pinAt = {for (var i = 0; i < e.pins.length; i++) e.pins[i]: i};
  final pinned = <MediaItem?>[for (var i = 0; i < e.pins.length; i++) null];
  final rest = <MediaItem>[];
  for (final ch in live) {
    final ed = e.edits[ch.key];
    if (ed != null && ed.hidden) continue;
    final shown = ed?.name == null ? ch : ch.copyWith(name: ed!.name);
    final at = pinAt[ch.key];
    if (at != null) {
      pinned[at] = shown;
    } else {
      rest.add(shown);
    }
  }
  return [...pinned.whereType<MediaItem>(), ...rest];
}
