import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';
import 'users_screen.dart';

/// Карточка человека у модерации (ТЗ §4.1, п.3 и 8).
///
/// Решение всегда с причиной: её увидит и человек, и следующий модератор,
/// который откроет карточку. История отличает единичный срыв от привычки.
class AdminUserCardScreen extends ConsumerWidget {
  const AdminUserCardScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(adminUserProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Карточка'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/moderation/users'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: user.when(
        loading: () => const TkSkeletonList(count: 3),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(adminUserProvider(userId)),
        ),
        data: (u) => _Body(user: u),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.user});

  final AdminUser user;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  Future<void> _apply(String status, String title, String hint) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title, hint: hint),
    );
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(jobsApiProvider).setUserStatus(
                  t,
                  widget.user.id,
                  status: status,
                  reason: reason,
                  idempotencyKey:
                      'status-${widget.user.id}-${DateTime.now().microsecondsSinceEpoch}',
                ),
          );
      ref.invalidate(adminUserProvider(widget.user.id));
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Решение применено и записано в журнал')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final u = widget.user;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(u.displayName, style: TkText.h2),
              const SizedBox(height: 4),
              Text(
                '${u.phone}${u.city.isEmpty ? '' : ' · ${u.city}'}',
                style: TkText.body.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in u.roles) TkChip(label: r, selected: false, onTap: null),
                  if (u.verified) const TkChip(label: 'Проверен', selected: true, onTap: null),
                ],
              ),
              if (u.createdAt != null) ...[
                const SizedBox(height: 8),
                Text('На площадке с ${tkShortDate(u.createdAt)}',
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Состояние: ${u.statusRu}',
                  style: TkText.body.copyWith(fontWeight: FontWeight.w600)),
              if (u.reason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(u.reason, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              if (u.isActive) ...[
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _apply('frozen', 'Заморозить отклики и ставки',
                          'За что: жалобы, срывы договорённостей, оплата мимо площадки'),
                  child: const Text('Заморозить ставки и отклики'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TkColors.error),
                  onPressed: _busy
                      ? null
                      : () => _apply('banned', 'Закрыть доступ',
                          'За что: повторные подтверждённые нарушения'),
                  child: const Text('Закрыть доступ'),
                ),
              ] else ...[
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _apply('active', 'Снять ограничения',
                          'Почему снимаем: разобрались, ошибка, человек исправился'),
                  child: const Text('Снять ограничения'),
                ),
                if (u.isFrozen) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: TkColors.error),
                    onPressed: _busy
                        ? null
                        : () => _apply('banned', 'Закрыть доступ',
                            'За что: нарушения продолжились после заморозки'),
                    child: const Text('Закрыть доступ'),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              Text(
                'Заморозка оставляет вход и переписку: у человека могут быть '
                'незакрытые сделки, и оборвать их — навредить второй стороне.',
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('История решений', style: TkText.h3),
        const SizedBox(height: 8),
        if (u.history.isEmpty)
          Text('Решений по этому человеку не было',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant))
        else
          for (final a in u.history)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${a.actionRu}'
                      '${a.createdAt != null ? ' · ${tkShortDate(a.createdAt)}' : ''}',
                      style: TkText.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (a.reason.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(a.reason,
                          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _text = TextEditingController();

  static const _minLength = 10;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final short = _text.text.trim().length < _minLength;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TkTextField(
            controller: _text,
            label: 'Причина',
            hint: widget.hint,
            maxLines: 3,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            'Причину увидит и человек, и следующий модератор, который откроет '
            'карточку. Решение попадёт в журнал.',
            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: short ? null : () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}
