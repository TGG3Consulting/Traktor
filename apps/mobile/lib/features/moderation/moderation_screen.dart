import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_settings.dart';
import '../../core/session_refresh.dart';
import '../auth/auth_controller.dart';
import '../jobs/jobs_providers.dart';

/// Очередь проверки техники (ТЗ §4.1, п.2).
///
/// Исполнителю на последнем шаге визарда обещали ответ за сутки — поэтому
/// очередь отсортирована по возрасту, а просрочка подсвечена.
final moderationQueueProvider = FutureProvider<List<ModerationItem>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).moderationQueue(t));
});

/// Есть ли у вошедшего доступ к модерации. Роль приходит в сессии, поэтому
/// пункт меню появляется сам — отдельного входа для админки не нужно.
final isModeratorProvider = Provider<bool>((ref) {
  final roles = ref.watch(sessionProvider)?.user.roles ?? const <String>[];
  return roles.contains('moderator') || roles.contains('admin');
});

class ModerationScreen extends ConsumerWidget {
  const ModerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(moderationQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Проверка техники'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: queue.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(moderationQueueProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const TkEmptyState(
              icon: TkIcons.checkCircle,
              title: 'Очередь пуста',
              description: 'Все карточки разобраны — новые появятся здесь сами',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(moderationQueueProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _QueueCard(item: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _QueueCard extends ConsumerStatefulWidget {
  const _QueueCard({required this.item});

  final ModerationItem item;

  @override
  ConsumerState<_QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends ConsumerState<_QueueCard> {
  bool _busy = false;

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(jobsApiProvider).approveEquipment(
                  t,
                  widget.item.id,
                  idempotencyKey: 'approve-${widget.item.id}-'
                      '${DateTime.now().microsecondsSinceEpoch}',
                ),
          );
      ref.invalidate(moderationQueueProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Одобрено — владельцу ушло уведомление')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не получилось: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Отказ без причины бесполезен: человек не поймёт, что исправить, и просто
  /// уйдёт. Поэтому причина обязательна, а частые формулировки — под рукой.
  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(jobsApiProvider).rejectEquipment(
                  t,
                  widget.item.id,
                  reason.trim(),
                  idempotencyKey: 'reject-${widget.item.id}-'
                      '${DateTime.now().microsecondsSinceEpoch}',
                ),
          );
      ref.invalidate(moderationQueueProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отклонено — причина ушла владельцу')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не получилось: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final lang = (ref.watch(appSettingsProvider).locale ?? const Locale('ru')).languageCode;

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title.isEmpty ? 'Без названия' : item.title,
                  style: TkText.h3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.overdue ? TkColors.error : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'ждёт ${item.waitingHours} ч',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: item.overdue ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (item.categoryTitle(lang).isNotEmpty) item.categoryTitle(lang),
              if (item.year != null) '${item.year} г',
            ].join(' · '),
            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),

          if (item.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Strip(title: 'Фотографии техники', urls: item.photos),
          ],
          if (item.docs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Strip(title: 'Документы', urls: item.docs),
          ],

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  child: const Text('Отклонить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _approve,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Одобрить'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => context.push('/users/${item.ownerId}'),
            child: Text(
              'Открыть профиль владельца',
              style: TkText.caption.copyWith(color: TkColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Полоса изображений: фото техники и документы модератор смотрит рядом.
class _Strip extends StatelessWidget {
  const _Strip({required this.title, required this.urls});

  final String title;
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ClipRRect(
              borderRadius: TkRadius.cardR,
              child: Image.network(
                urls[i],
                width: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 120,
                  color: scheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: TkIcon(TkIcons.fileText, size: 20, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  /// Частые причины — чтобы модератор не сочинял текст каждый раз, а формулировка
  /// оставалась понятной владельцу.
  static const _templates = [
    'Фото не соответствует технике',
    'Документ нечитаем — переснимите при дневном свете',
    'Документ не подтверждает владение техникой',
    'Данные в карточке не совпадают с документом',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Причина отказа'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _templates)
                TkChip(
                  label: t,
                  selected: _reason.text == t,
                  onTap: () => setState(() => _reason.text = t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TkTextField(
            controller: _reason,
            label: 'Что исправить',
            maxLines: 3,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text),
          child: const Text('Отклонить'),
        ),
      ],
    );
  }
}
