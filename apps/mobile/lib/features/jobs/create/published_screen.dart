import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Экран после публикации (ТЗ §2.6): подтверждение и ссылка для шеринга.
///
/// Ссылка здесь не украшение: сарафан — основной канал для такой площадки,
/// заказчику проще скинуть задание знакомому исполнителю, чем ждать отклика.
class JobPublishedScreen extends ConsumerWidget {
  const JobPublishedScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final link = 'https://app.homly.am/#/jobs/$jobId';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: TkColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: TkIcon(TkIcons.checkCircle, size: 38, color: TkColors.success),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Задание опубликовано', style: TkText.h1, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Обычно первые отклики приходят в течение часа. '
                'Мы пришлём уведомление, как только они появятся.',
                textAlign: TextAlign.center,
                style: TkText.body.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ссылка скопирована')),
                    );
                  },
                  icon: TkIcon(TkIcons.share, size: 16, color: scheme.onSurface),
                  label: const Text('Поделиться ссылкой'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('К моим заданиям'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/jobs/$jobId'),
                child: const Text('Посмотреть задание'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
