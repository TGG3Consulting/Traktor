# identity

Сервис входа Traktor: OTP по SMS (Dexatel), JWT ES256 с ротацией refresh, профиль, JWKS. Реализует `contracts/openapi/traktor.yaml` (раздел identity). Только стандартная библиотека Go — компилируется офлайн; продовый Postgres — по build-тегу `postgres`.

## Эндпоинты
- `POST /v1/auth/otp/start` — отправить код на телефон
- `POST /v1/auth/otp/verify` — проверить код → сессия (access+refresh+user)
- `POST /v1/auth/refresh` — обновить пару токенов (ротация, reuse-detection)
- `GET /v1/me` — профиль по Bearer-токену
- `GET /.well-known/jwks.json` — публичный ключ для проверки токенов другими сервисами
- `GET /healthz`

## Запуск (dev, без БД и без реальных SMS)
```bash
TEST_MODE=1 go run ./cmd/identity     # fake SMS, эфемерный ключ, in-memory store
```

## Переменные окружения
- `PORT` (по умолчанию 8080)
- `TEST_MODE=1` — fake SMS (коды не уходят реально)
- `DEXATEL_API_KEY`, `DEXATEL_SENDER` — прод-SMS
- `JWT_EC_PRIVATE_KEY_PEM` — приватный ключ ES256 (Secret Manager); в dev генерируется эфемерный
- `JWT_KID` — идентификатор ключа

## Тесты
```bash
go test ./...   # OTP-флоу, блокировка после 3 попыток, ротация refresh с reuse-detection
```

## Прод-сборка (с Postgres, в CI)
```bash
go build -tags postgres ./cmd/identity
```

## Границы (что доделывается на шаге поднятия БД)
- Postgres-реализация Store (сейчас in-memory) — по тегу `postgres`, схема в `migrations/0001_init.sql`.
- `/me` возвращает данные из claims; полный профиль — после GetUserByID в Postgres.
- Refresh сохраняет семью токенов; сквозная привязка к пользователю по ID — с реальной БД.
- Outbox-события (UserRegistered) — на шаге шины.
- Реальные поля Dexatel API — уточнить по их докам после аккаунта (интерфейс Provider не меняется).
