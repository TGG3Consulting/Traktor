import 'package:flutter/material.dart';

import '../icons/tk_icon.dart';
import '../icons/tk_icons.dart';
import '../tokens.dart';

/// Галерея фотографий с добавлением и удалением (ТЗ §2.5, §2.6).
///
/// Первый снимок — обложка: именно его видят в ленте, поэтому он подписан.
/// Один компонент на технику и на задания: одинаковые правила и одинаковый вид.
class TkPhotoGrid extends StatelessWidget {
  const TkPhotoGrid({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    this.max = 8,
    this.busy = false,
    this.tileSize = 104,
    this.coverLabel = 'Обложка',
  });

  final List<String> photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final int max;
  final bool busy;
  final double tileSize;

  /// Пусто — подпись обложки не показывается (например, у документов).
  final String coverLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < photos.length; i++)
          SizedBox(
            width: tileSize,
            height: tileSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: TkRadius.cardR,
                  child: Image.network(
                    photos[i],
                    fit: BoxFit.cover,
                    // Битая ссылка не должна выглядеть как поломка экрана:
                    // показываем заглушку и даём удалить снимок.
                    errorBuilder: (_, __, ___) => Container(
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: TkIcon(TkIcons.image,
                          size: 22, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                if (i == 0 && coverLabel.isNotEmpty)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: TkColors.primary,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: Text(
                        coverLabel,
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: Semantics(
                    button: true,
                    label: 'Удалить фото',
                    child: InkWell(
                      onTap: busy ? null : () => onRemove(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: TkIcon(TkIcons.x, size: 12, color: scheme.onSurface),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (photos.length < max)
          InkWell(
            onTap: busy ? null : onAdd,
            borderRadius: TkRadius.cardR,
            child: Container(
              width: tileSize,
              height: tileSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: TkRadius.cardR,
              ),
              child: busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TkIcon(TkIcons.camera, size: 22, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 4),
                        Text('Добавить',
                            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}
