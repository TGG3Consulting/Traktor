import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../jobs_providers.dart';
import 'wizard_controller.dart';
import 'wizard_scaffold.dart';

/// Шаг 1 из 5 — что нужно сделать (ТЗ §2.6, прототип `create1`).
///
/// Крупные плитки категорий с иконками Phosphor плюс переключатель «опишу
/// задачу — пусть исполнители сами предложат технику»: не каждый заказчик
/// знает, какая машина ему нужна, и упереться в этот выбор — потерять заказ.
class CreateStep1 extends ConsumerStatefulWidget {
  const CreateStep1({super.key});

  @override
  ConsumerState<CreateStep1> createState() => _CreateStep1State();
}

class _CreateStep1State extends ConsumerState<CreateStep1> {
  String? _categoryId;
  bool _openToAny = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(wizardControllerProvider).job;
    _categoryId = draft?.categoryId;
    _openToAny = draft?.openToAny ?? false;
  }

  bool get _canContinue => _categoryId != null || _openToAny;

  Future<void> _next() async {
    final ok = await ref.read(wizardControllerProvider.notifier).save(
          JobDraftInput(
            categoryId: _categoryId ?? '',
            openToAny: _openToAny,
            draftStep: 2,
          ),
          goToStep: 2,
        );
    if (ok && mounted) context.go('/jobs/create/2');
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(workCategoriesProvider);
    final l = AppLocalizations.of(context);
    final state = ref.watch(wizardControllerProvider);

    return WizardScaffold(
      step: 1,
      subtitle: l.step1Title,
      onBack: () => context.go('/home'),
      error: state.error,
      primaryLabel: l.nextStep,
      onPrimary: _canContinue && !state.saving ? _next : null,
      hint: _canContinue ? null : l.step1Hint,
      child: categories.when(
        loading: () => const TkSkeletonList(count: 4),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(workCategoriesProvider),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            _Tiles(
              categories: list,
              selectedId: _categoryId,
              onSelect: (id) => setState(() {
                _categoryId = _categoryId == id ? null : id;
                if (_categoryId != null) _openToAny = false;
              }),
            ),
            const SizedBox(height: 16),
            TkCard(
              child: Row(
                children: [
                  const TkIcon(TkIcons.chatCircle, size: 22, color: TkColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.openToAny,
                      style: TkText.body,
                    ),
                  ),
                  Switch(
                    value: _openToAny,
                    onChanged: (v) => setState(() {
                      _openToAny = v;
                      if (v) _categoryId = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _OtherTypesHint(),
          ],
        ),
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.categories, required this.selectedId, required this.onSelect});

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.45,
      ),
      itemCount: categories.length,
      itemBuilder: (context, i) {
        final c = categories[i];
        final selected = c.id == selectedId;
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: selected ? TkColors.primary.withValues(alpha: 0.12) : scheme.surface,
          borderRadius: TkRadius.cardR,
          child: InkWell(
            borderRadius: TkRadius.cardR,
            onTap: () => onSelect(c.id),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: TkRadius.cardR,
                border: Border.all(
                  color: selected ? TkColors.primary : scheme.outlineVariant,
                  width: selected ? 1.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TkIcon(
                    TkIcons.byName(c.icon),
                    size: 28,
                    color: selected ? TkColors.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.name.forLang(lang),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TkText.body.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Подсказка про остальные типы заказа (ТЗ §5.1): человеку, которому нужна
/// просто техника на час, незачем описывать «задание».
class _OtherTypesHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: TkRadius.cardR,
      ),
      child: Row(
        children: [
          TkIcon(TkIcons.info, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Нужна не работа под ключ, а техника на время, грузовик или люди? '
              'Вернитесь назад и выберите другой тип заказа.',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
