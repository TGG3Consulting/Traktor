# Traktor — монорепо

Маркетплейс заданий и аренды техники (Армения). Единый репозиторий: клиенты (Flutter), сервисы (Go), инфраструктура (Terraform), контракты (OpenAPI + события).

> Управляющие документы проекта — в `docs/` (ТЗ, архитектура, план) и `ORCHESTRATOR.md` в корне. Визуал — только из брендбука `design/brand/`.

## Структура

```
apps/
  mobile/        Flutter iOS+Android (клиент заказчика и исполнителя)
  web/           Flutter Web (клиент + публичные SEO-страницы)
  admin/         Flutter Web (админ-панель — модерация, споры, каталог)
packages/
  design_system/ дизайн-система из брендбука: токены, темы, UI-kit (§1.10 ТЗ)
  api_client/    кодоген Dart-клиента из contracts/openapi (Фаза 2, шаг контрактов)
  realtime/      Centrifugo-клиент: reconnect, recovery, мультиплекс каналов
  l10n/          локализации hy / ru / en (ARB)
services/        Go-сервисы (identity, gateway, catalog, orders, auction, deals, …)
infra/terraform/ dev / stage / prod: GCP Cloud Run, Cloud SQL, Redis, Pub/Sub, Cloudflare
contracts/
  openapi/       единый контракт REST API (source of truth для api_client и серверов)
  events/        реестр схем доменных событий (JSON Schema, проверка совместимости в CI)
```

## Стек (архитектура v1.2, см. docs/arhitektura-v1.md)

Клиенты — Flutter 3 / Dart 3, Riverpod 2, go_router. Бэкенд — Go, GCP Cloud Run, PostgreSQL 16 + PostGIS, Pub/Sub (transactional outbox), Redis, Centrifugo (realtime), Cloudflare R2 (медиа), Typesense (поиск), MapLibre/OSM (карты). Firebase — только FCM/Crashlytics/Analytics/Remote Config.

## Инструменты

- **Melos** — управление Dart/Flutter-пакетами монорепо (`melos bootstrap`, `melos run analyze`).
- **CI** — GitHub Actions: lint → тесты → контрактные проверки → сборка → деплой dev.

## Статус (Фаза 2 — фундамент)

- [x] Структура монорепо
- [x] `packages/design_system` из брендбука (токены + темы + ядро UI-kit)
- [ ] Контракты OpenAPI + реестр событий, кодоген `api_client`
- [ ] Terraform dev/stage/prod
- [ ] Сервисы `gateway` + `identity` (Dexatel OTP, JWT)
- [ ] Каркасы Flutter-приложений: онбординг → SMS-вход → профиль → роли → темы → языки

Полный план фаз — `docs/plan-razrabotki.md`.
