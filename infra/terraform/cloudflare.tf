# ── Cloudflare: R2 (медиа), DNS на gateway ─────────────────

# R2-бакет для медиа (фото техники/работ). Нулевой egress (ADR-8).
resource "cloudflare_r2_bucket" "media" {
  account_id = var.cloudflare_account_id
  name       = "${local.name}-media"
}

# api.<domain> → gateway (проксируется через Cloudflare). Cloud Run по умолчанию
# даёт *.run.app; для кастомного домена используем domain mapping + CNAME.
resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.env == "prod" ? "api" : "api.${var.env}"
  type    = "CNAME"
  value   = "ghs.googlehosted.com" # цель домен-маппинга Cloud Run
  proxied = true
  ttl     = 1
}

# media.<domain> → R2 (публичная раздача через привязанный домен R2/CDN).
resource "cloudflare_record" "media" {
  zone_id = var.cloudflare_zone_id
  name    = var.env == "prod" ? "media" : "media.${var.env}"
  type    = "CNAME"
  value   = "public.r2.dev"
  proxied = true
  ttl     = 1
}

# Домен-маппинг Cloud Run для gateway (кастомный домен вместо *.run.app).
resource "google_cloud_run_domain_mapping" "api" {
  location = var.region
  name     = var.env == "prod" ? "api.${var.domain}" : "api.${var.env}.${var.domain}"
  metadata {
    namespace = var.project_id
  }
  spec {
    route_name = "${local.name}-gateway"
  }
  depends_on = [module.gateway]
}
