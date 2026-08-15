import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

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
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(sessionProvider)?.user;
    final pending = user?.deleteAfter;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.deleteAccountTitle),
        leading: IconButton(
          tooltip: l.back,
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
                  Text(l.accountDeletesOn(tkShortDate(pending)),
                      style: TkText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    l.deletePendingHint,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _cancel,
              child: Text(l.keepAccount),
            ),
          ] else ...[
            Text(l.whatHappens, style: TkText.h3),
            const SizedBox(height: 8),
            _Point(
              icon: TkIcons.clock,
              text: l.delPoint1,
            ),
            _Point(
              icon: TkIcons.user,
              text: l.delPoint2,
            ),
            _Point(
              icon: TkIcons.star,
              text: l.delPoint3,
            ),
            _Point(
              icon: TkIcons.warning,
              text: l.delPoint4,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: TkColors.error),
              onPressed: _busy ? null : _confirm,
              child: Text(l.deleteAccount),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    // Двойное подтверждение (ТЗ §2.3): необратимое действие не должно
    // выполняться одним касанием.
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteAccountQ),
        content: Text(l.deleteAccountBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.keepIt),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TkColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.deleteYes),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).requestDeletion();
      messenger.showSnackBar(
        SnackBar(content: Text(l.deleteScheduled)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.detail)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).cancelDeletion();
      messenger.showSnackBar(SnackBar(content: Text(l.deleteCancelled)));
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
