
# The algorithm searches for matching substructs in the translation scheme
# comparing the first property of the Old and New structure scheme
# There is a risk of wrong translation if in the New structure scheme
# a property is added in front. Meaning the New APIs extend existing structure
# with new property added on the first position.

function ConvertFrom-DeprecatedBodyCommon {
    # Output body translation is always old -> new direction
    param(
        [Parameter()]
        [PSCustomObject]
        $OperationTranslateSchema,

        [Parameter()]
        [PSCustomObject]
        $OperationOutputObject
    )
    $convertArrayToPSObject = $false

    if ($OperationOutputObject -is [array]) {
        if ($OperationOutputObject.Count -eq 0) {
            $result = @()
            return , $result
        }
        else {
            if ($null -ne $OperationTranslateSchema.OldOutBodyStruct) {
                $oldSchemaProperties = $OperationTranslateSchema.OldOutBodyStruct | Get-Member -MemberType NoteProperty
                $convertArrayToPSObject = ($null -ne $oldSchemaProperties -and `
                        $oldSchemaProperties.Count -eq 2 -and `
                        $oldSchemaProperties[0].Name -eq 'key' -and `
                        $oldSchemaProperties[1].Name -eq 'value')
            }
        }
    }

    if ($convertArrayToPSObject) {
        $resultObject = New-Object PSCustomObject

        foreach ($outputObject in $OperationOutputObject) {
            $translationSchema = [PSCustomObject]@{
                'OldOutBodyStruct' = $($OperationTranslateSchema.OldOutBodyStruct.value)
                'NewOutBodyStruct' = $($OperationTranslateSchema.NewOutBodyStruct)
            }
            $resultObject | Add-Member -MemberType NoteProperty -Name $outputObject.Key -Value (ConvertFrom-DeprecatedBodyCommon $translationSchema $outputObject.value)
        }

        $resultObject

    }
    else {

        foreach ($outputObject in $OperationOutputObject) {

            if (-not $OperationTranslateSchema.OldOutBodyStruct -and -not $OperationTranslateSchema.NewOutBodyStruct) {
                # No Translation Needed
                # return
                $outputObject
            }

            if (-not $OperationTranslateSchema.OldOutBodyStruct -and $OperationTranslateSchema.NewOutBodyStruct) {
                # Translation Impossible
                # return
                $outputObject
            }

            if ($OperationTranslateSchema.OldOutBodyStruct -and -not $OperationTranslateSchema.NewOutBodyStruct) {
                # Old Operation Presents Simple Type as a Structure

                $oldSchemaProperties = $OperationTranslateSchema.OldOutBodyStruct | Get-Member -MemberType NoteProperty
                if ($null -ne $oldSchemaProperties -and $oldSchemaProperties.Count -eq 1) {
                    # Value Wrapper Pattern

                    foreach ($element in $outputObject) {
                        if ($element -is [array] -and $element.Length -eq 0) {
                            # empty array isconverted to empty object
                            $result = New-Object PSCustomObject
                            # return
                            $result
                        }
                        else {
                            # return
                            $element.$($oldSchemaProperties[0].Name)
                        }
                    }
                }

                if ($null -ne $oldSchemaProperties -and `
                        $oldSchemaProperties.Count -eq 2 -and `
                        $oldSchemaProperties[0].Name -eq 'key' -and `
                        $oldSchemaProperties[1].Name -eq 'value') {

                    $result = New-Object PSCustomObject

                    # Map to Array Pattern
                    foreach ($element in $outputObject) {
                        if ($element -is [array] -and $element.Length -eq 0) {
                            # empty array isconverted to empty object
                        }
                        else {
                            $result = New-Object PSCustomObject
                            $result | Add-Member -MemberType NoteProperty -Name $element.key -Value $element.Value
                        }
                    }

                    # return
                    $result
                }
            }


            if ($OperationTranslateSchema.OldOutBodyStruct -and $OperationTranslateSchema.NewOutBodyStruct) {
                # Structure to Structure Translation
                $oldStructProps = $OperationTranslateSchema.OldOutBodyStruct | Get-Member -MemberType NoteProperty
                $newStructProps = $OperationTranslateSchema.NewOutBodyStruct | Get-Member -MemberType NoteProperty
                if ($null -ne $newStructProps -and $null -ne $oldStructProps) {
                    if ($newStructProps[0].Name -eq $oldStructProps[0].Name) {
                        # Structures match no translation needed
                        # Traverse and Translate each property

                        $resultObject = New-Object PSCustomObject

                        foreach ($prop in $oldStructProps) {
                            $translationSchema = [PSCustomObject]@{
                                'OldOutBodyStruct' = $($OperationTranslateSchema.OldOutBodyStruct.$($prop.Name))
                                'NewOutBodyStruct' = $($OperationTranslateSchema.NewOutBodyStruct.$($prop.Name))
                            }

                            $translatedValue = (ConvertFrom-DeprecatedBodyCommon $translationSchema $outputObject.($prop.Name))

                            if ($null -ne $translatedValue) {
                                $resultObject | Add-Member `
                                    -MemberType NoteProperty `
                                    -Name $prop.Name `
                                    -Value $translatedValue
                            }
                        }

                        # return
                        $resultObject
                    }
                    else {
                        if ($oldStructProps.Count -eq 1) {
                            # Value Wrapper Pattern
                            $translationSchema = [PSCustomObject]@{
                                'OldOutBodyStruct' = $($OperationTranslateSchema.OldOutBodyStruct.$($oldStructProps[0].Name))
                                'NewOutBodyStruct' = $($OperationTranslateSchema.NewOutBodyStruct)
                            }

                            # return
                            (ConvertFrom-DeprecatedBodyCommon $translationSchema $outputObject.($oldStructProps[0].Name))
                        }

                        if ($oldStructProps.Count -eq 2 -and `
                                $oldStructProps[0].Name -eq 'key' -and `
                                $oldStructProps[1].Name -eq 'value') {
                            # Map to Array pattern

                            # Handle Empty array
                            if ($outputObject -is [array] -and $outputObject.Length -eq 0) {
                                # empty array isconverted to empty object
                                $result = New-Object PSCustomObject
                                # return
                                $result
                            }
                            else {
                                $result = New-Object PSCustomObject

                                foreach ($element in $outputObject) {
                                    $translationSchema = [PSCustomObject]@{
                                        'OldOutBodyStruct' = $($OperationTranslateSchema.OldOutBodyStruct.value)
                                        'NewOutBodyStruct' = $($OperationTranslateSchema.NewOutBodyStruct)
                                    }

                                    $result | Add-Member `
                                        -MemberType NoteProperty `
                                        -Name $element.key `
                                        -Value (ConvertFrom-DeprecatedBodyCommon $translationSchema ($element.value))
                                }

                                # return
                                $result
                            }
                        }
                    }
                }

                if ($null -eq $newStructProps -and $null -ne $oldStructProps) {
                    # Old Operation Presents Simple Type as a Structure
                    foreach ($element in $outputObject) {
                        $noteProperties = $element | Get-Member -MemberType NoteProperty
                        if ($null -ne $noteProperties -and $noteProperties.Count -eq 1) {
                            # Value Wrapper Pattern

                            # return
                            $element.$($noteProperties[0].Name)
                        }

                        if ($null -ne $noteProperties -and `
                                $noteProperties.Count -eq 2 -and `
                                $noteProperties[0].Name -eq 'key' -and `
                                $noteProperties[1].Name -eq 'value') {
                            # Map to Array Pattern
                            $result = New-Object PSCustomObject
                            $result | Add-Member -MemberType NoteProperty -Name $element.key -Value $element.Value
                            # return
                            $result
                        }
                    }
                }

                if ($null -eq $newStructProps -and $null -eq $oldStructProps) {
                    # If the OperationOutputObject is an array, using foreach will result in
                    # returning only the first element of the array, instead of the whole array.
                    if ($OperationOutputObject -is [array]) {
                        # return the whole array and use the comma syntax in the case of array with only one element
                        , $OperationOutputObject
                    } else {
                        # return the current object only
                        $outputObject
                    }
                }
            }
        }
    }
}

function ConvertTo-DeprecatedBodyCommon {
    # Input body translation is always new -> old direction
    param(
        [Parameter()]
        [PSCustomObject]
        $OperationTranslateSchema,

        [Parameter()]
        [PSCustomObject]
        $OperationInputObject
    )
    if ($OperationInputObject -is [array] -and $OperationInputObject.Count -eq 0) {
        return (New-Object PSCustomObject)
    }


    $result = $null
    if ($OperationInputObject -is [array]) {
        $result = @()
    }

    foreach ($inputObject in $OperationInputObject) {
        $singleObjectResult = $null
        if (-not $OperationTranslateSchema.OldInBodyStruct -and -not $OperationTranslateSchema.NewInBodyStruct) {
            # No Translation Needed
            $singleObjectResult = $inputObject
        }

        if (-not $OperationTranslateSchema.OldInBodyStruct -and $OperationTranslateSchema.NewInBodyStruct) {
            # Translation Impossible
            # return and let the server to fail
            $singleObjectResult = $inputObject
        }

        if ($OperationTranslateSchema.OldInBodyStruct -and -not $OperationTranslateSchema.NewInBodyStruct) {
            # Old Operation Presents Simple Type as a Structure
            $oldSchemaProperties = $OperationTranslateSchema.OldInBodyStruct | Get-Member -MemberType NoteProperty
            if ($null -ne $oldSchemaProperties -and $oldSchemaProperties.Count -eq 1) {
                # Value Wrapper Pattern

                foreach ($element in $inputObject) {
                    if ($element -is [PSCustomObject] -and ($element | Get-Member -MemberType NoteProperty).Count -eq 0) {
                        # empty PSCustom Object is converted to empty array
                        # return
                        $singleObjectResult = @()
                    }
                    else {
                        $resultObject = New-Object PSCustomObject
                        $resultObject | Add-Member -MemberType NoteProperty -Name $oldSchemaProperties[0].Name -Value $element
                        # return
                        $singleObjectResult = $resultObject
                    }
                }
            }

            if ($null -ne $oldSchemaProperties -and `
                    $oldSchemaProperties.Count -eq 2 -and `
                    $oldSchemaProperties[0].Name -eq 'key' -and `
                    $oldSchemaProperties[1].Name -eq 'value') {
                # Map to Array Pattern
                foreach ($element in $outputObject) {
                    if ($element -is [PSCustomObject] -and ($element | Get-Member -MemberType NoteProperty).Count -eq 0) {
                        # empty PSCustom Object is converted to empty array
                        # return
                        $singleObjectResult = @()
                    }
                    else {
                        $resultObject = New-Object PSCustomObject
                        $resultObject | Add-Member -MemberType NoteProperty -Name 'key' -Value $element.key
                        $resultObject | Add-Member -MemberType NoteProperty -Name 'value' -Value $element.Value
                        # return
                        $singleObjectResult = $resultObject
                    }
                }
            }
        }

        if ($OperationTranslateSchema.OldInBodyStruct -and $OperationTranslateSchema.NewInBodyStruct) {
            # Structure to Structure Translation
            $oldStructProps = $OperationTranslateSchema.OldInBodyStruct | Get-Member -MemberType NoteProperty
            $newStructProps = $OperationTranslateSchema.NewInBodyStruct | Get-Member -MemberType NoteProperty
            if ($null -ne $newStructProps -and $null -ne $oldStructProps) {
                <#
                    In the deprecated vSphere APIs, the 'client_token' is in the body
                    and in the new vSphere APIs, the 'client_token' is moved to the header parameters.
                    There're 10 vSphere APIs using the 'client_token' and in each the 'client_token' is the
                    first element. So we need to remove it from the body so that the translation algorithm can
                    work as expected - either we're left with matching Structures or the Wrapper Pattern occurs.
                #>
                if ($oldStructProps[0].Name -eq 'client_token') {
                    $oldStructProps = $oldStructProps[1..($oldStructProps.Length - 1)]
                }

                if ($newStructProps[0].Name -eq $oldStructProps[0].Name) {
                    # Structures match no translation needed
                    # Traverse and Translate each property

                    $resultObject = New-Object PSCustomObject

                    foreach ($prop in $oldStructProps) {
                        # Assuming the New Structure has all the properties the old one has
                        # In case the new one has more they won't be translated
                        $translationSchema = [PSCustomObject]@{
                            'OldInBodyStruct' = $($OperationTranslateSchema.OldInBodyStruct.$($prop.Name))
                            'NewInBodyStruct' = $($OperationTranslateSchema.NewInBodyStruct.$($prop.Name))
                        }

                        $translatedValue = (ConvertTo-DeprecatedBodyCommon $translationSchema $inputObject.($prop.Name))

                        if ($null -ne $translatedValue) {
                            $resultObject | Add-Member `
                                -MemberType NoteProperty `
                                -Name $prop.Name `
                                -Value $translatedValue
                        }
                    }

                    # return
                    $singleObjectResult = $resultObject
                }
                else {
                    if ($oldStructProps.Count -eq 1) {
                        # Spec Wrapper Pattern
                        $translationSchema = [PSCustomObject]@{
                            'OldInBodyStruct' = $($OperationTranslateSchema.OldInBodyStruct.$($oldStructProps[0].Name))
                            'NewInBodyStruct' = $($OperationTranslateSchema.NewInBodyStruct)
                        }


                        $translatedValue = (ConvertTo-DeprecatedBodyCommon $translationSchema $inputObject)
                        $resultObject = New-Object PSCustomObject
                        $resultObject | Add-Member `
                            -MemberType NoteProperty `
                            -Name $oldStructProps[0].Name `
                            -Value $translatedValue

                        # return
                        $singleObjectResult = $resultObject
                    }

                    if ($oldStructProps.Count -eq 2 -and `
                            $oldStructProps[0].Name -eq 'key' -and `
                            $oldStructProps[1].Name -eq 'value') {
                        # Array to Map pattern

                        # Handle Empty array
                        if ($inputObject -is [PSCustomObject] -and ($inputObject | Get-Member -MemberType NoteProperty).Count -eq 0) {
                            # empty PSObject is converted to empty array
                            # return
                            $singleObjectResult = @()
                        }
                        else {
                            $singleObjectResult = @()
                            foreach ($element in $inputObject) {
                                $notePropertyMemebers = $element | Get-Member -MemberType NoteProperty
                                if ($notePropertyMemebers.Count -ne 1) {
                                    throw "Input object array to map cannot be translated because element has more than one key note property"
                                }

                                # Note property name is mapped to the 'key' property of the old structure
                                # Note property value is mapped to the 'value' property of the old structure
                                $translationSchema = [PSCustomObject]@{
                                    'OldInBodyStruct' = $($OperationTranslateSchema.OldInBodyStruct.value)
                                    'NewInBodyStruct' = $($OperationTranslateSchema.NewInBodyStruct)
                                }
                                $resultObject = New-Object PSCustomObject
                                $resultObject | Add-Member -MemberType NoteProperty -Name 'key' -Value $notePropertyMemebers[0].Name
                                $resultObject | Add-Member -MemberType NoteProperty -Name 'value' -Value (ConvertTo-DeprecatedBodyCommon $translationSchema ($element.$($notePropertyMemebers[0].Name)))
                                # return
                                $singleObjectResult += $resultObject
                            }
                        }
                    }
                }
            }

            if ($null -eq $newStructProps -and $null -ne $oldStructProps) {
                # Old Operation Presents Simple Type as a Structure
                foreach ($element in $inputObject) {
                    $noteProperties = $element | Get-Member -MemberType NoteProperty
                    if ($noteProperties.Count -eq 1) {
                        # Query Input Array Parameter Pattern
                        $resultObject = [PSCustomObject] @{
                            $noteProperties[0].Name = $element.($noteProperties[0].Name)
                        }

                        $resultObject
                    } elseif ($oldStructProps.Count -eq 1) {
                        # Spec Wrapper Pattern
                        $resultObject = New-Object PSCustomObject
                        $resultObject | Add-Member `
                            -MemberType NoteProperty `
                            -Name $oldStructProps[0].Name `
                            -Value $element

                        # return
                        $singleObjectResult = $resultObject
                    }

                }
            }

            if ($null -eq $newStructProps -and $null -eq $oldStructProps) {
                # return
                $singleObjectResult = $inputObject
            }
        }

        if ($result -is [array]) {
            $result += $singleObjectResult
        } else {
            $result = $singleObjectResult
        }
    }

    # return converted result
    if ($result -is [array] -and $result.Count -eq 1) {
        return , $result
    } else {
        return $result
    }
}

function Convert-StructureDefitionToArrayDefinition {
    <#
    .SYNOPSIS
    Converts structure definition from translation scheme to array definition

    .DESCRIPTION
    The convertor is for the purpose of translating body structure defined in the translation schema to query parameters definition,

    .PARAMETER DataStructureDefinition
    PSCustomObject that represents the InBody definition of a translation schema for an API operation
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [PSCustomObject]
        $DataStructureDefinition,

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ref]$StructureObject
    )

    $newStructureObject =New-Object PSCustomObject

    foreach ($dsDef in $DataStructureDefinition) {
        $dsDef | Get-Member -MemberType NoteProperty | Foreach-Object {
            if ($dsDef.$($_.Name) -is [PSCustomObject]) {
                # For some APIs multiple structures are converted list of query params
                # We assume there are no nested structures in the query params
                # The modst complext case is assumed to be
                #  {
                #      'loc_spec': {
                #            'locaiton': 'string'
                #      }
                #      'filter_spec': {
                #        'max_result': 'integer'
                #      }
                #   }
                #
                # which is converted to @(locaiton, max_result) query parameters
                #
                $parentPropertyName = $_.Name
                $dsDef.$($_.Name) | Get-Member -MemberType NoteProperty | Foreach-Object {
                    $newStructureObject | Add-Member -MemberType NoteProperty -Name "$($parentPropertyName).$($_.Name)" -Value $($StructureObject.Value.$parentPropertyName.$($_.Name))
                    # result
                    "$($parentPropertyName).$($_.Name)"
                }
            } else {
                $newStructureObject | Add-Member -MemberType NoteProperty -Name $($_.Name) -Value $($StructureObject.Value.$($_.Name))
                # result
                $_.Name
            }
        }
    }

    $StructureObject.Value = $newStructureObject
}

function ConvertTo-DeprecatedQueryParamCommon {
    # Converts Query Param object from new -> old direction
    param(
        [Parameter()]
        [PSCustomObject]
        $OperationTranslateSchema,

        [Parameter()]
        [PSCustomObject]
        $OperationQueryInputObject
    )


    if ($null -ne $OperationTranslateSchema.OldInQueryParams -and `
            $null -ne $OperationTranslateSchema.NewInQueryParams -and `
            $OperationQueryInputObject -is [PSCustomObject]) {

        $resultObject = New-Object PSCustomObject

        $newQueryParamDefinition = $null

        if ($OperationTranslateSchema.NewInQueryParams -isnot [array] -and `
            $OperationTranslateSchema.NewInQueryParams -is [PSCustomObject]) {

            $newQueryParamDefinition = (Convert-StructureDefitionToArrayDefinition -DataStructureDefinition $OperationTranslateSchema.NewInQueryParams -StructureObject ([ref]$OperationQueryInputObject))
        } else {
            $newQueryParamDefinition = $OperationTranslateSchema.NewInQueryParams
        }

        foreach ($newQueryParam in $newQueryParamDefinition) {
            foreach ($oldQueryParam in $OperationTranslateSchema.OldInQueryParams) {
                $value = $($OperationQueryInputObject."$newQueryParam")
                if ($null -ne $value) {
                    $propName = $newQueryParam
                    if ($oldQueryParam -eq $newQueryParam) {
                        # leave it as-is
                        $resultObject | Add-Member -MemberType NoteProperty -Name $propName -Value $value
                    }
                    elseif ($oldQueryParam.EndsWith(".$newQueryParam")) {
                        # Use the old property name
                        $propName = $oldQueryParam
                        $resultObject | Add-Member -MemberType NoteProperty -Name $propName -Value $value
                    }
                }
            }
        }

        # return
        $resultObject
    }
    else {
        # The conversion is not possible
        $OperationQueryInputObject
    }
}
# SIG # Begin signature block
# MIIphwYJKoZIhvcNAQcCoIIpeDCCKXQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD0Tpo0XunmJgOu
# mDH1INfpGRqAXwvlDMEjyO1Q3s6bAaCCDnQwggawMIIEmKADAgECAhAIrUCyYNKc
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
# NwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEID7jK169nGzPit/B
# 1Gv00GqglYfk3fHL89vPvwkxdPQ7MA0GCSqGSIb3DQEBAQUABIICAGCLUcYnMxHK
# onin0uH0IINL8NTghrNWyyNszV+worfPfOuV9TSl2B9qzNHn7mUg+CVbmpCa24Z2
# QGsjGVbiPYAX432BocRQjY3SmgImx4B7kEl32jNclUMp9cH8FW0zaATl2E7Gn7dh
# rlXEzgd8LCNLI2kLXfjFnGDz3s405Qx2mckbnc3lPut0g8mxzYK0usbfShSkMiHz
# fpHqLe5Rbb/AxedlKNshKg3kyqsZV1TfVSxYXv4Zi8RkUY6qFC8UmsYzcalhAqqE
# jHoNWoCqNvNMmYlwQMWs/7+qtP9l0didMgc2XAQb9vCOdt37EawVSQV23nOurriF
# uhea4T0Sn366X/Lx9eaeKwqex6u49zh3UyFcgS9rCpA3oOrFW2RhOgUXtfgCr3bc
# 150dadWKsNglaka3mv78XpDG0YiqEtUHG3eM8g6hmzkZWszzbWSxJahu2EH/lg/U
# qmIAan03Z3VtiCSw8KQA3ffJF44Cwa7kOGF5cfHK029cFdGdo3owtFclUJcTqiAS
# SfZHO44vhRHQpZQAshFglsUzPUuG97qB2tgxD0RxAYxenIKgrqjLQmhDnKotmpfg
# rhPPvbkdnvAi34Uaq9MtBjrjTK8tAqwt1OR5PhPmMIHdEWRAiLe2hOByxdHKIS3f
# DQ0CLO43WIkh//o5CcRKlX4rLDUQNMrAoYIXPzCCFzsGCisGAQQBgjcDAwExghcr
# MIIXJwYJKoZIhvcNAQcCoIIXGDCCFxQCAQMxDzANBglghkgBZQMEAgEFADB3Bgsq
# hkiG9w0BCRABBKBoBGYwZAIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAE
# IPdpl9WuWw9mV3eLgEREbLf7zUUipl/uLT0kC1bTsVKUAhA/aLLpkpPW8vrc6bc6
# 8aHbGA8yMDI0MDcyNDE5NDUzOFqgghMJMIIGwjCCBKqgAwIBAgIQBUSv85SdCDmm
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
# MQ8XDTI0MDcyNDE5NDUzOFowKwYLKoZIhvcNAQkQAgwxHDAaMBgwFgQUZvArMsLC
# yQ+CXc6qisnGTxmcz0AwLwYJKoZIhvcNAQkEMSIEIHP0AIKFMUUaFTF+ybLG3ozp
# MHRNTJmFyWLa03oVziIAMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEINL25G3tdCLM
# 0dRAV2hBNm+CitpVmq4zFq9NGprUDHgoMA0GCSqGSIb3DQEBAQUABIICAJlCvmTj
# +F9SxD6NWvG90hR9xqPLnq7GB0rH4rLKzP2M2j2oa8Up+tV/suLd3lOJ96vXWtve
# Z1gr8c5sIAHlpr/hC7a3c0/MjYroHzvd7WbTrv9rwgZkmVKfZLpm2yh9KfmKWLof
# //lmsmE2/EUHkB7XFu80YTTFXDAqIR1w2QRB41APYizuQ6/aHmrjxDOzXhLkb3tX
# SD/EwXtPO27nLnLt1KN+J+lsUoBBrfWRvDhRbp08nYoyvkWxNCV7mZBlQxXdrOns
# OlQeYvjscbOSFuBiIL0X7o1UdDX+GpnPNEM+dcHKBudNk7qAGLaG0Gqp9HGWudhS
# mqq8H6KHqm0qdIBT9RC6LuHu/ceJCFnh1mPtUnBVmlz+5gAmjF3qP8mdWpSKaPkm
# JJG/L50rvFcbI6KXUF2eTKh8r+gm6fJkgBKUW5xoyqx61++p/CtkwWtavB645Tvs
# RYyc4NBUHe2F0/nOAQm3uASVTaK3G5NousPNXp/mEs7oiN6KuoI2E8LQ/BNuv5wK
# JtcurEUaAAoW6/IEQ2NhuE6apesOS8t/FkaJZ6UO7EgB577K0bqNuGnJIAVYSiNn
# 5R3XCqFvFGAhK+1G20mg2VhIs/Io6qNjM7P4AIRJ98cQaAWVUQMbWgxLH+mpZ37M
# FjEhNv8OoVBLjTlAiduhwAjWIyOiPy4MIzpr
# SIG # End signature block
