# Powershell script to configure vRealize Lifecycle Managerv(vRSLCM), deploy single node vidm
# and optionally deploy vRA, vRLI and vROPS single/simple deployment
# 
# vRSLCM API Browserver - https://code.vmware.com/apis/1161/vrealize-suite-lifecycle-manager
# vRSLCM API Documentation - https://vdc-download.vmware.com/vmwb-repository/dcr-public/9326d555-f77f-456d-8d8a-095aa4976267/c98dabed-ee9a-42ca-87c7-f859698730d1/vRSLCM-REST-Public-API-for-8.4.0.pdf
# JSON specs to deploy vRealize Suite Products using vRealize Suite LifeCycle Manager 8.0 https://kb.vmware.com/s/article/75255 
#
# Henk Engelsman - https://www.vtam.nl
# 21 Oct 2021
# - Use of native json over powershell formatted json
# - Import license from file
# - dns/ntp bugfix
# - renamed some variables
# 27 Oct 2021
# - bugfix Change vCenter Password to use Locker Password
# Import-Module VMware.PowerCLI
# 19 Nov 2021 - Updated for 8.6.1 release
#
# 22 Dec 2021 - Choose wether to deploy vRA or not
# 29 Dec 2021 - Configure vRSLCM. Option to deploy vRA, vRLI and vROPS
#################
### VARIABLES ###
#################
$vrslcmVmname = "bvrslcm"
$domain = "infrajedi.local"
$vrslcmHostname = $vrslcmVmname + "." + $domain #joins vmname and domain to generate fqdn
$vrslcmUsername = "admin@local" #the default admin account for vRSLCM web interface
$vrlscmAdminPassword = "VMware01!" #the NEW admin@local password to set
$vrslcmDefaultAccount = "configadmin"
$vrslcmDefaultAccountPassword = "VMware01!"
$vrslcmAdminEmail = $vrslcmDefaultAccount + "@" + $domain 
$vrslcmDcName = "dc-mgmt" #vRSLCM Datacenter Name
$vrslcmDcLocation = "Rotterdam, South Holland, NL"
$vrslcmProdEnv = "vRealize" #Name of the vRSLCM Environment where vRA is deployed

$dns1 = "192.168.1.204"
$dns2 = "192.168.1.205"
$ntp1 = "192.168.1.1"
$gateway = "192.168.1.1"
$netmask = "255.255.255.0"

$vrealizeLicense = Get-Content "C:\Private\Homelab\Lics\vRealizeS2019Ent-license.txt"
$vrealizeLicenseAlias = "vRealizeSuite2019"

# Set $importCert to $true to import your pre generated certs.
# Configure the paths below to import your existing Certificates
# If $false is selected, a wildcard certificate will be generated in vRSLCM
$importCert = $true
$PublicCertPath = "C:\Private\Homelab\Certs\pub_bvrslcm.cer"
$PrivateCertPath = "C:\Private\Homelab\Certs\priv_bvrslcm.cer"
$CertificateAlias = "vRealizeCertificate"

$vCenterServer = "vcsamgmt.infrajedi.local"
$vcenterUsername = "administrator@vsphere.local"
$vCenterPassword = "VMware01!"

$nfsSourceLocation="192.168.1.10:/data/ISO/vRealize/latest" #NFS location where ova files are stored.
$deployDatastore = "DS01-SSD870-1" #vSphere Datastore to use for deployment
$deployCluster = "dc-mgmt#cls-mgmt" #vSphere Cluster - Notation <datacenter>#<cluster>
$deployNetwork = "VMNet1"
$deployVmFolderName = "vRealize-Beta" #vSphere VM Folder Name

$vidmVmName = "bvidm"
$vidmHostname = $vidmVMName + "." + $domain
$vidmIp = "192.168.1.182"
$vidmVersion = "3.3.5" # for example 3.3.4, 3.3.5
$vidmResize = $true

$deployvRA = $false
$vraVmName = "bvra"
$vraHostname = $vraVMName + "." + $domain
$vraIp = "192.168.1.185"
$vraVersion = "8.6.1" # for example 8.6.0, 8.5.1, 8.5.0, 8.4.2

$deployvRLI = $true
$vrliNFSSourceLocation=$nfsSourceLocation #NFS location where vRLI ova is stored.
$vrliVmName = "bvrli"
$vrliHostname = $vrliVmName + "." + $domain
$vrliIp = "192.168.1.186"
$vrliVersion = "8.6.2"

$deployvROPS = $true
$vropsNFSSourceLocation=$nfsSourceLocation #NFS location where vROPS ova is stored.
$vropsVmName = "bvrops"
$vropsHostname = $vropsVmName + "." + $domain
$vropsIp = "192.168.1.187"
$vropsVersion = "8.6.2"


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

#Change initial / default password after deployment
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $vrslcmUsername,"vmware")))
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')
$header.add("Authorization", "Basic $base64AuthInfo")
$uri =  "https://$vrslcmHostname/lcm/authzn/api/firstboot/updatepassword"
$data=@"
{
    "username" : "$vrslcmUsername",
    "password" : "$vrlscmAdminPassword"
}
"@
Invoke-RestMethod -Uri $uri -Headers $header -Method Put -Body $data

#Login to vRSLCM with new password
#Build Header, including authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $vrslcmUsername,$vrlscmAdminPassword)))
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')
$header.add("Authorization", "Basic $base64AuthInfo")

#Login
$uri = "https://$vrslcmHostname/lcm/authzn/api/login"
Invoke-RestMethod -Uri $uri -Headers $header -Method Post -ErrorAction Stop


##############################################
### Connect to vCenter to get VM Folder Id ###
##############################################
Connect-VIServer $vCenterServer -User $vcenterUsername -Password $vCenterPassword
$vmfolder = Get-Folder -Type VM -Name $deployVmFolderName
#The Id has the notation Folder-group-<groupId>. For the JSON input we need to strip the first 7 characters
$deployVmFolderId = $vmfolder.Id.Substring(7) +"(" + $deployVmFolderName + ")"
#DisConnect-VIServer $vCenterServer -Confirm:$false


##############################
### CREATE LOCKER ACCOUNTS ###
##############################

# Create vCenter account in Locker
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/passwords"
$data=@"
{
    "alias" : "$vCenterServer",
    "password" : "$vCenterPassword",
    "passwordDescription" : "vCenter Admin password",
    "userName" : "$vcenterUsername"
}
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add $data.passwordDescription to Locker" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vc_vmid = $response.vmid
$vcPasswordLockerEntry="locker`:password`:$vc_vmid`:$vCenterServer" #note the escape characters

# Create Default Installation account in Locker
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/passwords"
$data=@"
{
    "alias" : "default",
    "password" : "$vrslcmDefaultAccountPassword",
    "passwordDescription" : "Default Product Password",
    "userName" : "root"
}
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
    $response
} catch {
    write-host "Failed to add $data.passwordEscription to Locker" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$dp_vmid = $response.vmid
$defaultPasswordLockerEntry="locker`:password`:$dp_vmid`:default" ##note the escape characters


#####################################
### Create Datacenter and vCenter ###
#####################################

# Create Datacenter
$dcuri = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters"
$data =@"
{
    "dataCenterName" : "$vrslcmDcName",
    "primaryLocation" : "$vrslcmDcLocation"
}
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $dcuri -Headers $header -Body $data 
    $response
} catch {
    write-host "Failed to create datacenter $data.dataCenterName" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$datacenterRequestId = $response.requestId
$dc_vmid = $response.dataCenterVmid

# Check Datacenter Creation Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$datacenterRequestId"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 180
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 3
    #Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
    Write-Host "Datacenter creation and validation Status" $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to create Datacenter $vrslcmDcName at " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
Write-Host "Datacenter creation and validation Status" $response.state -ForegroundColor Black -BackgroundColor Green

# Create vCenter
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters/$dc_vmid/vcenters"
$data=@"
{
    "vCenterHost" : "$vCenterServer",
    "vCenterName" : "$vCenterServer",
    "vcPassword" : "$vcPasswordLockerEntry",
    "vcUsedAs" : "MANAGEMENT_AND_WORKLOAD",
    "vcUsername" : "$vcenterUsername"
}
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add vCenter $data.vCenterHost" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vCenterRequestId = $response.requestId

# Check vCenter Creation Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$vCenterRequestId"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 180
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 3
    #Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
    Write-Host "vCenter creation and validation Status" $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to add vCenter $vCenterServer at " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
Write-Host "vCenter creation and validation Status" $response.state -ForegroundColor Black -BackgroundColor Green


###############################
### ADD DNS AND NTP SERVERS ###
###############################
# Add NTP Server
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/ntp-servers"
$data = @"
{
    "name" : "ntp01",
    "hostName" : "$ntp1"
}
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add NTP Server $ntp1" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

# Add DNS Server 1
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/dns"
$data = @"
{
    "name" : "dns01",
    "hostName" : "$dns1"
}
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add DNS Server $dns1" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
# Add DNS Server 2
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/dns"
$data = @"
{
    "name" : "dns02",
    "hostName" : "$dns2"
}
"@
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
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/license/validate-and-add"
$data=@"
{
    "alias" : "$vrealizeLicenseAlias",
    "description" : "vRealize Suite 2019 License",
    "serialKey" : "$vrealizeLicense"
}
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to add License $vrealizeLicenseAlias to Locker" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$licenseRequestId = $response.requestId

# Check License Creation Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$licenseRequestId"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$Timeout = 180
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 5
    #Write-Verbose -Message "Still waiting for action to complete after [$totalSecs] seconds..."
    Write-Host "Licence creation and validation Status" $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to add License key $vrealizeLicense at " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
Write-Host "Licence creation and validation Status" $response.state -ForegroundColor Black -BackgroundColor Green

# Get ID of imported License
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/licenses/alias/$vrealizeLicenseAlias"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$licenseId = $response.vmid
$defaultLicenseLockerEntry="locker`:license`:$licenseId`:$vrealizeLicenseAlias" ##note the escape character

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
    $certificateData=@"
    {
        "alias": "$CertificateAlias",
        "certificateChain" : "$FlatPublicCert",
        "passphrase" : "",
        "privateKey" : "$FlatPrivateCert"
    }
"@
    $uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates/import"
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $certificateData
    } catch {
        write-host "Failed to import Certificate $CertificateAlias" -ForegroundColor red
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        break
    }

    # Get ID of imported Certificate
    $uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates?aliasQuery=$CertificateAlias"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $certificateId = $response.certificates.vmid
}
elseif ($importCert -eq $false) {
    #Generate new (wildcard) certificate. Formatted in JSON format
    #prep cert inputs derived from $domain and $vrslcmDcLocation variables
    $certo = $domain.Split(".")[0]
    $certoU = $domain.Split(".")[1]
    $certi = ($vrslcmDcLocation.Split(",")[0]).trim()
    $certst = ($vrslcmDcLocation.Split(",")[1]).trim()
    $certc = ($vrslcmDcLocation.Split(",")[2]).trim()
    $certificateData = @"
    {
        "alias": "$CertificateAlias",
        "cN": "vrealize.$domain",
        "o": "$certo",
        "oU": "$certoU",
        "c": "$certc",
        "sT": "$certst",
        "l": "$certi",
        "size": "2048",
        "validity": "1460",
        "host": [
            "*.$domain"
        ]
    }
"@
    $uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates"
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $certificateData 
    } catch {
        write-host "Failed to create Standard Certificate $CertificateAlias" -ForegroundColor red
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        break
    }
    # Get ID of Generated Certificate
    $uri = "https://$vrslcmHostname/lcm/locker/api/v2/certificates?aliasQuery=$CertificateAlias"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $certificateId = $response.certificates.vmid
    }
$CertificateLockerEntry="locker`:certificate`:$certificateId`:$CertificateAlias" ##note the escape character



#################################################
### CREATE GLOBAL ENVIRONMENT AND DEPLOY VIDM ###
#################################################

#Check if VIDM VM already exist
if (get-vm -Name $vidmVmName -ErrorAction SilentlyContinue){
    Write-Host "Check if VM $vidmVmName exists"
    Write-Host "VM with name $vidmVmName already found. Stopping Deployment" -ForegroundColor White -BackgroundColor Red
    break
} 
# Get all Product Binaries from NFS location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries"
$data=@"
{
  "sourceLocation" : "$nfsSourceLocation",
  "sourceType" : "NFS"
}
"@
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
$response

# Import VIDM ova/binary from NFS location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries/download"
$data = @"
[
    {
        "filePath":  "/data/nfsfiles/vidm.ova",
        "name":  "vidm.ova",
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
Write-Host "Binary Mapping Import Status" $response.state -ForegroundColor Black -BackgroundColor Green


###################
### DEPLOY VIDM ###
###################
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments"
$vidmDeployJSON=@"
{
    "environmentName": "globalenvironment",
    "infrastructure": {
      "properties": {
        "dataCenterVmid": "$dc_vmId",
        "regionName": "default",
        "zoneName": "default",
        "vCenterName": "$vCenterServer",
        "vCenterHost": "$vCenterServer",
        "vcUsername": "$vcenterUsername",
        "vcPassword": "$vcPasswordLockerEntry",
        "acceptEULA": "true",
        "enableTelemetry": "false",
        "adminEmail": "$vrslcmAdminEmail",
        "defaultPassword": "$defaultPasswordLockerEntry",
        "certificate": "$CertificateLockerEntry",
        "cluster": "$deployCluster",
        "storage": "$deployDatastore",
        "folderName": "$deployVmFolderId",
        "resourcePool": "",
        "diskMode": "thin",
        "network": "$deployNetwork",
        "masterVidmEnabled": "false",
        "dns": "$dns1",
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
        "id": "vidm",
        "version": "$vidmVersion",
        "properties": {
          "vidmAdminPassword": "$defaultPasswordLockerEntry",
          "syncGroupMembers": true,
          "defaultConfigurationUsername": "$vrslcmDefaultAccount",
          "defaultConfigurationEmail": "$vrslcmAdminEmail",
          "defaultConfigurationPassword": "$defaultPasswordLockerEntry",
          "certificate": "$CertificateLockerEntry",
          "fipsMode": "false",
          "nodeSize": "medium"
        },
        "clusterVIP": {
          "clusterVips": []
        },
        "nodes": [
          {
            "type": "vidm-primary",
            "properties": {
              "vmName": "$vidmVmName",
              "hostName": "$vidmHostname",
              "ip": "$vidmIp",
              "gateway": "$gateway",
              "domain": "$domain",
              "searchpath": "$domain",
              "dns": "$dns1",
              "netmask": "$netmask",
              "contentLibraryItemId": "",
              "vCenterHost": "$vCenterServer",
              "cluster": "$deployCluster",
              "resourcePool": "",
              "network": "$deployNetwork",
              "storage": "$deployDatastore",
              "diskMode": "thin",
              "vCenterName": "$vCenterServer",
              "vcUsername": "$vcenterUsername",
              "vcPassword": "$vcPasswordLockerEntry"
            }
          }
        ]
      }
    ]
  }
"@
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
Write-Host "VIDM Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green

###########################################
# Downsize VIDM to 2 vCPU | 6 GB          #
# For Testing / Homelab environment only! #
###########################################

if ($vidmResize -eq $true) {
    write-host "VIDM VM will be resized to smallest size. Not supported for production environments"  -ForegroundColor Black -BackgroundColor Yellow
    # Power OFF VIDM via vRSLCM Request
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/globalenvironment/products/vidm/power-off"
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header
    $vidmPowerOffRequestId = $response.requestId
    # Check VIDM Power OFF Request
    $uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$vidmPowerOffRequestId"
    Write-Host "VIDM Power OFF Started at" (get-date -format HH:mm)
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $Timeout = 3600
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
        Start-Sleep -Seconds 60
        Write-Host "VIDM Power OFF Status at " (get-date -format HH:mm) $response.state
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
        if ($response.state -eq "FAILED"){
            Write-Host "FAILED to Power OFF VIDM " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
            Break
        }
    }
    $timer.Stop()
    Write-Host "VIDM Power OFF Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green

    # Resize VIDM
    Set-VM -vm $vidmVmName -MemoryGB 8 -NumCpu 2 -Confirm:$false
    $vidmvm = get-vm -Name $vidmVmName
    Write-Host "VIDM VM Set to " $vidmVm.NumCpu " vCPU and " $vidmVM.MemoryGB " GB Memory" -ForegroundColor Black -BackgroundColor Green

    #Power ON VIDM
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/globalenvironment/products/vidm/power-on"
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header
    $vidmPowerOnRequestId = $response.requestId
    # Check VIDM Power ON Request
    $uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$vidmPowerOnRequestId"
    Write-Host "VIDM Power ON Started at" (get-date -format HH:mm)
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $Timeout = 3600
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
        Start-Sleep -Seconds 60
        Write-Host "VIDM Power ON Status at " (get-date -format HH:mm) $response.state
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
        if ($response.state -eq "FAILED"){
            Write-Host "FAILED to Power ON VIDM " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
            Break
        }
    }
    $timer.Stop()
    Write-Host "VIDM Power ON Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green
}


##################
### DEPLOY VRA ###
##################
if (get-vm -Name $vraVmName -ErrorAction SilentlyContinue) {
    Write-Host "Check if VM $vraVmName exists"
    Write-Host "VM with name $vraVmName already found. Stopping Deployment" -ForegroundColor White -BackgroundColor Red
    break
}

if ($deployvRA -eq $true)
{
Write-Host "Start importing vRA Binaries" -ForegroundColor Black -BackgroundColor Green
# Import vRA binaries from NFS location
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
    write-host "Failed to Download from NFS Repo" -ForegroundColor red
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
Write-Host "Binary Mapping Import Status" $response.state -ForegroundColor Black -BackgroundColor Green

# Start vRA Deployment
Write-Host "Starting vRA Deployment" -ForegroundColor Black -BackgroundColor Green
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments"
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
        "dns": "$dns1",
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
          "certificate": "$CertificateLockerEntry",
          "productPassword": "$defaultPasswordLockerEntry",
          "licenseRef": "$defaultLicenseLockerEntry",
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
Write-Host "vRA Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green
}
else {
    Write-Host "You have selected to not deploy vRA" -ForegroundColor Black -BackgroundColor Yellow
}
# END Deploy vRA


###################
### DEPLOY VRLi ###
###################

if ($deployvRLI -eq $true)
{
Write-Host "Start importing vRLI Binaries" -ForegroundColor Black -BackgroundColor Green
# Retrieve available Product Binaries from vRLI NFS location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries"
$data=@"
{
  "sourceLocation" : "$vRLINFSSourceLocation",
  "sourceType" : "NFS"
}
"@
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data
$vrliova = ($response  | Where-Object {($_.name -like "*Log*") -and ($_.type -eq "install")}).name #Select vRLI OVA Name
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


# Check if Existing vRealize Environment is already created
$uri=""
$response=""
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/$vrslcmProdEnv"
try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
} catch {
    write-host "Environment does not exist." -ForegroundColor Black -BackgroundColor Yellow
    break
}
if ($response -eq ""){
    Write-Host "New environment: " $vrslcmProdEnv " will be created" -ForegroundColor Black -BackgroundColor Yellow
    #$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments" #Create New Environment
} elseif ($response.status -eq "COMPLETED"){
    Write-Host "vRLi will be deployed in existing environment: " $vrslcmProdEnv -ForegroundColor Black -BackgroundColor Green
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/$vrslcmProdEnv/products" #Add to existing Environment
}
Write-Host "Uri is: $uri" -ForegroundColor Black -BackgroundColor Yellow

# Deploy VRLI
Write-Host "Start vRLi Deployment" -ForegroundColor Black -BackgroundColor Green
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
          "nodeSize": "small",
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
          "configureAffinitySeparateAll": "true",
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


### END DEPLOY VRLI
}


######################
# Start Deploy vROPS #
######################
if ($deployvROPS -eq $true)
{

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

# Check if Existing vRealize Environment is already created
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/$vrslcmProdEnv"
try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
} catch {
    write-host "Environment does not exist." -ForegroundColor Black -BackgroundColor Yellow
    break
}
if ($response -eq ""){
    Write-Host "New environment: " $vrslcmProdEnv " will be created" -ForegroundColor Black -BackgroundColor Yellow
    #$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments" #Create New Environment
} elseif ($response.status -eq "COMPLETED"){
    Write-Host "vROPS will be deployed in existing environment: " $vrslcmProdEnv -ForegroundColor Black -BackgroundColor Green
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments/$vrslcmProdEnv/products" #Add to existing Environment
}
Write-Host "Uri is: $uri" -ForegroundColor Black -BackgroundColor Yellow
Write-Host "Starting vROPS Deployment" -ForegroundColor Black -BackgroundColor Green

#Deploy vROPS
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
        "id": "vrops",
        "version": "$vropsVersion",
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
       ],
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
        }
      }
    ]
  }
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $vropsDeployJSON #uri depends on if Environment exists
} catch {
    write-host "Failed to deploy vROPS in $vrslcmProdEnv Environment" -ForegroundColor White -BackgroundColor Red
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
Write-Host "vROPS Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green

### END DEPLOY VROPS
}

#RESET CA
#$uri = "https://$vrslcmHostname/lcm/locker/api/certificates/ca"
#Invoke-RestMethod -Method Patch -Uri $uri -Headers $header

