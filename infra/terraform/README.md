# infra/terraform

Инфраструктура Traktor как код: GCP (Cloud Run, Cloud SQL Postgres 16, Memorystore Redis, Pub/Sub, Secret Manager, Artifact Registry, VPC-connector) + Cloudflare (R2 для медиа, DNS на API и медиа). Один корневой модуль, параметризуется по окружению (`dev` / `stage` / `prod`) через tfvars.

> Применяется ПОСЛЕ заведения аккаунтов Тиграном (GCP + billing, Cloudflare, домен). До этого — только чтение/ревью; ничего не разворачивается.

## Что создаётся
- Артефакт-реестр `traktor` для Docker-образов сервисов.
- Приватная сеть + VPC-connector (Cloud Run ↔ Cloud SQL/Redis по приватным адресам).
- Cloud SQL Postgres 16 (PITR-бэкапы; REGIONAL HA в prod).
- Redis 7 (BASIC в dev, STANDARD_HA в prod).
- Топики Pub/Sub на каждый домен + DLQ.
- Секреты (полки) в Secret Manager: ключ JWT, Dexatel, пароль БД, ключ шифрования телефонов. **Значения кладутся вручную, в state не попадают.**
- Cloud Run: `identity` (внутренний, только gateway) и `gateway` (публичный), с секретными env из Secret Manager.
- Cloudflare: R2-бакет медиа, CNAME `api.<domain>` → gateway (домен-маппинг Cloud Run), `media.<domain>` → R2.

## Порядок применения (когда аккаунты готовы)
```bash
# 1. Бакет для state (один раз):
gsutil mb -l europe-west3 gs://traktor-tfstate

# 2. Инициализация состояния окружения:
terraform init -backend-config="bucket=traktor-tfstate" -backend-config="prefix=env/dev"

# 3. Значения секретов (пример — ключ JWT):
gcloud secrets versions add traktor-dev-jwt-ec-private-key-pem --data-file=jwt_ec.pem

# 4. Применение:
cp envs/dev.tfvars.example envs/dev.tfvars   # заполнить
terraform apply -var-file=envs/dev.tfvars
```

Образы `identity`/`gateway` собираются и пушатся в Artifact Registry в CI (или вручную `gcloud builds submit`); их теги подставляются в tfvars.

## Провайдеры
- google ~> 6.0, cloudflare ~> 4.0. Токены/креды — из окружения (`GOOGLE_APPLICATION_CREDENTIALS`, `CLOUDFLARE_API_TOKEN`), не в коде.

## Замечания по безопасности (архитектура §9)
- Cloud SQL — без публичного IP (только приватная сеть).
- identity — `INGRESS_TRAFFIC_INTERNAL_ONLY`.
- Секреты — только в Secret Manager, доступ по сервисному аккаунту сервиса.
- `dev.tfvars` и `*.pem` — в `.gitignore` (уже добавлено в корневой .gitignore).
