// Video preview player — Web stub.
//
// video_player does not accept filesystem paths on Web, and Clip Studio is a
// native-first editor, so Web shows a static placeholder instead of a player.
import 'package:material_ui/material_ui.dart';

import '../clip_models.dart';

class ClipPreview extends StatelessWidget {
  const ClipPreview({super.key, required this.clip});

  final ClipEdit? clip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_filter_rounded,
            size: 34,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            clip == null ? 'Добавь клип' : 'Превью доступно в приложении',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
