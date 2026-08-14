-- Откат первой миграции notifications.
DROP TABLE IF EXISTS notifications.outbox;
DROP TABLE IF EXISTS notifications.devices;
DROP SCHEMA IF EXISTS notifications;
