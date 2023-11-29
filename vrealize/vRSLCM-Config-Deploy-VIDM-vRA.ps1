# Powershell script to configure Aria / vRealize Lifecycle (Manager) - vRSLCM, deploy single node vidm and optionally deploy vRA.
#
# vRSLCM API Browserver - https://code.vmware.com/apis/1161/vrealize-suite-lifecycle-manager
# vRSLCM API Documentation - https://vdc-download.vmware.com/vmwb-repository/dcr-public/9326d555-f77f-456d-8d8a-095aa4976267/c98dabed-ee9a-42ca-87c7-f859698730d1/vRSLCM-REST-Public-API-for-8.4.0.pdf
# JSON specs to deploy vRealize Suite Products using vRealize Suite LifeCycle Manager 8.0 https://kb.vmware.com/s/article/75255 
# Check out the script vRSLCM-Deployment.ps1 for initial deployment and OVA distribution
#
# Henk Engelsman - https://www.vtam.nl
# 29 Nov 2022


#################
### VARIABLES ###
#################
$vrslcmVmname = "vrslcm"
$domain = "domain.local"
$vrslcmHostname = $vrslcmVmname + "." + $domain #joins vmname and domain to generate fqdn
$vrslcmUsername = "admin@local" #the default admin account for vRSLCM web interface
$vrslcmAdminPassword = "VMware01!" #the NEW admin@local password to be set for vRSLCM. default is vmware and needs to be changed at first login
$vrslcmDefaultAccount = "configadmin"
$vrslcmDefaultAccountPassword = "VMware01!" #Password used for the default installation account for products
$vrslcmAdminEmail = $vrslcmDefaultAccount + "@" + $domain 
$vrslcmDcName = "my-vrslcm-dc" #vRSLCM Datacenter Name
$vrslcmDcLocation = "Rotterdam;South Holland;NL;51.9225;4.47917" # You have to put in the coordinates to make this work
$vrslcmProdEnv = "Aria" #Name of the vRSLCM Environment where vRA is deployed
$dns1 = "192.168.1.111"
$dns2 = "192.168.1.112"
$ntp1 = "192.168.1.1"
$gateway = "192.168.1.1"
$netmask = "255.255.255.0"
$installPSPack = $false
$pspackfile = "Z:\VMware\Aria\vrlcm-8.14.0-PSPACK3.pspak"

#Get Licence key from file or manually enter key below
#$vrealizeLicense = "ABCDE-01234-FGHIJ-56789-KLMNO"
$vrealizeLicense = Get-Content "Z:\Lics\vRealizeS2019Ent-license.txt"
$vrealizeLicenseAlias = "vRealizeSuite2019"

# Set $importCert to $true to import your pre generated certs.
# I have used a wildcard cert here, which will be used for VIDM and vRA (not a best practice)
# Configure the paths below to import your existing Certificates
# If $importCert = $false is used, a wildcard certificate will be generated in vRSLCM
$importCert = $true
$replaceLCMCert = $true
$PublicCertPath = "Z:\Certs\vrealize-2026-wildcard.pem"
$PrivateCertPath = "Z:\Certs\vrealize-2026-wildcard-priv.pem"
$CertificateAlias = "vRealizeCertificate"

#vCenter Variables
$vcenterHostname = "vcenter.domain.local"
$vcenterUsername = "administrator@vsphere.local"
$vcenterPassword = "VMware01!"
$deployDatastore = "Datastore01" #vSphere Datastore to use for deployment
$deployCluster = "datacenter#cluster" #vSphere Cluster - Notation <datacenter>#<cluster>. Example dc-mgmt#cls-mgmt
$deployNetwork = "VM Network"
$deployVmFolderName = "Aria" #vSphere VM Folder Name

#OVA Variables
$ovaSourceType = "Local" # Local or NFS
$ovaSourceLocation="/data" #
$ovaFilepath = $ovaSourceLocation
if ($ovaSourceType -eq "NFS"){
    $ovaSourceLocation="192.168.1.2:/ISO/Aria/latest" #NFS location where ova files are stored.
	$ovaFilepath="/data/nfsfiles"
}

#VIDM Variables
$deployVIDM = $true
$vidmVmName = "vidm"
$vidmHostname = $vidmVMName + "." + $domain
$vidmIp = "192.168.1.130"
$vidmVersion = "3.3.7"
$vidmResize = $false #if set to $true, resizes VIDM to 2 vCPU 8GB RAM. Unsupported option for prod. works in lab.

#vRA Variables
$deployvRA = $true
$vraVmName = "vra"
$vraHostname = $vraVMName + "." + $domain
$vraIp = "192.168.1.140"
$vraVersion = "8.14.1"

### END VARIABLES ###


### Start Skip Certificate Checks ###
if ($PSEdition -eq 'Core') {
    $PSDefaultParameterValues.Add("Invoke-RestMethod:SkipCertificateCheck", $true)
}

if ($PSEdition -eq 'Desktop') {
    # Enable communication with self signed certs when using Windows Powershell
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

    if ("TrustAllCertificatePolicy" -as [type]) {} else {
        Add-Type @"
	using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertificatePolicy : ICertificatePolicy {
        public TrustAllCertificatePolicy() {}
		public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate certificate,
            WebRequest wRequest, int certificateProblem) {
            return true;
        }
	}
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertificatePolicy
    }
}
### End Skip Certificate Checks ###


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
    "password" : "$vrslcmAdminPassword"
}
"@
Invoke-RestMethod -Uri $uri -Headers $header -Method Put -Body $data

#Login to vRSLCM with new password. Build Header, including authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $vrslcmUsername,$vrslcmAdminPassword)))
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')
$header.add("Authorization", "Basic $base64AuthInfo")
$uri = "https://$vrslcmHostname/lcm/authzn/api/login" #Login
Invoke-RestMethod -Uri $uri -Headers $header -Method Post -ErrorAction Stop


##############################################
### Connect to vCenter to get VM Folder Id ###
##############################################
Connect-VIServer $vcenterHostname -User $vcenterUsername -Password $vcenterPassword
$vmfolder = Get-Folder -Type VM -Name $deployVmFolderName
#The Id has the notation Folder-group-<groupId>. For the JSON input we need to strip the first 7 characters
$deployVmFolderId = $vmfolder.Id.Substring(7) +"(" + $deployVmFolderName + ")"


##############################
### CREATE LOCKER ACCOUNTS ###
##############################

# Create vCenter account in Locker
$uri = "https://$vrslcmHostname/lcm/locker/api/v2/passwords"
$data=@"
{
    "alias" : "$vcenterHostname",
    "password" : "$vcenterPassword",
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
$vcPasswordLockerEntry="locker`:password`:$vc_vmid`:$vcenterHostname" #note the escape characters

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
    "vCenterHost" : "$vcenterHostname",
    "vCenterName" : "$vcenterHostname",
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
$response =""
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
        Write-Host "FAILED to add vCenter $vcenterHostname at " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
Write-Host "vCenter creation and validation Status" $response.state -ForegroundColor Black -BackgroundColor Green


###############################
### ADD DNS AND NTP SERVERS ###
###############################
# Add NTP Server
$response =""
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
$response =""
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
$response =""
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
$response =""
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
# Import existing certificate if $importCert is set to $true
# Note the public certificate should have the complete certificate chain.
if ($importCert -eq $true){
    $PublicCert = get-content $PublicCertPath
    $PrivateCert = get-content $PrivateCertPath
    #join al lines together with \n in between and end with \n
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
    $response =""
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
    $certi = ($vrslcmDcLocation.Split(";")[0]).trim()
    $certst = ($vrslcmDcLocation.Split(";")[1]).trim()
    $certc = ($vrslcmDcLocation.Split(";")[2]).trim()
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


################################################
### Replace Aria Suite Lifecycle Certificate ###
################################################

if ($replaceLCMCert -eq $true){
    $uri = "https://$vrslcmHostname/lcm/lcops/api/environments/lcm/products/lcm/updatecertificate"
    $body = @"
{
    "certificateVmId":"$certificateId",
    "components":[]
}
"@
    try {
        $replaceLCMCertResponse = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $body
    } catch {
        write-host "Failed to replace Certificate for $CertificateAlias" -ForegroundColor red
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        break
    }  
    $replaceLCMCertRequestid = $replaceLCMCertResponse.requestId

    # Check Certificate Replacement Progress
    $uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$replaceLCMCertRequestid"
    Write-Host "Certificate Replacement Started at" (get-date -format HH:mm)
    #Write-Host "This will cause restart of Services"
    $response=""
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $Timeout = 900
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
        Start-Sleep -Seconds 60
        Write-Host "Certificate Replacement Status at " (get-date -format HH:mm) $response.state
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
        if ($response.state -eq "FAILED"){
            Write-Host "FAILED Certificate Replacement " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
            Break
        }
    }
    $timer.Stop()
    Write-Host "Certificate Replacement " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green
    }


#################################
### Import and Install PSPack ###
#################################

#Upload PSPACK##
if ($installPSPack -eq $true) {
    $form = @{
    file = get-item -path $pspackfile}
    $response =""
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/system-pspack/import"
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Form $form
    $pspackRequestId = $response.requestId

    # Check PSPACK UploadRequest
    $uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$pspackRequestId"
    $response =""
    Write-Host "PSPack Upload Started at" (get-date -format HH:mm)
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $Timeout = 900
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
        Start-Sleep -Seconds 60
        Write-Host "PSPack Upload Status at " (get-date -format HH:mm) $response.state
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
        if ($response.state -eq "FAILED"){
            Write-Host "FAILED to Upload PSPack " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
            Break
        }
    }
    $timer.Stop()
    Write-Host "PSPPack Upload" (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green

    # GET PSPack to retrieve PSPackId
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/system-pspack"
    $pspackIdResponse = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $pspackId = $pspackIdResponse.pspackId

    # Install PSPack
    $uri = "https://$vrslcmHostname/lcm/lcops/api/v2/system-pspack/$pspackId"
    $pspackInstallResponse = Invoke-RestMethod -Method Post -Uri $uri -Headers $header
    $pspackInstallResponse
    $pspackInstallRequestId = $pspackInstallResponse.requestId

    # Check PSPACK Install Progress
    $uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$pspackInstallRequestId"
    Write-Host "PSPack Install Started at" (get-date -format HH:mm)
    Write-Host "This will cause restart of Services"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
    $Timeout = 900
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
        Start-Sleep -Seconds 60
        Write-Host "PSPack Install Status at " (get-date -format HH:mm) $response.state
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
        if ($response.state -eq "FAILED"){
            Write-Host "FAILED to Install PSPack " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
            Break
        }
    }
    $timer.Stop()
    Write-Host "PSPPack Install" (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green
    }
# END Install PSPack


#################################################
### CREATE GLOBAL ENVIRONMENT AND DEPLOY VIDM ###
#################################################

if ($deployVIDM -eq $true){

Write-Host "VIDM Binaries will be imported from $OVASourceType" -ForegroundColor Black -BackgroundColor Green

# Get all Product Binaries from Source Location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries"
$data=@"
{
  "sourceLocation" : "$OVASourceLocation",
  "sourceType" : "$OVASourceType"
}
"@
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data
$response

# Import VIDM Product Binaries from Source location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries/download"
$data = @"
[
    {
        "filePath": "$ovaFilepath/vidm.ova",
        "name": "vidm.ova",
        "type": "install"
    }
]
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to import Binaries from $ovaSourceType" -ForegroundColor red
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
        "vCenterName": "$vcenterHostname",
        "vCenterHost": "$vcenterHostname",
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
              "vCenterHost": "$vcenterHostname",
              "cluster": "$deployCluster",
              "resourcePool": "",
              "network": "$deployNetwork",
              "storage": "$deployDatastore",
              "diskMode": "thin",
              "vCenterName": "$vcenterHostname",
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
}



##################
### DEPLOY VRA ###
##################
if ($deployvRA -eq $true)
{
Write-Host "Start importing vRA Binaries" -ForegroundColor Black -BackgroundColor Green
# Import vRA binaries from NFS location
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/product-binaries/download"
$data = @"
[
    {
        "filePath": "$ovaFilepath/vra.ova",
        "name": "vra.ova",
        "type": "install"
    }
]
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to Import OVA file from $ovaSourceType" -ForegroundColor red
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
        "vCenterName": "$vcenterHostname",
        "vCenterHost": "$vcenterHostname",
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
else {
    Write-Host "You have selected to not resize VIDM" -ForegroundColor Black -BackgroundColor Yellow
}


DisConnect-VIServer $vcenterHostname -Confirm:$false