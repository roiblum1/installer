output "hostnames" {
  value = keys(local.filtered_records)
}

output "infra_records" {
  value = var.infra_ips
}