using module VMware.PowerCLI.VCenter.Types.CertificateManagement
using namespace VMware.VimAutomation.ViCore.Types.V1
using namespace VMware.VimAutomation.ViCore.Types.V1.Inventory
using namespace System.Security.Cryptography.X509Certificates
using namespace VMware.VimAutomation.Sdk.Util10Ps.BaseCmdlet
using namespace VMware.VimAutomation.Sdk.Types.V1
using namespace VMware.VimAutomation.ViCore.Types.V1

. (Join-Path $PSScriptRoot "../utils/Connection.ps1")
. (Join-Path $PSScriptRoot "../utils/Report-CommandUsage.ps1")
. (Join-Path $PSScriptRoot "../utils/Get-ConnectionUid.ps1")
. (Join-Path $PSScriptRoot "../types/builders/New-TrustedCertificateInfo.ps1")

<#
.SYNOPSIS

This cmdlet retrieves information about the trusted certificates in a vCenter Server environment.

.DESCRIPTION

This cmdlet retrieves information about the certificates trusted by a vCenter Server instance and/or its connected ESXi hosts.
The returned object is a pair of the certificate and the vCenter Server or ESXi entity that trusts the certificate. The cmdlet might return more than one certificate/entity object.
If you pass no parameters, the command returns all certificate/entity pairs trusted by the vCenter Server instance and the connected ESXi hosts.

.PARAMETER Id
Specifies the UIDs of the trusted certificates you want to retrieve.

Note: If you specify multiple UIDs, the system returns a certificate/entity object for each UID.

.PARAMETER VCenterOnly
Specifies that the result includes only the certificates trusted by the vCenter Server instance.

.PARAMETER EsxOnly
Specifies that the result includes only the certificates trusted by the connected ESXi hosts.

.PARAMETER VMHost
Specifies one or more ESXi hosts whose trusted certificates you want to retrieve.

.PARAMETER Server
Specifies the vCenter Server systems on which you want to run the cmdlet.
If no value is provided or $null value is passed to this parameter, the command runs on the default server.
For more information about default servers, see the description of the Connect-VIServer cmdlet.

.EXAMPLE
PS C:\> Get-VITrustedCertificate

Retrieves the certificates trusted by the vCenter Server instance and the connected ESXi hosts.

.EXAMPLE
PS C:\> Get-VITrustedCertificate -VCenterOnly

Retrieves the certificates trusted by the vCenter Server system only.

.EXAMPLE
PS C:\> Get-VITrustedCertificate -EsxOnly

Retrieves the certificates trusted by the connected ESXi hosts only.

.EXAMPLE
PS C:\> Get-VITrustedCertificate -VMHost 'MyHost'

Retrieves the certificates trusted by the specified ESXi host(s) only.

.OUTPUTS
Zero or more TrustedCertificateInfo objects

.LINK

https://developer.vmware.com/docs/powercli/latest/vmware.powercli.vcenter/commands/get-vitrustedcertificate


#>
function Get-VITrustedCertificate {
    [CmdletBinding(
       ConfirmImpact = "None",
       DefaultParameterSetName = "Default")]
    [OutputType([TrustedCertificateInfo])]
    Param (
      [Parameter(
         Mandatory = $true,
         ParameterSetName = "ById"
      )]
      [string[]]
      $Id,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = "VCenterOnly"
        )]
        [switch]
        $VCenterOnly,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = "EsxOnly"
        )]
        [switch]
        $EsxOnly,

        [Parameter(
            Mandatory = $true,
            Position = 0,
            ParameterSetName = "PerEsx",
            ValueFromPipeline = $true
        )]
        [ObnArgumentTransformation([VMHost])]
        [VMHost[]]
        $VMHost,

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName = "VCenterOnly")]
        [Parameter(ParameterSetName = "EsxOnly")]
        [Parameter(ParameterSetName = "PerEsx")]
        [ObnArgumentTransformation([VIServer], Critical = $true)]
        [VIServer]
        $Server
    )

   Begin {
      Report-CommandUsage $MyInvocation
      
      if ($Id) {
         # ById parameter set
         $Id | % {
            if (![DistinguishedName]::IsDistinguishedName($_)) {
               Write-PowerCLIError `
                  -ErrorObject "Id '$($_)' is invalid trusted certificate Uid." `
                  -ErrorId "PowerCLI_VITrustedCertificate_InvalidUid" `
                  -Terminating
            }

            $parentDn = [DistinguishedName]::GetParentDn($_)
            if ($parentDn -eq $null) {
               Write-PowerCLIError `
                  -ErrorObject "Id '$($_)' is invalid trusted certificate Uid." `
                  -ErrorId "PowerCLI_VITrustedCertificate_InvalidTrustedCertificateUid_TopLevelUid" `
                  -Terminating
            }
            $parentDnKey = [DistinguishedName]::GetRdnKey($parentDn)
            if ($parentDnKey -ne [DnKeyListSdk]::VIServer -and `
               $parentDnKey -ne [DnKeyListViCore]::VMHost) {
                  Write-PowerCLIError `
                     -ErrorObject "Id '$($_)' is invalid trusted certificate Uid." `
                     -ErrorId "PowerCLI_VITrustedCertificate_InvalidTrustedCertificateUid_NotVmHostOrViServerParent" `
                     -Terminating
               }
         }
      } else {
         # All other parameter sets
         # Handle Server obn first
         if($Server) {
            $resolvedServer = Resolve-ObjectByName -Object $Server `
               -Type ([VIServer]) `
               -OneObjectExpected

            $Server = [VIServer] $resolvedServer
         }

         $activeServer = GetActiveServer($Server)
         ValidateApiVersionSupported -server $activeServer -major 6 -minor 7 -ErrorAction:Stop

         # Handle OBN
         if($VMHost) {
            $resolvedVMHosts = Resolve-ObjectByName -Object $VMHost `
               -Type ([VMHost]) `
               -CollectorCmdlet 'Get-VMHost' `
               -OneOrMoreObjectsExpected `
               -Server $activeServer

            $VMHost = [VMHost[]] $resolvedVMHosts
         }
      }
   }

   Process {
      if ($Id) {
         # ById parameter set
         $foundIds = [System.Collections.ArrayList]::new()

         $Id | ? {
            [DistinguishedName]::GetRdnKey([DistinguishedName]::GetParentDn($_)) -eq [DnKeyListSdk]::VIServer
         } | % {
            $currentServer = $_ | Get-ConnectionUid | Get-ServerByUid
            $currentApiServer = GetApiServer($currentServer)

            ValidateApiVersionSupported -server $currentServer -major 6 -minor 7 -ErrorAction:Stop
            $result = $null
            $result = [DistinguishedName]::GetRdnValue($_) | Get-ViCenterTrustedCertificate `
               -ApiServer $currentApiServer `
               -Server $currentServer
            if($result) {
               $foundIds.Add($result.Uid) | Out-Null
               $result
            }
         }

         $vmhostIds = $id | % {
            [DistinguishedName]::GetParentDn($_)
         } | ? {
            [DistinguishedName]::GetRdnKey($_) -eq [DnKeyListViCore]::VMHost
         } | Get-Unique

         if ($vmhostIds) {
            $vmhostIds | % {
               $vmhostServer = $_ | Get-ConnectionUid | Get-ServerByUid
               Get-VMHost -Id $_ -Server $vmhostServer | `
                  Get-VMHostTrustedCertificate -Server $vmhostServer | ? {
                     $Id -contains $_.Uid
                  } | % {
                     $foundIds.Add($_.Uid) | Out-Null
                     $_
                  }
            }
         }

         foreach ($currentId in $Id) {
            if (-not $foundIds.Contains($currentId)) {
               Write-PowerCLIError `
                  -ErrorObject "[VITrustedCertificate] with Uid '$currentId' not found." `
                  -ErrorId "PowerCLI_VITrustedCertificate_IdNotFound" `
                  -ErrorCategory ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
            }
         }
      } else {
         # all other parameter sets

         # Validate all objects are from the same server
         if($VMHost) {
            $VMHost | ValidateSameServer -ExpectedServer $activeServer
         }

         $collectVc = $PsCmdlet.ParameterSetName -eq 'Default' -or `
            ($PsCmdlet.ParameterSetName -eq 'VCenterOnly' -and $VCenterOnly.ToBool())

         $collectEsx = $PsCmdlet.ParameterSetName -eq 'Default' -or `
            ($PsCmdlet.ParameterSetName -eq 'EsxOnly' -and $EsxOnly.ToBool())

         if ($collectVc) {
            $apiServer = GetApiServer($activeServer)
            
            try {
               $trustedChainIds =
                  Invoke-ListCertificateManagementTrustedRootChains -Server $apiServer -ErrorAction:Stop | ForEach-Object { $_.chain }

               foreach($trustedChainId in $trustedChainIds) {
                  $trustedChainId | Get-ViCenterTrustedCertificate -ApiServer $apiServer -Server $activeServer | Write-Output
               }
            } catch {
               Write-PowerCLIError `
                  -ErrorObject $_ `
                  -ErrorId "PowerCLI_VITrustedCertificate_FailedToListVcTrustChains"
            }
         }

         if ($collectEsx) {
            $tempVMHost = Get-VMHost -Server $activeServer
            if ($tempVMHost) {
               $VMHost = $tempVMHost
            }
         }

         if ($VMHost) {
            foreach ($currentVMHost in $VMHost) {
               $currentVMHost | Get-VMHostTrustedCertificate -Server $activeServer | Write-Output
            }
         }
      }
   }
}

function Get-VMHostTrustedCertificate {
   param(
      [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
      [VMHost]
      $VMHost,

      [Parameter(Mandatory = $true)]
      [VIServer]
      $Server
   )

   try {
      $certificateManager = Get-View $VMHost.ExtensionData.ConfigManager.CertificateManager -Server $Server
      $trustedCertificates = $certificateManager.ListCACertificates()
      foreach($trustedCertificate in $trustedCertificates) {
         try {
            $certificate = ConvertTo-X509Certificate -CertificatePEM $trustedCertificate
            New-TrustedCertificateInfo `
               -IdWithinStore $certificate.Thumbprint `
               -Certificate $certificate `
               -TargetESXi $VMHost | Write-Output
         } catch {
            Write-PowerCLIError `
               -ErrorObject $_ `
               -ErrorId "PowerCLI_VITrustedCertificate_FailedEsxParseCertificate"
         }
      }
   } catch {
      Write-PowerCLIError `
         -ErrorObject $_ `
         -ErrorId "PowerCLI_VITrustedCertificate_FailedToListEsxTrustChains"
   }
}

function Get-ViCenterTrustedCertificate {
   param(
      [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
      [string]
      $TrustedChainId,

      [Parameter(Mandatory = $true)]
      [PSTypeName('vSphereServerConfiguration')]
      $ApiServer,

      [Parameter(Mandatory = $true)]
      [VIServer]
      $Server
   )

   $trustedChain = $null
   try {
      $trustedChain = Invoke-GetChainCertificateManagementTrustedRootChains `
         -Chain $TrustedChainId `
         -Server $ApiServer `
         -ErrorAction:Stop
   } catch {
      $serverError = $_.Exception.ServerError

      if($serverError.error_type -ne "NOT_FOUND") {
         Write-PowerCLIError `
            -ErrorObject $_ `
            -ErrorId "PowerCLI_VITrustedCertificate_Invoke_GetChainCertificateManagementTrustedRootChains"
      }
   }

   if($trustedChain) {
      if($trustedChain.cert_chain.cert_chain.Length -gt 1) {
         throw "Unexpected API response - chain contains more than one entity."
      }
      $chain = $trustedChain.cert_chain.cert_chain[0]
      try {
         New-TrustedCertificateInfo `
            -IdWithinStore $TrustedChainId `
            -Certificate (Resolve-TrustChain -TrustChainPem $chain) `
            -TargetVC $Server | `
            Write-Output
      } catch {
         Write-PowerCLIError `
            -ErrorObject $_ `
            -ErrorId "PowerCLI_VITrustedCertificate_FailedVcParseCertificate"
      }
   }
}

# SIG # Begin signature block
# MIIpiAYJKoZIhvcNAQcCoIIpeTCCKXUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDXL8S5Vx8dqlXx
# 4tkIVzmK4JYtX7CTtSI0G2LgNhlXh6CCDnQwggawMIIEmKADAgECAhAIrUCyYNKc
# TJ9ezam9k67ZMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0z
# NjA0MjgyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDVtC9C0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0
# JAfhS0/TeEP0F9ce2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJr
# Q5qZ8sU7H/Lvy0daE6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhF
# LqGfLOEYwhrMxe6TSXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+F
# LEikVoQ11vkunKoAFdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh
# 3K3kGKDYwSNHR7OhD26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJ
# wZPt4bRc4G/rJvmM1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQay
# g9Rc9hUZTO1i4F4z8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbI
# YViY9XwCFjyDKK05huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchAp
# QfDVxW0mdmgRQRNYmtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRro
# OBl8ZhzNeDhFMJlP/2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IB
# WTCCAVUwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+
# YXsIiGX0TkIwHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAED
# MAgGBmeBDAEEATANBgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql
# +Eg08yy25nRm95RysQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFF
# UP2cvbaF4HZ+N3HLIvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1h
# mYFW9snjdufE5BtfQ/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3Ryw
# YFzzDaju4ImhvTnhOE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5Ubdld
# AhQfQDN8A+KVssIhdXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw
# 8MzK7/0pNVwfiThV9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnP
# LqR0kq3bPKSchh/jwVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatE
# QOON8BUozu3xGFYHKi8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bn
# KD+sEq6lLyJsQfmCXBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQji
# WQ1tygVQK+pKHJ6l/aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbq
# yK+p/pQd52MbOoZWeE4wgge8MIIFpKADAgECAhAGQAJb/wxIlzKZ1GMgg8N7MA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwHhcNMjQwMzI4MDAwMDAwWhcNMjcwMzMw
# MjM1OTU5WjCBxDETMBEGCysGAQQBgjc8AgEDEwJVUzEZMBcGCysGAQQBgjc8AgEC
# EwhEZWxhd2FyZTEdMBsGA1UEDwwUUHJpdmF0ZSBPcmdhbml6YXRpb24xEDAOBgNV
# BAUTBzY2MTAxMTcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMREw
# DwYDVQQHEwhTYW4gSm9zZTEVMBMGA1UEChMMQnJvYWRjb20gSW5jMRUwEwYDVQQD
# EwxCcm9hZGNvbSBJbmMwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC6
# 8C+jJxKfxp9c1A6fghwSNjnvV+Y1my2XmTHEPmk7COFTWw1VRBZBtv/zUXrSStlW
# 9Qqqp48wk+H+H5oM0qL9jsUQ6wAJpmjt33F3xvKqc8ehzVZLXUEACQBXTo30Hnbh
# bcacKAyX9sGByGqKlR6cHHrEebSWMoxOO6TOgYg06xfeYzxpx8HqMQjOKgNEbh4c
# m1Yx+ER/4BmWmYcvVHR9KtXwJWxmzUJCaS5OB9lp8JqO5+uAHvpGtQEAb39/h/vy
# 290isCYw16/uaLOz5Epchv5fogTBTh4o6SXWHam03FfMNVbmbMVuciTzfPSDt0i5
# xQWYtVkwVU+NGE4XUutX4zbaing53QYKNAa+NW9FiWcaoEwE1qTvk7ilsucPzdqC
# ikQpHyaaGCzHoDhveSLiJKgKRiDqee8KXfa/hkCoat9AtCihyd899kJ1kSlTO9fk
# ci5/CdKwmwXQIKh6OPueKr+OJ69XPx0V+RaaMAkkVtFb7/VwecFmFgsXFkAK8ulP
# aGYyIFOFqLMqH8ZuKiLVP5HkxDgSitJcWbaSf89TJuxNqh0vV1k4iwaQpcmQZhPK
# 49pNlj5j0cyw8B+xTYNDwnKvyoWgqKAb2cfzc6pCLk2GJLBwakKZ5YKC50XdhPlS
# yrqlLTb5otZRoYWFGKL1SqxxrBjRqg4qp1RvuxRcBQIDAQABo4ICAjCCAf4wHwYD
# VR0jBBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHQYDVR0OBBYEFL9ZTMS/Phgv
# GnXZm3XOrmDoJSIfMD0GA1UdIAQ2MDQwMgYFZ4EMAQMwKTAnBggrBgEFBQcCARYb
# aHR0cDovL3d3dy5kaWdpY2VydC5jb20vQ1BTMA4GA1UdDwEB/wQEAwIHgDATBgNV
# HSUEDDAKBggrBgEFBQcDAzCBtQYDVR0fBIGtMIGqMFOgUaBPhk1odHRwOi8vY3Js
# My5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQw
# OTZTSEEzODQyMDIxQ0ExLmNybDBToFGgT4ZNaHR0cDovL2NybDQuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAy
# MUNBMS5jcmwwgZQGCCsGAQUFBwEBBIGHMIGEMCQGCCsGAQUFBzABhhhodHRwOi8v
# b2NzcC5kaWdpY2VydC5jb20wXAYIKwYBBQUHMAKGUGh0dHA6Ly9jYWNlcnRzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNI
# QTM4NDIwMjFDQTEuY3J0MAkGA1UdEwQCMAAwDQYJKoZIhvcNAQELBQADggIBAMLk
# M/5BZB1j2xjjR9IkyDYtLrqS9IztErzl4ogf2dXuAgBJP1EKm/EN4oOi/BHxLW0T
# VuclGZ3aEa3/n3UlHxqmvKm+4elD5oh4sEOm7+J7ECV0HobeZhRiLmdyla1Mqbxw
# xp56AVvhG/++nf+AVzw95c671a3kb+6VXMDzZK1qcUh6zyLklZ/vfjKipry9KgMR
# sXd81I+PRr+99iRI+5pUsF7ixmS4vTldNh2r/VRFKLtXtTefZ20Q55Efu/8NefJf
# fD/+LLmHszB3LRlguFYOUGon7q8eQKi20PMW6PQb8az4mn6MfA1Y2x+L7HFDiy//
# VMOy5DqcKOHWqz/NZr7/VEPtywoLbHlUwNJyFY0wnQhzvPCg67YpDEYERDnggtpe
# OchKlJoqLKQInq6xDLTtco+ynR6IHnWRcz+oYhm6TdvRcmP7giiqObKEFXQwLsjS
# HsqRluk2FQ4DhG63+8gyD4rKQVoybP0obE7Gi2RYHOT0qwPos6GklZraht/capa7
# wos1gNKXJL7G6BaCXQWCyakT76ZOJOdHzHjJ2n+yBgKWWGBv186nrP5nfuRu0vJE
# HG74cy5oRwe3vme6ztPQy9VSgSrP+g67bZ6yPe+z09T7NczW4aXrXbMUdTb02zKQ
# sK8WEKfcvzBmZ115SwMuf3g34C5yRhOsWInfosmAMYIaajCCGmYCAQEwfTBpMQsw
# CQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERp
# Z2lDZXJ0IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIw
# MjEgQ0ExAhAGQAJb/wxIlzKZ1GMgg8N7MA0GCWCGSAFlAwQCAQUAoHwwEAYKKwYB
# BAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGC
# NwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIOGTpYgwB3O7S61x
# OzFc4pWpLo91zv5HFvYpGkQUSz9kMA0GCSqGSIb3DQEBAQUABIICAF2TqNmVIs8q
# jKBLNSzhoP7MqDVifjUiCZCfXrcfv1n9EKgudR7gYhoVTA7um2XNfCR62G3wdcTh
# CDsx2z+8ssDbRYwJbh1LET/t4QWecVFxLkcFd86X0cAPgjETmIn6YRwggdezTfYo
# 4eIomLqj3/F8r8WeC19T4cyDoP3Ov8dPQXkmJrAIf9bOjFyZnmR5xwPMwGKXWLwZ
# TaXLPrAJtAsdUIpq2Li417qfNXz7v8ZxYxvnzx+k9xAnuivzgKXe7cbu55sUdfhF
# bNikbOCCwSD6S/S/ZPaLkwe897tlUFGkXyUB4CadxrhBTogdJEahc59OYwZl9rZJ
# fDzqW8dJfPRWdldfjGuf6SbFuwle0LesHwOsatocBSvMxc7wH7bBMTpNT4FmJ05T
# GVzkMxl0dj6StTbMH+6g2YVcBBlynwUvKLMxVLVp53wrl9e1Pf5OLXBC+9F4eFfk
# XdCRhXvYZsCIqmy50aahHjxm/ipGvpm7xm5NT/CeNDzjKRwNnLEj0W/+BIAarWUn
# R/V679iKft9LrvbMz2U9kBgYGE3rMgOmhAajVSy8+qUrG+n+w0Vsjsy6pYCe7AO0
# ZYUrFVg3bzaouMjps3T+xSGHq0+MeWAp1KUXAxXKE5QxwxaorMIsZSCtLe/JuNs0
# demDGA8s2f7EQa9HGCND19pV1pOZQycwoYIXQDCCFzwGCisGAQQBgjcDAwExghcs
# MIIXKAYJKoZIhvcNAQcCoIIXGTCCFxUCAQMxDzANBglghkgBZQMEAgEFADB4Bgsq
# hkiG9w0BCRABBKBpBGcwZQIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAE
# IPcjDTlq9AwIvFGm9Ue21XxC8rQzofMzNSFUGqfeI7W0AhEAkhWri+95Zvd7Gk/9
# P86r4hgPMjAyNDA3MjQxOTQ5MzBaoIITCTCCBsIwggSqoAMCAQICEAVEr/OUnQg5
# pr/bP1/lYRYwDQYJKoZIhvcNAQELBQAwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoT
# DkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJT
# QTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTAeFw0yMzA3MTQwMDAwMDBaFw0z
# NDEwMTMyMzU5NTlaMEgxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjEgMB4GA1UEAxMXRGlnaUNlcnQgVGltZXN0YW1wIDIwMjMwggIiMA0GCSqG
# SIb3DQEBAQUAA4ICDwAwggIKAoICAQCjU0WHHYOOW6w+VLMj4M+f1+XS512hDgnc
# L0ijl3o7Kpxn3GIVWMGpkxGnzaqyat0QKYoeYmNp01icNXG/OpfrlFCPHCDqx5o7
# L5Zm42nnaf5bw9YrIBzBl5S0pVCB8s/LB6YwaMqDQtr8fwkklKSCGtpqutg7yl3e
# GRiF+0XqDWFsnf5xXsQGmjzwxS55DxtmUuPI1j5f2kPThPXQx/ZILV5FdZZ1/t0Q
# oRuDwbjmUpW1R9d4KTlr4HhZl+NEK0rVlc7vCBfqgmRN/yPjyobutKQhZHDr1eWg
# 2mOzLukF7qr2JPUdvJscsrdf3/Dudn0xmWVHVZ1KJC+sK5e+n+T9e3M+Mu5SNPvU
# u+vUoCw0m+PebmQZBzcBkQ8ctVHNqkxmg4hoYru8QRt4GW3k2Q/gWEH72LEs4VGv
# tK0VBhTqYggT02kefGRNnQ/fztFejKqrUBXJs8q818Q7aESjpTtC/XN97t0K/3k0
# EH6mXApYTAA+hWl1x4Nk1nXNjxJ2VqUk+tfEayG66B80mC866msBsPf7Kobse1I4
# qZgJoXGybHGvPrhvltXhEBP+YUcKjP7wtsfVx95sJPC/QoLKoHE9nJKTBLRpcCcN
# T7e1NtHJXwikcKPsCvERLmTgyyIryvEoEyFJUX4GZtM7vvrrkTjYUQfKlLfiUKHz
# OtOKg8tAewIDAQABo4IBizCCAYcwDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQC
# MAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwIAYDVR0gBBkwFzAIBgZngQwBBAIw
# CwYJYIZIAYb9bAcBMB8GA1UdIwQYMBaAFLoW2W1NhS9zKXaaL3WMaiCPnshvMB0G
# A1UdDgQWBBSltu8T5+/N0GSh1VapZTGj3tXjSTBaBgNVHR8EUzBRME+gTaBLhklo
# dHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRSU0E0MDk2
# U0hBMjU2VGltZVN0YW1waW5nQ0EuY3JsMIGQBggrBgEFBQcBAQSBgzCBgDAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMFgGCCsGAQUFBzAChkxo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRSU0E0
# MDk2U0hBMjU2VGltZVN0YW1waW5nQ0EuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCB
# GtbeoKm1mBe8cI1PijxonNgl/8ss5M3qXSKS7IwiAqm4z4Co2efjxe0mgopxLxjd
# TrbebNfhYJwr7e09SI64a7p8Xb3CYTdoSXej65CqEtcnhfOOHpLawkA4n13IoC4l
# eCWdKgV6hCmYtld5j9smViuw86e9NwzYmHZPVrlSwradOKmB521BXIxp0bkrxMZ7
# z5z6eOKTGnaiaXXTUOREEr4gDZ6pRND45Ul3CFohxbTPmJUaVLq5vMFpGbrPFvKD
# NzRusEEm3d5al08zjdSNd311RaGlWCZqA0Xe2VC1UIyvVr1MxeFGxSjTredDAHDe
# zJieGYkD6tSRN+9NUvPJYCHEVkft2hFLjDLDiOZY4rbbPvlfsELWj+MXkdGqwFXj
# hr+sJyxB0JozSqg21Llyln6XeThIX8rC3D0y33XWNmdaifj2p8flTzU8AL2+nCps
# eQHc2kTmOt44OwdeOVj0fHMxVaCAEcsUDH6uvP6k63llqmjWIso765qCNVcoFstp
# 8jKastLYOrixRoZruhf9xHdsFWyuq69zOuhJRrfVf8y2OMDY7Bz1tqG4QyzfTkx9
# HmhwwHcK1ALgXGC7KP845VJa1qwXIiNO9OzTF/tQa/8Hdx9xl0RBybhG02wyfFgv
# Z0dl5Rtztpn5aywGRu9BHvDwX+Db2a2QgESvgBBBijCCBq4wggSWoAMCAQICEAc2
# N7ckVHzYR6z9KGYqXlswDQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMxFTAT
# BgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEh
# MB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTIyMDMyMzAwMDAw
# MFoXDTM3MDMyMjIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYg
# U0hBMjU2IFRpbWVTdGFtcGluZyBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBAMaGNQZJs8E9cklRVcclA8TykTepl1Gh1tKD0Z5Mom2gsMyD+Vr2EaFE
# FUJfpIjzaPp985yJC3+dH54PMx9QEwsmc5Zt+FeoAn39Q7SE2hHxc7Gz7iuAhIoi
# GN/r2j3EF3+rGSs+QtxnjupRPfDWVtTnKC3r07G1decfBmWNlCnT2exp39mQh0YA
# e9tEQYncfGpXevA3eZ9drMvohGS0UvJ2R/dhgxndX7RUCyFobjchu0CsX7LeSn3O
# 9TkSZ+8OpWNs5KbFHc02DVzV5huowWR0QKfAcsW6Th+xtVhNef7Xj3OTrCw54qVI
# 1vCwMROpVymWJy71h6aPTnYVVSZwmCZ/oBpHIEPjQ2OAe3VuJyWQmDo4EbP29p7m
# O1vsgd4iFNmCKseSv6De4z6ic/rnH1pslPJSlRErWHRAKKtzQ87fSqEcazjFKfPK
# qpZzQmiftkaznTqj1QPgv/CiPMpC3BhIfxQ0z9JMq++bPf4OuGQq+nUoJEHtQr8F
# nGZJUlD0UfM2SU2LINIsVzV5K6jzRWC8I41Y99xh3pP+OcD5sjClTNfpmEpYPtMD
# iP6zj9NeS3YSUZPJjAw7W4oiqMEmCPkUEBIDfV8ju2TjY+Cm4T72wnSyPx4Jduyr
# XUZ14mCjWAkBKAAOhFTuzuldyF4wEr1GnrXTdrnSDmuZDNIztM2xAgMBAAGjggFd
# MIIBWTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBS6FtltTYUvcyl2mi91
# jGogj57IbzAfBgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8B
# Af8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBpMCQG
# CCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKG
# NWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290
# RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQC
# MAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAfVmOwJO2b5ipRCIBfmbW
# 2CFC4bAYLhBNE88wU86/GPvHUF3iSyn7cIoNqilp/GnBzx0H6T5gyNgL5Vxb122H
# +oQgJTQxZ822EpZvxFBMYh0MCIKoFr2pVs8Vc40BIiXOlWk/R3f7cnQU1/+rT4os
# equFzUNf7WC2qk+RZp4snuCKrOX9jLxkJodskr2dfNBwCnzvqLx1T7pa96kQsl3p
# /yhUifDVinF2ZdrM8HKjI/rAJ4JErpknG6skHibBt94q6/aesXmZgaNWhqsKRcnf
# xI2g55j7+6adcq/Ex8HBanHZxhOACcS2n82HhyS7T6NJuXdmkfFynOlLAlKnN36T
# U6w7HQhJD5TNOXrd/yVjmScsPT9rp/Fmw0HNT7ZAmyEhQNC3EyTN3B14OuSereU0
# cZLXJmvkOHOrpgFPvT87eK1MrfvElXvtCl8zOYdBeHo46Zzh3SP9HSjTx/no8Zhf
# +yvYfvJGnXUsHicsJttvFXseGYs2uJPU5vIXmVnKcPA3v5gA3yAWTyf7YGcWoWa6
# 3VXAOimGsJigK+2VQbc61RWYMbRiCQ8KvYHZE/6/pNHzV9m8BPqC3jLfBInwAM1d
# wvnQI38AC+R2AibZ8GV2QqYphwlHK+Z/GqSFD/yYlvZVVCsfgPrA8g4r5db7qS9E
# FUrnEw4d2zc4GqEr9u3WfPwwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBha
# MA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lD
# ZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDky
# MzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0
# ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo
# 3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutW
# xpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQ
# RBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nP
# zaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6P
# gNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEB
# fCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3
# wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2
# mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2
# Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF1
# 3nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+d
# IPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMB
# Af8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSME
# GDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYB
# BQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20w
# QwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNV
# HSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9
# thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4
# offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cG
# AxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9
# HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvP
# J6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXiji
# uZQxggN2MIIDcgIBATB3MGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2Vy
# dCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNI
# QTI1NiBUaW1lU3RhbXBpbmcgQ0ECEAVEr/OUnQg5pr/bP1/lYRYwDQYJYIZIAWUD
# BAIBBQCggdEwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJ
# BTEPFw0yNDA3MjQxOTQ5MzBaMCsGCyqGSIb3DQEJEAIMMRwwGjAYMBYEFGbwKzLC
# wskPgl3OqorJxk8ZnM9AMC8GCSqGSIb3DQEJBDEiBCDVY+ZbnvgzXIjfJNRgcVE3
# aGj7hJv6Y82ySF9l9s9+mDA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDS9uRt7XQi
# zNHUQFdoQTZvgoraVZquMxavTRqa1Ax4KDANBgkqhkiG9w0BAQEFAASCAgCLbGR2
# BBKoAvCYmRy8YocDUKmhIDGkBivDuU06MSmRTyNHgoSRaL/ev84yRqXckc4dPkOm
# VIGQtnkBejbINGQXhgn4yq6WnLTTFfBD2iFzKkWzyOnFhgzZPUQ1XehKT0ZK+gUm
# M3AdV1nYx/fmxQIl9qHMSgkFjfJeiMHl1XaWXLQGSqfm1mOWXhvr8WvIXDxRMqbd
# nxX6LrCdlUMGIjfj3BPJgz6OARkWBXie5f+ECUPM1VxO6glXZvFGbxZqN8RPH4ve
# v7sWtMcb3nCRBWosNaz2LGlC6xuPYSmkFOCOycfthr42iFuXzZKM7MO8s65VxVd4
# nqT9wozagDktrQSXtm5hwgsSGMsSE932da62s8nZ5AvX4zB+KJv3nmM49/xviAVe
# aXsC3KjZ6PNda+4jtjS0jZuq8TavClJIEpfNlWFPXVWv7iuFoDCAV+oerra5yuOg
# /L48Xi2NTvEJY8cn4Wy8teQgsXSsWrK1xOAaR6LuEj0x46qWfNsoFt7M/Sk0T4fr
# 1pZgPlwFffbexuLYsL66XOtUMWiE/jaetPg8IVCyffh/HlS9u6VObAncgAFP/OLw
# 9PNcDSL+6I5BI3WUPamT84M4dmLWbfcGeHMzYAosE4JrsfVb0vExaXpEr/j/dwjt
# +ghZmmT5bbqe1chRb6NoQY+gIDQG0sdxSq84IA==
# SIG # End signature block
