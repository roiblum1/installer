# -------------------------
#  OpenShift UPI Variables for Disconnected Environment
# -------------------------

# Bootstrap management options
$bootstrap_complete = $false  # Set to true after bootstrap is complete to remove bootstrap resources
$deploy_lb = $true  # Option to deploy the load balancer VM (set to false to use DNS-based load balancing)

# vCenter connection details
$vcenter            = "vcenter.example.local"
$username           = "administrator@vsphere.local"
$password           = "YourVcenterPassword"  # Use a secure method in production
$vcentercredpath    = ".\vcenter-creds.xml"  # Optional: use Import-Clixml for credentials

# Infrastructure details
$clustername        = "ocp4"
$basedomain         = "example.local"
$searchDomain       = "example.local"  # This will be applied to all VMs
$datacenter         = "DC1"
$cluster            = "Cluster1"
$datastore          = "datastore1"
$portgroup          = "VM Network"

# Network details
$apivip             = "192.168.1.100"     # Virtual IP for API endpoint
$ingressvip         = "192.168.1.101"     # Virtual IP for ingress
$lb_ip_address      = "192.168.1.99"      # Load balancer IP
$gateway            = "192.168.1.1"
$netmask            = "255.255.255.0"
$dns                = "192.168.1.10"

# Cluster specification
$control_plane_count       = 3
$control_plane_num_cpus    = 8
$control_plane_memory      = 32768
$control_plane_ip_addresses = @("192.168.1.10", "192.168.1.11", "192.168.1.12")
$control_plane_hostnames   = @("control-plane-0", "control-plane-1", "control-plane-2")

$compute_count      = 3  # Worker node count
$compute_num_cpus   = 8
$compute_memory     = 16384
$compute_ip_addresses = @("192.168.1.20", "192.168.1.21", "192.168.1.22")
$compute_hostnames  = @("compute-0", "compute-1", "compute-2")

$infra_count        = 3  # Infrastructure node count
$infra_num_cpus     = 8
$infra_memory       = 32768
$infra_ip_addresses = @("192.168.1.110", "192.168.1.111", "192.168.1.112")
$infra_hostnames    = @("infra-0", "infra-1", "infra-2")

$bootstrap_ip_address = "192.168.1.9"

$version            = "4.14.0"  # OCP version
$vm_template        = "rhcos-4.14"  # Template name

# Offline/disconnected config
$downloadInstaller  = $false  # Do not attempt online downloads
$uploadTemplateOva  = $true   # Import the local OVA template
$createInstallConfig= $true
$generateIgnitions  = $true
$waitForComplete    = $true
$secureboot         = $false  # Set to true if you want secure boot enabled
$CreateDNSRecords   = $false  # Set to true if you want to create DNS records using nsupdate

# SSH key - path to your public key
$sshkeypath         = ".\id_rsa.pub"

# Storage Policy (optional)
$storagepolicy      = ""  # Specify a Storage Policy ID if needed

# Disconnected registry configuration
$imageContentSources = @(
    @{
        source = "quay.io/openshift-release-dev/ocp-release"
        mirrors = @("registry.example.local:5000/openshift-release-dev/ocp-release")
    },
    @{
        source = "quay.io/openshift-release-dev/ocp-v4.0-art-dev"
        mirrors = @("registry.example.local:5000/openshift-release-dev/ocp-v4.0-art-dev")
    }
)

# Pull secret - paste from Red Hat Cloud console or use disconnected mirror config
$pullsecret = @"
{"auths":{"registry.example.local:5000":{"auth":"base64encodedcredentials"}}}
"@

# Install config template - will be populated with values from above
$installconfig = @"
{
  "apiVersion": "v1",
  "baseDomain": "example.com",
  "compute": [
    {
      "architecture": "amd64",
      "hyperthreading": "Enabled",
      "name": "worker",
      "platform": {},
      "replicas": 3
    }
  ],
  "controlPlane": {
    "architecture": "amd64",
    "hyperthreading": "Enabled",
    "name": "master",
    "platform": {},
    "replicas": 3
  },
  "metadata": {
    "creationTimestamp": null,
    "name": "example"
  },
  "networking": {
    "clusterNetwork": [
      {
        "cidr": "10.128.0.0/14",
        "hostPrefix": 23
      }
    ],
    "machineNetwork": [
      {
        "cidr": "192.168.1.0/24"
      }
    ],
    "networkType": "OVNKubernetes",
    "serviceNetwork": [
      "172.30.0.0/16"
    ]
  },
  "platform": {
    "vsphere": {
      "apiVIP": "192.168.1.100",
      "ingressVIP": "192.168.1.101",
      "vcenter": "vcenter.example.com",
      "username": "administrator@vsphere.local",
      "password": "password",
      "datacenter": "datacenter",
      "defaultDatastore": "datastore",
      "cluster": "cluster",
      "network": "network"
    }
  },
  "pullSecret": "",
  "sshKey": ""
}
"@