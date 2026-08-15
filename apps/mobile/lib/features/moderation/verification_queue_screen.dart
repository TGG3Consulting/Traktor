import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Очередь проверки людей (ТЗ §2.3).
///
/// Человеку обещан ответ за сутки, поэтому старые заявки сверху. Модератор
/// сверяет документ с профилем: имя и телефон показаны рядом со снимком.
final verificationQueueProvider = FutureProvider<List<Verification>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).verificationQueue(t));
});

class VerificationQueueScreen extends ConsumerWidget {
  const VerificationQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(verificationQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Проверка людей'),
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
          onRetry: () => ref.invalidate(verificationQueueProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const TkEmptyState(
              icon: TkIcons.idCard,
              title: 'Заявок нет',
              description: 'Разобранные заявки уходят отсюда сами',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(verificationQueueProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _VerificationCard(item: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _VerificationCard extends ConsumerStatefulWidget {
  const _VerificationCard({required this.item});

  final Verification item;

  @override
  ConsumerState<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends ConsumerState<_VerificationCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final messenger = ScaffoldMessenger.of(context);
    var reason = '';
    if (!approve) {
      final text = await showDialog<String>(
        context: context,
        builder: (_) => const _RejectDialog(),
      );
      if (text == null) return;
      reason = text;
    }

    setState(() => _busy = true);
    try {
      await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(jobsApiProvider).reviewVerification(
                  t,
                  widget.item.id,
                  approve: approve,
                  reason: reason,
                  idempotencyKey:
                      'verify-${widget.item.id}-${DateTime.now().microsecondsSinceEpoch}',
                ),
          );
      ref.invalidate(verificationQueueProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? 'Бейдж выдан' : 'Заявка отклонена')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.detail)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = widget.item;

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v.userName.isEmpty ? 'Без имени' : v.userName, style: TkText.h3),
          const SizedBox(height: 2),
          Text(
            '${v.userPhone} · ${v.docKindRu}'
            '${v.createdAt != null ? ' · ${tkShortDate(v.createdAt)}' : ''}',
            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: v.documents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => GestureDetector(
                // Разглядеть номер документа в списке невозможно, поэтому
                // снимок открывается во весь экран.
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    insetPadding: const EdgeInsets.all(12),
                    child: InteractiveViewer(child: Image.network(v.documents[i])),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: TkRadius.cardR,
                  child: Image.network(v.documents[i], width: 150, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Отклонить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Выдать бейдж'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Отказ с причиной: без неё человек не поймёт, что переснять, и либо подаст
/// то же самое ещё раз, либо уйдёт.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _text = TextEditingController();

  static const _minLength = 10;
  static const _templates = [
    'Снимок засвечен, номер документа не читается',
    'Видна только часть документа — нужен разворот целиком',
    'Имя в документе не совпадает с именем в профиле',
    'Это не документ, удостоверяющий личность',
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final short = _text.text.trim().length < _minLength;

    return AlertDialog(
      title: const Text('Причина отказа'),
      content: SingleChildScrollView(
        child: Column(
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
                    selected: false,
                    onTap: () => setState(() {
                      _text.text = t;
                      _text.selection = TextSelection.collapsed(offset: t.length);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TkTextField(
              controller: _text,
              label: 'Что переснять',
              maxLines: 3,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: short ? null : () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Отклонить'),
        ),
      ],
    );
  }
}
