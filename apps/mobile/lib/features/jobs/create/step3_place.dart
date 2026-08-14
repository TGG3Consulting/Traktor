import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'wizard_controller.dart';
import 'wizard_scaffold.dart';

/// Шаг 3 из 5 — где и когда (ТЗ §2.6).
///
/// Карта появится вместе с MapLibre; до тех пор место задаётся адресом и
/// выбором ориентира — иначе шаг вообще нельзя было бы пройти, а публиковать
/// задание без координат нельзя: без них оно не попадёт ни в чью ленту.
class CreateStep3 extends ConsumerStatefulWidget {
  const CreateStep3({super.key});

  @override
  ConsumerState<CreateStep3> createState() => _CreateStep3State();
}

class _CreateStep3State extends ConsumerState<CreateStep3> {
  late final TextEditingController _address;
  String _access = 'unknown';
  String _dateMode = 'asap';
  DateTime? _start;
  DateTime? _end;
  Geo? _geo;
  String _cityKey = 'yerevan';

  /// Ориентиры Армении: пока нет карты, это честный способ получить координаты
  /// с точностью города — по ним лента и расстояния уже работают.
  static const _cities = <String, ({String title, Geo geo})>{
    'yerevan': (title: 'Ереван', geo: Geo(40.1872, 44.5152)),
    'gyumri': (title: 'Гюмри', geo: Geo(40.7894, 43.8475)),
    'vanadzor': (title: 'Ванадзор', geo: Geo(40.8060, 44.4939)),
    'abovyan': (title: 'Абовян', geo: Geo(40.2681, 44.6270)),
    'ashtarak': (title: 'Аштарак', geo: Geo(40.2989, 44.3617)),
    'dilijan': (title: 'Дилижан', geo: Geo(40.7408, 44.8620)),
    'ijevan': (title: 'Иджеван', geo: Geo(40.8792, 45.1486)),
    'kapan': (title: 'Капан', geo: Geo(39.2072, 46.4053)),
  };

  @override
  void initState() {
    super.initState();
    final draft = ref.read(wizardControllerProvider).job;
    _address = TextEditingController(text: draft?.address ?? '');
    _access = draft?.access ?? 'unknown';
    _dateMode = draft?.dateMode ?? 'asap';
    _start = draft?.dateStart;
    _end = draft?.dateEnd;
    _geo = draft?.geo ?? _cities[_cityKey]!.geo;
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_address.text.trim().isEmpty || _geo == null) return false;
    if (_dateMode == 'exact') return _start != null;
    if (_dateMode == 'range') return _start != null && _end != null && !_end!.isBefore(_start!);
    return true;
  }

  Future<void> _next() async {
    final ok = await ref.read(wizardControllerProvider.notifier).save(
          JobDraftInput(
            address: _address.text.trim(),
            geo: _geo,
            access: _access,
            dateMode: _dateMode,
            dateStart: _dateMode == 'asap' ? null : _start,
            dateEnd: _dateMode == 'range' ? _end : null,
            draftStep: 4,
          ),
          goToStep: 4,
        );
    if (ok && mounted) context.go('/jobs/create/4');
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        // Конец раньше начала — бессмыслица, поправляем сразу.
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wizardControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return WizardScaffold(
      step: 3,
      subtitle: 'Где и когда',
      onBack: () => context.go('/jobs/create/2'),
      error: state.error,
      saving: state.saving,
      primaryLabel: 'Далее',
      onPrimary: _valid ? _next : null,
      hint: _address.text.trim().isEmpty
          ? 'Укажите адрес — исполнители ищут работу рядом с собой'
          : 'Укажите даты',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const Text('Где', style: TkText.h3),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cities.entries
                .map((e) => TkChip(
                      label: e.value.title,
                      selected: _cityKey == e.key,
                      onTap: () => setState(() {
                        _cityKey = e.key;
                        _geo = e.value.geo;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          TkTextField(
            label: 'Адрес или ориентир',
            controller: _address,
            hint: 'Улица, дом, ориентир',
            onChanged: (_) => setState(() {}),
            helper: 'Точный адрес увидит только выбранный исполнитель — '
                'до сделки в ленте видна примерная зона.',
          ),
          const SizedBox(height: 16),
          const Text('Подъезд для техники', style: TkText.h3),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TkChip(
                label: 'Есть',
                selected: _access == 'yes',
                onTap: () => setState(() => _access = 'yes'),
              ),
              TkChip(
                label: 'Нет',
                selected: _access == 'no',
                onTap: () => setState(() => _access = 'no'),
              ),
              TkChip(
                label: 'Не знаю',
                selected: _access == 'unknown',
                onTap: () => setState(() => _access = 'unknown'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Когда', style: TkText.h3),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TkChip(
                label: 'Как можно скорее',
                selected: _dateMode == 'asap',
                onTap: () => setState(() => _dateMode = 'asap'),
              ),
              TkChip(
                label: 'Диапазон дат',
                selected: _dateMode == 'range',
                onTap: () => setState(() => _dateMode = 'range'),
              ),
              TkChip(
                label: 'Точная дата',
                selected: _dateMode == 'exact',
                onTap: () => setState(() => _dateMode = 'exact'),
              ),
            ],
          ),
          if (_dateMode != 'asap') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: _dateMode == 'range' ? 'Начало' : 'Дата',
                    value: _start,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                if (_dateMode == 'range') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateButton(
                      label: 'Конец',
                      value: _end,
                      onTap: () => _pickDate(isStart: false),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: TkRadius.cardR,
            ),
            child: Row(
              children: [
                TkIcon(TkIcons.mapPin, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Карта с точкой появится здесь вместе с картами MapLibre. '
                    'Сейчас место берём по выбранному городу — лента и расстояния уже работают.',
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TkIcon(TkIcons.calendar, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(value == null ? label : tkShortDate(value)),
        ],
      ),
    );
  }
}
