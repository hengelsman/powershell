# Sample Script to create Bearer token and build Authentication Header
# Henk Engelsman
# 16 Nov 2023
#
# VMware Developer Documentation - APIs
#   https://developer.vmware.com/apis
# vRealize Automation 8.6 API Programming Guide
#   https://developer.vmware.com/docs/14701/GUID-56F0E471-0FD7-4C5C-BB4B-A68E95810645.html
#
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

# vRA VARIABLES
$vraName = "vra"
$domain = "domain.local"
$vraHostname = $vraname+"."+$domain
$vraUsername = "admin"
$vraPassword = "VMware1!" #note use ` as escape character for special chars like $
$vraUserDomain = "System Domain" #Use "System Domain" for local users", otherwise use the AD domain.


##########################
### Start login to vRA ###
##########################

# Create vRA Auth Header
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')


# Get vRA Refresh Token
$uri = "https://$vraHostname/csp/gateway/am/api/login?access_token"
$data=@"
{
  "username" : "$vraUsername",
  "password" : "$vraPassword",
  "domain" : "$vraUserDomain"
}
"@

try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
} catch {
    write-host "Failed to Connect to host: $vraHostname" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vraRefreshToken = $response.refresh_token


# Get vRA Bearer Token
$data =@{
    refreshToken=$vraRefreshToken
} | ConvertTo-Json
$uri = "https://$vraHostname/iaas/api/login"
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
    $response
} catch {
    write-host "Failed to Connect to host: $vraHostname" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vraBearerToken = $response.token

#Add Bearer Authentication to Header
$header.add("Authorization", "Bearer $vraBearerToken")

##########################
### End login to vRA   ###
##########################


# REST example to retrieve Cloud Accounts
$uri = "https://$vraHostname/iaas/api/cloud-accounts/"
$response = Invoke-RestMethod -Method get -Uri $uri -Headers $header
#Check $response for the full response
$response.content |Select-Object name, cloudAccountType, id

# REST example to retrieve Projects
$uri = "https://$vraHostname/project-service/api/projects/"
$response = Invoke-RestMethod -Method get -Uri $uri -Headers $header
#Check $response for the full response
$response.content |Select-Object name, id