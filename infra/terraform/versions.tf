terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  # Состояние хранится в GCS (бакет задаётся при init через -backend-config).
  # terraform init -backend-config="bucket=traktor-tfstate" -backend-config="prefix=env/dev"
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "cloudflare" {
  # CLOUDFLARE_API_TOKEN — из окружения (Secret Manager / CI), не в коде.
}
