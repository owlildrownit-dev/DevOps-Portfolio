output "network" {
  value = docker_network.this.name
}

output "db_container" {
  value = docker_container.db.name
}
