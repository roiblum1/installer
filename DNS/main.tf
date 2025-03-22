// main.tf for DNS module
locals {
  filtered_records = { for k, v in var.records : k => v if v != "" }
  records_to_delete = var.records_to_delete
}

resource "null_resource" "dns_record" {
  for_each = local.filtered_records

  # This allows for record updates when content changes and stores variables for destroy time
  triggers = {
    hostname = each.key
    ip       = each.value
    ttl      = var.ttl
  }

  provisioner "local-exec" {
    command = <<EOF
echo "update add ${each.key} ${var.ttl} A ${each.value}" | nsupdate -v -d
EOF
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
echo "update delete ${self.triggers.hostname} ${self.triggers.ttl} A ${self.triggers.ip}" | nsupdate -v -d
EOF
  }
}

# Resource to explicitly delete DNS records (for bootstrap completion)
resource "null_resource" "delete_dns_record" {
  for_each = var.records_to_delete

  triggers = {
    hostname = each.key
    ip       = each.value
    ttl      = var.ttl
  }

  provisioner "local-exec" {
    command = <<EOF
echo "update delete ${each.key} ${var.ttl} A ${each.value}" | nsupdate -v -d
EOF
  }
}

# Create a wildcard domain for apps pointing to infra machines
resource "null_resource" "wildcard_dns_records" {
  count = length(var.infra_ips) > 0 ? length(var.infra_ips) : 0

  # Store all variables needed at destroy time in triggers
  triggers = {
    infra_ip       = var.infra_ips[count.index]
    count_index    = count.index
    ttl            = var.ttl
    cluster_domain = var.cluster_domain
  }

  provisioner "local-exec" {
    command = <<EOF
echo "update add infra-${count.index}.apps.${var.cluster_domain} ${var.ttl} A ${var.infra_ips[count.index]}" | nsupdate -v -d
echo "update add *.apps.${var.cluster_domain} ${var.ttl} A ${var.infra_ips[count.index]}" | nsupdate -v -d
EOF
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
echo "update delete infra-${self.triggers.count_index}.apps.${self.triggers.cluster_domain} ${self.triggers.ttl} A ${self.triggers.infra_ip}" | nsupdate -v -d
echo "update delete *.apps.${self.triggers.cluster_domain} ${self.triggers.ttl} A ${self.triggers.infra_ip}" | nsupdate -v -d
EOF
  }
}