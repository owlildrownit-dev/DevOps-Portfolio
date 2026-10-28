variable "project" {
  description = "Префикс имен всех ресурсов стенда"
  type        = string
  default     = "demo"
}

variable "postgres_image" {
  description = "Образ PostgreSQL"
  type        = string
  default     = "postgres:16"
}

variable "db_password" {
  description = "Пароль пользователя БД. Передается через TF_VAR_db_password, в коде не хранится"
  type        = string
  sensitive   = true
}
