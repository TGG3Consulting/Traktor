import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';

/// Удаление аккаунта (ТЗ §2.3, §4.3).
///
/// Уйти с площадки человек должен мочь. Но удаление без отсрочки — необратимая
/// кнопка рядом с обычными настройками: нажимают в сердцах, а возвращаются
/// через день. Поэтому здесь честно сказано, что произойдёт, и как вернуться.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(sessionProvider)?.user;
    final pending = user?.deleteAfter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Удаление аккаунта'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (pending != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TkColors.warning.withValues(alpha: 0.14),
                borderRadius: TkRadius.cardR,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Аккаунт удалится ${tkShortDate(pending)}',
                      style: TkText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'До этого дня всё работает как обычно. Любой вход в приложение '
                    'отменяет удаление — как и кнопка ниже.',
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _cancel,
              child: const Text('Оставить аккаунт'),
            ),
          ] else ...[
            const Text('Что произойдёт', style: TkText.h3),
            const SizedBox(height: 8),
            const _Point(
              icon: TkIcons.clock,
              text: 'Тридцать дней аккаунт ждёт: за это время можно передумать, '
                  'просто войдя снова.',
            ),
            const _Point(
              icon: TkIcons.user,
              text: 'Потом имя, телефон и город стираются, профиль становится '
                  'обезличенным.',
            ),
            const _Point(
              icon: TkIcons.star,
              text: 'Отзывы и завершённые сделки остаются без вашего имени: '
                  'на них держится рейтинг второй стороны.',
            ),
            const _Point(
              icon: TkIcons.warning,
              text: 'Незакрытые сделки лучше довести до конца — исполнитель или '
                  'заказчик ждёт вас.',
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: TkColors.error),
              onPressed: _busy ? null : _confirm,
              child: const Text('Удалить аккаунт'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final messenger = ScaffoldMessenger.of(context);
    // Двойное подтверждение (ТЗ §2.3): необратимое действие не должно
    // выполняться одним касанием.
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Аккаунт исчезнет через 30 дней. Всё это время его можно вернуть — '
          'достаточно войти в приложение.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TkColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).requestDeletion();
      messenger.showSnackBar(
        const SnackBar(content: Text('Аккаунт будет удалён через 30 дней')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.detail)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).cancelDeletion();
      messenger.showSnackBar(const SnackBar(content: Text('Удаление отменено')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.detail)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TkIcon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TkText.body)),
        ],
      ),
    );
  }
}
