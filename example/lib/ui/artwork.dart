import 'package:material_ui/material_ui.dart';

/// Rounded square artwork. Shows a gradient placeholder with [placeholderIcon] while [url] loads, when it fails, or
/// when there is no [url].
class Artwork extends StatelessWidget {
  const new({super.key, this.url, this.size, this.radius = 24, this.placeholderIcon = Icons.music_note_rounded});

  /// Network image to show, if any.
  final String? url;

  /// Edge length. When `null` the artwork fills the available width.
  final double? size;

  /// Corner radius.
  final double radius;

  /// Icon shown in the placeholder.
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(icon: placeholderIcon);
    final url = this.url;
    final Widget content = url == null || url.isEmpty
        ? placeholder
        : Image.network(
            url,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                wasSynchronouslyLoaded || frame != null ? child : placeholder,
            errorBuilder: (context, error, stackTrace) => placeholder,
          );
    return SizedBox.square(
      dimension: size,
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: content),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const new({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: Icon(icon, size: constraints.biggest.shortestSide * 0.4, color: colors.onPrimaryContainer),
        ),
      ),
    );
  }
}
