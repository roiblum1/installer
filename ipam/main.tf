// main.tf
locals {
  # Use the full CIDR value (e.g. "172.20.10.2/28") provided in var.machine_cidr.
  network = var.machine_cidr

  # When no static IPs are provided, use the hostnames list.
  hostnames = length(var.static_ip_addresses) == 0 ? var.hostnames : []

  # Run the script once (if dynamic assignment is needed) and decode the returned JSON string into a list.
  free_ips = length(var.static_ip_addresses) == 0 ? jsondecode(data.external.free_ip[0].result["ip_addresses"]) : var.static_ip_addresses
}

data "external" "free_ip" {
  # Only run the external script if no static IPs are provided.
  count = length(var.static_ip_addresses) == 0 ? 1 : 0

  program = [
    "bash",
    "-c",
    "echo '{\"cidr\": \"${var.machine_cidr}\", \"hosts\": ${length(var.hostnames)} }' | ${path.module}/cidr_to_ip.sh"
  ]
}
