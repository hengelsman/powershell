# Powershell script to install PSPack file for Aria Suite Lifecycle / vRealize Suite Lifecycle Manager / vRSLCM
# 
# Check out the script vRSLCM-Deployment.ps1 for initial deployment and OVA distribution
# Check out the script vRSLCM-Config-Deploy-VIDM-vRA.ps1 for initial deployment, VIDM and vRA Deployment
# vRSLCM API Browserver - https://code.vmware.com/apis/1161/vrealize-suite-lifecycle-manager
# vRSLCM API Documentation - https://vdc-download.vmware.com/vmwb-repository/dcr-public/9326d555-f77f-456d-8d8a-095aa4976267/c98dabed-ee9a-42ca-87c7-f859698730d1/vRSLCM-REST-Public-API-for-8.4.0.pdf
# JSON specs to deploy vRealize Suite Products using vRealize Suite LifeCycle Manager 8.0 https://kb.vmware.com/s/article/75255 
#
# Henk Engelsman - https://www.vtam.nl
# 08 Sept 2023

#################
### VARIABLES ###
#################

#vCenter Variables
$vCenterHostname = "vcsamgmt.infrajedi.local"
$vcenterUsername = "administrator@vsphere.local"
$vCenterPassword = "VMware1!"
$createSnapshot = $true

#vRSLCM Variables
$vrslcmVmname = "vrslcm"
$domain = "infrajedi.local"
$vrslcmHostname = $vrslcmVmname + "." + $domain #joins vmname and domain to generate fqdn
$vrslcmUsername = "admin@local" #the default admin account for vRSLCM web interface
$vrslcmAdminPassword = "VMware01!" #the NEW admin@local password to set
$installPSPack = $false
$pspackfile = "Z:\VMware\Aria\vrlcm-8.14.0-PSPACK3.pspak"


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


# Create Snapshot of vRSLCM VM
Connect-VIServer $vCenterHostname -User $vcenterUsername -Password $vCenterPassword -WarningAction SilentlyContinue
if ($createSnapshot -eq $true){
    Write-Host "Create Snapshot before installing PSPack" -ForegroundColor White -BackgroundColor DarkGreen
    New-Snapshot -VM $vrslcmVmname -Name "vRSLCM Pre PSPack Install Snapshot"
}
Disconnect-VIServer $vCenterHostname -Confirm:$false


#Login to vRSLCM. Build Header, including authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $vrslcmUsername,$vrslcmAdminPassword)))
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')
$header.add("Authorization", "Basic $base64AuthInfo")
$uri = "https://$vrslcmHostname/lcm/authzn/api/login" #Login
Invoke-RestMethod -Uri $uri -Headers $header -Method Post -ErrorAction Stop



#################################
### Import and Install PSPack ###
#################################

#Upload PSPACK##
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
# END Install PSPack