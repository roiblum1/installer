// ID identifying the cluster to create. Use your username so that resources created can be tracked back to you.
cluster_id = "example-cluster"

// Domain of the cluster. This should be "${cluster_id}.${base_domain}".
cluster_domain = "example-cluster.company.internal"

// Base domain from which the cluster domain is a subdomain.
base_domain = "company.internal"

// Search domain for the cluster's network configuration
search_domain = "myprivate.company"

// Whether to deploy a dedicated load balancer VM (true) or use DNS-based load balancing (false)
// When set to false, API endpoints will point directly to control plane nodes using DNS load balancing
deploy_lb = true

// Name of the vSphere server. 
vsphere_server = "vcenter.company.internal"

// User on the vSphere server.
vsphere_user = "administrator@vsphere.local"

// Password of the user on the vSphere server.
# vsphere_password = "password"

// Name of the VM template to clone to create VMs for the cluster.
vm_template = "rhcos-latest"

// The machine_cidr where IP addresses will be assigned for cluster nodes.
machine_cidr = "172.20.10.0/24"

// DNS server addresses for VM configurations
vm_dns_addresses = ["172.20.10.10", "172.20.10.11"]

// The number of control plane VMs to create. Default is 3.
control_plane_count = 3

// The number of compute VMs to create. Default is 3.
compute_count = 3

// The number of infrastructure VMs to create. Default is 3.
infra_count = 3

// Hardware configuration for control plane nodes
control_plane_memory = "16384"
control_plane_num_cpus = "4"

// Hardware configuration for compute nodes
compute_memory = "8192"
compute_num_cpus = "4"

// Hardware configuration for infrastructure nodes
infra_memory = "16384"
infra_num_cpus = "4"

// Ignition config paths
bootstrap_ignition_path = "./bootstrap.ign"
control_plane_ignition_path = "./master.ign"
compute_ignition_path = "./worker.ign"

// Path to SSH public key for VMs
ssh_public_key_path = "~/.ssh/id_rsa.pub"

// Set static IP addresses if desired instead of using the CIDR scanner
// The lb_ip_address is only used when deploy_lb is true
// bootstrap_ip_address = "172.20.10.10"
// lb_ip_address = "172.20.10.11"
// control_plane_ip_addresses = ["172.20.10.20", "172.20.10.21", "172.20.10.22"]
// compute_ip_addresses = ["172.20.10.30", "172.20.10.31", "172.20.10.32"]
// infra_ip_addresses = ["172.20.10.40", "172.20.10.41", "172.20.10.42"]

// A list of maps where each map defines a specific failure domain.
failure_domains = [
    {
        // Name of the vSphere data center.
        datacenter = "dc1"
        // Name of the vSphere cluster.
        cluster = "cluster1"
        // Name of the vSphere data store to use for the VMs.
        datastore = "datastore1"
        // Name of the vSphere network to use for the VMs.
        network = "VM Network"
        // UUID of the distributed switch which is hosting the portgroup (if applicable)
        distributed_virtual_switch_uuid = ""
    },
    {
        // Name of the vSphere data center.
        datacenter = "dc1"
        // Name of the vSphere cluster.
        cluster = "cluster2"
        // Name of the vSphere data store to use for the VMs.
        datastore = "datastore2"
        // Name of the vSphere network to use for the VMs.
        network = "VM Network"
        // UUID of the distributed switch which is hosting the portgroup (if applicable)
        distributed_virtual_switch_uuid = ""
    }
]