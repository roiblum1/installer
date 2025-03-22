using namespace VMware.VimAutomation.ViCore.Types.V1

function Resolve-ObjectByName {
   [CmdletBinding(DefaultParameterSetName = "ByCmdlet")]
   param(
      [Parameter(
         Position = 0,
         Mandatory = $true,
         ParameterSetName = "ByScript")]
      [Parameter(
         Mandatory = $true,
         ParameterSetName = "ByCmdlet")]
      [object[]]
      $Object,
      [Parameter(
         Mandatory = $true,
         ParameterSetName = "ByScript")]
      [Parameter(
         Mandatory = $true,
         ParameterSetName = "ByCmdlet")]
      [System.Type]
      $Type,
      [Parameter(
         ParameterSetName = "ByScript")]
      [scriptblock]
      $ObjectCollectorScript,
      [Parameter(
         ParameterSetName = "ByCmdlet")]
      [string]
      $CollectorCmdlet,

      [Parameter()]
      [switch]
      $AllowNoObjectResult,

      [Parameter()]
      [switch]
      $OneObjectExpected,
      [Parameter()]
      [switch]
      $OneOrMoreObjectsExpected,

      [Parameter()]
      [VIServer]
      $Server
   )

   Process {
      $resultList = New-Object System.Collections.Generic.List[object]

      $Object | % {
         try {
            $currentObject = $_
            if ($null -eq $currentObject) {
               # $null - just propagated
               $resultList.Add($null)
            } else {
               if ($currentObject.GetType().IsPrimitive) {
                  $currentObject = $currentObject.ToString()
               }

               if (($currentObject -is $Type) `
                  -and ($null -ne (Get-Member -InputObject $currentObject -Name 'IsObn')) `
                  -and $currentObject.IsObn) {
                  # Obn transformed object - extract the name and continue
                  $currentObject = $currentObject.Obn
               }

               if (($currentObject -is $Type) `
                  -and ($currentObject -isnot [VMware.VimAutomation.Sdk.Interop.V1.StringWrapper])) {
                  # Valid object from the required type - propagate
                  $resultList.Add($currentObject)
               } elseif ($currentObject -is [string]) {
                  # name of and object - collect object(s)
                  switch ($PsCmdlet.ParameterSetName) {
                     "ByScript" {
                        Invoke-Command -ScriptBlock $ObjectCollectorScript `
                           -NoNewScope `
                           -ArgumentList @($currentObject, $Server) | `
                              ForEach-Object { $resultList.Add($_) }
                     }
                     "ByCmdlet" {
                        & "$CollectorCmdlet" -Name $currentObject -Server $Server | `
                           ForEach-Object { $resultList.Add($_) }
                     }
                  }
               } elseif ($currentObject -is [VMware.VimAutomation.Sdk.Interop.V1.StringWrapper]) {
                  # Handle existing modules obn

                  $connectionIds = New-Object System.Collections.Generic.List[string]
                  if($Server) {
                     $Server | ForEach-Object { $connectionIds.Add($_.Uid) }
                  }

                  $objectNames = New-Object System.Collections.Generic.List[string]
                  $objectNames.Add($currentObject.String)

                  $objectTypes = New-Object System.Collections.Generic.List[System.Type]
                  $objectTypes.Add($Type)

                  Resolve-CoreServiceObjectByName -ConnectionIds $connectionIds `
                     -objectNames $objectNames `
                     -objectTypes $objectTypes | ForEach-Object { $resultList.Add($_) }
               } else {
                  Write-PowerCLIError "Unsupported parameter type. Supported parameters are strings - the name or id - or $Type - an actual object is supported." -Terminating
               }
            }
         } catch {
            Write-PowerCLIError $_
         }
      }

      if (($resultList.Count -eq 0) -And (-Not $AllowNoObjectResult)) {
         Write-PowerCLIError "Object by name resolution did not found any object but expected at least one." -Terminating
      }

      if (($resultList.Count -gt 1) -And $OneObjectExpected) {
         Write-PowerCLIError "Object by name resolution found more then one objects but expected exactly one." -Terminating
      }

      return $resultList.ToArray()
   }
}

# SIG # Begin signature block
# MIIphwYJKoZIhvcNAQcCoIIpeDCCKXQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCi6GM0VpJ/yCKS
# yv8OJsVkqMkSFlINrlQaUHM9DgsuKKCCDnQwggawMIIEmKADAgECAhAIrUCyYNKc
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
# sK8WEKfcvzBmZ115SwMuf3g34C5yRhOsWInfosmAMYIaaTCCGmUCAQEwfTBpMQsw
# CQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERp
# Z2lDZXJ0IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIw
# MjEgQ0ExAhAGQAJb/wxIlzKZ1GMgg8N7MA0GCWCGSAFlAwQCAQUAoHwwEAYKKwYB
# BAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGC
# NwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIAZIBnaSUuIMQvV8
# zWrx4eryk+r9hlAxZd5h/lbjYfiPMA0GCSqGSIb3DQEBAQUABIICAKwG3i/LZFke
# exDpvEypUDvzdjjPp5ZPf0lZnDbrLVFCrjOV2FfBNo6BOBSwxg5nZiFU6OtuV1FA
# NeG2Q6TnCo7mtC/YkwCiD+Y7PdN4eQjY2iqqALbGZI2eu8GzFpizXlg9WW3dDXqD
# +b7LgnbS9KfcJiMmbboyb5RgyjTHdcgAJjPcmXvdaAnhxLMKpxHaviCeqQXkIrkR
# kE7ZxWdGnMqbVMA4u+4n0foy5UnsxwWbtNO+pgArWF4y/3GAeFTdspWlXW8+SGfC
# OXbVisqtzE9U0frLSc+m0boOcwpjKmCzXg56tFWCBt4Say4JHIlB76E2fRiP+JXU
# kJjFHPFM0Bxty2CQpf6H1oqpVbZUYwjaQrufhqg7Hl6PD07AD44KOf1XaEkuhiRJ
# 0vfzYauWW4LXark8+9h448L59NUDpPlrXHManN9lXPDC2Sy9wJp06yNRH3reMH++
# +xs2tdsJ1OUaZytwkO3OuVF1UucMU0g/1TPk7DGDTkwoBwr9OvNiiE3xQ97ohUdq
# WtkjT7/hhc1bhzRBet33r++9n/Ka8J8zyLjaNO4wAFNSaHsixLTEupCcwL7f0Yj8
# t55qe32iaJxt4V7CGb9fXK249ampHg3DcLfTtT9hhTiMB/b4HUFxzy3d1Eqd4Za5
# lYaQWCP+k+omL08rkAZOkoaI1xGWyW9yoYIXPzCCFzsGCisGAQQBgjcDAwExghcr
# MIIXJwYJKoZIhvcNAQcCoIIXGDCCFxQCAQMxDzANBglghkgBZQMEAgEFADB3Bgsq
# hkiG9w0BCRABBKBoBGYwZAIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAE
# IFqr52EnwUtw00HaiGalaCaTWDpqoRPur8Cl1yP+q0XlAhBhG0SZ7JSqx5hA+AGn
# nB00GA8yMDI0MDcyNDE5NDk0MVqgghMJMIIGwjCCBKqgAwIBAgIQBUSv85SdCDmm
# v9s/X+VhFjANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMO
# RGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNB
# NDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTIzMDcxNDAwMDAwMFoXDTM0
# MTAxMzIzNTk1OVowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMzCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAKNTRYcdg45brD5UsyPgz5/X5dLnXaEOCdwv
# SKOXejsqnGfcYhVYwamTEafNqrJq3RApih5iY2nTWJw1cb86l+uUUI8cIOrHmjsv
# lmbjaedp/lvD1isgHMGXlLSlUIHyz8sHpjBoyoNC2vx/CSSUpIIa2mq62DvKXd4Z
# GIX7ReoNYWyd/nFexAaaPPDFLnkPG2ZS48jWPl/aQ9OE9dDH9kgtXkV1lnX+3RCh
# G4PBuOZSlbVH13gpOWvgeFmX40QrStWVzu8IF+qCZE3/I+PKhu60pCFkcOvV5aDa
# Y7Mu6QXuqvYk9R28mxyyt1/f8O52fTGZZUdVnUokL6wrl76f5P17cz4y7lI0+9S7
# 69SgLDSb495uZBkHNwGRDxy1Uc2qTGaDiGhiu7xBG3gZbeTZD+BYQfvYsSzhUa+0
# rRUGFOpiCBPTaR58ZE2dD9/O0V6MqqtQFcmzyrzXxDtoRKOlO0L9c33u3Qr/eTQQ
# fqZcClhMAD6FaXXHg2TWdc2PEnZWpST618RrIbroHzSYLzrqawGw9/sqhux7Ujip
# mAmhcbJsca8+uG+W1eEQE/5hRwqM/vC2x9XH3mwk8L9CgsqgcT2ckpMEtGlwJw1P
# t7U20clfCKRwo+wK8REuZODLIivK8SgTIUlRfgZm0zu++uuRONhRB8qUt+JQofM6
# 04qDy0B7AgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIw
# ADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgGBmeBDAEEAjAL
# BglghkgBhv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxqII+eyG8wHQYD
# VR0OBBYEFKW27xPn783QZKHVVqllMaPe1eNJMFoGA1UdHwRTMFEwT6BNoEuGSWh0
# dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZT
# SEEyNTZUaW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGDMIGAMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYBBQUHMAKGTGh0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQw
# OTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggIBAIEa
# 1t6gqbWYF7xwjU+KPGic2CX/yyzkzepdIpLsjCICqbjPgKjZ5+PF7SaCinEvGN1O
# tt5s1+FgnCvt7T1IjrhrunxdvcJhN2hJd6PrkKoS1yeF844ektrCQDifXcigLiV4
# JZ0qBXqEKZi2V3mP2yZWK7Dzp703DNiYdk9WuVLCtp04qYHnbUFcjGnRuSvExnvP
# nPp44pMadqJpddNQ5EQSviANnqlE0PjlSXcIWiHFtM+YlRpUurm8wWkZus8W8oM3
# NG6wQSbd3lqXTzON1I13fXVFoaVYJmoDRd7ZULVQjK9WvUzF4UbFKNOt50MAcN7M
# mJ4ZiQPq1JE3701S88lgIcRWR+3aEUuMMsOI5ljitts++V+wQtaP4xeR0arAVeOG
# v6wnLEHQmjNKqDbUuXKWfpd5OEhfysLcPTLfddY2Z1qJ+Panx+VPNTwAvb6cKmx5
# AdzaROY63jg7B145WPR8czFVoIARyxQMfq68/qTreWWqaNYiyjvrmoI1VygWy2ny
# Mpqy0tg6uLFGhmu6F/3Ed2wVbK6rr3M66ElGt9V/zLY4wNjsHPW2obhDLN9OTH0e
# aHDAdwrUAuBcYLso/zjlUlrWrBciI0707NMX+1Br/wd3H3GXREHJuEbTbDJ8WC9n
# R2XlG3O2mflrLAZG70Ee8PBf4NvZrZCARK+AEEGKMIIGrjCCBJagAwIBAgIQBzY3
# tyRUfNhHrP0oZipeWzANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEw
# HwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjIwMzIzMDAwMDAw
# WhcNMzcwMzIyMjM1OTU5WjBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAxoY1BkmzwT1ySVFVxyUDxPKRN6mXUaHW0oPRnkyibaCwzIP5WvYRoUQV
# Ql+kiPNo+n3znIkLf50fng8zH1ATCyZzlm34V6gCff1DtITaEfFzsbPuK4CEiiIY
# 3+vaPcQXf6sZKz5C3GeO6lE98NZW1OcoLevTsbV15x8GZY2UKdPZ7Gnf2ZCHRgB7
# 20RBidx8ald68Dd5n12sy+iEZLRS8nZH92GDGd1ftFQLIWhuNyG7QKxfst5Kfc71
# ORJn7w6lY2zkpsUdzTYNXNXmG6jBZHRAp8ByxbpOH7G1WE15/tePc5OsLDnipUjW
# 8LAxE6lXKZYnLvWHpo9OdhVVJnCYJn+gGkcgQ+NDY4B7dW4nJZCYOjgRs/b2nuY7
# W+yB3iIU2YIqx5K/oN7jPqJz+ucfWmyU8lKVEStYdEAoq3NDzt9KoRxrOMUp88qq
# lnNCaJ+2RrOdOqPVA+C/8KI8ykLcGEh/FDTP0kyr75s9/g64ZCr6dSgkQe1CvwWc
# ZklSUPRR8zZJTYsg0ixXNXkrqPNFYLwjjVj33GHek/45wPmyMKVM1+mYSlg+0wOI
# /rOP015LdhJRk8mMDDtbiiKowSYI+RQQEgN9XyO7ZONj4KbhPvbCdLI/Hgl27Ktd
# RnXiYKNYCQEoAA6EVO7O6V3IXjASvUaetdN2udIOa5kM0jO0zbECAwEAAaOCAV0w
# ggFZMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFLoW2W1NhS9zKXaaL3WM
# aiCPnshvMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB
# /wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYI
# KwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1
# aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RH
# NC5jcnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIw
# CwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQB9WY7Ak7ZvmKlEIgF+ZtbY
# IULhsBguEE0TzzBTzr8Y+8dQXeJLKftwig2qKWn8acHPHQfpPmDI2AvlXFvXbYf6
# hCAlNDFnzbYSlm/EUExiHQwIgqgWvalWzxVzjQEiJc6VaT9Hd/tydBTX/6tPiix6
# q4XNQ1/tYLaqT5Fmniye4Iqs5f2MvGQmh2ySvZ180HAKfO+ovHVPulr3qRCyXen/
# KFSJ8NWKcXZl2szwcqMj+sAngkSumScbqyQeJsG33irr9p6xeZmBo1aGqwpFyd/E
# jaDnmPv7pp1yr8THwcFqcdnGE4AJxLafzYeHJLtPo0m5d2aR8XKc6UsCUqc3fpNT
# rDsdCEkPlM05et3/JWOZJyw9P2un8WbDQc1PtkCbISFA0LcTJM3cHXg65J6t5TRx
# ktcma+Q4c6umAU+9Pzt4rUyt+8SVe+0KXzM5h0F4ejjpnOHdI/0dKNPH+ejxmF/7
# K9h+8kaddSweJywm228Vex4Ziza4k9Tm8heZWcpw8De/mADfIBZPJ/tgZxahZrrd
# VcA6KYawmKAr7ZVBtzrVFZgxtGIJDwq9gdkT/r+k0fNX2bwE+oLeMt8EifAAzV3C
# +dAjfwAL5HYCJtnwZXZCpimHCUcr5n8apIUP/JiW9lVUKx+A+sDyDivl1vupL0QV
# SucTDh3bNzgaoSv27dZ8/DCCBY0wggR1oAMCAQICEA6bGI750C3n79tQ4ghAGFow
# DQYJKoZIhvcNAQEMBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0
# IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNl
# cnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTIyMDgwMTAwMDAwMFoXDTMxMTEwOTIz
# NTk1OVowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3Rl
# ZCBSb290IEc0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAv+aQc2je
# u+RdSjwwIjBpM+zCpyUuySE98orYWcLhKac9WKt2ms2uexuEDcQwH/MbpDgW61bG
# l20dq7J58soR0uRf1gU8Ug9SH8aeFaV+vp+pVxZZVXKvaJNwwrK6dZlqczKU0RBE
# EC7fgvMHhOZ0O21x4i0MG+4g1ckgHWMpLc7sXk7Ik/ghYZs06wXGXuxbGrzryc/N
# rDRAX7F6Zu53yEioZldXn1RYjgwrt0+nMNlW7sp7XeOtyU9e5TXnMcvak17cjo+A
# 2raRmECQecN4x7axxLVqGDgDEI3Y1DekLgV9iPWCPhCRcKtVgkEy19sEcypukQF8
# IUzUvK4bA3VdeGbZOjFEmjNAvwjXWkmkwuapoGfdpCe8oU85tRFYF/ckXEaPZPfB
# aYh2mHY9WV1CdoeJl2l6SPDgohIbZpp0yt5LHucOY67m1O+SkjqePdwA5EUlibaa
# RBkrfsCUtNJhbesz2cXfSwQAzH0clcOP9yGyshG3u3/y1YxwLEFgqrFjGESVGnZi
# fvaAsPvoZKYz0YkH4b235kOkGLimdwHhD5QMIR2yVCkliWzlDlJRR3S+Jqy2QXXe
# eqxfjT/JvNNBERJb5RBQ6zHFynIWIgnffEx1P2PsIV/EIFFrb7GrhotPwtZFX50g
# /KEexcCPorF+CiaZ9eRpL5gdLfXZqbId5RsCAwEAAaOCATowggE2MA8GA1UdEwEB
# /wQFMAMBAf8wHQYDVR0OBBYEFOzX44LScV1kTN8uZz/nupiuHA9PMB8GA1UdIwQY
# MBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA4GA1UdDwEB/wQEAwIBhjB5BggrBgEF
# BQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBD
# BggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3Js
# My5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMBEGA1Ud
# IAQKMAgwBgYEVR0gADANBgkqhkiG9w0BAQwFAAOCAQEAcKC/Q1xV5zhfoKN0Gz22
# Ftf3v1cHvZqsoYcs7IVeqRq7IviHGmlUIu2kiHdtvRoU9BNKei8ttzjv9P+Aufih
# 9/Jy3iS8UgPITtAq3votVs/59PesMHqai7Je1M/RQ0SbQyHrlnKhSLSZy51PpwYD
# E3cnRNTnf+hZqPC/Lwum6fI0POz3A8eHqNJMQBk1RmppVLC4oVaO7KTVPeix3P0c
# 2PR3WlxUjG/voVA9/HYJaISfb8rbII01YBwCA8sgsKxYoA5AY8WYIsGyWfVVa88n
# q2x2zm8jLfR+cWojayL/ErhULSd+2DrZ8LaHlv1b0VysGMNNn3O3AamfV6peKOK5
# lDGCA3YwggNyAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0
# LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hB
# MjU2IFRpbWVTdGFtcGluZyBDQQIQBUSv85SdCDmmv9s/X+VhFjANBglghkgBZQME
# AgEFAKCB0TAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcNAQkF
# MQ8XDTI0MDcyNDE5NDk0MVowKwYLKoZIhvcNAQkQAgwxHDAaMBgwFgQUZvArMsLC
# yQ+CXc6qisnGTxmcz0AwLwYJKoZIhvcNAQkEMSIEINa4sJEtJg+ioofJqTKypi4A
# uBD9uvroVOtxMRIx7Md3MDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEINL25G3tdCLM
# 0dRAV2hBNm+CitpVmq4zFq9NGprUDHgoMA0GCSqGSIb3DQEBAQUABIICABMzP0Un
# ueGw+EIocYrbh972NkfzQQKXvc7E2/T49Be/hn6tDXYoWL70sZ4tkZusGOHd0WFf
# vUCYYY4Dv5RTg+6M1zg2fhtuPpEb52lz+tCi83kiBDbA+0vGICsK/pXPLmtUIdab
# B86fARgpMFFdxD2EUs2lqfB5n/AOdvvfqbXAhDytjzoxg5VNMhjmVQrsfdzlRhs/
# VTTj36MJuorfcZcEzxkPzSc77vPURck3gUeBzFfVutCKwp+HslMHz05yRFuTXdNZ
# +T2GuZMRrQTpLgFx9v9oqT5r5k0cGcP5bQ8b5IW8iWLxZampbbNUVAKQP7BDi1mE
# ZxoLwmpogusRIeCcgg6DzDkXdQHIhEa/kox6yi+1n8NCi5ecBuO7amJU8qHmi50/
# 9qh4xmU+vzii0FJVTVJbu91KLckV4r1EQ6RAmUvR7Obgi0nbi5Ix+uOxeLzLnliR
# mf21/GspB/0GslvdA5s6l9AadG4H+beWCgaI91rX8STXuagAoXLXMZz2fFy4FQ41
# cRS5wP6SzquvyBjGNUZypECdMSJziYWZKk6NgYqXqkeS16htH9Fh/eb1OebmvdWP
# 9OQgapaVeNKEzHVNa/lvsHdhEUwhkfBGd5maknpVJ+LOQLAkQoi59xvXdl7s6PBm
# T0VprHmDGtc1xt8SkMZAwPQAjM0dzVb6cmqN
# SIG # End signature block
