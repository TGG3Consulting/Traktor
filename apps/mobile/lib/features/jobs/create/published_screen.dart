import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../../../core/share_link.dart';

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
    final l = AppLocalizations.of(context);
    // Без решётки: этот адрес открывает бот мессенджера, чтобы собрать
    // превью карточки (ТЗ §4.2).
    final link = 'https://app.homly.am/jobs/$jobId';

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
              Text(l.jobPublished, style: TkText.h1, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                l.firstOffersSoon,
                textAlign: TextAlign.center,
                style: TkText.body.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => TkShare.copy(context, link),
                  icon: TkIcon(TkIcons.share, size: 16, color: scheme.onSurface),
                  label: Text(l.shareLink),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/home'),
                  child: Text(l.toMyJobs),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/jobs/$jobId'),
                child: Text(l.viewJob),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
