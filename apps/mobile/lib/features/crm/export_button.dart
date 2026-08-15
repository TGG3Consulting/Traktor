import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Выгрузка сделок за период (ТЗ §3.1 п.7, §3.2 п.6).
///
/// Отчёт нужен для бухгалтерии и налоговой, поэтому важнее не красота, а то,
/// чтобы файл открылся в Excel и не рассыпался: сервер отдаёт CSV с меткой
/// кодировки и точкой с запятой в разделителях.
class ExportButton extends ConsumerStatefulWidget {
  const ExportButton({super.key, required this.period, required this.asOwner});

  final String period;

  /// true — отчёт исполнителя (доходы), false — заказчика (расходы).
  final bool asOwner;

  @override
  ConsumerState<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<ExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(jobsApiProvider).exportDeals(
                  t,
                  period: widget.period,
                  asOwner: widget.asOwner,
                ),
          );
      if (!mounted) return;

      // Пока нет сохранения файла на всех платформах, кладём таблицу в буфер
      // обмена: её можно вставить в Excel или отправить бухгалтеру сообщением.
      // Это честнее пустой кнопки «скачать», которая ничего не делает.
      await Clipboard.setData(ClipboardData(text: String.fromCharCodes(bytes)));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Отчёт скопирован — вставьте в Excel или отправьте бухгалтеру'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не выгрузилось: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _export,
      icon: _busy
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const TkIcon(TkIcons.fileText, size: 18),
      label: const Text('Отчёт за период'),
    );
  }
}
