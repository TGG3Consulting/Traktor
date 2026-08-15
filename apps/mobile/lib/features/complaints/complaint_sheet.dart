import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'complaint_providers.dart';

/// Жалоба на задание или человека (ТЗ §4.1, п.6).
///
/// В отличие от спора, здесь нет сделки и нет второй стороны: человек просто
/// увидел что-то неправильное. Поэтому короткая форма — повод, свои слова и
/// отправка. Если пожаловаться некуда, человек не жалуется, а уходит.
Future<bool?> showComplaintSheet(
  BuildContext context, {
  required String targetKind,
  required String targetId,
  required String targetTitle,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ComplaintSheet(
      targetKind: targetKind,
      targetId: targetId,
      targetTitle: targetTitle,
    ),
  );
}

/// Поводы: подсказки, а не жёсткий список. Выбранный повод подставляется в
/// поле как начало фразы — дописать своими словами всё равно придётся, иначе
/// модерации нечего смотреть.
const _jobReasons = [
  'Просят предоплату до начала работы',
  'В описании обман: на месте всё иначе',
  'Задание не про технику и работы',
  'Оскорбления или угрозы в тексте',
];

const _userReasons = [
  'Не выходит на связь после договорённости',
  'Ведёт себя грубо',
  'Просит оплату мимо площадки',
  'Похоже на чужой аккаунт',
];

class _ComplaintSheet extends ConsumerStatefulWidget {
  const _ComplaintSheet({
    required this.targetKind,
    required this.targetId,
    required this.targetTitle,
  });

  final String targetKind;
  final String targetId;
  final String targetTitle;

  @override
  ConsumerState<_ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends ConsumerState<_ComplaintSheet> {
  final _reason = TextEditingController();
  bool _sending = false;
  String? _error;

  static const _minLength = 10;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _pick(String hint) {
    setState(() {
      _reason.text = _reason.text.trim().isEmpty ? hint : '${_reason.text.trim()} $hint';
      _reason.selection = TextSelection.collapsed(offset: _reason.text.length);
    });
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(complaintActionsProvider).complain(
            targetKind: widget.targetKind,
            targetId: widget.targetId,
            reason: _reason.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
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
    final left = _minLength - _reason.text.trim().length;
    final hints = widget.targetKind == 'job' ? _jobReasons : _userReasons;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
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
              const Text('Пожаловаться', style: TkText.h2),
              const SizedBox(height: 4),
              if (widget.targetTitle.isNotEmpty)
                Text(
                  widget.targetTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final h in hints)
                    TkChip(label: h, selected: false, onTap: () => _pick(h)),
                ],
              ),
              const SizedBox(height: 12),
              TkTextField(
                controller: _reason,
                label: 'В чём проблема',
                hint: 'Своими словами — модератор будет смотреть по этому описанию',
                maxLines: 4,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                helper: left > 0 ? 'Ещё $left символов' : null,
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
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _sending || left > 0 ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Отправить'),
              ),
              const SizedBox(height: 8),
              Text(
                'Модерация смотрит жалобы по очереди. О решении вы узнаете '
                'в уведомлениях.',
                textAlign: TextAlign.center,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
