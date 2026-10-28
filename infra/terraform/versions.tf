terraform {
  required_version = ">= 1.5"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # На стенде state хранится локально. В реальной команде здесь remote backend
  # (например, S3-совместимое хранилище) с блокировкой, чтобы два человека
  # не применяли изменения одновременно.
}

# Подключается к локальному Docker (DOCKER_HOST или /var/run/docker.sock)
provider "docker" {}
