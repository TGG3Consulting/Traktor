# ── identity: внутренний сервис (зовёт только gateway) ─────
module "identity" {
  source                = "./modules/cloud_run"
  name                  = "${local.name}-identity"
  region                = var.region
  image                 = var.identity_image
  service_account_email = google_service_account.identity.email
  min_instances         = local.min_instances
  ingress               = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  allow_unauthenticated = false
  vpc_connector         = google_vpc_access_connector.connector.id

  env = {
    PORT            = "8080"
    DEXATEL_SENDER  = "Traktor"
    JWT_KID         = var.env
    DB_HOST         = google_sql_database_instance.pg.private_ip_address
    DB_NAME         = google_sql_database.app.name
  }
  secret_env = {
    JWT_EC_PRIVATE_KEY_PEM = "${local.name}-jwt-ec-private-key-pem"
    DEXATEL_API_KEY        = "${local.name}-dexatel-api-key"
    DB_PASSWORD            = "${local.name}-db-password"
    PG_ENCRYPT_KEY         = "${local.name}-pg-encrypt-key"
  }
}

# ── gateway: публичный вход ────────────────────────────────
module "gateway" {
  source                = "./modules/cloud_run"
  name                  = "${local.name}-gateway"
  region                = var.region
  image                 = var.gateway_image
  service_account_email = google_service_account.gateway.email
  min_instances         = local.min_instances
  ingress               = "INGRESS_TRAFFIC_ALL"
  allow_unauthenticated = true
  vpc_connector         = google_vpc_access_connector.connector.id

  env = {
    PORT         = "8080"
    IDENTITY_URL = module.identity.uri
    JWKS_URL     = "${module.identity.uri}/.well-known/jwks.json"
    ALLOW_ORIGIN = "https://${var.domain}"
  }
}
