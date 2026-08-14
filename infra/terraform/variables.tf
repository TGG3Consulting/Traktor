variable "project_id" {
  type        = string
  description = "GCP Project ID (например traktor-472913)."
}

variable "region" {
  type        = string
  default     = "europe-west3" # Frankfurt — ближайший к Еревану
  description = "Регион GCP."
}

variable "env" {
  type        = string
  description = "Окружение: dev | stage | prod."
  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env должен быть dev, stage или prod."
  }
}

variable "domain" {
  type        = string
  description = "Основной домен (например getraktor.com)."
}

variable "cloudflare_account_id" {
  type        = string
  description = "ID аккаунта Cloudflare."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "ID зоны Cloudflare для домена."
}

variable "identity_image" {
  type        = string
  description = "Полный тег образа identity в Artifact Registry."
  default     = ""
}

variable "gateway_image" {
  type        = string
  description = "Полный тег образа gateway в Artifact Registry."
  default     = ""
}

variable "db_tier" {
  type        = string
  default     = "db-custom-2-4096" # 2 vCPU / 4 ГБ — старт; масштабируется
  description = "Тип инстанса Cloud SQL."
}

# Множители под окружение: dev дешевле, prod надёжнее.
locals {
  is_prod        = var.env == "prod"
  min_instances  = local.is_prod ? 1 : 0
  db_ha          = local.is_prod # high availability только в prod
  name           = "traktor-${var.env}"
}
