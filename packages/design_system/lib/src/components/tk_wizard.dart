import 'package:flutter/material.dart';

import '../icons/tk_icon.dart';
import '../icons/tk_icons.dart';
import '../tokens.dart';

/// Степпер визарда (ТЗ §1.10, прототип `.wsteps`): полоски по числу шагов,
/// пройденные — цветом бренда. Показывает, сколько ещё осталось: без этого
/// длинная форма ощущается бесконечной.
class TkWizardSteps extends StatelessWidget {
  const TkWizardSteps({super.key, required this.total, required this.current});

  final int total;

  /// Текущий шаг, начиная с 1.
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TkSpace.padMobile, vertical: 6),
      child: Row(
        children: List.generate(total, (i) {
          final done = i < current;
          return Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
              decoration: BoxDecoration(
                color: done ? TkColors.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Пустое состояние (ТЗ §1.11): иконка, одна фраза, одна кнопка.
/// Пустой экран без объяснения — самая частая причина «приложение сломалось».
class TkEmptyState extends StatelessWidget {
  const TkEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description = '',
    this.actionLabel,
    this.onAction,
  });

  final String icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TkIcon(icon, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title, style: TkText.h3, textAlign: TextAlign.center),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Состояние ошибки с кнопкой «Повторить» (ТЗ §1.11). Показываем причину:
/// «что-то пошло не так» не помогает ни человеку, ни поддержке.
class TkErrorState extends StatelessWidget {
  const TkErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TkIcon(TkIcons.warning, size: 40, color: TkColors.error),
            const SizedBox(height: 12),
            Text('Не удалось загрузить', style: TkText.h3),
            const SizedBox(height: 6),
            Text(
              message,
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Скелет-плейсхолдер списка на время загрузки (ТЗ §1.11): экран сразу
/// показывает форму будущего содержимого вместо крутящегося колеса.
class TkSkeletonList extends StatelessWidget {
  const TkSkeletonList({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(TkSpace.padMobile),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 104,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: TkRadius.cardR,
        ),
      ),
    );
  }
}
