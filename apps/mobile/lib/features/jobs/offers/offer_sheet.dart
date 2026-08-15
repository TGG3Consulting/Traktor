import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../../equipment/equipment_providers.dart';
import 'offers_providers.dart';

/// Шит отклика исполнителя (ТЗ §2.8: «Предложить свою» — цена, комментарий,
/// когда сможет).
///
/// Второстепенные сценарии живут в шитах, а не в отдельных экранах (§1.10):
/// исполнитель видит задание за шитом и не теряет контекст.
Future<bool?> showOfferSheet(
  BuildContext context, {
  required String jobId,
  required int jobPrice,
  required String currency,
  Offer? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OfferSheet(
      jobId: jobId,
      jobPrice: jobPrice,
      currency: currency,
      existing: existing,
    ),
  );
}

class _OfferSheet extends ConsumerStatefulWidget {
  const _OfferSheet({
    required this.jobId,
    required this.jobPrice,
    required this.currency,
    this.existing,
  });

  final String jobId;
  final int jobPrice;
  final String currency;
  final Offer? existing;

  @override
  ConsumerState<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends ConsumerState<_OfferSheet> {
  late final TextEditingController _price;
  late final TextEditingController _comment;
  late final TextEditingController _eta;
  late String _kind;
  String? _unitId;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e?.kind ?? 'accept';
    _price = TextEditingController(text: '${e?.price ?? widget.jobPrice}');
    _comment = TextEditingController(text: e?.comment ?? '');
    _eta = TextEditingController(text: e?.eta ?? '');
    _unitId = e?.unitId;
  }

  @override
  void dispose() {
    _price.dispose();
    _comment.dispose();
    _eta.dispose();
    super.dispose();
  }

  int get _priceValue => int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(offerActionsProvider).make(
            widget.jobId,
            kind: _kind,
            price: _kind == 'accept' ? widget.jobPrice : _priceValue,
            comment: _comment.text.trim(),
            eta: _eta.text.trim(),
            unitId: _unitId,
          );
      if (mounted) Navigator.pop(context, true);
    } on ValidationException catch (e) {
      setState(() {
        _sending = false;
        _error = e.fields.values.join('\n');
      });
    } on ApiException catch (e) {
      setState(() {
        _sending = false;
        _error = e.detail;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final l = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TkRadius.sheet)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(widget.existing == null ? l.offerSheetTitle : l.offerSheetEdit,
                  style: TkText.h2),
              const SizedBox(height: 4),
              Text(
                l.offerCommitment,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _KindButton(
                      label: l.acceptPrice(tkMoney(widget.jobPrice, currency: widget.currency)),
                      selected: _kind == 'accept',
                      onTap: () => setState(() {
                        _kind = 'accept';
                        _price.text = '${widget.jobPrice}';
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KindButton(
                      label: l.ownPrice,
                      selected: _kind == 'counter',
                      onTap: () => setState(() => _kind = 'counter'),
                    ),
                  ),
                ],
              ),
              if (_kind == 'counter') ...[
                const SizedBox(height: 14),
                TkTextField(
                  label: l.yourPriceField,
                  controller: _price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  helper: l.jobPriceIs(tkMoney(widget.jobPrice, currency: widget.currency)),
                ),
              ],
              // Чем откликаемся: заказчику важно видеть машину, а нам —
              // что она своя и опубликована (ТЗ §2.5).
              _UnitPicker(
                selected: _unitId,
                onSelected: (id) => setState(() => _unitId = id),
              ),
              const SizedBox(height: 14),
              TkTextField(
                label: l.whenCan,
                controller: _eta,
                hint: l.whenCanHint,
              ),
              const SizedBox(height: 14),
              TkTextField(
                label: l.commentLabel,
                controller: _comment,
                hint: l.commentHint,
                maxLines: 3,
                maxLength: 200,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TkColors.error.withValues(alpha: 0.12),
                    borderRadius: TkRadius.cardR,
                  ),
                  child: Text(_error!, style: TkText.caption.copyWith(color: TkColors.error)),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _sending || (_kind == 'counter' && _priceValue <= 0) ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.existing == null ? l.sendOffer : l.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? TkColors.primary.withValues(alpha: 0.12) : scheme.surface,
      borderRadius: TkRadius.buttonR,
      child: InkWell(
        borderRadius: TkRadius.buttonR,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: TkRadius.buttonR,
            border: Border.all(color: selected ? TkColors.primary : scheme.outlineVariant),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TkText.caption.copyWith(
                color: selected ? TkColors.primary : scheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Выбор техники для отклика. Показывается только если техника есть: пустой
/// блок с надписью «нет техники» в шите отклика только мешает.
class _UnitPicker extends ConsumerWidget {
  const _UnitPicker({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final all = ref.watch(myEquipmentProvider).valueOrNull ?? const <Equipment>[];
    final active = all.where((e) => e.isActive).toList();
    if (active.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(l.withWhat, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in active)
              TkChip(
                label: e.title,
                selected: selected == e.id,
                // Повторное нажатие снимает выбор: часть заданий не требует
                // конкретной машины.
                onTap: () => onSelected(selected == e.id ? null : e.id),
              ),
          ],
        ),
      ],
    );
  }
}
