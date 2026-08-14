variable "name" { type = string }
variable "region" { type = string }
variable "image" { type = string }
variable "service_account_email" { type = string }
variable "min_instances" {
  type    = number
  default = 0
}
variable "max_instances" {
  type    = number
  default = 10
}

# INGRESS_TRAFFIC_ALL (публичный) | INGRESS_TRAFFIC_INTERNAL_ONLY (только внутри).
variable "ingress" {
  type    = string
  default = "INGRESS_TRAFFIC_ALL"
}

variable "allow_unauthenticated" {
  type    = bool
  default = false
}

variable "vpc_connector" {
  type    = string
  default = ""
}

variable "env" {
  type    = map(string)
  default = {}
}

# Секретные переменные окружения: имя_переменной => secret_id в Secret Manager.
variable "secret_env" {
  type    = map(string)
  default = {}
}
