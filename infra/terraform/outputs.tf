output "gateway_url" {
  value       = module.gateway.uri
  description = "Прямой URL gateway (до кастомного домена)."
}

output "api_domain" {
  value       = var.env == "prod" ? "api.${var.domain}" : "api.${var.env}.${var.domain}"
  description = "Публичный адрес API после привязки домена."
}

output "db_instance" {
  value       = google_sql_database_instance.pg.name
  description = "Имя инстанса Cloud SQL."
}

output "media_bucket" {
  value       = cloudflare_r2_bucket.media.name
  description = "R2-бакет для медиа."
}

output "pubsub_topics" {
  value       = [for t in google_pubsub_topic.events : t.name]
  description = "Созданные топики событий."
}
