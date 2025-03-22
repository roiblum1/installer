using module VMware.PowerCLI.Sdk.Types
using module VMware.PowerCLI.VCenter.Types.CertificateManagement
using namespace VMware.VimAutomation.ViCore.Types.V1
using namespace VMware.VimAutomation.ViCore.Types.V1.Inventory
using namespace System.Security.Cryptography.X509Certificates
using namespace VMware.VimAutomation.Sdk.Util10Ps.BaseCmdlet

. (Join-Path $PSScriptRoot "../utils/Connection.ps1")
. (Join-Path $PSScriptRoot "../utils/Report-CommandUsage.ps1")
. (Join-Path $PSScriptRoot "../types/builders/New-TrustedCertificateInfo.ps1")

<#
.SYNOPSIS

This cmdlet adds a certificate or certificate chain to the vCenter Server or ESXi trusted stores.

.DESCRIPTION

This cmdlet adds a certificate or certificate chain to the vCenter Server or ESXi trusted stores.

To use this cmdlet, you must connect to vCenter Server through the Connect-VIServer cmdlet.

Note: The certificate or certificate chain will be added to both the vCenter Server instance and the connected ESXi hosts unless you use the VCenterOnly or EsxOnly parameters.

.PARAMETER PemCertificateOrChain

Specifies a certificate or certificate chain in PEM format to be added to the vCenter Server and/or ESXi trusted stores.

.PARAMETER X509Certificate

Specifies a certificate as an X509Certificate object to be added to the vCenter Server and/or ESXi trusted stores.

.PARAMETER X509Chain

Specifies a certificate chain as an X509Chain object to be added to the vCenter Server and/or ESXi trusted stores.

.PARAMETER VMHost

Specifies one or more ESXi hosts to whose trusted stores you want to add the certificate or certificate chain.

.PARAMETER VCenterOnly

Specifies that the certificate or certificate chain must be added only to the trusted store of the vCenter Server instance.

.PARAMETER EsxOnly

Specifies that the certificate or certificate chain must be added only to the trusted store of the ESXi hosts.


.EXAMPLE
PS C:\> $caPem = Get-Content ca.pem -Raw
Add-VITrustedCertificate -PemCertificateOrChain $caPem

Adds the certificate from ca.pem to the trusted certificate stores of the vCenter Server and all the ESXi hosts connected to the vCenter system.


.EXAMPLE
PS C:\> $caPem = Get-Content ca.pem -Raw
Add-VITrustedCertificate -PemCertificateOrChain $caPem -VCenterOnly

Adds the certificate from ca.pem to the trusted certificate store of the vCenter Server system.


.EXAMPLE
PS C:\> $caPem = Get-Content ca.pem -Raw
Add-VITrustedCertificate -PemCertificateOrChain $caPem -EsxOnly

Adds the certificate from ca.pem to the trusted certificate stores of the ESXi hosts of the vCenter Server system, but not to the vCenter itself.


.EXAMPLE
PS C:\> $caPem = Get-Content ca.pem -Raw
Add-VITrustedCertificate -VMHost 'MyHost' -PemCertificateOrChain $caPem

Adds the certificate from ca.pem to the trusted certificate store of the 'MyHost' ESXi host.


.OUTPUTS

One or more TrustedCertificateInfo objects


.LINK

https://developer.vmware.com/docs/powercli/latest/vmware.powercli.vcenter/commands/add-vitrustedcertificate

#>
function Add-VITrustedCertificate {
   [CmdletBinding(
      ConfirmImpact = "High",
      DefaultParameterSetName = "Default",
      SupportsShouldProcess = $True)]
   [OutputType([TrustedCertificateInfo])]
   Param (
      [Parameter(ValueFromPipeline = $true)]
      [String[]]
      $PemCertificateOrChain,

      [Parameter()]
      [X509Certificate[]]
      $X509Certificate,

      [Parameter()]
      [X509Chain[]]
      $X509Chain,

      [Parameter(Mandatory = $true, ParameterSetName = "PerEsx")]
      [ObnArgumentTransformation([VMHost])]
      [VMHost[]]
      $VMHost,

      [Parameter(Mandatory = $true, ParameterSetName = 'VCenterOnly')]
      [switch]
      $VCenterOnly,

      [Parameter(Mandatory = $true, ParameterSetName = 'EsxOnly')]
      [switch]
      $EsxOnly,

      [Parameter()]
      [ObnArgumentTransformation([VIServer], Critical = $true)]
      [VIServer]
      $Server
   )

   Begin {
      Report-CommandUsage $MyInvocation
      
      # Handle Server obn first
      if($Server) {
         $resolvedServer = Resolve-ObjectByName `
            -Object $Server `
            -Type ([VIServer]) `
            -OneObjectExpected

         $Server = [VIServer] $resolvedServer
      }

      $activeServer = GetActiveServer($Server)
      ValidateApiVersionSupported -server $activeServer -major 7 -minor 0

      # Collect OBN for parameter 'VMHost'
      if($VMHost) {
         $resolvedVMHost = Resolve-ObjectByName -Object $VMHost `
            -Type ([VMHost]) `
            -CollectorCmdlet 'Get-VMHost' `
            -OneOrMoreObjectsExpected `
            -Server $activeServer

         $VMHost = [VMHost[]] $resolvedVMHost
      }

      # Validate that only one of:
      #   PemCertificateOrChain
      #   X509Certificate
      #   X509Chain
      # is present

      $counter = 0
      if ($PemCertificateOrChain) {
         $PemCertificateOrChain | Confirm-PemContainsCertificates
         $counter += 1
      }

      if ($X509Certificate) {
         $counter += 1
      }

      if ($X509Chain) {
         $counter += 1
      }

      if ($counter -eq 0) {
         Write-PowerCLIError `
            -ErrorObject 'One of the parameters PemCertificateOrChain, X509Certificate or X509Chain must be supplied.' `
            -Terminating
      } elseif ($counter -gt 1) {
         Write-PowerCLIError `
            -ErrorObject 'Only one of the parameters PemCertificateOrChain, X509Certificate or X509Chain must be supplied.' `
            -Terminating
      }
   }

   Process {
      # Validate all objects are from the same server
      if($VMHost) {
         $VMHost | ValidateSameServer -ExpectedServer $activeServer
      }

      $updateVc = $PsCmdlet.ParameterSetName -eq 'Default' -or `
         ($PsCmdlet.ParameterSetName -eq 'VCenterOnly' -and $VCenterOnly.ToBool())

      $updateEsx = $PsCmdlet.ParameterSetName -eq 'Default' -or `
         ($PsCmdlet.ParameterSetName -eq 'EsxOnly' -and $EsxOnly.ToBool())

      if ($updateEsx) {
         $tempVMHost = Get-VMHost -Server $activeServer
         if ($tempVMHost) {
            $VMHost = $tempVMHost
         }
      }

      $pemCertArray = [System.Collections.ArrayList]::new()

      if ($PemCertificateOrChain) {
         $PemCertificateOrChain | Read-PemCertificate | % {
            $pemCertArray.Add($_) | Out-Null
         }
         if ($pemCertArray.Count -eq 0) {
            Write-PowerCLIError `
               -ErrorObject 'No certificate found in the PemCertificateOrChain.' `
               -ErrorId "PowerCLI_VITrustedCertificate_NoCertificateFoundInPemCertificateOrChain"
         }
      } elseif ($X509Certificate) {
         $X509Certificate | ConvertTo-PemCertificate | % {
            $pemCertArray.Add($_) | Out-Null
         }
      } elseif ($X509Chain) {
         $X509Chain | % { $_.ChainElements } | % {
            ConvertTo-PemCertificate -X509Certificate $_.Certificate
         } | % {
            $pemCertArray.Add($_) | Out-Null
         }
         if ($pemCertArray.Count -eq 0) {
            Write-PowerCLIError `
               -ErrorObject 'No certificates found in the X509Chain' `
               -ErrorId "PowerCLI_VITrustedCertificate_NoCertificateFoundInx509Chain"
         }
      }

      if ($pemCertArray.Count -gt 0) {
         $vcName = ''
         if ($updateVc) {
            $vcName = $activeServer.Name
         }

         $shouldProcessDescription = Get-ShouldProcessMessage $pemCertArray $vcName ($VMHost | Select-Object -ExpandProperty Name)
         $shouldProcessWarning = Get-ShouldProcessMessage $pemCertArray $vcName ($VMHost | Select-Object -ExpandProperty Name) -warning

         if($PSCmdlet.ShouldProcess(
            $shouldProcessDescription,
            $shouldProcessWarning,
            "Add certificate")) {

            if ($updateVc) {
               $apiServer = GetApiServer($activeServer)
               
               try {
                  $trustedChainIds =
                     $pemCertArray | % {
                        Initialize-CertificateManagementX509CertChain -CertChain ([string[]]@($_))
                     } | `
                     Initialize-CertificateManagementVcenterTrustedRootChainsCreateSpec | `
                     Invoke-CreateCertificateManagementTrustedRootChains `
                        -Server $apiServer `
                        -ErrorAction:Stop

                  Get-VITrustedCertificate `
                     -Id ($trustedChainIds | % {
                        $UidUtil.Append($activeServer.Uid, "ViTrustedCertificate", $_)
                     }) | `
                     Write-Output
               } catch {
                  Write-PowerCLIError `
                     -ErrorObject $_ `
                     -ErrorId "PowerCLI_VITrustedCertificate_FailedToAddVcTrustChains"
               }
            }

            if ($VMHost) {
               foreach ($currentVMHost in $VMHost) {
                  try {
                     $certificateManager = Get-View $currentVMHost.ExtensionData.ConfigManager.CertificateManager -Server $activeServer
                     $addingCertificatesThumbprints = [System.Collections.ArrayList]::new()
                     $trustedCertificates = [System.Collections.ArrayList]::new()

                     $pemCertArray | % {
                        $trustedCertificates.Add($_) | Out-Null
                        $_ | ConvertTo-X509Certificate | %{
                           $addingCertificatesThumbprints.Add($_.Thumbprint) | Out-Null
                        }
                     }

                     $currentTrustedCertificates = $certificateManager.ListCACertificates()
                     if ($currentTrustedCertificates) {
                        $trustedCertificates.AddRange($currentTrustedCertificates)
                     }

                     $certificateManager.ReplaceCACertificatesAndCRLs(
                        $trustedCertificates.ToArray(), $null) | Out-Null

                     Get-ViTrustedCertificate -Id ($addingCertificatesThumbprints | % {
                        $UidUtil.Append($currentVMHost.Uid, "ViTrustedCertificate", $_)
                     })
                  } catch {
                     Write-PowerCLIError `
                        -ErrorObject $_ `
                        -ErrorId "PowerCLI_VITrustedCertificate_FailedToAddEsxTrustChains"
                  }
               }
            }
         }
      }
   }
}

function Read-PemCertificate {
   param(
      [Parameter(ValueFromPipeline = $true)]
      [string]
      $pem
   )

   $beginStr = '-----BEGIN CERTIFICATE-----'
   $endStr = '-----END CERTIFICATE-----'
   $beginIndex = $pem.IndexOf($beginStr)
   while ($beginIndex -ge 0) {
      $endIndex = $pem.IndexOf($endStr, $beginIndex)
      if ($endIndex -gt $beginIndex) {
         $pem.Substring($beginIndex, $endIndex + $endStr.Length - $beginIndex) | Write-Output
         $beginIndex = $pem.IndexOf($beginStr, $endIndex)
      } else {
         Write-PowerCLIError `
            -ErrorObject @"
The PEM:
---------------------------
$pem
---------------------------
Contains '$beginStr' with missing '$endStr'.
"@ `
            -ErrorId 'PowerCLI_VITrustedCertificate_MissingEndCertificate'
         # END CERTIFICATE not found no need to continue
         break
      }
   }
}

function Get-ShouldProcessMessage {
   param(
      [string[]]
      $pem,

      [string]
      $vcName,

      [string[]]
      $hostName,

      [switch]
      $warning
   )

   $sb = [System.Text.StringBuilder]::new()

   if ($warning.ToBool()) {
      $sb.Append("Are you sure you want to add ") | Out-Null
   } else {
      $sb.Append("Adding ") | Out-Null
   }

   $pem | ConvertTo-X509Certificate | % {
      $sb.Append("'") | Out-Null
      $sb.Append($_.GetNameInfo([X509NameType]::SimpleName, $false)) | Out-Null
      $sb.Append("'") | Out-Null
      $sb.Append(", ") | Out-Null
   }
   $sb.Remove($sb.Length - 2, 2) | Out-Null

   $sb.Append(" certificate") | Out-Null
   if ($pem.Length -gt 1) {
      $sb.Append("s") | Out-Null
   }
   $sb.Append(" to") | Out-Null

   if(-not [string]::IsNullOrEmpty($vcName)) {
      $sb.Append(" vCenter Server '$vcName'") | Out-Null
      if ($hostName) {
         $sb.Append(" and") | Out-Null
      }
   }

   if ($hostName) {
      $sb.Append(" host") | Out-Null
      if ($hostName.Length -gt 1) {
         $sb.Append("s") | Out-Null
      }
      $sb.Append(" ") | Out-Null

      $hostName | % {
         $sb.Append("'$_', ") | Out-Null
      }

      $sb.Remove($sb.Length - 2, 2) | Out-Null
   }

   if ($warning.ToBool()) {
      $sb.Append("?") | Out-Null
   } else {
      $sb.Append(".") | Out-Null
   }

   $sb.ToString() | Write-Output
}

function Confirm-PemContainsCertificates {
   param(
      [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
      [string[]]
      $Pem
   )

   return

   $Pem | %{
      if (!$_.Contains('-----BEGIN CERTIFICATE-----') -or `
         !$_.Contains('-----END CERTIFICATE-----')) {
         Write-PowerCLIError `
            -ErrorObject "PemCertificateOrChain must contain a PEM certificate." `
            -Terminating
      }
   }
}

# SIG # Begin signature block
# MIIpiAYJKoZIhvcNAQcCoIIpeTCCKXUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAfUPE9iCL7xk1q
# bB7wnGblUnPTu4WF8u6zVReZgtFlNaCCDnQwggawMIIEmKADAgECAhAIrUCyYNKc
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
# NwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIBnE056fqEnWW7Xl
# hQtVBU58Uko3KvuvKbtazuL3GDGnMA0GCSqGSIb3DQEBAQUABIICABMefObybwPB
# xm9GXYUgeqKOpBIlGoaUZCSqDeAbFl2r0S/ewYUbpQ04Bs/2dNjLorTwjUlDgcKr
# KS5nT9uKbgk1+cnynbM4bxmH41SR4dCdhHm+OlT5Hi5veC9cnswnINOUKR6VyoF2
# 6dK0a4oQ2fHceiPilo9FfrbYXBv8tJnPjyJ/ffKzeHSp2vtr3TJaR4Sp3D/ceRz2
# JhwMsee3PH/AovFxeRkE31SHbPBqnt9Qnc9MFPtUU6ZRMSVHxl8dqtuORh2+JMVd
# FnS6GU2q9rbsBXi9lW+13DeMmIn+Vtfi790cVqZS4gqYMrVPGc16SEVYBHPdrZcI
# gBcbhD8zYwK5c9FQpn2jenICsaGKV3yb2FAiME3KXnV82Jt2tztoiCP14hzDVywg
# klihbWs5wfr+WetAkWnjb4k3wYI0XOCUlgAQ2WDsOcP0B160j7kuWowkXe1Yw89a
# uD5pn1DKWJCzAM6nRLce3hC9yWnXKwMP+jWmqVKMb2R0GYOj+dihVVDc61odlswy
# ct+5fUx0A5ED5FfU2NcdGNGiecs27RSSCEbDuUJc9Ix9rMPTLIeR6hF0S1/nIGxi
# eTaIMvGae16JPZtA0th5KeINaItcj0sjeeus1Xo6ChneX95WzNlAnrH6vEypUrj8
# H9qa3ZVMK7q1DBbZqz+W3561+TWHcaNXoYIXQDCCFzwGCisGAQQBgjcDAwExghcs
# MIIXKAYJKoZIhvcNAQcCoIIXGTCCFxUCAQMxDzANBglghkgBZQMEAgEFADB4Bgsq
# hkiG9w0BCRABBKBpBGcwZQIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAE
# IN55KN67TNFvWVU9EbsdGbnxUmp3kcd3UqbuHxUhzOzqAhEA60pcmvI9eSdBeLUt
# l02B1hgPMjAyNDA3MjQxOTQ5MzBaoIITCTCCBsIwggSqoAMCAQICEAVEr/OUnQg5
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
# wskPgl3OqorJxk8ZnM9AMC8GCSqGSIb3DQEJBDEiBCA26dlOuolxPHD2L8DSAlff
# Vrt0K8SfFBTajFDpepXTbTA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDS9uRt7XQi
# zNHUQFdoQTZvgoraVZquMxavTRqa1Ax4KDANBgkqhkiG9w0BAQEFAASCAgAysFai
# C5tJGpxekS8evHhaF0P67AC2fd2G/q7RSk2nTR03HeD0Jqn8OSw5vgVjDyHHc3jK
# /GNceQQCUWE/BjGKV71Wan+9u3DomWlqSVFx8QVPErqj7lmAiryotGqHxgwBCjxh
# /SinISeBe5XCnXwEPC5EVQntwM4t11FxqMmav7GO3+ypcAqE+yi+KcW3JJK7h1op
# XhvSApY5iAjVJ9SJEtVMvYYwdADUkdt4jMEATJMkHLsZuv0uLIlh1VuA9A11NQG6
# oSbRj8OEY5arX+gTHILLgG6XXUA/sZznoGa7a1qjK+HHds78B1J77dfY31L4ya26
# Y91/Zk3kk/IvZlwH217GDn8cVQDopaZJ0agf6jAL+OC0PGhECKKGzpvRBWCRiF7I
# 1Ahk2e7RzRzVbOCLgOzPolpQsPgeI411VOEuHTZ2dZPwx7lcdZy1SmgHLC/O+E/a
# KDZt+8Erf0b/cqWy9PKn8wgH6FtMc0H0N8RYwKqaf0TxBSih07jxe5Rm54Kv5p/v
# nCGWJ5wouhz1PQee7h3dgCHWxq6ZAGqURzDzR0PwNvtKO2L7CoKkEtlyKEa7Y53c
# R4ElP6yT5U/m9jj19B+oc8MrluBTnjxQY8LW+jtNJE/EoxmWK096LCb3wd8rCpEO
# 7GbaUHy/481BtgQsdBFuonRny0olVAGqA6bYRA==
# SIG # End signature block
