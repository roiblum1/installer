# OpenShift UPI Installation on vSphere for Disconnected Environments

This project demonstrates how to install an OpenShift User Provisioned Infrastructure (UPI) cluster on vSphere in disconnected (air-gapped) environments. Two installation methods are supported:

- **PowerCLI** - Using VMware PowerCLI scripts
- **Terraform** - Using HashiCorp Terraform

## Table of Contents
- [OpenShift UPI Installation on vSphere for Disconnected Environments](#openshift-upi-installation-on-vsphere-for-disconnected-environments)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites for Disconnected Installation](#prerequisites-for-disconnected-installation)
- [PowerCLI Method](#powercli-method)
  - [Pre-Requisites](#pre-requisites)
  - [PowerCLI Setup](#powercli-setup)
    - [Generating CLI Credentials](#generating-cli-credentials)
  - [Preparing for Disconnected Installation](#preparing-for-disconnected-installation)
  - [Configuration](#configuration)
    - [Network Settings](#network-settings)
    - [Bootstrap Management Options](#bootstrap-management-options)
    - [Node Configuration](#node-configuration)
  - [Build a Cluster with PowerCLI](#build-a-cluster-with-powercli)
    - [1. Configure Your Environment](#1-configure-your-environment)
    - [2. Run the Deployment Script](#2-run-the-deployment-script)
    - [3. Monitor the Installation](#3-monitor-the-installation)
  - [Bootstrap Completion](#bootstrap-completion)
  - [Post-Installation Configuration](#post-installation-configuration)
- [Terraform Method](#terraform-method)
  - [Pre-Requisites](#pre-requisites-1)
  - [Preparing for Disconnected Installation](#preparing-for-disconnected-installation-1)
  - [Build a Cluster with Terraform](#build-a-cluster-with-terraform)
  - [Bootstrap Completion (Terraform)](#bootstrap-completion-terraform)
  - [Infrastructure Nodes](#infrastructure-nodes)
  - [DNS Configuration](#dns-configuration)
  - [Troubleshooting](#troubleshooting)
    - [Common Issues in Disconnected Environments](#common-issues-in-disconnected-environments)

## Prerequisites for Disconnected Installation

For a disconnected (air-gapped) installation, you need the following components prepared in advance:

1. **RHCOS OVA Template** - Download the Red Hat CoreOS (RHCOS) OVA template matching your OpenShift version
2. **OpenShift Installer Binary** - Download the `openshift-install` binary for your target version
3. **Local Registry** - A container registry accessible in your disconnected environment with OpenShift images
4. **DNS Server** - A DNS server for your cluster's domain name resolution 
5. **Pull Secret** - A modified pull secret that includes authentication for your local registry

# PowerCLI Method

This section describes the process to generate the vSphere VMs using PowerShell, VMware.PowerCLI and the supplied scripts in this module.

## Pre-Requisites

* PowerShell
* PowerShell VMware.PowerCLI Module

## PowerCLI Setup

PowerShell will need to have VMware.PowerCLI plugin installed:

```shell
pwsh -Command 'Install-Module VMware.PowerCLI -Force -Scope CurrentUser'
```

### Generating CLI Credentials

The PowerShell scripts require that a credentials file be generated with the credentials to be used for generating the vSphere resources. This does not have to be the credentials used by the OpenShift cluster via the install-config.yaml, but must have all permissions to create folders, tags, templates, and vms. To generate the credentials files, run:

```shell
pwsh -command "$User='<username>';$Password=ConvertTo-SecureString -String '<password>' -AsPlainText -Force;$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password;$Credential | Export-Clixml secrets/vcenter-creds.xml"
```

Be sure to modify `<username>` to be the username for vCenter and `<password>` to the your password. The output of this needs to go into `secrets/vcenter-creds.xml`. Make sure the secrets directory exists before running the credentials generation command above.

## Preparing for Disconnected Installation

1. Download the RHCOS OVA template for your OpenShift version
2. Download the OpenShift installer binary (`openshift-install`)
3. Prepare a `disconnected` directory to store required files:

```shell
mkdir -p disconnected
cp rhcos-<version>.ova disconnected/
cp openshift-install disconnected/
```

4. Update the `variables.ps1` file with your local registry details:

```powershell
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

# Pull secret for your disconnected registry
$pullsecret = @"
{"auths":{"registry.example.local:5000":{"auth":"base64encodedcredentials"}}}
"@
```

## Configuration

The PowerCLI script provided by this project is highly configurable. It can handle all aspects of creating a UPI cluster environment in a disconnected setting.

### Network Settings

These properties define the basic network configuration for your cluster:

| Property          | Description                                                      |
|-------------------|------------------------------------------------------------------|
| searchDomain      | Search domain to add to all VMs network configuration            |
| apivip            | Virtual IP for API endpoint                                      |
| ingressvip        | Virtual IP for ingress                                           |
| lb_ip_address     | Load balancer IP                                                 |
| gateway           | Network gateway                                                  |
| netmask           | Network mask                                                     |
| dns               | DNS server IP address                                            |

### Bootstrap Management Options

| Property          | Description                                                      |
|-------------------|------------------------------------------------------------------|
| bootstrap_complete | Flag to indicate bootstrap process is complete (set to true after bootstrap to remove bootstrap resources) |
| deploy_lb         | Whether to deploy a dedicated load balancer VM (set to false to use DNS-based load balancing) |

### Node Configuration

| Property                   | Description                                           |
|----------------------------|-------------------------------------------------------|
| control_plane_count        | Number of control plane VMs                           |
| control_plane_num_cpus     | Number of CPUs for control plane VMs                  |
| control_plane_memory       | Memory (MB) for control plane VMs                     |
| control_plane_ip_addresses | Static IP addresses for control plane VMs             |
| compute_count              | Number of compute VMs                                 |
| compute_num_cpus           | Number of CPUs for compute VMs                        |
| compute_memory             | Memory (MB) for compute VMs                           |
| compute_ip_addresses       | Static IP addresses for compute VMs                   |
| infra_count                | Number of infrastructure VMs                          |
| infra_num_cpus             | Number of CPUs for infrastructure VMs                 |
| infra_memory               | Memory (MB) for infrastructure VMs                    |
| infra_ip_addresses         | Static IP addresses for infrastructure VMs            |
| bootstrap_ip_address       | Static IP address for bootstrap VM                    |

## Build a Cluster with PowerCLI

### 1. Configure Your Environment

Edit `variables.ps1` to match your environment:
- Set vCenter details
- Configure DNS, network, and IP ranges
- Set pull secret for disconnected registry
- Configure search domain and node specifications

### 2. Run the Deployment Script

```powershell
pwsh -f main.ps1
```

This script will:
1. Create ignition configs if enabled
2. Import the RHCOS template (or use existing template)
3. Create and configure the load balancer VM
4. Create bootstrap, control plane, compute, and infrastructure nodes
5. Optional: Wait for installation to complete

### 3. Monitor the Installation

After the VMs are created, you can monitor the installation:

```bash
./openshift-install wait-for bootstrap-complete --log-level=info
```

## Bootstrap Completion

Once bootstrap is complete, you can remove the bootstrap node to free resources and update the load balancer configuration by running the script again with bootstrap_complete set to true:

1. Edit `variables.ps1` and change `$bootstrap_complete = $false` to `$bootstrap_complete = $true`
2. Run the script again:

```powershell
pwsh -f main.ps1
```

The script will:
1. Remove the bootstrap VM
2. Update the load balancer configuration to remove bootstrap references
3. Clean up bootstrap DNS records if configured

## Post-Installation Configuration

After the cluster is fully installed, configure the infrastructure nodes to run OpenShift infrastructure services:

```powershell
pwsh -f post-install-config.ps1
```

This script will:
1. Add infrastructure node role labels
2. Apply taints to ensure only infrastructure workloads run on these nodes
3. Move the following components to infrastructure nodes:
   - Ingress Router
   - Registry
   - Monitoring Stack

# Terraform Method

This section will walk you through generating a cluster using Terraform in a disconnected environment.

## Pre-Requisites

* Terraform
* RHCOS OVA Template
* OpenShift Installer Binary
* Local Registry

## Preparing for Disconnected Installation

1. Create an install-config.yaml with references to your local registry:

```yaml
apiVersion: v1
baseDomain: example.local
metadata:
  name: ocp4
networking:
  machineNetwork:
  - cidr: "192.168.1.0/24"
platform:
  vsphere:
    vcenter: vcenter.example.local
    username: YOUR_VSPHERE_USER
    password: YOUR_VSPHERE_PASSWORD
    datacenter: dc1
    defaultDatastore: datastore1
pullSecret: '{"auths":{"registry.example.local:5000":{"auth":"base64encodedcredentials"}}}'
sshKey: YOUR_SSH_KEY
imageContentSources:
- mirrors:
  - registry.example.local:5000/openshift-release-dev/ocp-release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.example.local:5000/openshift-release-dev/ocp-v4.0-art-dev
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

2. Run `openshift-install create ignition-configs`.

3. Fill out a terraform.tfvars file for your disconnected environment:

```hcl
// Basic cluster information
cluster_id = "ocp4"
cluster_domain = "ocp4.example.local"
base_domain = "example.local"

// vSphere connection details
vsphere_server = "vcenter.example.local"
vsphere_user = "administrator@vsphere.local"
vsphere_password = "password"

// VM template from local OVA
vm_template = "rhcos-4.14"

// Network configuration
machine_cidr = "192.168.1.0/24"
vm_dns_addresses = ["192.168.1.10"]
search_domain = "example.local"

// Node counts
control_plane_count = 3
compute_count = 3
infra_count = 3

// Optional: deploy load balancer
deploy_lb = true

// Search domain for all VMs
search_domain = "example.local"

// Path to ignition files
bootstrap_ignition_path = "./bootstrap.ign"
control_plane_ignition_path = "./master.ign"
compute_ignition_path = "./worker.ign"
```

## Build a Cluster with Terraform

1. Initialize Terraform to use local providers:

```bash
terraform init
```

2. Apply the Terraform configuration:

```bash
terraform apply -auto-approve
```

3. Wait for the bootstrapping to complete:

```bash
./openshift-install wait-for bootstrap-complete
```

## Bootstrap Completion (Terraform)

Once bootstrap is complete:

```bash
terraform apply -auto-approve -var 'bootstrap_complete=true'
```

This will:
1. Destroy the bootstrap VM
2. Remove bootstrap from load balancer configuration
3. Update DNS records if configured

## Infrastructure Nodes

Infrastructure nodes are dedicated to running OpenShift infrastructure components like:

- Ingress Router
- Image Registry
- Monitoring Stack
- Logging Stack

These nodes are tainted to prevent application workloads from running on them, ensuring resources are dedicated to platform services.

After the cluster is installed, run the post-installation script to configure the infrastructure nodes:

```powershell
pwsh -f post-install-config.ps1
```

## DNS Configuration

For disconnected environments, you'll need to configure DNS for:

1. API endpoints: `api.clustername.domain` and `api-int.clustername.domain`
2. Application wildcard domain: `*.apps.clustername.domain`
3. Node records: `bootstrap.clustername.domain`, `master-0.clustername.domain`, etc.
4. Optional: etcd SRV records

The DNS module provides functionality to create these records using the `nsupdate` command:

```bash
echo "update add api.ocp4.example.local 8600 A 192.168.1.100" | nsupdate -v -d
```

## Troubleshooting

### Common Issues in Disconnected Environments

1. **Registry Access**
   - Verify your pull secret includes authentication for your local registry
   - Ensure registry is accessible from all nodes

2. **DNS Resolution**
   - Confirm all required DNS records are created
   - Check search domain configuration on VMs

3. **Bootstrap Issues**
   - Check bootstrap VM logs: `ssh core@bootstrap-ip journalctl -f`
   - Verify bootstrap can reach the local registry and DNS

4. **Network Configuration**
   - Ensure static IPs are correctly assigned
   - Verify gateway and netmask configuration

5. **Load Balancer**
   - Confirm HAProxy configuration includes all nodes
   - Check if API endpoint is accessible: `curl -k https://api.clustername.domain:6443/version`