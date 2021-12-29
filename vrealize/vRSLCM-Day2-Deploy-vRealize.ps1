# Powershell Script to deploy vRealize components after initial vRSLCM and VIDM Deployment
# 
# vRSLCM API Browserver - https://code.vmware.com/apis/1161/vrealize-suite-lifecycle-manager
# vRSLCM API Documentation - https://vdc-download.vmware.com/vmwb-repository/dcr-public/9326d555-f77f-456d-8d8a-095aa4976267/c98dabed-ee9a-42ca-87c7-f859698730d1/vRSLCM-REST-Public-API-for-8.4.0.pdf
# JSON specs to deploy vRealize Suite Products using vRealize Suite LifeCycle Manager 8.0 https://kb.vmware.com/s/article/75255 
#
# Henk Engelsman - https://www.vtam.nl
# 2021/12/29 - Initial version based on other/previous scripts.
#

#################
### VARIABLES ###
#################
$vrslcmVmname = "bvrslcm"
$domain = "infrajedi.local"
$vrslcmHostname = $vrslcmVmname + "." + $domain #joins vmname and domain to generate fqdn
$vrslcmUsername = "admin@local" #the default admin account for vRSLCM web interface
$vrlscmPassword = "VMware01!" #the NEW admin@local password to set
$vrslcmDefaultAccount = "configadmin"
$vrslcmAdminEmail = $vrslcmDefaultAccount + "@" + $domain 
$vrslcmDcName = "dc-mgmt" #vRSLCM Datacenter Name
$vrslcmDcLocation = "Rotterdam, South Holland, NL"
$vrslcmProdEnv = "vRealize" #Name of the vRSLCM Environment where vRA is deployed

$dns1 = "192.168.1.204"
$dns2 = "192.168.1.205"
$ntp1 = "192.168.1.1"
$gateway = "192.168.1.1"
$netmask = "255.255.255.0"

$vrealizeLicenseAlias = "vRealizeSuite2019"

$CertificateAlias = "vRealizeCertificate"
$vCenterServer = "vcsamgmt.infrajedi.local"
$vCenterAccount = "administrator@vsphere.local"
$vCenterPassword = "VMware01!"

$vCenterServer = "vcsamgmt.infrajedi.local"
$vcenterUsername = "administrator@vsphere.local"
$vCenterPassword = "VMware01!"

$nfsSourceLocation="192.168.1.10:/data/ISO/vRealize/latest" #NFS location where vidm.ova and vra.ova are stored.
$deployDatastore = "DS01-SSD870-1" #vSphere Datastore to use for deployment
$deployCluster = "dc-mgmt#cls-mgmt" #vSphere Cluster - Notation <datacenter>#<cluster>
$deployNetwork = "VMNet1"
$deployVmFolderName = "vRealize-Beta" #vSphere VM Folder Name

$deployvRA = $false
$vraNFSSourceLocation="192.168.1.10:/data/ISO/vRealize/latest" #NFS location where vRLI ova is stored.
$vraVmName = "bvra"
$vraHostname = $vraVMName + "." + $domain
$vraIp = "192.168.1.185"
$vraVersion = "8.6.1" # for example 8.4.0, 8.4.1, 8.4.2, 8.5.0, 8.5.1

$deployvRLI = $true
$vrliNFSSourceLocation="192.168.1.10:/data/ISO/vRealize/latest" #NFS location where vRLI ova is stored.
$vrliVmName = "bvrli"
$vrliHostname = $vrliVmName + "." + $domain
$vrliIp = "192.168.1.186"
$vrliVersion = "8.6.1"

$deployvROPS = $true
$vropsNFSSourceLocation="192.168.1.10:/data/ISO/vRealize/latest" #NFS location where vROPS ova is stored.
$vropsVmName = "bvrops"
$vropsHostname = $vropsVmName + "." + $domain
$vropsIp = "192.168.1.187"
$vropsVersion = "8.6.1"


############################################################################
### Login | create authentication header ###
############################################################################

#Login - Build Header, including authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $vrslcmUsername,$vrlscmPassword)))
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')
$header.add("Authorization", "Basic $base64AuthInfo")
$uri = "https://$vrslcmHostname/lcm/authzn/api/login"
Invoke-RestMethod -Uri $uri -Headers $header -Method Post -ErrorAction Stop

# Get Datacenter Id
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$dc_vmid = $response.dataCenterVmid
Write-Host "DataCenter Id (dc_vmid): " $dc_vmid -BackgroundColor Green -ForegroundColor Black

# Get ID of imported License
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/licenses/alias/$vrealizeLicenseAlias"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$licenseId = $response.vmid
$defaultLicenseLockerEntry="locker`:license`:$licenseId`:$vrealizeLicenseAlias" ##note the escape character
Write-Host "vRealize License Locker Entry: " $defaultLicenseLockerEntry -BackgroundColor Green -ForegroundColor Black

# Get ID of Generated Certificate
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates?aliasQuery=$CertificateAlias"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$certificateId = $response.certificates.vmid
$CertificateLockerEntry="locker`:certificate`:$certificateId`:$CertificateAlias" ##note the escape character
Write-Host "vRealize Certificate Locker Entry: " $CertificateLockerEntry -BackgroundColor Green -ForegroundColor Black

# Get Default Installation account from Locker
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/passwords?aliasQuery=default"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$defaultProductPass_vmid = $response.passwords.vmid
$defaultPasswordLockerEntry="locker`:password`:$defaultProductPass_vmid`:default" ##note the escape character
Write-Host "Default Account/Password Locker Entry: " $defaultPasswordLockerEntry -BackgroundColor Green -ForegroundColor Black

# Get vCenter account from Locker
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/passwords?aliasQuery=$vcenterServer"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$vc_vmid = $response.passwords.vmid
$vcPasswordLockerEntry="locker`:password`:$vc_vmid`:$vCenterServer" #note the escape characters
Write-Host "vCenter Account/Password Locker Entry: " $vcPasswordLockerEntry -BackgroundColor Green -ForegroundColor Black

# Connect to vCenter to get VM Folder Id
Connect-VIServer $vCenterServer -User $vCenterAccount -Password $vCenterPassword
$vmfolder = Get-Folder -Type VM -Name $deployVmFolderName
#The Id has the notation Folder-group-<groupId>. For the JSON input we need to strip the first 7 characters
$deployVmFolderId = $vmfolder.Id.Substring(7) +"(" + $deployVmFolderName + ")"
Write-Host "vCenter Deployment Folder id: " $deployVmFolderName -BackgroundColor Green -ForegroundColor Black

###################
### DEPLOY VRLi ###
###################

# Retrieve available Product Binaries from vRLI NFS location
if ($deployvRLI -eq $true){
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries"
$data=@"
{
  "sourceLocation" : "$vRLINFSSourceLocation",
  "sourceType" : "NFS"
}
"@
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
$vrliova = ($response  | Where-Object {($_.name -like "*Log*") -and ($_.type -eq "install")}).name #Select vRLI OVA Name
$vrliova
# Import vRLI Product Binaries from NFS location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries/download"
$data = @"
[
    {
        "filePath":  "/data/nfsfiles/$vrliova",
        "name":  "$vrliova",
        "type":  "install"
    }
]
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to Download from NFS Repo" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$binaryMappingRequestId = $response.requestId

#### Wait until the import has finished ####
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$binaryMappingRequestId"
Write-Host "Binary Mapping Import Started at" (get-date -format HH:mm)
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 3600
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 60
    Write-Host "Binary Mapping Import Status at " (get-date -format HH:mm) $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED import Binaries " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
if ($response.state -eq "COMPLETED"){
    Write-Host "Binary Mapping Import Status" $response.state -ForegroundColor Black -BackgroundColor Green
  }
  else {
    Write-Host "Binary Mapping Import Status" $response.state -ForegroundColor Black -BackgroundColor Red
  }

# DEPLOY VRLI
Write-Host "Starting vRLi Deployment"
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments"
$vrliDeployJSON = @"
{
    "environmentName": "$vrslcmProdEnv",
    "infrastructure": {
      "properties": {
        "dataCenterVmid": "$dc_vmId",
        "regionName":"",
        "zoneName":"",
        "vCenterName": "$vCenterServer",
        "vCenterHost": "$vCenterServer",
        "vcUsername": "$vcenterUsername",
        "vcPassword": "$vcPasswordLockerEntry",
        "acceptEULA": "true",
        "enableTelemetry": "false",
        "defaultPassword": "$defaultPasswordLockerEntry",
        "certificate": "$CertificateLockerEntry",
        "cluster": "$deployCluster",
        "storage": "$deployDatastore",
        "resourcePool": "",
        "diskMode": "thin",
        "network": "$deployNetwork",
        "folderName": "$deployVmFolderId",
        "masterVidmEnabled": "false",
        "dns": "$dns1,$dns2",
        "domain": "$domain",
        "gateway": "$gateway",
        "netmask": "$netmask",
        "searchpath": "$domain",
        "timeSyncMode": "ntp",
        "ntp": "$ntp1",
        "isDhcp": "false"
      }
    },
    "products": [
      {
        "id": "vrli",
        "version": "$vrliVersion",
        "clusterVIP": {
          "clusterVips": []
        },
        "nodes": [
          {
            "type": "vrli-master",
            "properties": {
              "vmName": "$vrliVmName",
              "hostName": "$vrliHostname",
              "ip": "$vrliIp"
            }
          }
       ],
        "properties": {
          "nodeSize": "xsmall",
          "certificate": "$CertificateLockerEntry",
          "productPassword": "$defaultPasswordLockerEntry",
          "adminEmail": "$vrslcmAdminEmail",
          "fipsMode": "false",
          "licenseRef": "$defaultLicenseLockerEntry",
          "configureClusterVIP": "false",
          "affinityRule": "false",
          "isUpgradeVmCompatibility": "true",
          "vrliAlwaysUseEnglish": "true",
          "masterVidmEnabled": "true",
          "configureAffinitySeparateAll": "false",
          "timeSyncMode": "ntp",
          "ntp": "$ntp1"
        }
      }
    ]
  }
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $vrliDeployJSON
} catch {
    write-host "Failed to create $vrslcmProdEnv Environment" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vrliRequestId = $response.requestId

# Check vRLI Deployment Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$vrliRequestId"
Write-Host "vRLI Deployment Started at" (get-date -format HH:mm)
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 7200
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 60
    Write-Host "vRLi Deployment Status at " (get-date -format HH:mm) $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to deploy vRLI " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
if ($response.state -ne "COMPLETED"){
  Write-Host "vRLI Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor White -BackgroundColor Red
}
else {
  Write-Host "vRLI Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green    
}
}




####################
### DEPLOY vROPS ###
####################
if ($deployvRLI -eq $true){
# Retrieve available Product Binaries from vRLI NFS location
Write-Host "Start importing vROPS Binaries" -ForegroundColor Black -BackgroundColor Green
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries"
$data=@"
{
  "sourceLocation" : "$vROPSNFSSourceLocation",
  "sourceType" : "NFS"
}
"@
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data
$vropsova = ($response  | Where-Object {($_.name -like "*Operations*") -and ($_.type -eq "install")}).name #Select vRLI OVA Name

# Import vROPS Product Binaries from NFS location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries/download"
$data = @"
[
    {
        "filePath":  "/data/nfsfiles/$vropsova",
        "name":  "$vropsova",
        "type":  "install"
    }
]
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to Download vROPS from NFS Repo" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$binaryMappingRequestId = $response.requestId

# Wait until the import has finished
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$binaryMappingRequestId"
Write-Host "Binary Mapping Import Started at" (get-date -format HH:mm)
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 3600
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 60
    Write-Host "Binary Mapping Import Status at " (get-date -format HH:mm) $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED import Binaries " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
if ($response.state -eq "COMPLETED"){
    Write-Host "Binary Mapping Import Status" $response.state -ForegroundColor Black -BackgroundColor Green
  }
  else {
    Write-Host "Binary Mapping Import Status" $response.state -ForegroundColor Black -BackgroundColor Red
  }

# Check if Environment with specified name is already created
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/$vrslcmProdEnv"
try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
} catch {
    write-host "Environment does not exist" -ForegroundColor Black -BackgroundColor Yellow
    Write-Host "New environment: " $vrslcmProdEnv " will be created" -ForegroundColor Black -BackgroundColor Green
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments" #Create New Environment
    #Write-Host "Uri is         : " $uri -ForegroundColor Black -BackgroundColor Yellow
    break
}
if ($response.status -eq "COMPLETED"){
  Write-Host "Environment " $vrslcmProdEnv " exists" -ForegroundColor Black -BackgroundColor Green
  Write-Host "vROPS will be deployed in existing environment: " $vrslcmProdEnv -ForegroundColor Black -BackgroundColor Green
  $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/$vrslcmProdEnv/products" #Add to existing Environment
  #Write-Host "Uri is: " $uri -ForegroundColor Black -BackgroundColor Yellow
}

Write-Host "Starting vROPS Deployment" -ForegroundColor Black -BackgroundColor Green

$vropsDeployJSON = @"
{
    "environmentName": "$vrslcmProdEnv",
    "infrastructure": {
      "properties": {
        "dataCenterVmid": "$dc_vmId",
        "regionName":"",
        "zoneName":"",
        "vCenterName": "$vCenterServer",
        "vCenterHost": "$vCenterServer",
        "vcUsername": "$vcenterUsername",
        "vcPassword": "$vcPasswordLockerEntry",
        "acceptEULA": "true",
        "enableTelemetry": "false",
        "defaultPassword": "$defaultPasswordLockerEntry",
        "certificate": "$CertificateLockerEntry",
        "cluster": "$deployCluster",
        "storage": "$deployDatastore",
        "resourcePool": "",
        "diskMode": "thin",
        "network": "$deployNetwork",
        "folderName": "$deployVmFolderId",
        "masterVidmEnabled": "true",
        "dns": "$dns1,$dns2",
        "domain": "$domain",
        "gateway": "$gateway",
        "netmask": "$netmask",
        "searchpath": "$domain",
        "timeSyncMode": "ntp",
        "ntp": "$ntp1",
        "isDhcp": "false"
      }
    },
    "products": [
      {
        "id": "vrops",
        "version": "$vropsVersion",
        "properties": {
          "deployOption": "xsmall",
          "certificate": "$CertificateLockerEntry",
          "productPassword": "$defaultPasswordLockerEntry",
          "adminEmail": "$vrslcmAdminEmail",
          "fipsMode": "false",
          "licenseRef": "$defaultLicenseLockerEntry",
          "configureClusterVIP": "false",
          "masterVidmEnabled": "true",
          "affinityRule": "false",
          "configureAffinitySeparateAll": "false",
          "disableTls": "TLSv1,TLSv1.1",
          "isCaEnabled": "false",
          "timeSyncMode": "ntp",
          "ntp": "$ntp1"
        },
        "clusterVIP": {
          "clusterVips": []
        },
        "nodes": [
          {
            "type": "master",
            "properties": {
              "vmName": "$vropsVmName",
              "hostName": "$vropsHostname",
              "ip": "$vropsIp"
            }
          }
       ]
      }
    ]
  }
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $vropsDeployJSON
} catch {
    write-host "Failed to create $vrslcmProdEnv Environment" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vropsRequestId = $response.requestId

# Check vROPS Deployment Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$vropsRequestId"
Write-Host "vROPS Deployment Started at" (get-date -format HH:mm)
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 7200
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 60
    Write-Host "vROPS Deployment Status at " (get-date -format HH:mm) $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to deploy vROPS " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
if ($response.state -ne "COMPLETED"){
  Write-Host "vROPS Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor White -BackgroundColor Red
}
else {
  Write-Host "vROPS Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green    
}
}


##################
### DEPLOY VRA ###
##################
if ($deployvRA -eq $true){
# Retrieve available Product Binaries from vRA NFS location
Write-Host "Start importing vRA Binaries" -ForegroundColor Black -BackgroundColor Green
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries"
$data=@"
{
  "sourceLocation" : "$vRANFSSourceLocation",
  "sourceType" : "NFS"
}
"@
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data
$vropsova = ($response  | Where-Object {($_.name -like "*Operations*") -and ($_.type -eq "install")}).name #Select vRLI OVA Name

# Import vRA Product Binaries from NFS location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries/download"
$data = @"
[
    {
        "filePath":  "/data/nfsfiles/vra.ova",
        "name":  "vra.ova",
        "type":  "install"
    }
]
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to Download vRA from NFS Repo" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$binaryMappingRequestId = $response.requestId

# Wait until the import has finished
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$binaryMappingRequestId"
Write-Host "Binary Mapping Import Started at" (get-date -format HH:mm)
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 3600
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 60
    Write-Host "Binary Mapping Import Status at " (get-date -format HH:mm) $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED import Binaries " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
if ($response.state -eq "COMPLETED"){
    Write-Host "Binary Mapping Import Status" $response.state -ForegroundColor Black -BackgroundColor Green
  }
  else {
    Write-Host "Binary Mapping Import Status" $response.state -ForegroundColor Black -BackgroundColor Red
  }

# Check if Environment with specified name is already created
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/$vrslcmProdEnv"
try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
} catch {
    write-host "Environment does not exist" -ForegroundColor Black -BackgroundColor Yellow
    Write-Host "New environment: " $vrslcmProdEnv " will be created" -ForegroundColor Black -BackgroundColor Green
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments" #Create New Environment
    #Write-Host "Uri is         : " $uri -ForegroundColor Black -BackgroundColor Yellow
    break
}
if ($response.status -eq "COMPLETED"){
  Write-Host "Environment " $vrslcmProdEnv " exists" -ForegroundColor Black -BackgroundColor Green
  Write-Host "vRA will be deployed in existing environment: " $vrslcmProdEnv -ForegroundColor Black -BackgroundColor Green
  $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/$vrslcmProdEnv/products" #Add to existing Environment
  #Write-Host "Uri is: " $uri -ForegroundColor Black -BackgroundColor Yellow
}

Write-Host "Starting vROPS Deployment" -ForegroundColor Black -BackgroundColor Green

$vraDeployJSON =@"
{
    "environmentName": "$vrslcmProdEnv",
    "infrastructure": {
      "properties": {
        "dataCenterVmid": "$dc_vmId",
        "regionName":"",
        "zoneName":"",
        "vCenterName": "$vCenterServer",
        "vCenterHost": "$vCenterServer",
        "vcUsername": "$vCenterAccount",
        "vcPassword": "$vcPassword",
        "acceptEULA": "true",
        "enableTelemetry": "false",
        "defaultPassword": "$defaultProductPass",
        "certificate": "$defaultCertificate",
        "cluster": "$deployCluster",
        "storage": "$deployDatastore",
        "resourcePool": "",
        "diskMode": "thin",
        "network": "$deployNetwork",
        "folderName": "$deployVmFolderId",
        "masterVidmEnabled": "false",
        "dns": "$dns1,$dns2",
        "domain": "$domain",
        "gateway": "$gateway",
        "netmask": "$netmask",
        "searchpath": "$domain",
        "timeSyncMode": "ntp",
        "ntp": "$ntp1",
        "isDhcp": "false"
      }
    },
    "products": [
      {
        "id": "vra",
        "version": "$vraVersion",
        "properties": {
          "certificate": "$defaultCertificate",
          "productPassword": "$defaultProductPass",
          "licenseRef": "$defaultLicense",
          "nodeSize": "medium",
          "fipsMode": "false",
          "vraK8ServiceCidr": "",
          "vraK8ClusterCidr": "",
          "timeSyncMode": "ntp",
          "ntp": "$ntp1"
        },
        "clusterVIP": {
          "clusterVips": []
        },
        "nodes": [
          {
            "type": "vrava-primary",
            "properties": {
              "vmName": "$vraVmName",
              "hostName": "$vraHostname",
              "ip": "$vraIp"
            }
          }
       ]
      }
    ]
  }
"@
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments"
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $vraDeployJSON
} catch {
    write-host "Failed to create $vrslcmProdEnv Environment" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vraRequestId = $response.requestId

# Check vRA Deployment Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$vraRequestId"
Write-Host "vRA Deployment Started at" (get-date -format HH:mm)
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 7200
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 60
    Write-Host "vRA Deployment Status at " (get-date -format HH:mm) $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to deploy vRA " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
Write-Host "vRA Deployment Status at " (get-date -format HH:mm) $response.state
$timer.Stop()
if ($response.state -ne "COMPLETED"){
  Write-Host "vROPS Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor White -BackgroundColor Red
}
else {
  Write-Host "vROPS Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green    
}
}




# Allow Selfsigned certificates in powershell
Function Unblock-SelfSignedCert() {
if ([System.Net.ServicePointManager]::CertificatePolicy -notlike 'TrustAllCertsPolicy') {
    Add-Type -TypeDefinition @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object -TypeName TrustAllCertsPolicy
    }
}

Unblock-SelfSignedCert #run above function to unblock selfsigned certs

#Use TLS 1.2 for REST calls
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
