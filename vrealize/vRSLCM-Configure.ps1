# Powershell script to configure Aria / vRealize Lifecycle (Manager) - vRSLCM
#
# vRSLCM API Browserver - https://code.vmware.com/apis/1161/vrealize-suite-lifecycle-manager
# vRSLCM API Documentation - https://vdc-download.vmware.com/vmwb-repository/dcr-public/9326d555-f77f-456d-8d8a-095aa4976267/c98dabed-ee9a-42ca-87c7-f859698730d1/vRSLCM-REST-Public-API-for-8.4.0.pdf
# JSON specs to deploy vRealize Suite Products using vRealize Suite LifeCycle Manager 8.0 https://kb.vmware.com/s/article/75255 
# Check out the script vRSLCM-Deployment.ps1 for initial deployment and OVA distribution
# Check out the script vRSLCM-Config-Deploy-VIDM-vRA.ps1 for initial deployment for VIDM and vRA
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
