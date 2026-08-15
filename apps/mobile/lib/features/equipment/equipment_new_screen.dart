import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import 'equipment_providers.dart';

/// Точка входа в визард техники: заводит черновик на сервере и сразу открывает
/// первый шаг. Отдельный экран нужен, чтобы черновик создавался один раз — при
/// создании прямо из кнопки повторное нажатие плодило бы пустые карточки.
class EquipmentNewScreen extends ConsumerStatefulWidget {
  const EquipmentNewScreen({super.key});

  @override
  ConsumerState<EquipmentNewScreen> createState() => _EquipmentNewScreenState();
}

class _EquipmentNewScreenState extends ConsumerState<EquipmentNewScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final draft = await ref.read(equipmentActionsProvider).startDraft();
      if (!mounted) return;
      context.pushReplacement('/equipment/${draft.id}/edit/1');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.addEquipmentTitle)),
      body: _error == null
          ? const Center(child: CircularProgressIndicator())
          : TkErrorState(
              message: _error!,
              onRetry: () {
                setState(() => _error = null);
                _start();
              },
            ),
    );
  }
}
