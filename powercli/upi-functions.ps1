#!/usr/bin/pwsh

########################################################################
# Function: updateDisk
# Purpose : Workaround for vSphere 8.0 crash when Set-HardDisk is used.
########################################################################
function updateDisk {
    param (
        [Parameter(Mandatory=$true)][int]$CapacityGB,
        [Parameter(Mandatory=$true)]$VM
    )

    $newDiskSizeKB    = $CapacityGB * 1024 * 1024
    $newDiskSizeBytes = $newDiskSizeKB * 1024
    $vmMo             = get-view -id $VM.ExtensionData.MoRef
    $devices          = $vmMo.Config.Hardware.Device

    $spec                  = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.DeviceChange     = New-Object VMware.Vim.VirtualDeviceConfigSpec[] (1)
    $spec.DeviceChange[0]  = New-Object VMware.Vim.VirtualDeviceConfigSpec
    $spec.DeviceChange[0].Operation = 'edit'

    foreach($d in $devices) {
        if ($d.DeviceInfo.Label -like "Hard disk*") {
            $spec.DeviceChange[0].Device = $d
        }
    }

    $spec.DeviceChange[0].Device.CapacityInBytes = $newDiskSizeBytes
    $spec.DeviceChange[0].Device.CapacityInKB    = $newDiskSizeKB

    $vmMo.ReconfigVM_Task($spec) > $null
}

########################################################################
# Function: Set-SecureBoot
# Purpose : Helper to enable Secure Boot on a VM
########################################################################
function Set-SecureBoot {
    param(
        [Parameter(Mandatory=$true)]
        $VM
    )

    $spec           = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.Firmware  = [VMware.Vim.GuestOsDescriptorFirmwareType]::efi

    $boot = New-Object VMware.Vim.VirtualMachineBootOptions
    $boot.EfiSecureBootEnabled = $true

    $spec.BootOptions = $boot

    $VM.ExtensionData.ReconfigVM($spec)
}

########################################################################
# Function: New-VMNetworkConfig
# Purpose : Define static network settings, including search domain.
########################################################################
function New-VMNetworkConfig {
    param(
        [Parameter(Mandatory=$true)][string]$DNS,
        [Parameter(Mandatory=$true)][string]$Gateway,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$IPAddress,
        [Parameter(Mandatory=$true)][string]$Netmask,
        [Parameter(Mandatory=$false)][string]$SearchDomain
    )

    $network = @"
{
  "ipAddress": "$($IPAddress)",
  "netmask": "$($Netmask)",
  "dns": "$($DNS)",
  "hostname": "$($Hostname)",
  "gateway": "$($Gateway)",
  "searchDomain": "$($SearchDomain)"
}
"@ 

    return $network | ConvertFrom-Json
}

########################################################################
# Function: New-OpenShiftVM
# Purpose : Clones a VM from a template, injects ignition data & static
#           network info (including search domain), sets advanced config.
########################################################################
function New-OpenShiftVM {
    param(
        # Mandatory parameters
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$Template,
        [Parameter(Mandatory=$true)][string]$IgnitionData,
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][string]$Network,

        # Optional parameters
        [string]$Datastore,
        [string]$Location,
        [string]$ResourcePool,
        [int]$MemoryMB,
        [int]$NumCpu,
        [switch]$SecureBoot,
        [string]$StoragePolicy,
        [PSCustomObject]$Networking
    )

    # Build argument collection for New-VM
    $args = $PSBoundParameters.Clone()
    $args.Remove('Template')       | Out-Null
    $args.Remove('IgnitionData')   | Out-Null
    $args.Remove('Tag')            | Out-Null
    $args.Remove('Networking')     | Out-Null
    $args.Remove('Network')        | Out-Null
    $args.Remove('MemoryMB')       | Out-Null
    $args.Remove('NumCpu')         | Out-Null
    $args.Remove('SecureBoot')     | Out-Null

    # Remove anything unset or blank
    foreach ($key in $args.Keys) {
        if ($null -eq $args[$key] -or $args[$key] -eq "") {
            $args.Remove($key) | Out-Null
        }
    }

    # If a storage policy was provided, retrieve the ref
    if ($null -ne $StoragePolicy -and $StoragePolicy -ne "") {
        $storagePolicyRef      = Get-SpbmStoragePolicy -Id $StoragePolicy
        $args["StoragePolicy"] = $storagePolicyRef
    }

    # Clone the virtual machine
    $vm = New-VM -VM $Template @args

    # Assign a cleanup or identification tag
    New-TagAssignment -Entity $vm -Tag $Tag | Out-Null

    # Update VM specs (CPU, Memory) if requested
    if ($null -ne $MemoryMB -and $null -ne $NumCpu) {
        Set-VM -VM $vm -MemoryMB $MemoryMB -NumCpu $NumCpu -CoresPerSocket 4 -Confirm:$false | Out-Null
    }

    # Enlarge first disk to 120 GB
    updateDisk -VM $vm -CapacityGB 120

    # Update the VM's network adapter to the correct Portgroup
    $pg = Get-VirtualPortgroup -Name $Network -VMHost (Get-VMHost -VM $vm) -ErrorAction SilentlyContinue
    if ($pg) {
        $vm | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $pg -Confirm:$false | Out-Null
    }

    # Set advanced settings required by RHCOS/Afterburn
    New-AdvancedSetting -Entity $vm -Name "disk.enableUUID"                   -Value "TRUE"          -Confirm:$false -Force | Out-Null
    New-AdvancedSetting -Entity $vm -Name "stealclock.enable"                 -Value "TRUE"          -Confirm:$false -Force | Out-Null
    New-AdvancedSetting -Entity $vm -Name "guestinfo.ignition.config.data.encoding" -Value "base64"  -Confirm:$false -Force | Out-Null
    New-AdvancedSetting -Entity $vm -Name "guestinfo.ignition.config.data"    -Value $IgnitionData   -Confirm:$false -Force | Out-Null
    New-AdvancedSetting -Entity $vm -Name "guestinfo.hostname"                -Value $Name           -Confirm:$false -Force | Out-Null

    # If static networking is provided, create the kernel args
    if ($null -ne $Networking) {
        $kargs = "ip=$($Networking.ipAddress)::$($Networking.gateway):$($Networking.netmask):$($Networking.hostname):ens192:none:$($Networking.dns)"

        # If we have a search domain set, append it
        if ($null -ne $Networking.searchDomain -and $Networking.searchDomain -ne "") {
            # The RHCOS initrd network parser supports appending "search=<domain>" at the end
            $kargs += " search=$($Networking.searchDomain)"
        }

        New-AdvancedSetting -Entity $vm `
                            -Name "guestinfo.afterburn.initrd.network-kargs" `
                            -Value $kargs -Confirm:$false -Force | Out-Null
    }

    # Enable secure boot if requested
    if ($SecureBoot) {
        Set-SecureBoot -VM $vm
    }

    return $vm
}

########################################################################
# Function: New-VMConfigs
# Purpose : Generate VM configurations
########################################################################
function New-VMConfigs {
    $virtualMachines = @"
{
    "virtualmachines": {}
}
"@ | ConvertFrom-Json -Depth 2
    
    # Generate Bootstrap (only if bootstrap_complete is false)
    if (-Not $bootstrap_complete) {
        $vm = @{
            type = "bootstrap"
            server = $vcenter
            datacenter = $datacenter
            cluster = $cluster
            network = $portgroup
            datastore = $datastore
            ip = $bootstrap_ip_address
        }
        add-member -Name "bootstrap" -value $vm -MemberType NoteProperty -InputObject $virtualMachines.virtualmachines
    }

    # Generate Control Plane
    for (($i = 0); $i -lt $control_plane_count; $i++) {
        $vm = @{
            type = "master"
            server = $vcenter
            datacenter = $datacenter
            cluster = $cluster
            network = $portgroup
            datastore = $datastore
            ip = $control_plane_ip_addresses[$i]
        }
        add-member -Name $control_plane_hostnames[$i] -value $vm -MemberType NoteProperty -InputObject $virtualMachines.virtualmachines
    }

    # Generate Compute
    for (($i = 0); $i -lt $compute_count; $i++) {
        $vm = @{
            type = "worker"
            server = $vcenter
            datacenter = $datacenter
            cluster = $cluster
            network = $portgroup
            datastore = $datastore
            ip = $compute_ip_addresses[$i]
        }
        add-member -Name $compute_hostnames[$i] -value $vm -MemberType NoteProperty -InputObject $virtualMachines.virtualmachines
    }

    # Generate Infrastructure Nodes
    if ($infra_count -gt 0) {
        for (($i = 0); $i -lt $infra_count; $i++) {
            $vm = @{
                type = "infra"
                server = $vcenter
                datacenter = $datacenter
                cluster = $cluster
                network = $portgroup
                datastore = $datastore
                ip = $infra_ip_addresses[$i]
            }
            add-member -Name $infra_hostnames[$i] -value $vm -MemberType NoteProperty -InputObject $virtualMachines.virtualmachines
        }
    }

    return $virtualMachines | ConvertTo-Json
}

########################################################################
# Function: New-LoadBalancerIgnition
# Purpose : Generate load balancer ignition config
########################################################################
function New-LoadBalancerIgnition {
    param (
        [string]$sshKey,
        [array]$apiBackendAddresses = $null
    )

    $haproxyService = @"
[Unit]
Description=HAProxy Load Balancer
After=network.target

[Service]
ExecStartPre=/usr/sbin/setenforce 0
ExecStart=/usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"@

    # Use provided API backend addresses if specified, otherwise use default behavior
    if ($null -eq $apiBackendAddresses) {
        $api = $control_plane_ip_addresses
        # Only include bootstrap if not marked as complete
        if (-Not $bootstrap_complete) {
            $api = @($bootstrap_ip_address) + $api
        }
    } else {
        $api = $apiBackendAddresses
    }

    # Use infrastructure nodes for ingress if available, otherwise compute nodes
    if ($infra_count -gt 0 -and $infra_ip_addresses.Length -gt 0) {
        $ingress = $infra_ip_addresses
    } else {
        $ingress = $compute_ip_addresses
    }

    # Create HAProxy configuration
    $haproxyConfig = @"
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

defaults
    mode                    tcp
    log                     global
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout check           10s
    maxconn                 3000

frontend api
    bind *:6443
    default_backend api-backend

frontend machine-config
    bind *:22623
    default_backend machine-config-backend

frontend http
    bind *:80
    default_backend http-backend

frontend https
    bind *:443
    default_backend https-backend

backend api-backend
    balance source
"@

    # Add API backend servers
    foreach ($addr in $api) {
        $haproxyConfig += "    server $addr $addr:6443 check`n"
    }

    $haproxyConfig += @"

backend machine-config-backend
    balance source
"@

    # Add machine-config backend servers (same as API)
    foreach ($addr in $api) {
        $haproxyConfig += "    server $addr $addr:22623 check`n"
    }

    $haproxyConfig += @"

backend http-backend
    balance source
    mode tcp
"@

    # Add HTTP backend servers
    foreach ($addr in $ingress) {
        $haproxyConfig += "    server $addr $addr:80 check`n"
    }

    $haproxyConfig += @"

backend https-backend
    balance source
    mode tcp
"@

    # Add HTTPS backend servers
    foreach ($addr in $ingress) {
        $haproxyConfig += "    server $addr $addr:443 check`n"
    }

    # Encode the haproxy config to base64
    $haproxyConfigBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($haproxyConfig))
    $haproxyServiceBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($haproxyService))

    # Create ignition config
    $ignitionConfig = @"
{
  "ignition": {
    "version": "3.2.0"
  },
  "passwd": {
    "users": [
      {
        "name": "core",
        "sshAuthorizedKeys": [
          "$sshKey"
        ]
      }
    ]
  },
  "storage": {
    "files": [
      {
        "path": "/etc/haproxy/haproxy.cfg",
        "mode": 644,
        "contents": {
          "source": "data:text/plain;charset=utf-8;base64,$haproxyConfigBase64"
        },
        "overwrite": true
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "name": "haproxy.service",
        "enabled": true,
        "contents": "$haproxyService"
      }
    ]
  }
}
"@

    return $ignitionConfig
}

function New-OpenshiftVMs {
    param(
        $NodeType
    )

    Write-Output "Creating $($NodeType) VMs"

    # Skip bootstrap creation if bootstrap_complete is true
    if ($NodeType -eq "bootstrap" -and $bootstrap_complete) {
        Write-Output "Bootstrap is marked as complete, skipping bootstrap VM creation"
        return
    }

    $jobs = @()
    $vmStep = (100 / ($vmHash.virtualmachines.Count + 1))  # +1 to avoid divide by zero if empty
    $vmCount = 1
    foreach ($key in $vmHash.virtualmachines.Keys) {
        $node = $vmHash.virtualmachines[$key]

        if ($NodeType -ne $node.type) {
            continue
        }

        $jobs += Start-ThreadJob -n "create-vm-$($metadata.infraID)-$($key)" -ScriptBlock {
            param($key,$node,$vm_template,$metadata,$tag,$scriptdir,$cliContext,$searchDomain)
            . ${scriptdir}\variables.ps1
            . ${scriptdir}\upi-functions.ps1
            Use-PowerCLIContext -PowerCLIContext $cliContext

            $name = "$($metadata.infraID)-$($key)"
            Write-Output "Creating $($name)"

            $rp = Get-ResourcePool -Name $($metadata.infraID) -Location $(Get-Cluster -Name $($node.cluster)) -Server $node.server
            $datastoreInfo = Get-Datastore -Name $node.datastore -Location $node.datacenter -Server $node.server

            # Pull network config for each node
            if ($node.type -eq "master") {
                $numCPU = $control_plane_num_cpus
                $memory = $control_plane_memory
            } elseif ($node.type -eq "worker") {
                $numCPU = $compute_num_cpus
                $memory = $compute_memory
            } elseif ($node.type -eq "infra") {
                $numCPU = $infra_num_cpus
                $memory = $infra_memory
            } else {
                # should only be bootstrap
                $numCPU = $control_plane_num_cpus
                $memory = $control_plane_memory
            }
            $ip = $node.ip
            $network = New-VMNetworkConfig -Server $node.server -Hostname $name -IPAddress $ip -Netmask $netmask -Gateway $gateway -DNS $dns -SearchDomain $searchDomain

            # Get the content of the ignition file per machine type (bootstrap, master, worker, infra)
            # For infra nodes, use the worker ignition
            $ignitionFile = if ($node.type -eq "infra") { "./worker.ign" } else { "./$($node.type).ign" }
            $bytes = Get-Content -Path $ignitionFile -AsByteStream
            $ignition = [Convert]::ToBase64String($bytes)

            # Get correct tag
            $tagCategory = Get-TagCategory -Server $node.server -Name "openshift-$($metadata.infraID)" -ErrorAction continue 2>$null
            $tag = Get-Tag -Server $node.server -Category $tagCategory -Name "$($metadata.infraID)" -ErrorAction continue 2>$null

            # Get correct template / folder
            $folder = Get-Folder -Server $node.server -Name $clustername -Location $node.datacenter
            $template = Get-VM -Server $node.server -Name $vm_template -Location $($node.datacenter)

            # Clone the virtual machine from the imported template
            $vm = New-OpenShiftVM -Server $node.server -Template $template -Name $name -ResourcePool $rp -Datastore $datastoreInfo -Location $folder -IgnitionData $ignition -Tag $tag -Networking $network -Network $node.network -SecureBoot $secureboot -StoragePolicy $storagepolicy -NumCPU $numCPU -MemoryMB $memory

            # Handle VM startup with delay if required
            if ($node.type -eq "master" -And $delayVMStart) {
                # To give bootstrap some time to start, lets wait 2 minutes
                Start-ThreadJob -ThrottleLimit 5 -InputObject $vm {
                    Start-Sleep -Seconds 90
                    $input | Start-VM
                }
            } elseif (($node.type -eq "worker" -or $node.type -eq "infra") -And $delayVMStart) {
                # Workers and infra nodes are not needed right away, wait till masters
                # have started machine-server. Wait 7 minutes to start.
                Start-ThreadJob -ThrottleLimit 5 -InputObject $vm {
                    Start-Sleep -Seconds 600
                    $input | Start-VM
                }
            } else {
                $vm | Start-VM
            }
        } -ArgumentList @($key,$node,$vm_template,$metadata,$tag,$SCRIPTDIR,$cliContext,$searchDomain)
        Write-Progress -id 222 -Activity "Creating virtual machines" -PercentComplete ($vmStep * $vmCount)
        $vmCount++
    }
    Wait-Job -Job $jobs
    foreach ($job in $jobs) {
        Receive-Job -Job $job
    }
}

function Remove-DnsRecord {
    param(
        [string]$Name
    )
    
    try {
        # This is a placeholder - implement with your actual DNS management method
        # For example, using nsupdate:
        $ttl = 8600 # Match the TTL we used in Terraform
        $command = @"
echo "update delete $Name $ttl A" | nsupdate -v -d
"@
        Invoke-Expression $command
        Write-Output "Removed DNS record for $Name"
    }
    catch {
        Write-Error "Failed to remove DNS record for $Name: $_"
    }
}