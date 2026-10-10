import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../screens/channel_details_screen.dart';
import 'collections_sheet.dart';
import 'peek.dart';

/// What pressing and holding a title does: a live channel opens its options (see [showChannelSheet]);
/// a movie or series opens a quick look at it (see [showPeek]) with My list one tap away.
void itemMenu(BuildContext context, MediaItem item) {
  if (item.kind == MediaKind.live) {
    showChannelSheet(context, item);
  } else {
    showPeek(context, item);
  }
}

/// The options for one live channel: My list, a name of your own, hide it, pin it to the top of the
/// channel lists and move it among the pinned ones. Changes are kept per profile and never touch the
/// provider.
Future<void> showChannelSheet(BuildContext context, MediaItem ch, {bool details = true}) {
  final pal = LayoutPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.surface,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => ChannelSheet(channel: ch, details: details),
  );
}

class ChannelSheet extends StatelessWidget {
  final MediaItem channel;

  /// Offer the channel's page (off when the sheet is opened from that page, or from the player).
  final bool details;
  const ChannelSheet({super.key, required this.channel, this.details = true});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = LayoutPalette.of(context);
    final key = channel.key;
    final edit = s.channelEdits.edits[key];
    final pinned = s.isPinned(key);
    final pinAt = s.channelEdits.pins.indexOf(key);
    final edited = edit != null || pinned;

    Widget tile(IconData icon, String title, VoidCallback onTap, {String? subtitle, bool close = false}) => ListTile(
          leading: Icon(icon, color: pal.accent),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: () {
            if (close) Navigator.pop(context);
            onTap();
          },
        );

    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 8), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text(channel.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: pal.text)),
        ),
        if (edit?.name != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text('Provider name: ${edit!.original}', style: TextStyle(color: pal.muted, fontSize: 13)),
          ),
        if (details)
          tile(Icons.info_outline, 'Channel details', () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChannelDetailsScreen(channel: channel)));
          }, subtitle: "What's on, the schedule, other copies", close: true),
        tile(s.isFavorite(channel) ? Icons.star : Icons.star_border, s.isFavorite(channel) ? 'Remove from My list' : 'Add to My list',
            () => s.toggleFavorite(channel)),
        tile(Icons.collections_bookmark_outlined, 'Add to a collection', () => showCollectionsSheet(context, channel)),
        tile(Icons.edit_outlined, 'Rename', () async {
          final n = await askCollectionName(context, title: 'Rename channel', initial: channel.name);
          if (n != null) s.renameChannel(channel, n);
          if (context.mounted) Navigator.pop(context);
        }),
        if (!pinned)
          tile(Icons.push_pin_outlined, 'Pin to the top', () => s.pinChannel(channel), subtitle: 'Pinned channels come first in every channel list')
        else ...[
          tile(Icons.push_pin, 'Unpin', () => s.unpinChannel(key)),
          if (pinAt > 0) tile(Icons.arrow_upward, 'Move up among the pinned', () => s.movePinned(key, -1)),
          if (pinAt < s.channelEdits.pins.length - 1) tile(Icons.arrow_downward, 'Move down among the pinned', () => s.movePinned(key, 1)),
        ],
        tile(Icons.visibility_off_outlined, 'Hide this channel', () => s.hideChannel(channel),
            subtitle: 'Settings > Library > Edited channels brings it back', close: true),
        if (edited) tile(Icons.restore, 'Undo my changes to this channel', () => s.resetChannel(key), close: true),
      ]),
    );
  }
}
