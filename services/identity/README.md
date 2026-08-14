# identity

Сервис входа Traktor: OTP по SMS (Dexatel), JWT ES256 с ротацией refresh, профиль, JWKS. Реализует `contracts/openapi/traktor.yaml` (раздел identity).

Библиотеки (правило 23): `golang-jwt/jwt/v5` — выпуск и проверка токенов, `lestrrat-go/jwx/v2` — JWKS, `go-chi/chi/v5` — роутер, `jackc/pgx/v5` — Postgres, `golang-migrate/migrate/v4` — миграции. Самописной криптографии нет.

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

## Хранилище
`DATABASE_URL` пуст → in-memory (dev и тесты). Задан → Postgres через pgx; схема
накатывается автоматически при старте (`migrations/000001_init.up.sql`, своя таблица
версий `schema_migrations_identity`). Телефоны хранятся зашифрованными (pgcrypto),
поиск — по `phone_hash`; ключ шифрования — `PHONE_ENC_KEY` (обязателен при DATABASE_URL).

Интеграционные тесты БД: `scripts\pg-test.bat` (поднимает Postgres в Docker) или
`go test -tags integration ./internal/store/` с заданным `TEST_DATABASE_URL`.

## Границы (что доделывается дальше)
- Outbox-события (UserRegistered) — на шаге шины.
- Реальные поля Dexatel API — уточнить по их докам после аккаунта (интерфейс Provider не меняется).
- Фоновая чистка просроченных OTP и refresh-токенов.
