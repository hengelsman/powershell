##
#
# Sample vROPS API Script
#
# v0.1 | 30 March 2022
# Henk Engelsman

#Variables
$vropshostname = "vrops.infrajedi.local"
$vropsauthsource = "local"
$vropsusername = "admin"
$vropspassword = "VMware2021!"

# Unblock selfsigned Certs
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
Unblock-SelfSignedCert    

#Use TLS 1.2 for REST calls
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;


######################
# Create vROPS Login #
######################
# Create API Header
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')

# Acquire vROPS Token with username/password
$uri = "https://$vropshostname/suite-api/api/auth/token/acquire"
$body=@"
{
    "username" : "$vropsusername",
    "authSource" : "$vropsauthsource",
    "password" : "$vropspassword"
}
"@
try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $body 
} catch {
    write-host "Failed to Connect to host: $vropshostname" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vropstoken = $response.token
#$vropstoken
$header.add("Authorization", "vRealizeOpsToken $vropstoken") #add token to Header - Note this uses vRealizeOpsToken, not Bearer


### Do vROPS API Stuff Here ###



# Terminate vROPS Session
$uri = "https://$vropshostname/suite-api/api/auth/token/release"
Invoke-RestMethod -Method Post -Uri $uri -Headers $header