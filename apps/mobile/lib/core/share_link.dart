import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ссылки, которыми делятся (ТЗ §4.2).
///
/// Адрес без решётки: часть после неё на сервер не отправляется, и бот
/// мессенджера собрал бы превью из пустой страницы. Так у ссылки в WhatsApp
/// появляется карточка с названием, ценой и фотографией — по такой переходят,
/// по голой не переходят.
class TkShare {
  TkShare._();

  static const _base = 'https://app.homly.am';

  static String job(String id) => '$_base/jobs/$id';

  static String user(String id) => '$_base/users/$id';

  /// Кладёт ссылку в буфер и говорит об этом человеку. Системного «Поделиться»
  /// в вебе нет, а копирование работает везде одинаково.
  static Future<void> copy(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка скопирована — можно отправить в мессенджер')),
    );
  }

  /// Кнопка в шапке экрана.
  static Widget button(BuildContext context, String link) {
    return IconButton(
      tooltip: 'Поделиться',
      onPressed: () => copy(context, link),
      icon: TkIcon(TkIcons.share, size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
