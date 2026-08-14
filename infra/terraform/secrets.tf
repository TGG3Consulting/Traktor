# Секреты в Secret Manager. Значения задаются ВНЕ Terraform (gcloud / консоль),
# в код и state не попадают. Здесь — только «полки» под них и права доступа.
resource "google_secret_manager_secret" "secrets" {
  for_each = toset([
    "jwt-ec-private-key-pem", # приватный ключ ES256 для identity
    "dexatel-api-key",        # ключ SMS-провайдера
    "db-password",            # пароль пользователя БД
    "pg-encrypt-key",         # ключ шифрования телефонов (pgcrypto)
  ])
  secret_id = "${local.name}-${each.value}"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# Сервисные аккаунты сервисов (принцип наименьших прав).
resource "google_service_account" "identity" {
  account_id   = "${local.name}-identity"
  display_name = "Traktor identity (${var.env})"
}

resource "google_service_account" "gateway" {
  account_id   = "${local.name}-gateway"
  display_name = "Traktor gateway (${var.env})"
}

# identity читает свои секреты (ключ JWT, Dexatel, пароль БД, ключ шифрования).
resource "google_secret_manager_secret_iam_member" "identity_access" {
  for_each  = google_secret_manager_secret.secrets
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.identity.email}"
}
