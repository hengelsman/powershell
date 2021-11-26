# Script to Enable custom Names on vRA 8.6.1
# Please be aware this is a beta feature for this release.
# The existing custom naming on project level is removed after enabling.
# This can break your current scripting to setup projects.
# Reachout to VMware Global Support for assistance
#
# Henk Engelsman
# 2021/11/26
#
#
#Allow Selfsigned certificate
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

#Use TLS 1.2 for REST calls
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
#Unblock Selfsigned Certs (uses function and the end)
Unblock-SelfSignedCert

#VARIABLES
$vraName = "vra"
$domain = "infrajedi.local"
$vraHostname = $vraname+"."+$domain
$vraUsername = "configadmin"
$vraPassword = "VMware01!" #note use ` as escape character for special chars like $
$vraUserDomain = "System Domain" #Use "System Domain" for local users", otherwise use the AD domain.

#Create Header
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

###########################
# Enable custom hostnames #
###########################
$uri = "https://$vraHostname/provisioning/config/toggles"
$data = @"
{
    "key": "enable.custom.naming",
    "value": "true"
}
"@
Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data 
