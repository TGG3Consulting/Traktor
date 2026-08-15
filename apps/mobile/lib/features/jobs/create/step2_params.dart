import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../equipment/photo_picker.dart';
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
  List<String> _photos = const [];
  bool _uploading = false;

  static const _minDescription = 20; // ТЗ §2.6: описание не короче 20 символов

  @override
  void initState() {
    super.initState();
    final draft = ref.read(wizardControllerProvider).job;
    _title = TextEditingController(text: draft?.title ?? '');
    _description = TextEditingController(text: draft?.description ?? '');
    _params.addAll(draft?.params ?? const {});
    _photos = draft?.photos ?? const [];
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
            photos: _photos,
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
    final l = AppLocalizations.of(context);
    final left = _minDescription - _description.text.trim().length;

    return WizardScaffold(
      step: 2,
      subtitle: l.step2Title,
      onBack: () => context.go('/jobs/create/1'),
      error: state.error,
      saving: state.saving,
      primaryLabel: l.nextStep,
      onPrimary: _valid ? _next : null,
      hint: _title.text.trim().isEmpty ? l.step2Hint : l.addMoreChars(left),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          TkTextField(
            label: l.titleLabel,
            controller: _title,
            hint: l.titleHint,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TkTextField(
            label: l.descLabel,
            controller: _description,
            hint: _hintFor(category, l),
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            helper: l.descHelper(_minDescription),
          ),
          if (category != null && category.specTemplate.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(l.paramsTitle, style: TkText.h3),
            const SizedBox(height: 4),
            Text(
              l.paramsHint,
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
          Text(l.photosTitle, style: TkText.h3),
          const SizedBox(height: 4),
          Text(
            l.photosHint,
            style: TkText.caption
                .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TkPhotoGrid(
            photos: _photos,
            busy: _uploading,
            onAdd: _addPhotos,
            onRemove: (i) => setState(() => _photos = [..._photos]..removeAt(i)),
          ),
        ],
      ),
    );
  }

  /// Добавить фотографии места: выбор, сжатие и загрузка в хранилище.
  /// Адреса сохранятся вместе с остальными полями шага.
  Future<void> _addPhotos() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final urls = await ref.read(photoUploaderProvider).pickAndUpload(
            folder: 'jobs',
            limit: 8 - _photos.length,
          );
      if (urls.isEmpty || !mounted) return;
      setState(() => _photos = [..._photos, ...urls].take(8).toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).photoFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Подсказка-шаблон по категории (ТЗ §2.6 шаг 2).
  /// Подсказка зависит от вида работ: «опишите работу» ничего не подсказывает,
  /// а «длина и глубина траншеи» — подсказывает.
  String _hintFor(Category? c, AppLocalizations l) => switch (c?.slug) {
        'work-earth' => l.hintEarth,
        'work-transport' => l.hintTransport,
        'work-crane' => l.hintCrane,
        'work-demolition' => l.hintDemolition,
        'work-agro' => l.hintAgro,
        'work-clearing' => l.hintClearing,
        _ => l.hintOther,
      };
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
