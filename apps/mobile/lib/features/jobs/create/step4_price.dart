import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'wizard_controller.dart';
import 'wizard_scaffold.dart';

/// Шаг 4 из 5 — цена и режим (ТЗ §2.6, прототип `create4`).
///
/// Здесь заказчик выбирает, как считать цену: фиксированная — исполнители
/// принимают или предлагают своё; обратный аукцион — торгуются вниз.
/// Резервная цена скрыта от исполнителей: об этом честно написано рядом.
class CreateStep4 extends ConsumerStatefulWidget {
  const CreateStep4({super.key});

  @override
  ConsumerState<CreateStep4> createState() => _CreateStep4State();
}

class _CreateStep4State extends ConsumerState<CreateStep4> {
  late final TextEditingController _budget;
  late final TextEditingController _reserve;
  String _mode = 'fixed';
  int _durationH = 24;
  bool _autoExtend = true;
  int _decisionWindowH = 12;
  int _workers = 0;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(wizardControllerProvider).job;
    _budget = TextEditingController(text: draft?.budgetAmount?.toString() ?? '');
    _reserve = TextEditingController(text: draft?.auction?.reserveAmount?.toString() ?? '');
    _mode = draft?.mode ?? 'fixed';
    _durationH = draft?.auction?.durationH ?? 24;
    _autoExtend = draft?.auction?.autoExtend ?? true;
    _decisionWindowH = draft?.auction?.decisionWindowH ?? 12;
    _workers = draft?.workersCount ?? 0;
  }

  @override
  void dispose() {
    _budget.dispose();
    _reserve.dispose();
    super.dispose();
  }

  int? get _budgetValue => int.tryParse(_budget.text.replaceAll(RegExp(r'[^0-9]'), ''));
  int? get _reserveValue => int.tryParse(_reserve.text.replaceAll(RegExp(r'[^0-9]'), ''));

  /// Резерв выше стартовой цены делает торг невозможным — ловим это до
  /// отправки, чтобы человек не получил отказ на последнем шаге.
  String? get _reserveError {
    final r = _reserveValue, b = _budgetValue;
    if (_mode != 'auction' || r == null || b == null) return null;
    return r > b ? 'Выше стартовой цены — тогда ни одна ставка не пройдёт' : null;
  }

  bool get _valid =>
      (_budgetValue ?? 0) > 0 && _reserveError == null;

  Future<void> _next() async {
    final ok = await ref.read(wizardControllerProvider.notifier).save(
          JobDraftInput(
            budgetAmount: _budgetValue,
            currency: 'AMD',
            mode: _mode,
            workersCount: _workers,
            auction: _mode == 'auction'
                ? AuctionSettings(
                    durationH: _durationH,
                    reserveAmount: _reserveValue,
                    autoExtend: _autoExtend,
                    decisionWindowH: _decisionWindowH,
                  )
                : null,
            draftStep: 5,
          ),
          goToStep: 5,
        );
    if (ok && mounted) context.go('/jobs/create/5');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wizardControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return WizardScaffold(
      step: 4,
      subtitle: 'Цена и режим',
      onBack: () => context.go('/jobs/create/3'),
      error: state.error,
      saving: state.saving,
      primaryLabel: 'Далее',
      onPrimary: _valid ? _next : null,
      hint: 'Укажите цену — без неё исполнителям не на что ориентироваться',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          TkTextField(
            label: _mode == 'auction' ? 'Стартовая цена, ֏' : 'Цена, ֏',
            controller: _budget,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            helper: _budgetValue == null
                ? 'Подсказка по похожим заданиям появится, когда наберётся статистика'
                : tkMoney(_budgetValue),
          ),
          const SizedBox(height: 18),
          _ModeSwitch(
            mode: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 14),
          if (_mode == 'auction') ...[
            TkCard(
              child: Column(
                children: [
                  _Row(
                    title: 'Длительность',
                    child: Wrap(
                      spacing: 6,
                      children: [6, 12, 24, 48]
                          .map((h) => TkChip(
                                label: '$h ч',
                                selected: _durationH == h,
                                onTap: () => setState(() => _durationH = h),
                              ))
                          .toList(),
                    ),
                  ),
                  const Divider(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TkTextField(
                        label: 'Минимальная цена (необязательно), ֏',
                        controller: _reserve,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        error: _reserveError,
                        onChanged: (_) => setState(() {}),
                        helper: 'Скрыта от исполнителей. Ставки ниже неё не рассматриваются.',
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  _Row(
                    title: 'Автопродление +10 минут',
                    subtitle: 'при ставке в последние 5 минут',
                    child: Switch(
                      value: _autoExtend,
                      onChanged: (v) => setState(() => _autoExtend = v),
                    ),
                  ),
                  const Divider(height: 20),
                  _Row(
                    title: 'Окно моего решения',
                    subtitle: 'сколько у вас будет времени выбрать победителя',
                    child: Wrap(
                      spacing: 6,
                      children: [6, 12, 24]
                          .map((h) => TkChip(
                                label: '$h ч',
                                selected: _decisionWindowH == h,
                                onTap: () => setState(() => _decisionWindowH = h),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
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
                      'Исполнители соревнуются, снижая цену. Вы выбираете победителя сами — '
                      'платформа лишь советует лучшего по цене, рейтингу и близости.',
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          TkCard(
            child: _Row(
              title: 'Нужны разнорабочие',
              subtitle: 'в дополнение к технике',
              child: Row(
                children: [
                  IconButton(
                    onPressed: _workers > 0 ? () => setState(() => _workers--) : null,
                    icon: TkIcon(TkIcons.minus, size: 14, color: scheme.onSurfaceVariant),
                    tooltip: 'Меньше',
                  ),
                  Text('$_workers', style: TkText.h3),
                  IconButton(
                    onPressed: _workers < 20 ? () => setState(() => _workers++) : null,
                    icon: TkIcon(TkIcons.plus, size: 14, color: scheme.onSurfaceVariant),
                    tooltip: 'Больше',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Переключатель режима: два равных варианта, выбранный залит цветом бренда.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(String value, String label, String icon) {
      final selected = mode == value;
      return Expanded(
        child: Material(
          color: selected ? TkColors.primary : scheme.surface,
          borderRadius: TkRadius.buttonR,
          child: InkWell(
            borderRadius: TkRadius.buttonR,
            onTap: () => onChanged(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TkIcon(icon, size: 16, color: selected ? Colors.white : scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TkText.body.copyWith(
                      color: selected ? Colors.white : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: TkRadius.buttonR,
      ),
      child: Row(
        children: [
          item('fixed', 'Фиксированная', TkIcons.money),
          const SizedBox(width: 4),
          item('auction', 'Аукцион', TkIcons.lightning),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TkText.body),
              if (subtitle != null)
                Text(subtitle!,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        child,
      ],
    );
  }
}
