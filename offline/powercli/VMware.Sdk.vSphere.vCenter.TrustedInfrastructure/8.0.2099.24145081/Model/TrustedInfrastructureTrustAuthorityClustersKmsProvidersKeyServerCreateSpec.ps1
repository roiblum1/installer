#
# TrustedInfrastructure Paths
# The vcenter trusted_infrastructure package provides services that enable a Trusted Infrastructure. They are responsible for ensuring that infrastructure nodes are running trusted software and for releasing encryption keys only to trusted infrastructure nodes.
# Contact: powercli@vmware.com
# Generated by OpenAPI Generator: https://openapi-generator.tech
#

<#
.DESCRIPTION

The Providers.KeyServerCreateSpec structure contains fields that describe the desired configuration for the key server.

.PARAMETER Type
No description available.
.PARAMETER Description
Description of the key server. If unset, description will not be added.
.PARAMETER ProxyServer
No description available.
.PARAMETER ConnectionTimeout
Connection timeout in seconds. If unset, connection timeout will not be set.
.PARAMETER KmipServer
No description available.
.OUTPUTS

TrustedInfrastructureTrustAuthorityClustersKmsProvidersKeyServerCreateSpec<PSCustomObject>

.LINK

Online Version: https://developer.vmware.com/docs/vsphere-automation/latest/vcenter/data-structures/TrustedInfrastructure/TrustAuthorityClusters/Kms/Providers/KeyServerCreateSpec/
#>

function Initialize-TrustedInfrastructureTrustAuthorityClustersKmsProvidersKeyServerCreateSpec {
    [CmdletBinding(HelpURI = "https://developer.vmware.com/docs/vsphere-automation/latest/vcenter/data-structures/TrustedInfrastructure/TrustAuthorityClusters/Kms/Providers/KeyServerCreateSpec/")]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("KMIP")]
        ${Type},
        [Parameter(Mandatory = $false)]
        [ValidateScript({ $_ -is [string] })]
        ${Description},
        [Parameter(Mandatory = $false)]
        [PSTypeName("TrustedInfrastructureNetworkAddress")]
        [PSCustomObject]
        ${ProxyServer},
        [Parameter(Mandatory = $false)]
        [System.Nullable[Int64]]
        ${ConnectionTimeout},
        [Parameter(Mandatory = $false)]
        [PSTypeName("TrustedInfrastructureTrustAuthorityClustersKmsProvidersKmipServerCreateSpec")]
        [PSCustomObject]
        ${KmipServer}
    )

    Process {
        'Creating PSCustomObject: VMware.Sdk.vSphere.vCenter.TrustedInfrastructure => vSphereTrustedInfrastructureTrustAuthorityClustersKmsProvidersKeyServerCreateSpec' | Write-Debug

        if ($Type -eq $null) {
            throw "invalid value for 'Type', 'Type' cannot be null."
        }


        $PSO = [PSCustomObject]@{
            "PSTypeName" = "TrustedInfrastructureTrustAuthorityClustersKmsProvidersKeyServerCreateSpec"
            "type" = ${Type}
            "description" = ${Description}
            "proxy_server" = ${ProxyServer}
            "connection_timeout" = ${ConnectionTimeout}
            "kmip_server" = ${KmipServer}
        }


        return $PSO
    }
}

