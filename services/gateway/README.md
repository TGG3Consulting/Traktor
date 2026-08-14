# gateway

Единая точка входа для клиентов Traktor. Проверяет JWT по JWKS сервиса `identity` (локально, без похода в identity на каждый запрос), ограничивает частоту, требует `Idempotency-Key` на мутациях (ТЗ §4.3), проксирует к сервисам. Только стандартная библиотека Go.

## Цепочка обработки
`CORS → rate-limit (на IP) → auth (Bearer, JWKS) → idempotency → reverse-proxy`

Публичные пути без авторизации и Idempotency-Key: `/healthz`, `/v1/auth/*`, `/.well-known/*`.
На проверенных запросах вниз прокидываются заголовки `X-User-Id`, `X-User-Role`.

## Маршруты (растут с сервисами)
- `/v1/auth/*`, `/v1/me`, `/.well-known/*` → identity

## Запуск (dev; рядом должен работать identity)
```bash
# терминал 1: identity
cd ../identity && TEST_MODE=1 PORT=8081 go run ./cmd/identity
# терминал 2: gateway
JWKS_URL=http://localhost:8081/.well-known/jwks.json IDENTITY_URL=http://localhost:8081 \
  PORT=8080 go run ./cmd/gateway
```

## Переменные окружения
`PORT`, `JWKS_URL`, `IDENTITY_URL`, `RATE_LIMIT` (по умолчанию 100), `RATE_WINDOW_SEC` (60), `ALLOW_ORIGIN`.

## Тесты
```bash
go test ./...   # JWKS-проверка (валид/истёк/чужая подпись/неизвестный kid), маршрутизация по префиксу
```

## Границы
- Хранилище идемпотентных ключей — в Redis на шаге кэша (сейчас проверяется наличие заголовка).
- Общий пакет проверки JWT (authjwt) вынесем в отдельный модуль при подключении module-proxy (сейчас проверка дублируется в identity и gateway — минимально).
