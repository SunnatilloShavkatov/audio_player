import 'package:audio_player_example/ui/artwork.dart';
import 'package:material_ui/material_ui.dart';

/// Large artwork with the title and subtitle of the current item underneath.
class NowPlaying extends StatelessWidget {
  const new({
    super.key,
    required this.title,
    this.subtitle,
    this.artworkUrl,
    this.placeholderIcon = Icons.music_note_rounded,
    this.badge,
    this.maxArtworkSize = 320,
  });

  /// Main line, for example the track title.
  final String title;

  /// Secondary line, for example the album or artist.
  final String? subtitle;

  /// Artwork to show; a placeholder is shown when `null`.
  final String? artworkUrl;

  /// Icon used by the artwork placeholder.
  final IconData placeholderIcon;

  /// Optional widget shown above the title, for example a "Live" chip.
  final Widget? badge;

  /// Upper bound for the artwork edge length.
  final double maxArtworkSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    final badge = this.badge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxArtworkSize),
          child: Material(
            elevation: 6,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(28),
            child: Artwork(url: artworkUrl, radius: 28, placeholderIcon: placeholderIcon),
          ),
        ),
        const SizedBox(height: 24),
        if (badge != null) ...[badge, const SizedBox(height: 12)],
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
