import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../jobs_providers.dart';
import '../spec_labels.dart';
import 'wizard_controller.dart';
import 'wizard_scaffold.dart';

/// Шаг 2 из 5 — параметры (ТЗ §2.6).
///
/// Поля характеристик строятся из шаблона категории (specTemplate): добавить
/// категорию в справочник — и её поля появятся здесь без правок приложения.
class CreateStep2 extends ConsumerStatefulWidget {
  const CreateStep2({super.key});

  @override
  ConsumerState<CreateStep2> createState() => _CreateStep2State();
}

class _CreateStep2State extends ConsumerState<CreateStep2> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  final Map<String, dynamic> _params = {};

  static const _minDescription = 20; // ТЗ §2.6: описание не короче 20 символов

  @override
  void initState() {
    super.initState();
    final draft = ref.read(wizardControllerProvider).job;
    _title = TextEditingController(text: draft?.title ?? '');
    _description = TextEditingController(text: draft?.description ?? '');
    _params.addAll(draft?.params ?? const {});
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty &&
      _description.text.trim().length >= _minDescription;

  Future<void> _next() async {
    final ok = await ref.read(wizardControllerProvider.notifier).save(
          JobDraftInput(
            title: _title.text.trim(),
            description: _description.text.trim(),
            params: _params,
            draftStep: 3,
          ),
          goToStep: 3,
        );
    if (ok && mounted) context.go('/jobs/create/3');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wizardControllerProvider);
    final category = ref.watch(categoryByIdProvider(state.job?.categoryId));
    final lang = Localizations.localeOf(context).languageCode;
    final left = _minDescription - _description.text.trim().length;

    return WizardScaffold(
      step: 2,
      subtitle: 'Параметры',
      onBack: () => context.go('/jobs/create/1'),
      error: state.error,
      saving: state.saving,
      primaryLabel: 'Далее',
      onPrimary: _valid ? _next : null,
      hint: _title.text.trim().isEmpty
          ? 'Назовите задание — это первое, что видит исполнитель'
          : 'Добавьте ещё $left ${_charsWord(left)} описания',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          TkTextField(
            label: 'Название',
            controller: _title,
            hint: 'Например: выкопать траншею 40 м под водопровод',
            maxLength: 80,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TkTextField(
            label: 'Что нужно сделать',
            controller: _description,
            hint: _hintFor(category),
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            helper: 'Чем подробнее, тем точнее цены. Минимум $_minDescription символов.',
          ),
          if (category != null && category.specTemplate.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Параметры работы', style: TkText.h3),
            const SizedBox(height: 4),
            Text(
              'Необязательно, но с ними исполнители точнее считают цену',
              style: TkText.caption
                  .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            ...category.specTemplate.map((f) => _SpecInput(
                  field: f,
                  lang: lang,
                  value: _params[f.key],
                  onChanged: (v) => setState(() {
                    if (v == null) {
                      _params.remove(f.key);
                    } else {
                      _params[f.key] = v;
                    }
                  }),
                )),
          ],
          const SizedBox(height: 18),
          _PhotoHint(),
        ],
      ),
    );
  }

  /// Подсказка-шаблон по категории (ТЗ §2.6 шаг 2).
  String _hintFor(Category? c) => switch (c?.slug) {
        'work-earth' => 'Длина и глубина траншеи, тип грунта, есть ли подъезд для техники',
        'work-transport' => 'Что везём, вес и объём, откуда и куда, нужна ли погрузка',
        'work-crane' => 'Что поднимаем, вес, высота, сколько часов нужна техника',
        'work-demolition' => 'Что сносим, площадь и этажность, нужен ли вывоз мусора',
        'work-agro' => 'Площадь участка, вид работ, состояние поля',
        'work-clearing' => 'Площадь, что убрать, вывозить с участка или нет',
        _ => 'Опишите работу: объём, сроки, особенности участка',
      };

  String _charsWord(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'символов';
    return switch (n % 10) {
      1 => 'символ',
      2 || 3 || 4 => 'символа',
      _ => 'символов',
    };
  }
}

/// Поле характеристик по описанию из справочника.
class _SpecInput extends StatelessWidget {
  const _SpecInput({
    required this.field,
    required this.lang,
    required this.value,
    required this.onChanged,
  });

  final SpecField field;
  final String lang;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = field.label.forLang(lang).isEmpty ? field.key : field.label.forLang(lang);
    final scheme = Theme.of(context).colorScheme;

    switch (field.type) {
      case 'bool':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: TkText.body),
          value: value == true,
          onChanged: onChanged,
        );

      case 'select':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: field.options
                    .map((o) => TkChip(
                          label: tkOptionLabel(o),
                          selected: value == o,
                          onTap: () => onChanged(value == o ? null : o),
                        ))
                    .toList(),
              ),
            ],
          ),
        );

      case 'number':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TkTextField(
            label: field.unit.isEmpty ? label : '$label, ${field.unit}',
            initialValue: value?.toString() ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (v) {
              final normalized = v.replaceAll(',', '.').trim();
              if (normalized.isEmpty) return onChanged(null);
              onChanged(double.tryParse(normalized));
            },
          ),
        );

      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TkTextField(
            label: label,
            initialValue: value?.toString() ?? '',
            onChanged: (v) => onChanged(v.trim().isEmpty ? null : v.trim()),
          ),
        );
    }
  }

}

/// Фото места сильно повышают отклики (ТЗ §2.6). Загрузка появится вместе с
/// сервисом media — до тех пор честно говорим об этом, а не рисуем кнопку,
/// которая ничего не делает.
class _PhotoHint extends StatelessWidget {
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
          TkIcon(TkIcons.camera, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Фото места скоро можно будет прикрепить прямо здесь — с ними откликов заметно больше.',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
