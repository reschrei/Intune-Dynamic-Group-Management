# Intune Device Group Builder
The purpose of this project is to provide an automated way to build device groups in Entra ID / Intune. There is currently limitations on what data can be used to build dynamic device groups within Intune, this project will bridge the gap that the built in web tools.

This tool will both add devices that match the criteria as well as remove them. This way you never have devices sitting in groups that are inaccurate due to stale data, granted you run this script on a regular basis.

This project wasn't created with efficiency in mind, but it does get the job done. There are plans to widen the scope beyond just application installs (Hardware installed, patch level, etc.)

### What data can I build groups off of?
* Applications

If there is interest in building groups from other graph data, please create a Issue. Otherwise you're more than welcome to contribute!

## Prerequisites
* PowerShell Modules
  * [Microsoft Graph](https://www.powershellgallery.com/packages/Microsoft.Graph)
  * [powershell-yaml](https://www.powershellgallery.com/packages/powershell-yaml)
* A dedicated App Registration in your tenant
  * Permissions (Application Based - Grant Consent for your tenant)
    * DeviceManagementConfiguration.Read.All
    * DeviceManagementManagedDevices.Read.All
    * Directory.Read.All
    * GroupMember.ReadWrite.All

## Configuring Group Sync

There are two parts to setting this up.

1. Creating the group in Entra ID
1. Creating an entry in `groups.yaml`

### Create Entra ID Group

This can be done from either https://intune.microsoft.com/ or https://entra.microsoft.com/. 
Navigate to groups and create a new Security Group.

Naming Convention for groups being manged by this tool should be named `Auto - <App Name [version]>` (this naming convention is not required, but may be helpful to easily identify these within your tenant).

### Create `groups.yaml` Entry

The file has a few examples in it already and the top of the file contains information on what is required and optional in each entry.

```powershell
# (Required) name: <Entra Group Name>
# (Required) syncType: App
# (Required) application: <name of application>
# (Optional) version: <specific version number>
```

### Identifying App Names

You can use Microsoft Graph to dump a complete list of all apps that have been detected on our tenant's fleet of devices. You can use this list to figure out the app name and version numbers you would like to sync off of. Here is how you can get this list.

Be sure to install the `Microsoft.Graph` Powershell Module prior to running these commands

```powershell
# Sign in with your Azure Credential
Connect-MgGraph

# Gather a complete list of apps
$detectedApps = Get-MgDeviceManagementDetectedApp -All

# Display the list, feel free to manipulate this data as needed
$detectedApps
```

**NOTE:**
You may run into issues pulling this potentially large set of data down from Graph. Try adjusting your context accordingly. `Set-MgRequestContext -MaxRetry 5 -RetryDelay 10`

For example, you'll see many entries of Google Chrome. You can see the name in the `DisplayName` property and the version in the `Version` property.