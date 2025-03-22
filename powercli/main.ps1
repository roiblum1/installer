#!/usr/bin/pwsh

# -------------------------
#  Main Deployment Script for Disconnected Environment
# -------------------------

$ErrorActionPreference = "Stop"
$MYINV     = $MyInvocation
$SCRIPTDIR = Split-Path $MYINV.MyCommand.Path

Write-Output "SCRIPT DIR: $($SCRIPTDIR)"

# --------------------------------------------------------------------
# 1. Load Variables & Helper Functions
# --------------------------------------------------------------------
. ${SCRIPTDIR}\variables.ps1     # Your local environment variables
. ${SCRIPTDIR}\upi-functions.ps1 # Contains New-OpenShiftVM, New-VMNetworkConfig, etc.

# We do not have CA certs for vSphere, so ignore invalid SSL certs:
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -DefaultVIServerMode Multiple -ParticipateInCEIP:$false -Confirm:$false | Out-Null
$Env:GOVC_INSECURE = 1

# --------------------------------------------------------------------
# 2. Connect to vCenter
# --------------------------------------------------------------------
try {
    # Try to use the encrypted credentials file if it exists
    if (Test-Path $vcentercredpath) {
        Write-Output "Using saved credentials from $vcentercredpath"
        $viservers = @{}
        $viservers[$vcenter] = Connect-VIServer -Server $vcenter -Credential (Import-Clixml $vcentercredpath)
    } else {
        # Otherwise, use the username/password from variables.ps1
        Write-Output "Using credentials from variables.ps1"
        $secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($username, $secpasswd)
        $viservers = @{}
        $viservers[$vcenter] = Connect-VIServer -Server $vcenter -Credential $credential
        
        # Optionally save the credentials for future use
        if (!(Test-Path "secrets")) { 
            New-Item -ItemType Directory -Path "secrets" | Out-Null 
        }
        $credentialPath = Join-Path "secrets" "vcenter-creds.xml"
        Write-Output "Saving credentials to $credentialPath for future use"
        $credential | Export-Clixml -Path $credentialPath
    }
} catch {
    Write-Error "Failed to connect to vCenter: $_"
    exit 1
}

$cliContext = Get-PowerCLIContext

# --------------------------------------------------------------------
# 3. Verify Offline Environment Requirements
# --------------------------------------------------------------------

# Check for openshift-install binary
if (-not (Test-Path -Path "openshift-install")) {
    Write-Error "ERROR: 'openshift-install' binary not found in current directory. This is required for disconnected install."
    exit 1
}

# Check for RHCOS OVA
if ($uploadTemplateOva) {
    $ovaPath = "template-$($Version).ova"
    if (-not (Test-Path -Path $ovaPath)) {
        Write-Error "ERROR: OVA file '$ovaPath' not found locally. For disconnected install, this must be pre-downloaded."
        exit 1
    } else {
        Write-Output "Found local OVA template at '$ovaPath'; will use for VM creation."
    }
}

# --------------------------------------------------------------------
# 4. Prepare SSH Key
# --------------------------------------------------------------------
if (-not (Test-Path -Path $sshkeypath)) {
    Write-Error "ERROR: SSH key not found at $sshkeypath"
    exit 1
}

$sshKey = [string](Get-Content -Path $sshkeypath -Raw:$true) -Replace '\n',''

# --------------------------------------------------------------------
# 5. Generate install-config (offline / local usage)
# --------------------------------------------------------------------
if ($createInstallConfig) {
    Write-Output "Creating install-config.yaml for disconnected installation..."
    
    # Convert existing installconfig JSON into a PS object
    $config = ConvertFrom-Json -InputObject $installconfig

    # Update with local environment values
    $config.metadata.name                    = $clustername
    $config.baseDomain                       = $basedomain
    $config.sshKey                           = $sshKey
    $config.platform.vsphere.vcenter         = $vcenter
    $config.platform.vsphere.username        = $username
    $config.platform.vsphere.password        = $password
    $config.platform.vsphere.datacenter      = $datacenter
    $config.platform.vsphere.defaultDatastore= $datastore
    $config.platform.vsphere.cluster         = $cluster
    $config.platform.vsphere.network         = $portgroup
    $config.platform.vsphere.apiVIP          = $apivip
    $config.platform.vsphere.ingressVIP      = $ingressvip
    
    # Add OpenShift image references to the install-config if specified in variables
    if ($imageContentSources -and $imageContentSources.Count -gt 0) {
        $config | Add-Member -Name 'imageContentSources' -Value $imageContentSources -MemberType NoteProperty -Force
    }

    $config.pullSecret = $pullsecret -replace "`n", "" -replace " ", ""

    # Save backup of install-config
    if (-not (Test-Path -Path "backup")) { 
        New-Item -ItemType Directory -Path "backup" -Force | Out-Null 
    }
    $config | ConvertTo-Json -Depth 8 | Out-File -FilePath backup/install-config.yaml -Force:$true

    # Write out install-config.yaml
    $config | ConvertTo-Json -Depth 8 | Out-File -FilePath install-config.yaml -Force:$true
    
    Write-Output "Created install-config.yaml"
}

# --------------------------------------------------------------------
# 6. Generate ignitions
# --------------------------------------------------------------------
if ($generateIgnitions) {
    Write-Output "Generating manifests and ignition files..."
    
    # Create backup directory if it doesn't exist
    if (-not (Test-Path -Path "backup")) { 
        New-Item -ItemType Directory -Path "backup" -Force | Out-Null 
    }
    
    # Create manifests
    Write-Output "Creating manifests..."
    Start-Process -Wait -FilePath ./openshift-install -ArgumentList @("create", "manifests")

    # Create backup of manifests
    Copy-Item -Path .\openshift -Destination .\backup\openshift -Recurse -Force
    
    # Remove the default machine objects so we can do UPI
    Write-Output "Removing default machine objects for UPI deployment..."
    Remove-Item -Force -ErrorAction Ignore `
      .\openshift\99_openshift-cluster-api_master-machines-*.yaml, `
      .\openshift\99_openshift-cluster-api_worker-machineset-*.yaml

    # Create the ignition configs
    Write-Output "Creating ignition configs..."
    Start-Process -Wait -FilePath ./openshift-install -ArgumentList @("create", "ignition-configs")

    # Create backup of ignition files
    Copy-Item -Path .\*.ign -Destination .\backup\ -Force
    
    Write-Output "Manifests and ignition files generated successfully."
}

# --------------------------------------------------------------------
# 7. Read Installer metadata (infraID, etc.)
# --------------------------------------------------------------------
if (-not (Test-Path -Path "metadata.json")) {
    Write-Error "ERROR: metadata.json not found. Did the ignition generation succeed?"
    exit 1
}

$metadata = Get-Content -Path .\metadata.json | ConvertFrom-Json

# The script expects a base RHCOS template named "<infraID>-rhcos" if not set:
if ($null -eq $vm_template -or $vm_template -eq "") {
    $vm_template = "$($metadata.infraID)-rhcos"
    Write-Output "Using template name: $vm_template"
}

# --------------------------------------------------------------------
# 8. Create or get Tag Category and Tag for resources
# --------------------------------------------------------------------
$tagCategoryName = "openshift-$($metadata.infraID)"
$tagName         = $metadata.infraID

foreach ($viserver in $viservers.Keys) {
    $tagCategory = Get-TagCategory -Server $viserver -Name $tagCategoryName -ErrorAction SilentlyContinue
    if (-not $tagCategory) {
        Write-Output "Creating Tag Category $tagCategoryName"
        $tagCategory = New-TagCategory -Server $viserver -Name $tagCategoryName -EntityType "VirtualMachine","ResourcePool","Folder","Datastore","StoragePod"
    }
    $tag = Get-Tag -Server $viserver -Category $tagCategory -Name $tagName -ErrorAction SilentlyContinue
    if (-not $tag) {
        Write-Output "Creating Tag $tagName"
        $tag = New-Tag -Server $viserver -Category $tagCategory -Name $tagName
    }
}

# --------------------------------------------------------------------
# 9. Set up the datacenter, folder, resource pool, and template
# --------------------------------------------------------------------
$templateInProgress = @()
$jobs = @()

Write-Output "Setting up datacenter, folder, and resource pool..."

$datastoreInfo = Get-Datastore -Server $viservers[$vcenter] -Name $datastore -Location $datacenter

# Check / create folder
Write-Output "Checking for folder $($clustername) in $($datacenter)..."
$folder = Get-Folder -Server $viservers[$vcenter] -Name $clustername -Location $datacenter -ErrorAction SilentlyContinue
if (-not $folder) {
    Write-Output "Creating folder $($clustername) in $($datacenter)"
    (Get-View (Get-Datacenter -Server $viservers[$vcenter] -Name $datacenter).ExtensionData.vmfolder).CreateFolder($clustername) | Out-Null
    $folder = Get-Folder -Server $viservers[$vcenter] -Name $clustername -Location $datacenter
    New-TagAssignment -Server $viservers[$vcenter] -Entity $folder -Tag $tag | Out-Null
}

# Check / create resource pool
Write-Output "Checking for resource pool $($metadata.infraID) in $($cluster)..."
$rp = Get-ResourcePool -Server $viservers[$vcenter] -Name $($metadata.infraID) -Location (Get-Cluster -Server $viservers[$vcenter] -Name $($cluster)) -ErrorAction SilentlyContinue
if (-not $rp) {
    Write-Output "Creating resource pool $($metadata.infraID) in cluster $($cluster)"
    $rp = New-ResourcePool -Server $viservers[$vcenter] -Name $($metadata.infraID) -Location (Get-Cluster -Server $viservers[$vcenter] -Name $($cluster))
    New-TagAssignment -Server $viservers[$vcenter] -Entity $rp -Tag $tag | Out-Null
}

# Check if the RHCOS template exists
Write-Output "Checking for VM template '$vm_template' in $($datacenter)"
$template = Get-VM -Server $viservers[$vcenter] -Name $vm_template -Location $datacenter -ErrorAction SilentlyContinue

# If not found, import OVA
if (-not $template -and $uploadTemplateOva) {
    Write-Output "Template not found. Importing OVA template..."
    $vmhost = Get-Random -InputObject (Get-VMHost -Server $viservers[$vcenter] -Location (Get-Cluster -Server $viservers[$vcenter] -Name $cluster))
    $ovfConfig = Get-OvfConfiguration -Server $viservers[$vcenter] -Ovf $ovaPath
    
    # Map networks so OVA has a default
    $ovfConfig.NetworkMapping.VM_Network.Value = $portgroup

    Write-Output "Importing OVA template - this may take some time..."
    $templateVM = Import-VApp -Server $viservers[$vcenter] -Source $ovaPath -Name $vm_template `
                               -OvfConfiguration $ovfConfig -VMHost $vmhost `
                               -Datastore $datastoreInfo -Location $folder -Force:$true

    New-TagAssignment -Server $viservers[$vcenter] -Entity $templateVM -Tag $tag | Out-Null

    # Optional adjustments to the newly-imported template
    Write-Output "Configuring template VM settings..."
    Set-VM -Server $viservers[$vcenter] -VM $templateVM -MemoryGB 16 -NumCpu 4 -CoresPerSocket 4 -Confirm:$false | Out-Null
    updateDisk -VM $templateVM -CapacityGB 120
    New-AdvancedSetting -Server $viservers[$vcenter] -Entity $templateVM -Name "disk.EnableUUID" -Value "TRUE" -Confirm:$false -Force | Out-Null
    New-AdvancedSetting -Server $viservers[$vcenter] -Entity $templateVM -Name "guestinfo.ignition.config.data.encoding" -Value "base64" -Confirm:$false -Force | Out-Null
    
    Write-Output "Template OVA import and configuration complete."
}

# Handle bootstrap VM deletion if bootstrap is complete
if ($bootstrap_complete) {
    Write-Output "Bootstrap process marked as complete, handling bootstrap resources..."
    
    # Find and remove bootstrap VM
    $bootstrapVM = Get-VM -Server $viservers[$vcenter] -Name "$($metadata.infraID)-bootstrap*" -ErrorAction SilentlyContinue
    if ($bootstrapVM) {
        Write-Output "Stopping and removing bootstrap VM $($bootstrapVM.Name)"
        if ($bootstrapVM.PowerState -eq "PoweredOn") {
            Stop-VM -Server $viservers[$vcenter] -VM $bootstrapVM -Confirm:$false > $null
        }
        Remove-VM -Server $viservers[$vcenter] -VM $bootstrapVM -DeletePermanently -Confirm:$false
    } else {
        Write-Output "Bootstrap VM not found - already removed or never created"
    }
    
    # Find and delete bootstrap DNS records if DNS handler is available
    if ($CreateDNSRecords) {
        Write-Output "Removing bootstrap DNS records..."
        $bootstrapFQDN = "bootstrap-0.$($clustername).$($basedomain)"
        Remove-DnsRecord -Name $bootstrapFQDN
    }
}

# --------------------------------------------------------------------
# 10. Create the Load Balancer VM if needed
# --------------------------------------------------------------------
if ($deploy_lb) {
    Write-Output "Creating Load Balancer VM"

    # Get resources for LB
    $template = Get-VM -Server $viservers[$vcenter] -Name $vm_template -Location $datacenter -ErrorAction SilentlyContinue
    if (-not $template) {
        Write-Error "ERROR: Template $vm_template not found. Cannot proceed with VM creation."
        exit 1
    }

    # Determine API backends - exclude bootstrap if bootstrap_complete is true
    $apiBackends = @()
    if (-not $bootstrap_complete) {
        $apiBackends += $bootstrap_ip_address
    }
    $apiBackends += $control_plane_ip_addresses

    # Build LB ignition with API backends:
    $lbIgnition = New-LoadBalancerIgnition -sshKey $sshKey -apiBackendAddresses $apiBackends
    $ignition = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($lbIgnition))

    # Build static network config for LB (including optional SearchDomain)
    $lbNetwork = New-VMNetworkConfig `
        -Hostname    "$($metadata.infraID)-lb" `
        -IPAddress   $lb_ip_address `
        -Netmask     $netmask `
        -Gateway     $gateway `
        -DNS         $dns `
        -SearchDomain $searchDomain

    # Create the LB VM
    $lbVM = New-OpenShiftVM -IgnitionData $ignition `
                            -Name         "$($metadata.infraID)-lb" `
                            -Template     $template `
                            -ResourcePool $rp `
                            -Datastore    $datastoreInfo `
                            -Location     $folder `
                            -Tag          $tag `
                            -Networking   $lbNetwork `
                            -Network      $portgroup `
                            -SecureBoot   $secureboot `
                            -StoragePolicy $storagepolicy `
                            -MemoryMB 8192 `
                            -NumCpu   4

    # Power on the LB
    Write-Output "Starting the Load Balancer VM"
    $lbVM | Start-VM | Out-Null
}

# --------------------------------------------------------------------
# 11. Create the OpenShift VMs
# --------------------------------------------------------------------
$virtualmachines = New-VMConfigs

Write-Output "Creating OpenShift cluster VMs..."
$vmHash = ConvertFrom-Json -InputObject $virtualmachines -AsHashtable

Write-Progress -id 222 -Activity "Creating virtual machines" -PercentComplete 0

# Only create bootstrap VM if bootstrap is not marked as complete
if (-Not $bootstrap_complete) {
    New-OpenshiftVMs "bootstrap"
}

New-OpenshiftVMs "master"
New-OpenshiftVMs "worker"

# Create infrastructure nodes if defined
if ($infra_count -gt 0) {
    New-OpenshiftVMs "infra"
}

Write-Progress -id 222 -Activity "Completed virtual machines" -PercentComplete 100 -Completed

# Installation monitoring and completion code
if ($waitForComplete) {
    # -- Wait for cluster completion code here --
    # Extract kubeconfig keys for approval process
    if (Test-Path "auth/kubeconfig") {
        $match = Select-String "client-certificate-data: (.*)" -Path ./auth/kubeconfig
        [Byte[]]$bytes    = [Convert]::FromBase64String($match.Matches.Groups[1].Value)
        $clientCertData   = [System.Text.Encoding]::ASCII.GetString($bytes)

        $match = Select-String "client-key-data: (.*)" -Path ./auth/kubeconfig
        $bytes = [Convert]::FromBase64String($match.Matches.Groups[1].Value)
        $clientKeyData    = [System.Text.Encoding]::ASCII.GetString($bytes)

        # Create a X509Certificate2 object for Invoke-WebRequest
        $cert   = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($clientCertData, $clientKeyData)

        # Extract the kubernetes endpoint uri
        $match   = Select-String "server: (.*)" -Path ./auth/kubeconfig
        $kubeurl = $match.Matches.Groups[1].Value

        # Wait for API to be available
        $apiTimeout = (20*60)
        $apiCount = 1
        $apiSleep = 30
        Write-Progress -Id 444 -Status "1% Complete" -Activity "API" -PercentComplete 1
        
        :api while ($true) {
            Start-Sleep -Seconds $apiSleep
            try {
                $webrequest = Invoke-WebRequest -Uri "$($kubeurl)/version" -SkipCertificateCheck
                $version = (ConvertFrom-Json $webrequest.Content).gitVersion

                if ($version -ne "" ) {
                    Write-Output "API Version: $($version)"
                    Write-Progress -Id 444 -Status "Completed" -Activity "API" -PercentComplete 100
                    break api
                }
            } catch {}

            $percentage = ((($apiCount*$apiSleep)/$apiTimeout)*100)
            if ($percentage -le 100) {
                Write-Progress -Id 444 -Status "$percentage% Complete" -Activity "API" -PercentComplete $percentage
            }
            $apiCount++
        }

        # ---- Additional monitoring for CSRs and cluster completion ----
    } else {
        Write-Output "auth/kubeconfig not found - can't monitor cluster installation"
    }
}

Get-Job | Remove-Job -ErrorAction SilentlyContinue

foreach ($key in $viservers.Keys) {
    Write-Output "Disconnecting from $($key)"
    Disconnect-VIServer -Server $key -Force:$true -Confirm:$false
}

Write-Output "====================================================="  
Write-Output "OpenShift deployment complete!"
Write-Output "====================================================="
Write-Output "Next steps:"  
if (-not $bootstrap_complete) {
    Write-Output "1. Wait for bootstrap to complete, then run this script again with bootstrap_complete=`$true"
}
Write-Output "2. After the cluster is fully operational, apply the infrastructure node configuration"
Write-Output "   using the post-install-config.ps1 script"
Write-Output "3. Access the web console at: https://console-openshift-console.apps.$clustername.$basedomain"  
Write-Output "4. Use 'oc login' with your credentials to access the cluster from command line"