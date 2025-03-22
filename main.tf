locals {
  failure_domains = length(var.failure_domains) == 0 ? [{
    datacenter = var.vsphere_datacenter
    cluster = var.vsphere_cluster
    datastore = var.vsphere_datastore
    network = var.vm_network
    distributed_virtual_switch_uuid = ""
  }] : var.failure_domains

  failure_domain_count = length(local.failure_domains)
  
  # Create all FQDN and hostname lists
  bootstrap_fqdns       = ["bootstrap-0.${var.cluster_domain}"]
  lb_fqdns              = var.deploy_lb ? ["lb-0.${var.cluster_domain}"] : []
  api_lb_fqdns          = formatlist("%s.%s", ["api", "api-int"], var.cluster_domain)
  apps_wildcard_fqdn    = ["*.apps.${var.cluster_domain}"]
  control_plane_fqdns   = [for idx in range(var.control_plane_count) : "control-plane-${idx}.${var.cluster_domain}"]
  compute_fqdns         = [for idx in range(var.compute_count) : "compute-${idx}.${var.cluster_domain}"]
  infra_fqdns           = [for idx in range(var.infra_count) : "infra-${idx}.${var.cluster_domain}"]
  
  # Create hostnames without domain for IPAM module
  bootstrap_hostnames     = ["bootstrap-0"]
  lb_hostnames            = var.deploy_lb ? ["lb-0"] : []
  control_plane_hostnames = [for idx in range(var.control_plane_count) : "control-plane-${idx}"]
  compute_hostnames       = [for idx in range(var.compute_count) : "compute-${idx}"]
  infra_hostnames         = [for idx in range(var.infra_count) : "infra-${idx}"]
  
  # Combine all hostnames in a specific order for combined IPAM request
  all_hostnames = distinct(concat(
    var.bootstrap_complete ? [] : local.bootstrap_hostnames,
    local.lb_hostnames,
    local.control_plane_hostnames,
    local.compute_hostnames,
    local.infra_hostnames
  ))
  
  # Combine all static IPs if provided (must match the order of all_hostnames)
  all_static_ips = concat(
    var.bootstrap_complete ? [] : (var.bootstrap_ip_address != "" ? [var.bootstrap_ip_address] : []),
    var.deploy_lb && var.lb_ip_address != "" ? [var.lb_ip_address] : [],
    var.control_plane_ip_addresses,
    var.compute_ip_addresses,
    var.infra_ip_addresses
  )
  
  # Count the number of hosts of each type for slicing the results
  bootstrap_count = var.bootstrap_complete ? 0 : length(local.bootstrap_hostnames)
  lb_count = length(local.lb_hostnames)
  control_plane_count = length(local.control_plane_hostnames)
  compute_count = length(local.compute_hostnames)
  infra_count = length(local.infra_hostnames)
  
  # Calculate starting indices for slicing the all_ip_addresses list
  lb_start_idx = local.bootstrap_count
  control_plane_start_idx = local.lb_start_idx + local.lb_count
  compute_start_idx = local.control_plane_start_idx + local.control_plane_count
  infra_start_idx = local.compute_start_idx + local.compute_count
  
  # Extract IP addresses for each node type from the combined list
  bootstrap_ips = var.bootstrap_complete ? [] : (
                    var.bootstrap_ip_address != "" ? [var.bootstrap_ip_address] : 
                    length(module.ipam_all.ip_addresses) > 0 ? [module.ipam_all.ip_addresses[0]] : []
                  )
                  
  lb_ips = var.deploy_lb ? (
             var.lb_ip_address != "" ? [var.lb_ip_address] : 
             length(module.ipam_all.ip_addresses) > local.lb_start_idx ? [module.ipam_all.ip_addresses[local.lb_start_idx]] : []
           ) : []
           
  control_plane_ips = length(var.control_plane_ip_addresses) > 0 ? var.control_plane_ip_addresses : length(module.ipam_all.ip_addresses) > local.control_plane_start_idx ? slice(module.ipam_all.ip_addresses, local.control_plane_start_idx, local.control_plane_start_idx + local.control_plane_count) : []
                      
  compute_ips = length(var.compute_ip_addresses) > 0 ? var.compute_ip_addresses : length(module.ipam_all.ip_addresses) > local.compute_start_idx ? slice(module.ipam_all.ip_addresses, local.compute_start_idx, local.compute_start_idx + local.compute_count) : []
                
  infra_ips = length(var.infra_ip_addresses) > 0 ? var.infra_ip_addresses : length(module.ipam_all.ip_addresses) > local.infra_start_idx ? slice(module.ipam_all.ip_addresses, local.infra_start_idx, local.infra_start_idx + local.infra_count) : []
  
  # When bootstrap is removed, prepare records to delete
  bootstrap_records_to_delete = var.bootstrap_complete && var.bootstrap_ip_address != "" ? zipmap(local.bootstrap_fqdns, [var.bootstrap_ip_address]) : {}
  
  # Determine which IPs to use for API endpoints (LB or control plane nodes)
  api_endpoint_ips = var.deploy_lb && length(local.lb_ips) > 0 ? local.lb_ips : local.control_plane_ips
  
  # Collect all DNS records - exclude bootstrap if bootstrap_complete
  all_dns_records = merge(
    var.bootstrap_complete ? {} : zipmap(local.bootstrap_fqdns, local.bootstrap_ips),
    var.deploy_lb && length(local.lb_ips) > 0 ? zipmap(local.lb_fqdns, local.lb_ips) : {},
    zipmap(local.control_plane_fqdns, local.control_plane_ips),
    zipmap(local.compute_fqdns, local.compute_ips),
    zipmap(local.infra_fqdns, local.infra_ips),
    # For API endpoints, either use LB IP or add multiple A records for all control planes
    var.deploy_lb && length(local.lb_ips) > 0 ? 
      zipmap(local.api_lb_fqdns, [for _ in local.api_lb_fqdns : local.lb_ips[0]]) : 
      merge(
        length(local.control_plane_ips) > 0 ? { for api_fqdn in local.api_lb_fqdns : api_fqdn => local.control_plane_ips[0] } : {},
        length(local.control_plane_ips) > 1 ? { for api_fqdn in local.api_lb_fqdns : "${api_fqdn}-1" => local.control_plane_ips[1] } : {},
        length(local.control_plane_ips) > 2 ? { for api_fqdn in local.api_lb_fqdns : "${api_fqdn}-2" => local.control_plane_ips[2] } : {}
      )
  )
  
  datastores = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datastore"]]
  datacenters = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datacenter"]]
  datacenters_distinct = distinct([for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datacenter"]])
  clusters = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["cluster"]]
  networks = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["cluster"]]
  folders = [for idx in range(length(local.datacenters)) : "/${local.datacenters[idx]}/vm/${var.cluster_id}"]
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
   count = length(local.datacenters_distinct)
   name = local.datacenters_distinct[count.index]
}

data "vsphere_compute_cluster" "compute_cluster" {
   count = length(local.failure_domains)
   name = local.clusters[count.index]
   datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.datacenters[count.index])].id
}

data "vsphere_datastore" "datastore" {
   count = length(local.failure_domains)
   name = local.datastores[count.index]
   datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.datacenters[count.index])].id
}

data "vsphere_network" "network" {
  count = length(local.failure_domains)
  name          = local.failure_domains[count.index]["network"]
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index]["datacenter"])].id
  distributed_virtual_switch_uuid = local.failure_domains[count.index]["distributed_virtual_switch_uuid"]
}
 
data "vsphere_virtual_machine" "template" {
  count = length(local.datacenters_distinct)
  name          = var.vm_template
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.datacenters_distinct[count.index])].id
}
 
resource "vsphere_resource_pool" "resource_pool" {
  count                   = length(data.vsphere_compute_cluster.compute_cluster)
  name                    = var.cluster_id
  parent_resource_pool_id = data.vsphere_compute_cluster.compute_cluster[count.index].resource_pool_id
}
 
resource "vsphere_folder" "folder" {
  count = length(local.datacenters_distinct)
  path          = var.cluster_id
  type          = "vm"  
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.datacenters_distinct[count.index])].id
}

// Request IP addresses for all nodes at once - bootstrap is conditionally excluded
module "ipam_all" {
  source = "./ipam"
  hostnames = toset(local.all_hostnames)
  machine_cidr = var.machine_cidr
  static_ip_addresses = length(local.all_static_ips) > 0 ? local.all_static_ips : []
}

// Only create the LB module if deploy_lb is true
module "lb" {
  count = var.deploy_lb ? 1 : 0
  source = "./lb"
  lb_ip_address = local.lb_ips[0]

  api_backend_addresses = flatten([
    var.bootstrap_complete ? [] : local.bootstrap_ips,
    local.control_plane_ips]
  )

  ingress_backend_addresses = local.compute_ips
  infra_backend_addresses = local.infra_ips
  ssh_public_key_path = var.ssh_public_key_path
}

// Use the DNS module and include explicit record deletion for bootstrap if needed
module "dns" {
  source = "./DNS"
  records = local.all_dns_records
  records_to_delete = var.bootstrap_complete ? local.bootstrap_records_to_delete : {}
  cluster_domain = var.cluster_domain
  ttl = 8600
  infra_ips = local.infra_ips
}

// Only create the LB VM if deploy_lb is true
module "lb_vm" {
  count = var.deploy_lb ? 1 : 0
  source = "./vm"
  vmname = "lb-0"
  ipaddress = local.lb_ips[0]
  ignition = module.lb[0].ignition
  resource_pool_id = vsphere_resource_pool.resource_pool[0].id
  datastore_id = data.vsphere_datastore.datastore[0].id
  datacenter_id = data.vsphere_datacenter.dc[0].id
  network_id = data.vsphere_network.network[0].id
  folder_id = vsphere_folder.folder[0].path
  guest_id = data.vsphere_virtual_machine.template[0].guest_id
  template_uuid = data.vsphere_virtual_machine.template[0].id
  disk_thin_provisioned = data.vsphere_virtual_machine.template[0].disks[0].thin_provisioned
  cluster_domain = var.cluster_domain
  machine_cidr = var.machine_cidr
  search_domain = var.search_domain
  num_cpus = 2
  memory = 2096
  dns_addresses = var.vm_dns_addresses
}

// Only create bootstrap VM if bootstrap is not complete
module "bootstrap" {
  count = var.bootstrap_complete ? 0 : 1
  source = "./vm"
  ignition = file(var.bootstrap_ignition_path)
  vmname = "bootstrap-0"
  ipaddress = local.bootstrap_ips[0]
  resource_pool_id = vsphere_resource_pool.resource_pool[0].id
  datastore_id = data.vsphere_datastore.datastore[0].id
  datacenter_id = data.vsphere_datacenter.dc[0].id
  network_id = data.vsphere_network.network[0].id
  folder_id = vsphere_folder.folder[0].path
  guest_id = data.vsphere_virtual_machine.template[0].guest_id
  template_uuid = data.vsphere_virtual_machine.template[0].id
  disk_thin_provisioned = data.vsphere_virtual_machine.template[0].disks[0].thin_provisioned
  cluster_domain = var.cluster_domain
  machine_cidr = var.machine_cidr
  search_domain = var.search_domain
  num_cpus = 2
  memory = 8192
  dns_addresses = var.vm_dns_addresses
}

module "control_plane_vm" {
  count = var.control_plane_count
  source = "./vm"
  vmname = "control-plane-${count.index}"
  ipaddress = local.control_plane_ips[count.index]
  ignition = file(var.control_plane_ignition_path)
  resource_pool_id = vsphere_resource_pool.resource_pool[count.index % local.failure_domain_count].id
  datastore_id = data.vsphere_datastore.datastore[count.index % local.failure_domain_count].id
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].id
  network_id = data.vsphere_network.network[count.index % local.failure_domain_count].id
  folder_id = vsphere_folder.folder[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].path
  guest_id = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].guest_id
  template_uuid = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].id
  disk_thin_provisioned = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].disks[0].thin_provisioned
  cluster_domain = var.cluster_domain
  machine_cidr = var.machine_cidr
  search_domain = var.search_domain
  num_cpus = var.control_plane_num_cpus
  memory = var.control_plane_memory
  dns_addresses = var.vm_dns_addresses
}

module "compute_vm" {
  count = var.compute_count
  source = "./vm"
  ignition = file(var.compute_ignition_path)
  vmname = "compute-${count.index}"
  ipaddress = local.compute_ips[count.index]
  resource_pool_id = vsphere_resource_pool.resource_pool[count.index % local.failure_domain_count].id
  datastore_id = data.vsphere_datastore.datastore[count.index % local.failure_domain_count].id
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].id
  network_id = data.vsphere_network.network[count.index % local.failure_domain_count].id
  folder_id = vsphere_folder.folder[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].path
  guest_id = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].guest_id
  template_uuid = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].id
  disk_thin_provisioned = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].disks[0].thin_provisioned
  cluster_domain = var.cluster_domain
  machine_cidr = var.machine_cidr
  search_domain = var.search_domain
  num_cpus = var.compute_num_cpus
  memory = var.compute_memory
  dns_addresses = var.vm_dns_addresses
}

module "infra_vm" {
  count = var.infra_count
  source = "./vm"
  ignition = file(var.compute_ignition_path) # Using compute ignition as base
  vmname = "infra-${count.index}"
  ipaddress = local.infra_ips[count.index]
  resource_pool_id = vsphere_resource_pool.resource_pool[count.index % local.failure_domain_count].id
  datastore_id = data.vsphere_datastore.datastore[count.index % local.failure_domain_count].id
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].id
  network_id = data.vsphere_network.network[count.index % local.failure_domain_count].id
  folder_id = vsphere_folder.folder[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].path
  guest_id = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].guest_id
  template_uuid = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].id
  disk_thin_provisioned = data.vsphere_virtual_machine.template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].disks[0].thin_provisioned
  cluster_domain = var.cluster_domain
  machine_cidr = var.machine_cidr
  search_domain = var.search_domain
  num_cpus = var.infra_num_cpus
  memory = var.infra_memory
  dns_addresses = var.vm_dns_addresses
}