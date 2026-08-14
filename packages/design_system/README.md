# design_system

Дизайн-система Traktor. **Единственный источник визуала** в приложении — из брендбука `design/brand/` (логотип концепт B «T-балка»). В фичах запрещён хардкод цветов/радиусов — только через эти токены и компоненты (правило 8 ORCHESTRATOR).

## Состав

- `tokens.dart` — цвета, радиусы, отступы, типографика (синхронно с `design/brand/tokens.dart`).
- `status.dart` — единая статусная карта заказа/сделки (ТЗ §1.10): цвет + ключ локализации.
- `theme.dart` — светлая и тёмная `ThemeData` (обе обязательны, ТЗ §1.7). Задаётся один раз в корне приложения.
- `components/` — UI-kit (ТЗ §1.10): `TkButton`, `TkStatusBadge`, `TkChip`, `TkCard`, `TkTextField`. Дальше добавляются: bottom sheet, диалог подтверждения, toast/undo, skeleton, empty state, рейтинг-звёзды, таймер аукциона, степпер визарда.

## Использование

```dart
import 'package:design_system/design_system.dart';

MaterialApp(
  theme: TkTheme.light,
  darkTheme: TkTheme.dark,
  themeMode: ThemeMode.system, // светлая/тёмная/системная (ТЗ §1.7)
  home: Scaffold(
    body: Column(children: [
      TkButton(label: 'Опубликовать', onPressed: () {}),
      TkStatusBadge(status: TkStatus.bidding, label: l10n.status_bidding),
      TkChip(label: 'Аукцион', selected: true),
    ]),
  ),
);
```

## Проверка

`flutter test` (в `test/`) — токены совпадают с брендбуком, статусы уникальны, темы строятся, компоненты рендерятся и кликаются. Прогоняется в CI (`melos run test`).

## Шрифты

Inter (лат/кир) + Noto Sans Armenian (hy). На проде — self-host (bundle) вместо google_fonts для оффлайна и скорости; интерфейс уже это учитывает.
