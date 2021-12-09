# Sample Script to create Bearer token and build Authentication Header
# Henk Engelsman
# 09 dec 2021
#
# VMware Developer Documentation - APIs
#   https://developer.vmware.com/apis
# vRealize Automation 8.6 API Programming Guide
#   https://developer.vmware.com/docs/14701/GUID-56F0E471-0FD7-4C5C-BB4B-A68E95810645.html
#
#Use TLS 1.2 for REST calls
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
# Check the end of the script to Allow Selfsigned certificates if applicable


#vRA VARIABLES
$vraName = "vra"
$domain = "domain.local"
$vraHostname = $vraname+"."+$domain
$vraUsername = "admin"
$vraPassword = "VMware01!" #note use ` as escape character for special chars like $
$vraUserDomain = "System Domain" #Use "System Domain" for local users", otherwise use the AD domain.


##########################
### Start login to vRA ###
##########################

#Create vRA Auth Header
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')

#Get vRA Refresh Token
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
    $response
} catch {
    write-host "Failed to Connect to host: $vraHostname" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vraRefreshToken = $response.refresh_token

#Get vRA Bearer Token
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
$response.content |Select name, cloudAccountType, id

# REST example to retrieve Projects
$uri = "https://$vraHostname/project-service/api/projects/"
$response = Invoke-RestMethod -Method get -Uri $uri -Headers $header
#Check $response for the full response
$response.content |Select name, id



#################################
# Allow Selfsigned certificates #
#################################

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
Unblock-SelfSignedCert #(uses function above)