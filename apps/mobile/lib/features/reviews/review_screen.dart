import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'review_providers.dart';

/// Экран взаимной оценки после сделки (ТЗ §2.13, прототип `review`).
///
/// Звёзды обязательны, отметки и текст — нет. Отзыв не публикуется сразу:
/// он откроется вместе с отзывом второй стороны или через неделю, и об этом
/// сказано прямо на экране — иначе человек решит, что оценка пропала.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key, required this.dealId});

  final String dealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(reviewFormProvider(dealId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Оценка сделки'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/deals/$dealId'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: form.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(reviewFormProvider(dealId)),
        ),
        data: (f) {
          if (f.alreadyLeft) return _Left(form: f);
          if (!f.canReview) {
            return const TkEmptyState(
              icon: TkIcons.hourglass,
              title: 'Оценка пока недоступна',
              description: 'Оценить работу можно после того, как сделка завершена',
            );
          }
          return _Form(dealId: dealId, form: f);
        },
      ),
    );
  }
}

/// Оценка уже оставлена: показываем её и объясняем, что дальше.
class _Left extends StatelessWidget {
  const _Left({required this.form});

  final ReviewForm form;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = form.mine!;

    return ListView(
      padding: TkSpace.screenMobile,
      children: [
        Center(child: TkStars(value: mine.stars, size: 34)),
        const SizedBox(height: 12),
        if (mine.tags.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in mine.tags) TkChip(label: t, selected: true)],
          ),
        if (mine.text.isNotEmpty) ...[
          const SizedBox(height: 16),
          TkCard(child: Text(mine.text, style: TkText.body)),
        ],
        const SizedBox(height: 16),
        Text(
          mine.published
              ? 'Отзыв опубликован.'
              : 'Отзыв скрыт, пока не оценит вторая сторона. Он откроется '
                  'автоматически — сразу после её оценки или через неделю.',
          textAlign: TextAlign.center,
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.dealId, required this.form});

  final String dealId;
  final ReviewForm form;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _text = TextEditingController();
  final _issue = TextEditingController();
  final _tags = <String>{};
  int _stars = 0;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _issue.dispose();
    super.dispose();
  }

  /// Низкая оценка — необязательный вопрос «что пошло не так»: ответы нужны
  /// модерации, публично они не показываются (ТЗ §2.13).
  bool get _asksIssue => _stars > 0 && _stars < 3;

  Future<void> _send() async {
    if (_stars == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(reviewActionsProvider).leave(
            widget.dealId,
            stars: _stars,
            tags: _tags.toList(),
            text: _text.text.trim(),
            issue: _asksIssue ? _issue.text.trim() : '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.published
              ? 'Спасибо! Отзыв опубликован'
              : 'Спасибо! Отзыв откроется после оценки второй стороны'),
        ),
      );
      context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Оценка не отправилась: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = widget.form;
    final name = f.targetName.isEmpty ? 'вторую сторону' : f.targetName;
    final title = f.authorRole == 'owner'
        ? 'Как вам работалось с $name?'
        : 'Как отработал $name?';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: TkSpace.screenMobile,
            children: [
              Text(title, style: TkText.h2, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Center(
                child: TkStars(
                  value: _stars,
                  size: 38,
                  onChanged: (v) => setState(() => _stars = v),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in f.allowedTags)
                    TkChip(
                      label: tag,
                      selected: _tags.contains(tag),
                      onTap: () => setState(
                        () => _tags.contains(tag) ? _tags.remove(tag) : _tags.add(tag),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TkTextField(
                controller: _text,
                label: 'Отзыв (необязательно)',
                hint: 'Расскажите, как всё прошло — это поможет другим',
                maxLines: 3,
                maxLength: 500,
              ),
              if (_asksIssue) ...[
                const SizedBox(height: 12),
                TkTextField(
                  controller: _issue,
                  label: 'Что пошло не так? (необязательно)',
                  hint: 'Видит только модерация, в отзыве это не появится',
                  maxLines: 2,
                  maxLength: 500,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Отзывы публикуются одновременно после обеих оценок либо через неделю',
                textAlign: TextAlign.center,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_stars == 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Поставьте оценку от 1 до 5 звёзд',
                      textAlign: TextAlign.center,
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                FilledButton(
                  onPressed: _stars == 0 || _busy ? null : _send,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Отправить оценку'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
