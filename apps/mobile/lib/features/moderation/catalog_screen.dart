import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_refresh.dart';
import '../equipment/equipment_providers.dart';
import '../jobs/jobs_providers.dart';

/// Справочник у модерации (ТЗ §4.1, п.5).
///
/// Пока категории живут только в миграции, новый вид работ ждёт выката
/// сервиса: владелец не может отреагировать на спрос, пока не дойдут руки у
/// разработчика. Здесь тот же справочник правится на ходу.
final allCategoriesProvider =
    FutureProvider.family<List<Category>, String>((ref, kind) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).allCategories(t, kind: kind));
});

class CatalogEditScreen extends ConsumerStatefulWidget {
  const CatalogEditScreen({super.key});

  @override
  ConsumerState<CatalogEditScreen> createState() => _CatalogEditScreenState();
}

class _CatalogEditScreenState extends ConsumerState<CatalogEditScreen> {
  String _kind = 'work';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(allCategoriesProvider(_kind));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Справочник'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const TkIcon(TkIcons.plus, size: 18),
        label: const Text('Добавить'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                TkChip(
                  label: 'Работы',
                  selected: _kind == 'work',
                  onTap: () => setState(() => _kind = 'work'),
                ),
                const SizedBox(width: 8),
                TkChip(
                  label: 'Техника',
                  selected: _kind == 'unit',
                  onTap: () => setState(() => _kind = 'unit'),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const TkSkeletonList(count: 4),
              error: (e, _) => TkErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(allCategoriesProvider(_kind)),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const TkEmptyState(
                    icon: TkIcons.clipboardText,
                    title: 'Пусто',
                    description: 'Добавьте первую категорию — она появится в визарде сразу',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _CategoryRow(
                    category: list[i],
                    parentName: _parentName(list, list[i].parentId),
                    onEdit: () => _edit(context, list[i]),
                    onToggle: () => _toggle(list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _parentName(List<Category> all, String? parentId) {
    if (parentId == null) return '';
    for (final c in all) {
      if (c.id == parentId) return c.name.ru;
    }
    return '';
  }

  Future<void> _edit(BuildContext context, Category? current) async {
    final messenger = ScaffoldMessenger.of(context);
    final all = ref.read(allCategoriesProvider(_kind)).valueOrNull ?? const <Category>[];
    final result = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategorySheet(kind: _kind, current: current, all: all),
    );
    if (result == null) return;

    try {
      final api = ref.read(jobsApiProvider);
      await ref.read(sessionRefresherProvider).run((t) => current == null
          ? api.createCategory(t, result,
              idempotencyKey: 'cat-${result.slug}-${DateTime.now().microsecondsSinceEpoch}')
          : api.updateCategory(t, result,
              idempotencyKey: 'cat-${result.id}-${DateTime.now().microsecondsSinceEpoch}'));
      ref.invalidate(allCategoriesProvider(_kind));
      _refreshAppCatalog();
      messenger.showSnackBar(
        const SnackBar(content: Text('Справочник обновлён — изменения видны сразу')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.detail)));
    }
  }

  /// Справочник читают и обычные экраны: визард задания и визард техники.
  /// Без сброса их кэша правка появится только после перезапуска приложения.
  void _refreshAppCatalog() {
    ref.invalidate(workCategoriesProvider);
    ref.invalidate(unitCategoriesProvider);
  }

  Future<void> _toggle(Category c) async {
    try {
      await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(jobsApiProvider).setCategoryVisible(t, c.id, !c.active,
                idempotencyKey: 'vis-${c.id}-${DateTime.now().microsecondsSinceEpoch}'),
          );
      ref.invalidate(allCategoriesProvider(_kind));
      _refreshAppCatalog();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    }
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.parentName,
    required this.onEdit,
    required this.onToggle,
  });

  final Category category;
  final String parentName;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = category;

    return TkCard(
      onTap: onEdit,
      child: Row(
        children: [
          TkIcon(c.icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name.ru,
                  style: TkText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: c.active ? null : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    c.slug,
                    if (parentName.isNotEmpty) 'в «$parentName»',
                    if (c.specTemplate.isNotEmpty) 'полей: ${c.specTemplate.length}',
                  ].join(' · '),
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: c.active ? 'Скрыть' : 'Вернуть',
            onPressed: onToggle,
            icon: TkIcon(c.active ? TkIcons.eye : TkIcons.eyeSlash,
                size: 18, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Форма категории. Ключ задаётся один раз: по нему сходятся отчёты за прошлые
/// месяцы, поэтому при правке он показан, но не редактируется.
class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.kind, required this.current, required this.all});

  final String kind;
  final Category? current;
  final List<Category> all;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final TextEditingController _slug;
  late final TextEditingController _ru;
  late final TextEditingController _hy;
  late final TextEditingController _en;
  late final TextEditingController _icon;
  late final TextEditingController _sort;
  String? _parentId;
  late List<SpecField> _specs;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _slug = TextEditingController(text: c?.slug ?? '');
    _ru = TextEditingController(text: c?.name.ru ?? '');
    _hy = TextEditingController(text: c?.name.hy ?? '');
    _en = TextEditingController(text: c?.name.en ?? '');
    _icon = TextEditingController(text: c?.icon ?? 'wrench');
    _sort = TextEditingController(text: '${c?.sortOrder ?? 100}');
    _parentId = c?.parentId;
    _specs = List.of(c?.specTemplate ?? const []);
  }

  @override
  void dispose() {
    for (final c in [_slug, _ru, _hy, _en, _icon, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _ru.text.trim().isNotEmpty &&
      _hy.text.trim().isNotEmpty &&
      _en.text.trim().isNotEmpty &&
      (widget.current != null || _slug.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Родителем может быть только категория той же ветви и не она сама.
    final parents = widget.all
        .where((c) => c.id != widget.current?.id && c.parentId == null)
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TkRadius.sheet)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.current == null ? 'Новая категория' : 'Правка категории',
                  style: TkText.h2),
              const SizedBox(height: 12),
              if (widget.current == null)
                TkTextField(
                  controller: _slug,
                  label: 'Ключ',
                  hint: 'work-drilling — латиница, цифры и дефис',
                  onChanged: (_) => setState(() {}),
                )
              else
                Text('Ключ: ${widget.current!.slug} (не меняется — по нему сходятся отчёты)',
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              TkTextField(
                controller: _ru,
                label: 'Название (ру)',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TkTextField(
                controller: _hy,
                label: 'Название (հայ)',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TkTextField(
                controller: _en,
                label: 'Название (en)',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TkTextField(controller: _icon, label: 'Иконка Phosphor')),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: TkTextField(
                      controller: _sort,
                      label: 'Порядок',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Родитель', style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TkChip(
                    label: 'Верхний уровень',
                    selected: _parentId == null,
                    onTap: () => setState(() => _parentId = null),
                  ),
                  for (final p in parents)
                    TkChip(
                      label: p.name.ru,
                      selected: _parentId == p.id,
                      onTap: () => setState(() => _parentId = p.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Характеристики', style: TkText.h3),
                  const Spacer(),
                  TextButton(
                    onPressed: _addSpec,
                    child: const Text('Добавить поле'),
                  ),
                ],
              ),
              if (_specs.isEmpty)
                Text('Полей нет — визард покажет только общие шаги',
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant))
              else
                for (var i = 0; i < _specs.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_specs[i].label.ru} · ${_specs[i].key}'),
                    subtitle: Text(_specs[i].type),
                    trailing: IconButton(
                      tooltip: 'Убрать',
                      onPressed: () => setState(() => _specs.removeAt(i)),
                      icon: const TkIcon(TkIcons.trash, size: 18),
                    ),
                  ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _valid ? _save : null,
                child: const Text('Сохранить'),
              ),
              const SizedBox(height: 8),
              Text(
                'Изменения видны в приложении сразу, без обновления версии.',
                textAlign: TextAlign.center,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addSpec() async {
    final field = await showDialog<SpecField>(
      context: context,
      builder: (_) => const _SpecDialog(),
    );
    if (field != null) setState(() => _specs.add(field));
  }

  void _save() {
    final base = widget.current ??
        Category(
          id: '',
          kind: widget.kind,
          slug: _slug.text.trim(),
          name: const LocalizedName(),
        );
    Navigator.pop(
      context,
      base.copyWith(
        slug: widget.current?.slug ?? _slug.text.trim(),
        name: LocalizedName(
          hy: _hy.text.trim(),
          ru: _ru.text.trim(),
          en: _en.text.trim(),
        ),
        icon: _icon.text.trim(),
        sortOrder: int.tryParse(_sort.text.trim()) ?? 100,
        specTemplate: _specs,
        parentId: _parentId,
        clearParent: _parentId == null,
      ),
    );
  }
}

/// Одно поле характеристик. Тип определяет виджет в визарде, поэтому список
/// типов закрытый: незнакомый тип превратится в пустое место в форме.
class _SpecDialog extends StatefulWidget {
  const _SpecDialog();

  @override
  State<_SpecDialog> createState() => _SpecDialogState();
}

class _SpecDialogState extends State<_SpecDialog> {
  final _key = TextEditingController();
  final _label = TextEditingController();
  final _unit = TextEditingController();
  final _options = TextEditingController();
  String _type = 'number';

  @override
  void dispose() {
    for (final c in [_key, _label, _unit, _options]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _key.text.trim().isNotEmpty &&
      _label.text.trim().isNotEmpty &&
      (_type != 'select' || _options.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Поле характеристик'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TkTextField(
              controller: _key,
              label: 'Ключ',
              hint: 'depth — латиница, цифры и дефис',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TkTextField(
              controller: _label,
              label: 'Подпись (ру)',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final t in const ['number', 'text', 'select', 'bool'])
                  TkChip(
                    label: t,
                    selected: _type == t,
                    onTap: () => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_type == 'number')
              TkTextField(controller: _unit, label: 'Единица', hint: 'м, т, час'),
            if (_type == 'select')
              TkTextField(
                controller: _options,
                label: 'Варианты через запятую',
                hint: 'мягкий, скальный',
                onChanged: (_) => setState(() {}),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                    context,
                    SpecField(
                      key: _key.text.trim(),
                      type: _type,
                      unit: _unit.text.trim(),
                      options: _type == 'select'
                          ? _options.text
                              .split(',')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList()
                          : const [],
                      label: LocalizedName(ru: _label.text.trim()),
                    ),
                  )
              : null,
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
