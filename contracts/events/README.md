# Реестр доменных событий

Единый источник схем событий, которыми сервисы обмениваются через Pub/Sub (transactional outbox → шина). Правила:

- Одна схема на файл: `<domain>.<Event>.v<N>.json` (JSON Schema draft 2020-12).
- **Совместимость только назад:** новые поля — опциональные; удаление/переименование — новой версией `vN+1`, старая живёт, пока есть консьюмеры. CI проверяет диффы и валит ломающие изменения.
- Каждое событие несёт `eventId` (UUID, для идемпотентности консьюмера), `occurredAt` (UTC), `producer`, `payload`.
- Консьюмеры идемпотентны: `eventId` в таблице `processed_events`, повтор — no-op.

## Конверт (общий для всех событий)

```json
{
  "eventId": "uuid",
  "type": "auction.BidPlaced.v1",
  "occurredAt": "2026-08-13T14:32:05Z",
  "producer": "auction",
  "payload": { }
}
```

## Ключевые события v1 (по ТЗ + архитектуре)

identity: `UserRegistered`, `RoleSwitched`, `UserDeleted`
catalog: `EquipmentSubmitted`, `EquipmentApproved`, `EquipmentRejected`
orders: `JobPublished`, `JobUpdated`, `JobClosed`, `TransportRequested`
auction: `BidPlaced`, `BidOutbid`, `AuctionExtended`, `AuctionFinished`, `OfferMade`
deals: `DealConfirmed`, `DealStatusChanged`, `RentalExtended`, `RentalIdleStarted`, `DisputeOpened`
chat: `MessageSent`
reviews: `ReviewPublished`
media: `MediaProcessed`

`notifications` слушает все и делает fanout: FCM + Centrifugo + центр уведомлений (тихие часы, подписки-фильтры).
