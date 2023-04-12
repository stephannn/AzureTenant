Function Get-DeviceConfigurations(){

    param (
        [String]$DisplayName = $null
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/deviceConfigurations"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
    $filter = "?`$filter=startswith(displayname, '$DisplayName')"

    if($DisplayName){
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)$($filter)"
    } else {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
    }

    try {
        $Result = (Invoke-MgGraphRequest -Method Get -Uri $uri -OutputType PSObject).Value
        return $Result
    } catch {
        Write-Host $_ -ForegroundColor Red
    }

}

Function Get-DeviceConfigurationProfiles(){

    param (
        [String]$DisplayName = $null
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/configurationPolicies"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
    $filter = "?`$filter=startswith(displayname, '$DisplayName')"

    if($DisplayName){
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)$($filter)"
    } else {
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
    }

    try {
        $Result = (Invoke-MgGraphRequest -Method Get -Uri $uri -OutputType PSObject).Value
        return $Result
    } catch {
        Write-Host $_ -ForegroundColor Red
    }

}

Function Get-DeviceConfigurationProfileSetting(){

    param (
        [String]$id = $null,
        [int]$pageSize = 100 # set page size to 100 to retrieve maximum number of settings in one call
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/configurationPolicies/$id/settings"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$top=$pageSize" # add $top parameter to specify page size
    $allSettings = @() # initialize empty array to store all settings

    try {
        do {
            $result = (Invoke-MgGraphRequest -Method Get -Uri $uri -OutputType PSObject)
            $allSettings += $result.Value
            $uri = $result.'@odata.nextLink' # retrieve the next page URI from the response
        } while ($uri) # continue loop until there are no more pages to retrieve

        return $allSettings

    } catch {
        Write-Host $_ -ForegroundColor Red
    }

}

Function Compare-DeviceConfigurationProfileSetting(){

    param (
        [System.Array]$Main,
        [System.Array]$Base,
        [bool]$modify = $true
    )

    #$settingDebug = "device_vendor_msft_policy_config_localpoliciessecurityoptions_useraccountcontrol_behavioroftheelevationpromptforstandardusers"
    #$settingDebug = "user_vendor_msft_policy_config_experience_allowwindowsspotlight"
    $settingDebug = $null

    #$Template = $Base.psobject.Copy()

    $_TempCliXMLString  =   [System.Management.Automation.PSSerializer]::Serialize($Base, [int32]::MaxValue)
    $Template          =   [System.Management.Automation.PSSerializer]::Deserialize($_TempCliXMLString)

    $Main | ForEach-Object {
        #$type = $_.settingInstance.'@odata.type'
        [string]$settingDefinition = $_.settingInstance.settingDefinitionId.toString()
        $choiceSettingValue = $_.settingInstance.choiceSettingValue

        $Template.settingInstance | Where-Object { $_.settingDefinitionId -eq $settingDefinition } | ForEach-Object {
            if(!([string]::IsNullOrEmpty($_.choiceSettingValue))){
                # Debug setting
                if($settingDefinition -eq $settingDebug -or $null -eq $settingDebug){
                    
                    $cp = @()
                    $choiceSettingValueTemplate = $_.choiceSettingValue
                    ($choiceSettingValue | Get-Member -MemberType Properties).Name| ForEach-Object {
                        if($null -ne $choiceSettingValue.$_ -and $null -ne $choiceSettingValueTemplate.$_){
                            $cp += Compare-Object $choiceSettingValue.$_ $choiceSettingValueTemplate.$_
                        }
                    }
                    $cpresult = (![bool]($cp | ForEach-Object { $_ -ne $null }))

                    #if($choiceSettingValue -ne $_.choiceSettingValue){
                    if( $cpresult -eq $false){

                        Write-Host "Setting:         $settingDefinition" -ForegroundColor Green
                        Write-Host "Custom Setting:  $choiceSettingValue"
                        Write-Host "SB Setting:      $($_.choiceSettingValue)"
                    
                        if($modify -eq $true){
                            Write-Host "Changing Setting"
                            $_.choiceSettingValue = $choiceSettingValue
                        }
                    }
                }
            }
        }

        if($Template.settingInstance.settingDefinitionId -notcontains $settingDefinition ){
            Write-Host "Setting missing: $settingDefinition" -ForegroundColor Yellow
            Write-Host "Value: $choiceSettingValue"

            if($modify -eq $true){
                Write-Host "Adding Setting"
                # TBD
            }
        }
    }

    if($modify -eq $true){
        return $Template
    }

}

Function Add-DeviceConfigurationProfileSetting(){
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)] 
        [string]$Name,
        [Parameter(Mandatory=$false)] 
        [string]$Description,
        [Parameter(Mandatory=$true)] 
        [system.array]$Settings
    )

        # Defining Variables
        $graphApiVersion = "beta"
        $Resource = "deviceManagement/configurationPolicies"
        $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"


        #region build the policy
        $newPolicy = [pscustomobject]@{
            name         = $Name
            description  = $Description
            platforms    = "windows10"
            technologies = "mdm"
            settings     = $Settings
        }


        try {
            $result = Invoke-MgGraphRequest -Method POST -Uri $uri -Body (ConvertTo-Json -InputObject ($newPolicy) -Depth 20 ) -ContentType "application/json"
            return $result
        }
        catch {
            Write-Error $_.Exception 
            break
        }
    
}

$ConfProfiles = Get-DeviceConfigurationProfiles

$ConfProfileSetting_Custom = Get-DeviceConfigurationProfileSetting ($ConfProfiles | Where-Object {$_.name -eq "DZE_W11_Config_DEV"}).id
$ConfProfileSetting_SecurityBaseline = Get-DeviceConfigurationProfileSetting ($ConfProfiles | Where-Object {$_.name -eq "MSFT Windows 11 22H2 - Computer"}).id

$newsetting = Compare-DeviceConfigurationProfileSetting -Main $ConfProfileSetting_Custom -Base $ConfProfileSetting_SecurityBaseline -modify $true
$re = Add-DeviceConfigurationProfileSetting -Name "DZE_W11_Config_TEST" -Description "combined with SB" -Settings $newsetting


if($re){
    $ConfProfileSetting_Test = Get-DeviceConfigurationProfileSetting $re.id
    Compare-DeviceConfigurationProfileSetting -Main $ConfProfileSetting_Test -Base $ConfProfileSetting_SecurityBaseline -modify $false
}