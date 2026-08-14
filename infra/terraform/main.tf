# ── Включение нужных API GCP ───────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "vpcaccess.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# ── Реестр образов ─────────────────────────────────────────
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "traktor"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

# ── Приватная сеть для Cloud SQL / Redis / connector ───────
resource "google_compute_network" "vpc" {
  name                    = "${local.name}-vpc"
  auto_create_subnetworks = true
  depends_on              = [google_project_service.apis]
}

resource "google_vpc_access_connector" "connector" {
  name          = "${local.name}-conn"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.8.0.0/28"
  depends_on    = [google_project_service.apis]
}

# Private Services Access — чтобы Cloud SQL получил приватный IP в нашей сети.
resource "google_compute_global_address" "private_ip" {
  name          = "${local.name}-priv-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip.name]
  depends_on              = [google_project_service.apis]
}

# ── Cloud SQL Postgres (+PostGIS включается миграцией/расширением) ──
resource "google_sql_database_instance" "pg" {
  name             = "${local.name}-pg"
  database_version = "POSTGRES_16"
  region           = var.region
  depends_on       = [google_service_networking_connection.psa]

  settings {
    tier              = var.db_tier
    availability_type = local.db_ha ? "REGIONAL" : "ZONAL"
    disk_autoresize   = true
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true # PITR (архитектура §9)
      start_time                     = "02:00"
    }
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
  }
  deletion_protection = local.is_prod
}

resource "google_sql_database" "app" {
  name     = "traktor"
  instance = google_sql_database_instance.pg.name
}

# ── Redis (Memorystore) ────────────────────────────────────
resource "google_redis_instance" "cache" {
  name               = "${local.name}-redis"
  tier               = local.is_prod ? "STANDARD_HA" : "BASIC"
  memory_size_gb     = 1
  region             = var.region
  authorized_network = google_compute_network.vpc.id
  redis_version      = "REDIS_7_0"
  depends_on         = [google_project_service.apis]
}

# ── Pub/Sub: топики доменных событий ───────────────────────
resource "google_pubsub_topic" "events" {
  for_each = toset([
    "identity", "catalog", "orders", "auction", "deals", "chat", "reviews", "media",
  ])
  name       = "${local.name}-${each.value}"
  depends_on = [google_project_service.apis]
}

# Dead-letter топик для непереваренных событий (алерт на рост — в мониторинге).
resource "google_pubsub_topic" "dlq" {
  name       = "${local.name}-dlq"
  depends_on = [google_project_service.apis]
}
