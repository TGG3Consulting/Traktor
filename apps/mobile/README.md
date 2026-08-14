# traktor_mobile

Клиентское приложение Traktor (заказчик и исполнитель): iOS, Android, Web.
Вся вёрстка — из `packages/design_system` (брендбук `design/brand/`), сеть — через
`packages/api_client`, состояние — Riverpod, навигация — go_router.

## Как запустить

Проще всего — двойным кликом по скриптам (см. `КАК-ЗАПУСТИТЬ-ПРИЛОЖЕНИЕ.md` в корне):

- `scripts\app-demo.bat` — без сервера, код подтверждения **000000**;
- `scripts\app-real.bat` — с локальным бэкендом (порт 18080), код виден в окне identity.

Вручную:

```bash
flutter pub get
flutter gen-l10n
flutter run -d chrome                     # демо-режим, код 000000
flutter run -d chrome --dart-define=REAL_BACKEND=true \
                      --dart-define=API_BASE_URL=http://localhost:18080/v1
```

## Проверки

```bash
flutter analyze
flutter test
```

Платформы: web и windows сгенерированы (`flutter create . --platforms web,windows`).
Для android/ios папки создаются той же командой, когда будет установлен Android SDK
и появится доступ к Mac.
