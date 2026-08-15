import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dispute_providers.dart';

/// Открытие спора по сделке (ТЗ §4.1).
///
/// Спор — не кнопка «пожаловаться», а обращение к арбитру: модератор увидит
/// сделку целиком. Поэтому просим описать проблему словами, а не выбрать
/// причину из списка: список причин упрощает разбор до бессмыслицы.
Future<bool?> showDisputeSheet(BuildContext context, {required String dealId}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DisputeSheet(dealId: dealId),
  );
}

class _DisputeSheet extends ConsumerStatefulWidget {
  const _DisputeSheet({required this.dealId});

  final String dealId;

  @override
  ConsumerState<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends ConsumerState<_DisputeSheet> {
  final _reason = TextEditingController();
  bool _sending = false;
  String? _error;

  static const _minLength = 20;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(disputeActionsProvider).open(widget.dealId, _reason.text.trim());
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
              const Text('Открыть спор', style: TkText.h2),
              const SizedBox(height: 6),
              Text(
                'Опишите, что пошло не так. Модератор посмотрит переписку, фотографии '
                'и отметки времени по сделке и вынесет решение с объяснением — его '
                'получите вы оба.',
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TkTextField(
                controller: _reason,
                label: 'Что случилось',
                hint: 'Например: договаривались на 40 метров траншеи, выкопано 20',
                maxLines: 4,
                maxLength: 1000,
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
                    : const Text('Отправить на разбор'),
              ),
              const SizedBox(height: 8),
              Text(
                'Пока идёт разбор, оценки по сделке не выставляются.',
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
