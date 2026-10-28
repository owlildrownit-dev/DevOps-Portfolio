variable "project" {
  description = "Name prefix for all resources"
  type        = string
  default     = "demo"
}

variable "postgres_image" {
  description = "PostgreSQL image"
  type        = string
  default     = "postgres:16"
}

variable "db_password" {
  description = "Database user password. Passed via TF_VAR_db_password and never stored in code"
  type        = string
  sensitive   = true
}
