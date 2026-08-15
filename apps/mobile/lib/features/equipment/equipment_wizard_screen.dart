import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_settings.dart';
import '../jobs/spec_labels.dart';
import 'photo_picker.dart';
import 'equipment_providers.dart';

/// Визард добавления техники (ТЗ §2.5, прототип `equip_w1`…`equip_w4`).
///
/// Четыре шага: категория → данные и тарифы → фото → документы. Черновик
/// сохраняется на каждом шаге, поэтому закрытое приложение не стоит человеку
/// заново заполненной формы.
class EquipmentWizardScreen extends ConsumerStatefulWidget {
  const EquipmentWizardScreen({super.key, required this.equipmentId, required this.step});

  final String equipmentId;
  final int step;

  @override
  ConsumerState<EquipmentWizardScreen> createState() => _EquipmentWizardScreenState();
}

class _EquipmentWizardScreenState extends ConsumerState<EquipmentWizardScreen> {
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _hour = TextEditingController();
  final _shift = TextEditingController();
  final _day = TextEditingController();
  final _minHours = TextEditingController();
  final _delivery = TextEditingController();
  final _crewPrice = TextEditingController();
  final _specs = <String, String>{};

  Equipment? _item;
  String? _categoryId;
  List<String> _photos = const [];
  List<String> _docs = const [];
  int _crewSize = 0;
  bool _busy = false;
  bool _loaded = false;
  Map<String, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _brand, _model, _year, _hour, _shift, _day, _minHours, _delivery, _crewPrice
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final list = await ref.read(myEquipmentProvider.future);
    final item = list.where((e) => e.id == widget.equipmentId).firstOrNull;
    if (!mounted || item == null) {
      setState(() => _loaded = true);
      return;
    }
    setState(() {
      _item = item;
      _categoryId = item.categoryId.isEmpty ? null : item.categoryId;
      _brand.text = item.brand;
      _model.text = item.model;
      _year.text = item.year?.toString() ?? '';
      _hour.text = item.priceHour?.toString() ?? '';
      _shift.text = item.priceShift?.toString() ?? '';
      _day.text = item.priceDay?.toString() ?? '';
      _minHours.text = item.minHours?.toString() ?? '';
      _delivery.text = item.delivery?.toString() ?? '';
      _crewPrice.text = item.crewPrice?.toString() ?? '';
      _crewSize = item.crewSize;
      _photos = item.photos;
      for (final entry in item.specs.entries) {
        _specs[entry.key] = '${entry.value}';
      }
      _loaded = true;
    });
  }

  int? _int(TextEditingController c) {
    final raw = c.text.replaceAll(RegExp(r'[^0-9]'), '');
    return raw.isEmpty ? null : int.tryParse(raw);
  }

  /// Сохранение текущего шага. Идёт на каждом переходе: черновик должен
  /// переживать закрытие приложения (ТЗ §2.5).
  Future<bool> _save({required int nextStep}) async {
    setState(() => _busy = true);
    try {
      final specs = <String, dynamic>{};
      for (final entry in _specs.entries) {
        final v = entry.value.trim();
        if (v.isEmpty) continue;
        specs[entry.key] = num.tryParse(v.replaceAll(',', '.')) ?? v;
      }
      final updated = await ref.read(equipmentActionsProvider).patch(
            widget.equipmentId,
            categoryId: _categoryId,
            brand: _brand.text.trim(),
            model: _model.text.trim(),
            year: _int(_year),
            specs: specs,
            priceHour: _int(_hour),
            priceShift: _int(_shift),
            priceDay: _int(_day),
            minHours: _int(_minHours),
            delivery: _int(_delivery),
            crewSize: _crewSize,
            crewPrice: _int(_crewPrice),
            photos: _photos,
            draftStep: nextStep,
          );
      if (mounted) setState(() => _item = updated);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не сохранилось: $e')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next() async {
    final step = widget.step;
    if (step == 1 && _categoryId == null) return;
    if (!await _save(nextStep: step + 1)) return;
    if (!mounted) return;
    context.push('/equipment/${widget.equipmentId}/edit/${step + 1}');
  }

  /// Добавить снимки: выбор из галереи, загрузка в хранилище, сохранение
  /// адресов в карточке. Всё в одном действии — человеку не нужно понимать,
  /// что где-то есть отдельный «загрузить».
  Future<void> _addPhotos() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final urls = await ref.read(photoUploaderProvider).pickAndUpload(
            folder: 'equipment',
            limit: 8 - _photos.length,
          );
      if (urls.isEmpty || !mounted) return;
      setState(() => _photos = [..._photos, ...urls].take(8).toList());
      await ref.read(equipmentActionsProvider).patch(widget.equipmentId, photos: _photos);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Фото не загрузилось: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(int index) async {
    final next = [..._photos]..removeAt(index);
    setState(() => _photos = next);
    await ref.read(equipmentActionsProvider).patch(widget.equipmentId, photos: next);
  }

  /// Документы для бейджа «Проверен»: те же снимки, но в закрытый раздел.
  Future<void> _addDocs() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final urls = await ref.read(photoUploaderProvider).pickAndUpload(
            folder: 'docs',
            limit: 4 - _docs.length,
          );
      if (urls.isEmpty || !mounted) return;
      setState(() => _docs = [..._docs, ...urls].take(4).toList());
      await ref.read(equipmentActionsProvider).patch(widget.equipmentId, docs: _docs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Документ не загрузился: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Финал визарда. С документами — на проверку, без них — сразу в работу.
  Future<void> _submit({required bool withDocs}) async {
    if (!await _save(nextStep: 4)) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(equipmentActionsProvider).submit(widget.equipmentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isPending
              ? 'Отправлено на проверку — ответ придёт в течение суток'
              : 'Опубликовано со статусом «Без проверки»'),
        ),
      );
      context.go('/equipment');
    } catch (e) {
      if (!mounted) return;
      final fields = _fieldsFrom(e);
      if (fields.isNotEmpty) {
        setState(() => _errors = fields);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(fields.values.first)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не отправилось: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Сервер возвращает незаполненные поля — подсвечиваем их, а не показываем
  /// одну общую ошибку на весь визард.
  Map<String, String> _fieldsFrom(Object e) {
    if (e is ValidationException) return e.fields;
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = widget.step.clamp(1, 4);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавление техники'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/equipment'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: !_loaded
          ? const TkSkeletonList(count: 2)
          : Column(
              children: [
                TkWizardSteps(total: 4, current: step),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Text(
                        'Шаг $step из 4 · ${_stepTitle(step)}',
                        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      if (_item != null && !_item!.isDraft)
                        Text(
                          'черновик сохранён',
                          style: TkText.caption.copyWith(color: TkColors.success),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _body(step)),
                _footer(step),
              ],
            ),
    );
  }

  static String _stepTitle(int step) => switch (step) {
        1 => 'Категория',
        2 => 'Данные машины',
        3 => 'Фото',
        _ => 'Документы',
      };

  Widget _body(int step) => switch (step) {
        1 => _CategoryStep(
            selected: _categoryId,
            onSelected: (id) => setState(() => _categoryId = id),
          ),
        2 => _dataStep(context),
        3 => _photoStep(context),
        _ => _docsStep(context),
      };

  static const _brandHints = ['JCB', 'CAT', 'Komatsu', 'Hitachi', 'МТЗ', 'КамАЗ'];

  /// Шаг 2: марка, модель, год, характеристики категории и тарифы аренды.
  Widget _dataStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lang = (ref.watch(appSettingsProvider).locale ?? const Locale('ru')).languageCode;
    final category = ref.watch(unitCategoryByIdProvider(_categoryId));
    final specs = category?.specTemplate ?? const <SpecField>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        TkTextField(
          controller: _brand,
          label: 'Марка',
          hint: 'JCB, CAT, КамАЗ…',
          error: _errors['brand'],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in _brandHints)
              TkChip(
                label: b,
                selected: _brand.text.trim().toLowerCase() == b.toLowerCase(),
                onTap: () => setState(() => _brand.text = b),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TkTextField(
                controller: _model,
                label: 'Модель',
                hint: '3CX',
                error: _errors['model'],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: TkTextField(
                controller: _year,
                label: 'Год',
                hint: '2019',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                error: _errors['year'],
              ),
            ),
          ],
        ),
        if (specs.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Характеристики', style: TkText.h3),
          const SizedBox(height: 8),
          for (final field in specs) ...[
            TkTextField(
              label: tkSpecTitle(category, field.key, lang),
              initialValue: _specs[field.key] ?? '',
              keyboardType: field.type == 'number'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              onChanged: (v) => _specs[field.key] = v,
            ),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 8),
        const Text('Тарифы аренды', style: TkText.h3),
        Text(
          'Чтобы технику можно было взять почасово. Не сдаёте в аренду — оставьте пустым.',
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _money(_hour, '֏/час')),
            const SizedBox(width: 10),
            Expanded(child: _money(_shift, '֏/смена')),
            const SizedBox(width: 10),
            Expanded(child: _money(_day, '֏/сутки')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _money(_minHours, 'Мин. заказ, ч')),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _money(_delivery, 'Подача на объект, ֏')),
          ],
        ),
        const SizedBox(height: 14),
        TkCard(
          child: Column(
            children: [
              Row(
                children: [
                  const TkIcon(TkIcons.user, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Есть бригада рабочих', style: TkText.body)),
                  Switch(
                    value: _crewSize > 0,
                    onChanged: (v) => setState(() => _crewSize = v ? 2 : 0),
                  ),
                ],
              ),
              if (_crewSize > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Человек: $_crewSize', style: TkText.caption),
                          Slider(
                            value: _crewSize.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '$_crewSize',
                            onChanged: (v) =>
                                setState(() => _crewSize = v.round()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _money(_crewPrice, '֏/чел/час')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _money(TextEditingController c, String label) => TkTextField(
        controller: c,
        label: label,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      );


  /// Шаг 3: фотографии. Первая — обложка в ленте откликов.
  Widget _photoStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _photos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: TkRadius.cardR,
                    child: Image.network(
                      _photos[i],
                      width: 104,
                      height: 104,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 104,
                        height: 104,
                        color: scheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: TkIcon(TkIcons.image, size: 22,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const BoxDecoration(
                          color: TkColors.primary,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: const Text('Обложка',
                            style: TextStyle(fontSize: 10, color: Colors.white)),
                      ),
                    ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: InkWell(
                      onTap: () => _removePhoto(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: TkIcon(TkIcons.x, size: 12, color: scheme.onSurface),
                      ),
                    ),
                  ),
                ],
              ),
            if (_photos.length < 8)
              InkWell(
                onTap: _busy ? null : _addPhotos,
                borderRadius: TkRadius.cardR,
                child: Container(
                  width: 104,
                  height: 104,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: TkRadius.cardR,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TkIcon(TkIcons.camera, size: 22, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 4),
                      Text('Добавить',
                          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Первое фото видят в ленте откликов — снимите технику сбоку при дневном '
          'свете. Чужие снимки из интернета проверку не проходят.',
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Шаг 4: документы. Развилка объясняет последствия обоих вариантов честно.
  Widget _docsStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const Text('Техпаспорт или свидетельство о регистрации', style: TkText.body),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final d in _docs)
              ClipRRect(
                borderRadius: TkRadius.cardR,
                child: Image.network(
                  d,
                  width: 120,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 120,
                    height: 84,
                    color: scheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: TkIcon(TkIcons.fileText, size: 20,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            if (_docs.length < 4)
              InkWell(
                onTap: _busy ? null : _addDocs,
                borderRadius: TkRadius.cardR,
                child: Container(
                  width: 120,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: TkRadius.cardR,
                  ),
                  child: TkIcon(TkIcons.camera, size: 20, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TkIcon(TkIcons.lock, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Документы видит только модерация — в профиле они не публикуются',
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  TkIcon(TkIcons.checkCircle, size: 18, color: TkColors.success),
                  SizedBox(width: 8),
                  Text('С документами', style: TkText.h3),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Проверка занимает до суток. После неё появляется бейдж «Проверен» — '
                'такие карточки получают заметно больше заказов и бонус в скоринге.',
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Пропустить пока', style: TkText.h3),
              const SizedBox(height: 6),
              Text(
                'Техника публикуется сразу со статусом «Без проверки»: ставки делать '
                'можно, но в скоринге она ниже. Документы добавляются в любой момент.',
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer(int step) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
            if (step == 1 && _categoryId == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Выберите вид техники — от него зависят характеристики',
                  textAlign: TextAlign.center,
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            if (step < 4)
              FilledButton(
                onPressed: _busy || (step == 1 && _categoryId == null) ? null : _next,
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Далее'),
              )
            else ...[
              FilledButton(
                onPressed: _busy || _docs.isEmpty ? null : () => _submit(withDocs: true),
                child: const Text('Отправить на проверку'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => _submit(withDocs: false),
                child: const Text('Пропустить и опубликовать'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Шаг 1: дерево категорий техники.
class _CategoryStep extends ConsumerWidget {
  const _CategoryStep({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lang = (ref.watch(appSettingsProvider).locale ?? const Locale('ru')).languageCode;
    final cats = ref.watch(unitCategoriesProvider);

    return cats.when(
      loading: () => const TkSkeletonList(count: 3),
      error: (e, _) => TkErrorState(
        message: '$e',
        onRetry: () => ref.invalidate(unitCategoriesProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const TkEmptyState(
            icon: TkIcons.wrench,
            title: 'Справочник техники пуст',
            description: 'Категории появятся после обновления каталога',
          );
        }
        // Виды без подкатегорий показываем одним блоком: заголовок, под
        // которым лежит единственный чип с тем же словом, выглядит как ошибка.
        final simple = list.where((c) => c.children.isEmpty).toList();
        final grouped = list.where((c) => c.children.isNotEmpty).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (simple.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in simple)
                    TkChip(
                      label: c.name.forLang(lang),
                      selected: selected == c.id,
                      onTap: () => onSelected(c.id),
                    ),
                ],
              ),
            ],
            for (final root in grouped) ...[
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(root.name.forLang(lang), style: TkText.h3),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final child in root.children)
                    TkChip(
                      label: child.name.forLang(lang),
                      selected: selected == child.id,
                      onTap: () => onSelected(child.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'От категории зависят характеристики на следующем шаге: у экскаватора '
              'спросим ковш и глубину, у самосвала — тоннаж и кузов.',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}
