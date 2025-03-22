<#
.SYNOPSIS
A wrapper function for Invoke-WebRequest which gets content from a web page on the internet.

.DESCRIPTION
A wrapper function for Invoke-WebRequest which gets content from a web page on the internet.
For PowerShell Core the function calls the Invoke-WebRequest cmdlet directly.
For PowerShell 5.1 a custom Certificate Validator is used to cover the missing SkipCertificateCheck parameter.

.PARAMETER InvokeParams
The hashtable containing the parameters that are going to be passed to the Invoke-WebRequest cmdlet.

.PARAMETER SkipCertificateCheck
If the value is $true, skips certificate validation checks. This includes all validations such as
expiration, revocation, trusted root authority, etc.
#>
function Invoke-WebRequestX {
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject])]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $InvokeParams,

        [Parameter(Mandatory = $true)]
        [bool]
        $SkipCertificateCheck
    )

    $tempProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    $invokeWebRequestResult = $null

    if ($Global:PSVersionTable.PSEdition -eq 'Core') {
        $InvokeParams['SkipCertificateCheck'] = $SkipCertificateCheck

        $invokeWebRequestResult = Invoke-WebRequest @InvokeParams
    } else {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [CustomCertificatesValidator]::GetDelegate()

        try {
            $invokeWebRequestResult = Invoke-WebRequest @InvokeParams
        } finally {
            $debugLog = [CustomCertificatesValidator]::GetDebugLog()
            Write-Debug -Message $debugLog
        }
    }

    $ProgressPreference = $tempProgressPreference

    $invokeWebRequestResult
}

<#
.SYNOPSIS
A wrapper function for Invoke-RestMethod which sends an HTTP or HTTPS request to a RESTful web service.

.DESCRIPTION
A wrapper function for Invoke-RestMethod which sends an HTTP or HTTPS request to a RESTful web service.
For PowerShell Core the function calls the Invoke-RestMethod cmdlet directly.
For PowerShell 5.1 a custom Certificate Validator is used to cover the missing SkipCertificateCheck parameter.

.PARAMETER InvokeParams
The hashtable containing the parameters that are going to be passed to the Invoke-RestMethod cmdlet.

.PARAMETER SkipCertificateCheck
If the value is $true, skips certificate validation checks. This includes all validations such as
expiration, revocation, trusted root authority, etc.
#>
function Invoke-RestMethodX {
    [CmdletBinding()]
    [OutputType([System.Object])]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $InvokeParams,

        [Parameter(Mandatory = $true)]
        [bool]
        $SkipCertificateCheck
    )

    $invokeRestMethodResult = $null

    if ($Global:PSVersionTable.PSEdition -eq 'Core') {
        $InvokeParams['SkipCertificateCheck'] = $SkipCertificateCheck

        $invokeRestMethodResult = Invoke-RestMethod @InvokeParams
    } else {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [CustomCertificatesValidator]::GetDelegate()

        try {
            $invokeRestMethodResult = Invoke-RestMethod @InvokeParams
        } finally {
            $debugLog = [CustomCertificatesValidator]::GetDebugLog()
            Write-Debug -Message $debugLog
        }
    }

    $invokeRestMethodResult
}

<#
.SYNOPSIS
Retrieves the Certificate thumbprint for the specified remote host.

.DESCRIPTION
Retrieves the Certificate thumbprint for the specified remote host. Tcp and Ssl streams are used.

.PARAMETER RemoteHostName
The IPAddress of the remote host.

.PARAMETER Port
The port number of the remote host.

.PARAMETER Timeout
A TimeSpan that represents the number of milliseconds to wait, or a TimeSpan that represents -1 milliseconds to wait indefinitely.
#>
function Get-TlsCertificateThumbprintFromRemoteHost {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $RemoteHostName,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(0, 65535)]
        [int]
        $Port = 443,

        [Parameter(Mandatory = $false, Position = 2)]
        [int]
        $Timeout = 3000
    )

    $certificate = $null
    $certificateThumbprint = $null

    $sslStream = $null
    $tcpStream = $null
    $tcpClient = $null

    try {
        $tcpClient = New-Object -TypeName 'System.Net.Sockets.TcpClient'

        $iAsyncResult = $tcpClient.BeginConnect($RemoteHostName, $Port, $null, $null)
        $wait = $iAsyncResult.AsyncWaitHandle.WaitOne($Timeout, $false)

        if (!$wait) {
            $tcpClient.Close()
            Write-Warning -Message "Connection attempt to server $RemoteHostName has timed out."
        } else {
            $tcpClient.EndConnect($iAsyncResult) | Out-Null

            if ($tcpClient.Connected) {
                $tcpStream = $tcpClient.GetStream()

                $sslStream = New-Object -TypeName 'System.Net.Security.SslStream' -ArgumentList ($tcpStream, $false, ({ $true } -as [System.Net.Security.RemoteCertificateValidationCallback]))
                $sslStream.AuthenticateAsClient($RemoteHostName, $null, [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13, $false)

                $certificate = New-Object -TypeName 'System.Security.Cryptography.X509Certificates.X509Certificate2' -ArgumentList ($sslStream.RemoteCertificate)
                $certificateThumbprint = $certificate.Thumbprint
            } else {
                Write-Warning -Message "Unable to establish connection to server $RemoteHostName on port $Port."
            }
        }
    } catch {
        throw "SkipCertificateCheck with value True requires retrieving Certificate thumbprint from server $RemoteHostName which failed with the following error : $($_.Exception.Message)"
    } finally {
        if ($null -ne $certificate) {
            $certificate.Dispose()
        }

        if ($null -ne $sslStream) {
            $sslStream.Close()
            $sslStream.Dispose()
        }

        if ($null -ne $tcpStream) {
            $tcpStream.Close()
            $tcpStream.Dispose()
        }

        if ($null -ne $tcpClient) {
            $tcpClient.Close()
        }
    }

    $certificateThumbprint
}

<#
.SYNOPSIS
A wrapper function that extracts the password from a SecureString as plain text.

.DESCRIPTION
A wrapper function that extracts the password from a SecureString as plain text.
For PowerShell Core the function calls the ConvertFrom-SecureString cmdlet directly.
For PowerShell 5.1 the System.Runtime.InteropServices.Marshal type is used to extract
the password from the SecureString as plain text.

.PARAMETER Password
Specifies the SecureString Password from which the plain text password should be extracted.
#>
function Get-PlainTextPassword {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [SecureString]
        $Password
    )

    $plainTextPassword = $null

    if ($Global:PSVersionTable.PSEdition -eq 'Core') {
        $plainTextPassword = ConvertFrom-SecureString -SecureString $Password -AsPlainText
    } else {
        $passwordAsBinaryString = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($passwordAsBinaryString)
    }

    $plainTextPassword
}

<#
.SYNOPSIS
A wrapper function that converts a JSON to PSCustomObject.

.DESCRIPTION
A wrapper function that converts a JSON to PSCustomObject.
For PowerShell Core the function calls the ConvertFrom-Json cmdlet directly.
For PowerShell 5.1 the Newtonsoft.Json library is used to ensure the same behaviour
for both PowerShell versions.

.PARAMETER InputObject
Specifies the input JSON that should be converted to PSCustomObject.

.PARAMETER Depth
Gets or sets the maximum depth the JSON input is allowed to have. By default, it is 100.
#>
function ConvertFrom-JsonX {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]
        $InputObject,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1024)]
        [int]
        $Depth = 100
    )

    Process {
        $result = $null

        if ($Global:PSVersionTable.PSEdition -eq 'Core') {
            $result = ConvertFrom-Json -InputObject $InputObject -Depth $Depth
        } else {
            try {
                $jsonSerializerSettings = [Newtonsoft.Json.JsonSerializerSettings]::new()

                $jsonSerializerSettings.TypeNameHandling = [Newtonsoft.Json.TypeNameHandling]::None
                $jsonSerializerSettings.MetadataPropertyHandling = [Newtonsoft.Json.MetadataPropertyHandling]::Ignore
                $jsonSerializerSettings.MaxDepth = $Depth

                $deserializedObject = [Newtonsoft.Json.JsonConvert]::DeserializeObject($InputObject, $jsonSerializerSettings)

                if ($deserializedObject -is [Newtonsoft.Json.Linq.JObject]) {
                    $result = ConvertFrom-JObject -JObject $deserializedObject
                } elseif($deserializedObject -is [Newtonsoft.Json.Linq.JArray]) {
                    $result = ConvertFrom-JArray -JArray $deserializedObject
                } else {
                    $result = $deserializedObject
                }
            } catch {
                throw "Conversion from JSON failed with error: $($_.Exception.Message)"
            }
        }

        $result
    }
}

function ConvertFrom-JObject {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $JObject
    )

    $psCustomObjectResult = [PSCustomObject] @{}

    foreach ($entry in $JObject.GetEnumerator()) {
        if ($null -eq $entry.Key) {
            return $null
        }

        if ($entry.Value -is [Newtonsoft.Json.Linq.JObject]) {
            $entryValue = ConvertFrom-JObject -JObject $entry.Value

            $psCustomObjectResult | Add-Member -MemberType NoteProperty -Name $entry.Key -Value $entryValue
        } elseif ($entry.Value -is [Newtonsoft.Json.Linq.JValue]) {
            $psCustomObjectResult | Add-Member -MemberType NoteProperty -Name $entry.Key -Value $entry.Value.Value
        } elseif ($entry.Value -is [Newtonsoft.Json.Linq.JArray]) {
            $entryValue = ConvertFrom-JArray -JArray $entry.Value
            if ($null -eq $entryValue) {
                $entryValue = @()
            }

            $psCustomObjectResult | Add-Member -MemberType NoteProperty -Name $entry.Key -Value $entryValue
        }
    }

    $psCustomObjectResult
}

function ConvertFrom-JArray {
    [CmdletBinding()]
    [OutputType([array])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $JArray
    )

    $arrayResult = @()

    for ($i = 0; $i -lt $JArray.Count; $i++) {
        $entry = $JArray[$i]
        if ($entry -is [Newtonsoft.Json.Linq.JArray]) {
            $arrayResult += ConvertFrom-JArray -JArray $entry
        } elseif ($entry -is [Newtonsoft.Json.Linq.JObject]) {
            $arrayResult += ConvertFrom-JObject -JObject $entry
        } elseif ($entry -is [Newtonsoft.Json.Linq.JValue]) {
            $arrayResult += $entry.Value
        }
    }

    if ($arrayResult.Count -eq 1) {
        , $arrayResult
    } else {
        $arrayResult
    }
}

# SIG # Begin signature block
# MIIpiAYJKoZIhvcNAQcCoIIpeTCCKXUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDXehCgWaBdNU1V
# 5x8tv0fB+QeMO6168i4h4JcTs02CNqCCDnQwggawMIIEmKADAgECAhAIrUCyYNKc
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
# NwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIAKClgHpEjBZgM4d
# bI2sCMbLh7dtk21FVHG92ubRYvFNMA0GCSqGSIb3DQEBAQUABIICAGstfiVtoFsc
# qTAiYU+R1GXEUP/LrhIxS0PHK3NuG1ER+fO3Cvc0TKBo+bz6rzjoCC/xEr7lWy8z
# L+Kn7/I3z0C8NYfq6AIKmACFC53IxYIkSNrx10iGkxhuD2rzgL2IcA4bDHfu0Lvr
# h4FB6eUvI/iEFyEadq7o21kmmVQPgenNnDv/bhbQ1swsUG2km8adV0ZHo8SgTuFo
# 5pAWaxMurZGCjbcuAfLuf0VEGG+4+RziYehI4tBxsxI/Dp54c5Iwi49uor7A6nA2
# I28GkiuHGm5MSdF3e86/pveAxGPgRRDkmyYYoK3QSYBGi/AgBGm4Fv5NstyYLaOP
# YqmkpKsCwFlrAw/HvXTUGJgtc5hvDX22/tH+WRyB8bjw8uA6yKII4xwfAuf2QZ7G
# 7rtpftmvVLv9euI6bwbQZMSbqLPAPZoF3+WIbCksvlUdEeRM25S1aI8BhG4m0NNg
# QyV6EzbANNSgCXUYDK484deR1CK6pPaNxqBhTGjRAsajMNaRqw04qo0osiZYYKAk
# eojFXXzQosYl5Nz/BrOssn3XzbTFaJzqeZgI7l+x8qOII9nWFiy02ffBF9lUEqjG
# P69gRCQXlBuo/optGWFBMgs6z6nFMKThKaJvbdjB7hYVJ79j7NfiJQsD/hI7EweE
# tueVH3Ln5RDkKenuix8srJeVXJm7AtfioYIXQDCCFzwGCisGAQQBgjcDAwExghcs
# MIIXKAYJKoZIhvcNAQcCoIIXGTCCFxUCAQMxDzANBglghkgBZQMEAgEFADB4Bgsq
# hkiG9w0BCRABBKBpBGcwZQIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAE
# IDOMTT2gfXeD9dGAOywpI7BVUOnwx8YtlwUejWjbhk2vAhEA/JJ2WqOTaGVy2wtH
# 7+zrwxgPMjAyNDA3MjQxOTMzNDJaoIITCTCCBsIwggSqoAMCAQICEAVEr/OUnQg5
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
# BTEPFw0yNDA3MjQxOTMzNDJaMCsGCyqGSIb3DQEJEAIMMRwwGjAYMBYEFGbwKzLC
# wskPgl3OqorJxk8ZnM9AMC8GCSqGSIb3DQEJBDEiBCBpjN7U2Ok+8s3GfvGKhLDN
# ffpiXMU26G/Jx1fRdFdNJjA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDS9uRt7XQi
# zNHUQFdoQTZvgoraVZquMxavTRqa1Ax4KDANBgkqhkiG9w0BAQEFAASCAgANCHAN
# C+ZUxVgb45dwr2v9ouUbo/UTKuxoR0sXHIULI5MStstjp3ockv0/K5vzhrevTBwZ
# S/1RTVrC1WL1KSMTkjF8T/Xhws9K12KzkUugDhkG6ublQlBn5bAIBeCnq1oq/gZG
# tEkmXXAKshbhUqm36/MChhtq20/qwxijg2zrfoFSkJOJx3VJau+zAwiSZ5GUXURW
# 9X0i4Y+qSAPg4/J/LSNLWb36/F8gWlv7wvFKOqKLa/hxrXB7qkgU334AFUZWE2kl
# 4xhQcaTg5lvgGr2ADqBidiUsz8KXp1FB8hSFH4kVSaPoelFKiO9WnC7t+yZ5l8HE
# EEvDhe/EImGYT+5BCrN1wjI3OLnOlb+EnyD3eVWuABLyhc58hLRWth/pRn4tCi5l
# N6a3bLwX7Lh+y/QuDTqSmjgAYMbMMyTi6AiSLi04uTHqH6s92FDkwDwXvBMfCZxm
# MXJAkKYQ3Y9aS5xUFlMsFDLeGrxZrFXkG4Soq93ZMfgRXjzaU4M1jVXk0vT/eAC4
# Es8KlV6LKwBETbV7NO5Of16Xy4aoErqjW6W8pWMfmEItuY2p4tthh2mYuTzbACLE
# O7XKYRUAwknZYh+VYA04kf8v/Qtipdg/f2B4bwAwkGSD8KomCtkDqkJDw0zRMgD1
# U1hrRUUPDFL0u0EXnffNrNe5AnBnodDNBRawrQ==
# SIG # End signature block
