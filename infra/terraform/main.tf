locals {
  labels = {
    stand   = var.project
    managed = "terraform"
  }
}

resource "docker_network" "this" {
  name = "${var.project}-net"

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_volume" "pgdata" {
  name = "${var.project}-pgdata"
}

resource "docker_image" "postgres" {
  name         = var.postgres_image
  keep_locally = true
}

resource "docker_container" "db" {
  name    = "${var.project}-db"
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "POSTGRES_DB=shop",
    "POSTGRES_USER=shop",
    "POSTGRES_PASSWORD=${var.db_password}",
  ]

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["db"]
  }

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U shop -d shop"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 120

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "local_file" "ansible_vars" {
  filename        = "${path.module}/../ansible/inventory/group_vars/all/terraform.yml"
  file_permission = "0644"
  content = yamlencode({
    stand_name     = var.project
    docker_network = docker_network.this.name
    db_container   = docker_container.db.name
    db_host        = "db"
  })
}
