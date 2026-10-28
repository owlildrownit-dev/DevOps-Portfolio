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

  # State is stored locally here. A team setup would use a remote backend
  # (for example, S3-compatible storage) with locking, so that two people
  # cannot apply changes at the same time.
}

# Connects to the local Docker daemon (DOCKER_HOST or /var/run/docker.sock)
provider "docker" {}
