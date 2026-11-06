import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/ui/artwork.dart';
import 'package:material_ui/material_ui.dart';

/// What a playlist row shows for one item.
typedef PlaylistItemInfo = ({String title, String? subtitle, String? artworkUrl});

/// Reorderable list of [player]'s sequence. Tap a row to play it, drag the handle to move it and swipe it away to
/// remove it. [header] scrolls with the list.
class PlaylistView extends StatelessWidget {
  const new(this.player, {super.key, required this.describe, this.header, this.padding = EdgeInsets.zero});

  /// The player whose sequence is shown.
  final AudioPlayer player;

  /// Maps an item's source to the text and artwork shown in its row.
  final PlaylistItemInfo Function(IndexedAudioSource source) describe;

  /// Widget above the first row.
  final Widget? header;

  /// Padding around the list.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => StreamBuilder<SequenceState?>(
    stream: player.sequenceStateStream,
    builder: (context, snapshot) {
      final state = snapshot.data;
      final sequence = state?.sequence ?? [];
      return ReorderableListView.builder(
        header: header,
        padding: padding,
        buildDefaultDragHandles: false,
        itemCount: sequence.length,
        onReorderItem: (oldIndex, newIndex) => unawaited(player.moveAudioSource(oldIndex, newIndex)),
        itemBuilder: (context, i) => _PlaylistTile(
          key: ValueKey(sequence[i]),
          index: i,
          info: describe(sequence[i]),
          current: i == state?.currentIndex,
          onTap: () => unawaited(player.seek(Duration.zero, index: i).catchError((Object _) {})),
          onDismissed: () => unawaited(player.removeAudioSourceAt(i)),
        ),
      );
    },
  );
}

class _PlaylistTile extends StatelessWidget {
  const new({
    super.key,
    required this.index,
    required this.info,
    required this.current,
    required this.onTap,
    required this.onDismissed,
  });

  final int index;
  final PlaylistItemInfo info;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final subtitle = info.subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Dismissible(
        key: ValueKey(('dismiss', key)),
        direction: DismissDirection.endToStart,
        background: DecoratedBox(
          decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(14)),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Icon(Icons.delete_outline_rounded, color: colors.onErrorContainer),
            ),
          ),
        ),
        onDismissed: (_) => onDismissed(),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            selected: current,
            selectedTileColor: colors.secondaryContainer,
            selectedColor: colors.onSecondaryContainer,
            leading: Artwork(url: info.artworkUrl, size: 48, radius: 10),
            title: Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: subtitle == null ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: onTap,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (current) Icon(Icons.graphic_eq_rounded, color: colors.primary),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
