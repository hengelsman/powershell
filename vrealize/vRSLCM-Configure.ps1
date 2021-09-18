# Powershell script to configure vRealize Lifecycle Managerv(vRSLCM), deploy single node vidm and vRealize Automation (vRA)
# 
# vRSLCM API Browserver - https://code.vmware.com/apis/1161/vrealize-suite-lifecycle-manager
# vRSLCM API Documentation - https://vdc-download.vmware.com/vmwb-repository/dcr-public/9326d555-f77f-456d-8d8a-095aa4976267/c98dabed-ee9a-42ca-87c7-f859698730d1/vRSLCM-REST-Public-API-for-8.4.0.pdf
# JSON specs to deploy vRealize Suite Products using vRealize Suite LifeCycle Manager 8.0 https://kb.vmware.com/s/article/75255 
#
# Henk Engelsman - https://www.vtam.nl
# 18 Sept 2021
#
# Import-Module VMware.PowerCLI

#################
### VARIABLES ###
#################
$vrslcmVmname = "bvrslcm"
$domain = "infrajedi.local"
$vrslcmHostname = $vrslcmVmname + "." + $domain #joins vmname and domain to generate fqdn
$vrslcmUser = "admin@local" #the default admin account for vRSLCM web interface
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

$vrealizeLicense ="LICENSEKEY"
$vrealizeLicenseAlias = "vRealizeSuite2019"
$defaultProductPassword = "VMware01!"

$importCert = $false #Set to $true and configure the paths below to import your existing Certificates
$PublicCertPath = "C:\Private\Homelab\Certs\pub_bvrslcm.cer"
$PrivateCertPath = "C:\Private\Homelab\Certs\priv_bvrslcm.cer"

$vCenterServer = "vcsamgmt.infrajedi.local"
$vCenterAccount = "administrator@vsphere.local"
$vCenterPassword = "VMware01!"

$nfsSourceLocation="192.168.1.10:/data/ISO/vRealize/vRA8/latest" #NFS location where vidm.ova and vra.ova are stored.
$deployDatastore = "DS01-SSD870-1" #vSphere Datastore to use for deployment
$deployCluster = "dc-mgmt#cls-mgmt" #vSphere Cluster - Notation <datacenter>#<cluster>
$deployNetwork = "VMNet1"
$deployVmFolderName = "vRealize-Beta" #vSphere VM Folder Name

$vidmVmName = "bvidm"
$vidmHostname = $vidmVMName + "." + $domain
$vidmIp = "192.168.1.182"
$vidmVersion = "3.3.5" # for example 3.3.4, 3.3.5

$vraVmName = "bvra"
$vraHostname = $vraVMName + "." + $domain
$vraIp = "192.168.1.185"
$vraVersion = "8.5.1" # for example 8.4.0, 8.4.1, 8.4.2, 8.5.0, 8.5.1


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


############################################################################
### Change intial vRSLCM admin password and create authentication header ###
############################################################################

#Change initial / default password
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $vrslcmUser,"vmware")))
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')
$header.add("Authorization", "Basic $base64AuthInfo")
$data=@{
    "username" = "$vrslcmUser"
    "password" = "$vrlscmPassword"
}| ConvertTo-Json

$uri =  "https://$vrslcmHostname/lcm/authzn/api/firstboot/updatepassword"
Invoke-RestMethod -Uri $uri -Headers $header -Method Put -Body $data

#Create new Login
#Build Header, including authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $vrslcmUser,$vrlscmPassword)))
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')
$header.add("Authorization", "Basic $base64AuthInfo")

#Test Login
$uri = "https://$vrslcmHostname/lcm/authzn/api/login"
Invoke-RestMethod -Uri $uri -Headers $header -Method Post -ErrorAction Stop


##############################################
### Connect to vCenter to get VM Folder Id ###
##############################################
Connect-VIServer $vCenterServer -User $vCenterAccount -Password $vCenterPassword
$vmfolder = Get-Folder -Type VM -Name $deployVmFolderName
#The Id has the notation Folder-group-<groupId>. For the JSON input we need to strip the first 7 characters
$deployVmFolderId = $vmfolder.Id.Substring(7) +"(" + $deployVmFolderName + ")"

#Check if VIDM and VRA VMs already exist
if (get-vm -Name $vidmVmName -ErrorAction SilentlyContinue){
    Write-Host "Check if VM $vidmVmName exists"
    Write-Host "VM with name $vidmVmName already found. Stopping Deployment" -ForegroundColor White -BackgroundColor Red
    break
} elseif (get-vm -Name $vraVmName -ErrorAction SilentlyContinue) {
    Write-Host "Check if VM $vraVmName exists"
    Write-Host "VM with name $vraVmName already found. Stopping Deployment" -ForegroundColor White -BackgroundColor Red
    break
} else {
    Write-Host "VMs with names $vidmVmName and $vraVmName not found, Deployment will continue..." -ForegroundColor White -BackgroundColor DarkGreen
}
DisConnect-VIServer $vCenterServer -Confirm:$false


##############################
### CREATE LOCKER ACCOUNTS ###
##############################

# Create vCenter account in Locker
$data=@{
    alias="$vCenterServer"
    password="$vCenterPassword"
    passwordDescription="vCenter vcsamgmt admin password"
    userName="$vCenterAccount"
  }| ConvertTo-Json
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/passwords"
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
    $response
} catch {
    write-host "Failed to add $data.passwordDescription to Locker" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vc_vmid = $response.vmid
$vc_alias = $response.alias
$vc_username = $response.userName
$vcPassword="locker`:password`:$vc_vmid`:$vc_alias" #note the escape character


# Create Default Installation account in Locker
$data=@{
    alias="default"
    password="$defaultProductPassword"
    passwordDescription="Default Product Password"
    userName="root"
  } | ConvertTo-Json
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/passwords"
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
    $response
} catch {
    write-host "Failed to add $data.passwordEscription to Locker" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$defaultProductPass_vmid = $response.vmid
$defaultProductPass="locker`:password`:$defaultProductPass_vmid`:default" ##note the escape character
#$defaultProductPass_alias = $response.alias
#$defaultProductPass_username = $response.userName


#####################################
### Create Datacenter and vCenter ###
#####################################

# Create Datacenter
$dcuri = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters"
$data =@{
    dataCenterName="$vrslcmDcName"
    primaryLocation="$vrslcmDcLocation"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Method Post -Uri $dcuri -Headers $header -Body $data 
    $response
} catch {
    write-host "Failed to create datacenter $data.dataCenterName" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$dc_vmid = $response.dataCenterVmid


# Create vCenter
$data=@{
    vCenterHost="$vCenterServer"
    vCenterName="$vCenterServer"
    vcPassword="locker`:password`:$vc_vmid`:$vc_alias" #note the escape characters
    vcUsedAs="MANAGEMENT_AND_WORKLOAD"
    vcUsername="$vc_username"
  } | ConvertTo-Json
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters/$dc_vmid/vcenters"

try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Het is niet gelukt om vcenter $data.vCenterHost" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

###############################
### ADD DNS AND NTP SERVERS ###
###############################

# Add NTP Server
$data = @(
    @{
        name="ntp01"
        hostName=$ntp1
    }
) | ConvertTo-Json
$ntpuri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/ntp-servers"
try {
    $response = Invoke-RestMethod -Method Post -Uri $ntpuri -Headers $header -Body $data 
} catch {
    write-host "Failed to add NTP Server $ntp1" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

# Add DNS Server 1
$data = @(
    @{
        name="dns01"
        hostName=$dns1
    }
) | ConvertTo-Json
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/dns"
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add DNS Server $dns1" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

# Add DNS Server 2
$data = @(
    @{
        name="dns02";
        hostName=$dns2
    }
) | ConvertTo-Json
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/dns"

try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add DNS Server $dns2" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}


##################################
### Add vRealize Suite License ###
##################################
$data=@{
    alias="$vrealizeLicenseAlias"
    description="vRealize Suite 2019 License"
    serialKey="$vrealizeLicense"
  } | ConvertTo-Json
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/license/validate-and-add"
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add License $data.alias to Locker" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

$licenseRequestId = $response.requestId
# $licenseId = $response.vmid #This is not the licenseId required for JSON Input

# Check License Creation Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$licenseRequestId"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 60
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 1
    #Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
    Write-Host "Licence creation and validation Status" $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to add License key " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
Write-Host "Licence creation and validation Status" $response.state

# Get ID of imported License
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/licenses/alias/$vrealizeLicenseAlias"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$licenseId = $response.vmid


#######################################################
### Import existing certificate or generate new one ###
#######################################################

# Import existing certificate if selected
# Note the public certificate should have the complete chain.
# All lines have to be joined together with \n in between and should end on \n
# Rest of the body is Formatted in JSON format
if ($importCert -eq $true){
    $PublicCert = get-content $PublicCertPath
    $PrivateCert = get-content $PrivateCertPath
    $FlatPrivateCert = ([string]::join("\n",($PrivateCert.Split("`n")))) + "\n"
    $FlatPublicCert = ([string]::join("\n",($PublicCert.Split("`n")))) + "\n"
    $certificateData = "{
    `"alias`": `"vRealizeWildcard`",
    `"certificateChain`": `"$FlatPublicCert`",
    `"passphrase`": `"`",
    `"privateKey`": `"$FlatPrivateCert`"
    }"
    $uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates/import"
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $certificateData
    } catch {
        write-host "Failed to import Certificate" -ForegroundColor red
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        break
    }

    # Get ID of imported Certificate
    $uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates?aliasQuery=vRealizeWildcard"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $certificateId = $response.certificates.vmid
} elseif ($importCert -eq $false) {
    #Generate new (wildcard) certificate. Formatted in JSON format
    $certificateData = "{
        `"alias`": `"standardCertificate`",
        `"cN`": `"vrealize.infrajedi.local`",
        `"o`": `"infrajedi`",
        `"oU`": `"local`",
        `"c`": `"NL`",
        `"sT`": `"ZH`",
        `"l`": `"Rotterdam`",
        `"size`": `"2048`",
        `"validity`": `"1460`",
        `"host`": [
            `"*.infrajedi.local`"
            ]
    }"
    $uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates"
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $certificateData 
    } catch {
        write-host "Failed to create Standard Certificate" -ForegroundColor red
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        break
    }
    # Get ID of Generated Certificate
    $uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates?aliasQuery=standardCertificate"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $certificateId = $response.certificates.vmid
}

#############################
### BINARY SOURCE MAPPING ###
#############################

# Get all Product Binaries from NFS location
$data=@{
    sourceLocation="$nfsSourceLocation"
    sourceType="NFS"
  } | ConvertTo-Json
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries"
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add NFS Repository $nfsSourceLocation" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

#To Do: Check if files exist or error out before starting import Request.

# Import VIDM and vRA binaries from NFS location
$data = @(
    @{
        filePath="/data/nfsfiles/vidm.ova"
        name="vidm.ova"
        type="install"
    },
    @{
        filePath="/data/nfsfiles/vra.ova"
        name="vra.ova"
        type="install"
    }
) | ConvertTo-Json
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries/download"
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
Write-Host "Binary Mapping Import Status" $response.state



#################################################
### CREATE GLOBAL ENVIRONMENT AND DEPLOY VIDM ###
#################################################

###################
### DEPLOY VIDM ###
###################
$vidmDeployJSON = "{
    `"environmentName`": `"globalenvironment`",
    `"infrastructure`": {
      `"properties`": {
        `"dataCenterVmid`": `"$dc_vmId`",
        `"regionName`": `"default`",
        `"zoneName`": `"default`",
        `"vCenterName`": `"$vCenterServer`",
        `"vCenterHost`": `"$vCenterServer`",
        `"vcUsername`": `"$vCenterAccount`",
        `"vcPassword`": `"$vcPassword`",
        `"acceptEULA`": `"true`",
        `"enableTelemetry`": `"false`",
        `"adminEmail`": `"$vrslcmAdminEmail`",
        `"defaultPassword`": `"$defaultProductPass`",
        `"certificate`": `"locker`:certificate`:$certificateId`:vRealizeWildcard`",
        `"cluster`": `"$deployCluster`",
        `"storage`": `"$deployDatastore`",
        `"folderName`": `"$deployVmFolderId`",
        `"resourcePool`": `"`",
        `"diskMode`": `"thin`",
        `"network`": `"VMNet1`",
        `"masterVidmEnabled`": `"false`",
        `"dns`": `"$ntp1`",
        `"domain`": `"$domain`",
        `"gateway`": `"$gateway`",
        `"netmask`": `"$netmask`",
        `"searchpath`": `"$domain`",
        `"timeSyncMode`": `"ntp`",
        `"ntp`": `"$ntp1`",
        `"isDhcp`": `"false`"
      }
    },
    `"products`": [
      {
        `"id`": `"vidm`",
        `"version`": `"$vidmVersion`",
        `"properties`": {
          `"vidmAdminPassword`": `"$defaultProductPass`",
          `"syncGroupMembers`": true,
          `"defaultConfigurationUsername`": `"$vrslcmDefaultAccount`",
          `"defaultConfigurationEmail`": `"$vrslcmAdminEmail`",
          `"defaultConfigurationPassword`": `"$defaultProductPass`",
          `"certificate`": `"locker`:certificate`:$certificateId`:vRealizeWildcard`",
          `"fipsMode`": `"false`",
          `"nodeSize`": `"medium`"
        },
        `"clusterVIP`": {
          `"clusterVips`": []
        },
        `"nodes`": [
          {
            `"type`": `"vidm-primary`",
            `"properties`": {
              `"vmName`": `"$vidmVmName`",
              `"hostName`": `"$vidmHostname`",
              `"ip`": `"$vidmIp`",
              `"gateway`": `"$gateway`",
              `"domain`": `"$domain`",
              `"searchpath`": `"$domain`",
              `"dns`": `"$dns1`",
              `"netmask`": `"$netmask`",
              `"contentLibraryItemId`": `"`",
              `"vCenterHost`": `"$vCenterServer`",
              `"cluster`": `"$deployCluster`",
              `"resourcePool`": `"`",
              `"network`": `"$deployNetwork`",
              `"storage`": `"$deployDatastore`",
              `"diskMode`": `"thin`",
              `"vCenterName`": `"$vCenterServer`",
              `"vcUsername`": `"$vCenterAccount`",
              `"vcPassword`": `"$vcPassword`"
            }
          }
        ]
      }
    ]
  }"
 $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments"
 try {
     $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $vidmDeployJSON
 } catch {
     write-host "Failed to create Global Environment" -ForegroundColor red
     Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
     Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
     break
 }
$vidmRequestId = $response.requestId


# Check VIDM Deployment Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$vidmRequestId"
Write-Host "VIDM Deployment Started at" (get-date -format HH:mm)
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 3600
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 60
    Write-Host "VIDM Deployment Status at " (get-date -format HH:mm) $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to Deploy VIDM " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
Write-Host "VIDM Deployment Status at " (get-date -format HH:mm) $response.state


##################
### DEPLOY VRA ###
##################
Write-Host "Starting vRA Deployment"
$vraDeployJSON ="{
    `"environmentName`": `"$vrslcmProdEnv`",
    `"infrastructure`": {
      `"properties`": {
        `"dataCenterVmid`": `"$dc_vmId`",
        `"regionName`":`"`",
        `"zoneName`":`"`",
        `"vCenterName`": `"$vCenterServer`",
        `"vCenterHost`": `"$vCenterServer`",
        `"vcUsername`": `"$vCenterAccount`",
        `"vcPassword`": `"$vcPassword`",
        `"acceptEULA`": `"true`",
        `"enableTelemetry`": `"false`",
        `"defaultPassword`": `"$defaultProductPass`",
        `"certificate`": `"locker`:certificate`:$certificateId`:vRealizeWildcard`",
        `"cluster`": `"$deployCluster`",
        `"storage`": `"$deployDatastore`",
        `"resourcePool`": `"`",
        `"diskMode`": `"thin`",
        `"network`": `"$deployNetwork`",
        `"folderName`": `"$deployVmFolderId`",
        `"masterVidmEnabled`": `"false`",
        `"dns`": `"$dns1`",
        `"domain`": `"$domain`",
        `"gateway`": `"$gateway`",
        `"netmask`": `"$netmask`",
        `"searchpath`": `"$domain`",
        `"timeSyncMode`": `"ntp`",
        `"ntp`": `"$ntp1`",
        `"isDhcp`": `"false`"
      }
    },
    `"products`": [
      {
        `"id`": `"vra`",
        `"version`": `"$vraVersion`",
        `"properties`": {
          `"certificate`": `"locker`:certificate`:$certificateId`:vRealizeWildcard`",
          `"productPassword`": `"$defaultProductPass`",
          `"licenseRef`": `"locker`:license`:$licenseId`:vRealizeSuite2019`",
          `"nodeSize`": `"medium`",
          `"fipsMode`": `"false`",
          `"vraK8ServiceCidr`": `"`",
          `"vraK8ClusterCidr`": `"`",
          `"timeSyncMode`": `"ntp`",
          `"ntp`": `"$ntp1`"
        },
        `"clusterVIP`": {
          `"clusterVips`": []
        },
        `"nodes`": [
          {
            `"type`": `"vrava-primary`",
            `"properties`": {
              `"vmName`": `"$vraVmName`",
              `"hostName`": `"$vraHostname`",
              `"ip`": `"$vraIp`"
            }
          }
       ]
      }
    ]
  }"
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
