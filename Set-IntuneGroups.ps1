# This script will pull data regarding machine via 
# MS Graph, and determine if it needs to be added (or removed)
# from a group found in groups.yaml

# Connect to Azure Tenant via Microsoft Graph
$tenantId = '<Your Tenant ID>' # Production Tenant ID
$clientId = '<Your Intune Device Group Builder Registered App ID>' # Intune Device Group Builder
$clientSecret = '<Your Intune Device Group Builder Registered App Secret>'

### Begin Custom Functions ###
function Get-GroupMembers {
    param (
        $Group
    )
    Write-Verbose 'Gathering Group members'

    $tempGroupInfo = Get-MgGroup -Filter "displayName eq '$($Group)'"
    (Get-MgGroupMember -All -GroupId $tempGroupInfo.Id).Id
}

### End Custom Functions ###

### Being Main Script ###

# Prepping credentials for App Authentication
$secret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($clientId, $secret)

Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential

# Configuring Microsoft Graph Request Context (defaults seem to fail when running Get-MgDeviceManagementDetectedApp)
Set-MgRequestContext -MaxRetry 5 -RetryDelay 10 | Out-Null

# Gather data from Graph that will be used to aid with group add/removal decision making

# Detected Apps
$detectedApps = Get-MgDeviceManagementDetectedApp -All

#### Insert other data here if this groups sync expands beyond just application presence ####

# Begin looking at Groups we want to maintain
Write-Host 'Pulling data from groups.yaml'
$groups = Get-Content groups.yaml | ConvertFrom-Yaml

foreach ($group in $groups) {

    # Gathering Existing Group Members
    Write-Host "----------------------------------------`nEvaluating Group: $($group.name)`n----------------------------------------" -ForegroundColor Green
    $existingGroupMembers = Get-GroupMembers -Group $group.name

    # Identify Sync Type
    switch ($group.SyncType) {
        
        # All switch cases should simply return a list of Device Ids in the $targetedDevices variable
        # Group membership evaluation will function the same across any sync type.

        'App' {
            Write-Host "APP SYNC - $($group.name)"
            
            # Determine if specific version is requested
            $appVersionPresent = $group.ContainsKey("version")
            Write-Host "APP VERSION: $appVersionPresent"

            switch ($appVersionPresent) {
                $true {
                    Write-Host "Specific App Version Specified."
                    $apps = $detectedApps | Where-Object { ($_.DisplayName -like "*$($group.application)*") -and ($_.Version -eq "$($group.version)") }
                    Write-Host "$($group.application) $($group.version) - Apps Found: $($apps.count)"

                }
                $false {
                    Write-Host "No App Version Specified"
                    $apps = $detectedApps | Where-Object { $_.DisplayName -like "*$($group.application)*" }
                    Write-Host "$($group.application) - Apps Found: $($apps.count)"
                }
            }
            
            # for each app entity that matches, lets snag all of the device IDs (Converts Intune Id to Azure Device ID)
            # This is dumb, I know, but it is what it is.
            Write-Host "Translating GUIDs, this may take a moment..."
            $targetedDevices = foreach ($app in $apps) {
                $intuneIds = (Get-MgDeviceManagementDetectedAppManagedDevice -DetectedAppId $app.Id).Id
                foreach ($intuneId in $intuneIds) {
                    try {
                        $guildTranslation = (Get-MgDeviceManagementManagedDevice -ManagedDeviceId $intuneId -ErrorAction Stop).AzureAdDeviceId
                    } catch {
                        Write-Host "Failed to find device (Intune Id): $intuneId"
                        continue
                    }
                    (Get-MgDevice -Filter "DeviceId eq '$guildTranslation'").Id
                }
            }
            $targetedDevices = $targetedDevices | Sort-Object -Unique
        } # End App
    }

    # Evaluate Existing Group Membership, determine what PCs we need to add/remove from the group based on our findings
    Write-Host "Beginning group membership evaluation for $($group.name)"

    # If the group is currently empty, lets not worry about comparing groups and just populate it.
    if ($null -eq $existingGroupMembers) {
        Write-Host 'Found the group empty, filling the group.'
        foreach ($device in $targetedDevices) {
            try {
                # Adds Device to the Entra Group
                Write-Host "Adding $device to $($group.name)"
                New-MgGroupMember -GroupId (Get-MgGroup -Filter "DisplayName eq '$($group.name)'").Id -DirectoryObjectId $device -ErrorAction Stop
            }
            catch {
                Write-Host "Failed to add $device to $($group.name)"
                $Error[0]
            }
        }
    }
    
    # Now to compare the existing membership of the group and what we currently found with our target device list.
    else {
        Write-Host "A group compare is necessary, comparing groups."
        $groupCompare = Compare-Object -ReferenceObject $existingGroupMembers -DifferenceObject $targetedDevices -IncludeEqual
        $addCount = ($groupCompare | Where-Object {$_.SideIndicator -eq '=>'}).count
        $removeCount = ($groupCompare | Where-Object {$_.SideIndicator -eq '<='}).count
        
        if ($groupCompare.SideIndicator -contains '=>') {
            Write-Host "Adding $addCount device(s) to $($group.name)"
        }
        if ($groupCompare.SideIndicator -contains '<=') {
            Write-Host "Removing $removeCount device(s) to $($group.name)"
        }
        if (($groupCompare.SideIndicator -notcontains '=>') -and ($groupCompare.SideIndicator -notcontains '<=')) {
            Write-Host "Group Membership is correct. No changes being made."
        }

        foreach ($device in $groupCompare) {
            switch ($device.SideIndicator) {
                '=>' {
                    try {
                        # Adds Device to the Entra Group
                        Write-Host "Adding $($device.InputObject) to $($group.name)"
                        New-MgGroupMember -GroupId (Get-MgGroup -Filter "DisplayName eq '$($group.name)'").Id -DirectoryObjectId $device.InputObject -ErrorAction Stop
                    }
                    catch {
                        Write-Host "Failed to add $($device.InputObject) to $($group.name)"
                        $Error[0]
                    }
                }

                '<=' {
                    try {
                        # Remove Device from Entra Group
                        Write-Host "Removing $($device.InputObject) to $($group.name)"
                        Remove-MgGroupMemberByRef -GroupId (Get-MgGroup -Filter "DisplayName eq '$($group.name)'").Id -DirectoryObjectId $device.InputObject -ErrorAction Stop
                    }
                    catch {
                        Write-Host "Failed to remove $($device.InputObject) to $($group.name)"
                        $Error[0]
                    }
                }
            }
        }
    }
}

Disconnect-MgGraph

### End Main Script ###