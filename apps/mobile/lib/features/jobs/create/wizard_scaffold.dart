import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

/// Общий каркас шага визарда: заголовок, степпер, подпись «Шаг N из 5»,
/// содержимое и закреплённая внизу кнопка.
///
/// Один каркас на все пять шагов — чтобы шаги не разъезжались по отступам и
/// поведению кнопки, как это обычно происходит, когда каждый экран свой.
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    super.key,
    required this.step,
    required this.subtitle,
    required this.child,
    required this.primaryLabel,
    this.onPrimary,
    this.onBack,
    this.error,
    this.hint,
    this.saving = false,
    this.savedMark = true,
    this.total = 5,
  });

  final int step;
  final int total;
  final String subtitle;
  final Widget child;
  final String primaryLabel;

  /// null — кнопка неактивна (не хватает данных); подсказку пишем в [hint].
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final String? error;
  final String? hint;
  final bool saving;

  /// Отметка «черновик сохранён» — с шага 2, когда черновик уже есть.
  final bool savedMark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.newJob),
        leading: onBack == null
            ? null
            : IconButton(
                onPressed: onBack,
                icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
                tooltip: l.back,
              ),
      ),
      // Визард — это форма: на мониторе она не должна растягиваться во всю
      // ширину, иначе плитки категорий превращаются в полотна (ТЗ §1.8).
      body: SafeArea(
        child: TkReadable(
          child: Column(
          children: [
            TkWizardSteps(total: total, current: step),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.wizardStep(step, total, subtitle),
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (savedMark && step > 1)
                    Row(
                      children: [
                        const TkIcon(TkIcons.check, size: 13, color: TkColors.success),
                        const SizedBox(width: 4),
                        Text(l.draftSaved,
                            style: TkText.caption.copyWith(color: TkColors.success)),
                      ],
                    ),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TkColors.error.withValues(alpha: 0.12),
                    borderRadius: TkRadius.cardR,
                  ),
                  child: Row(
                    children: [
                      const TkIcon(TkIcons.warning, size: 18, color: TkColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(error!,
                            style: TkText.caption.copyWith(color: TkColors.error)),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(child: child),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  if (hint != null && onPrimary == null) ...[
                    Text(
                      hint!,
                      textAlign: TextAlign.center,
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: saving ? null : onPrimary,
                      child: saving
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(primaryLabel),
                    ),
                  ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
