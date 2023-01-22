##
#
# Sample vROPS API Script
#
# v0.1 | 30 March 2022
# Henk Engelsman

#Variables
$domain = "infrajedi.local"
$vropshostname = "vrops"+"." + $domain

# Use Local Auth Source
$vropsauthsource = "local"
$vropsusername = "admin"
$vropspassword = "VMware01!"

# Use VIDM Auth Source
# Note: The body to require a token is different and does not need "authSource"
$vropsauthsource = "VIDMAuthSource"
$vropsusername = "henk" + "@$domain" +"@$vropsauthsource"  #henk@infrajedi.local@VIDMAuthSource
$vropspassword = "Dali`$005" #note: Special characters must be escaped with `


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
# Note: Remove the line "authSource"
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


##########################
# Supermetrics API Calls #
##########################

# Get All SuperMetrics
$uri = "https://$vropshostname/suite-api/api/supermetrics"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.superMetrics |Select name,id

# Get Supermetric by name
$uri = "https://$vropshostname/suite-api/api/supermetrics?name=henkTestSuperMetric"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$supermetricId = $response.superMetrics.id

#Delete Supermetric by iD
$uri = "https://$vropshostname/suite-api/api/supermetrics/$supermetricId"
$response = Invoke-RestMethod -Method Delete -Uri $uri -Headers $header
$response


#############
#  Alerts   #
#############

# Get All Alerts example
$uri = "https://$vropshostname/suite-api/api/alerts"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$activeAlerts = $response.alerts |Select alertId,controlState, alertLevel, status |Where {$_.status -eq "ACTIVE"}
$criticalAlerts = $activeAlerts |Where {$_.alertLevel -eq "CRITICAL"}
Write-host "There are" $activeAlerts.Count "Active Alerts, with" $criticalAlerts.Count "Criticals" 




#Terminate vROPS Session
$uri = "https://$vropshostname/suite-api/api/auth/token/release"
Invoke-RestMethod -Method Post -Uri $uri -Headers $header