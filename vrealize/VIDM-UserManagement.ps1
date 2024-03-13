# PoSh script to check/add/configure VIDM account in local System Directory
# v0.3 - Henk Engelsman
# VMware Identity Manager (VIDM) API: https://developer.vmware.com/apis/57/

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


#VARIABLES
$vidmHostname = "vidm.infrajedi.local"
$vidmAdminUsername = "admin"
$vidmAdminPassword = "VMware01!"

#Create Initial Header to request Session Token
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type",	'application/json')
$authBody = @"
{
    "username": "$vidmAdminUsername",
    "password": "$vidmAdminPassword",
    "issueToken": "true"
}
"@

#Request Session Token
$uri = "https://$vidmHostname/SAAS/API/1.0/REST/auth/system/login"
$authResponse = Invoke-RestMethod -Uri $uri -Headers $header -Method Post -Body $authBody
$vidmSessionToken = $authResponse.sessionToken

#Add SessionToken to Header
$header.add("Authorization", "HZN $vidmSessionToken")



##### Do Stuff below #####



#####################################################
# Create New User with password in System Directory #
# Simple Example                                    #
#####################################################
$newVidmUser = "vratest01"
$newVidmPassword = "VMware01!"
$newVidmEmail = "vratest01@infrajedi.local"
$body = @"
{
    "name": {
        "givenName": "vra",
        "familyName": "test"
    },
    "userName": "$newVidmUser",
    "password": "$newVidmPassword",
    "emails": [
        {
            "value": "$newVidmEmail"
        }
    ]
}
"@
$uri =  "https://$vidmHostname/SAAS/jersey/manager/api/scim/Users"
$createUserResponse = Invoke-RestMethod -Uri $uri -Headers $header -Method Post -Body $body
$vidmUserId = $createUserResponse.id


#####################################################
# Create New User with password in System Directory #
# Extended Example                                  #
#####################################################
$newVidmUser = "vratest02"
$newVidmPassword = "VMware01!"
$newVidmEmail = "vratest02@infrajedi.local"
$body = @"
{
    "urn:scim:schemas:extension:workspace:1.0": {
        "domain": "System Domain"
    },
    "urn:scim:schemas:extension:enterprise:1.0": {},
    "schemas": [
        "urn:scim:schemas:extension:workspace:mfa:1.0",
        "urn:scim:schemas:extension:workspace:1.0",
        "urn:scim:schemas:extension:enterprise:1.0",
        "urn:scim:schemas:core:1.0"
    ],
    "name": {
        "givenName": "vra",
        "familyName": "test"
    },
    "userName": "$newVidmUser",
    "password": "$newVidmPassword",
    "emails": [
        {
            "value": "$newVidmEmail"
        }
    ]
}
"@
$uri =  "https://$vidmHostname/SAAS/jersey/manager/api/scim/Users"
$createUserResponse = Invoke-RestMethod -Uri $uri -Headers $header -Method Post -Body $body
$vidmUserId = $createUserResponse.id


##########################
# Reset Password of user #
##########################
    #First Get specific User
    $vidmUsername = "vratest03"
    $uri =  "https://$vidmHostname/SAAS/jersey/manager/api/scim/Users?filter=username%20eq%20%22$vidmusername%22"
    $userResponse = Invoke-RestMethod -Uri $uri -Headers $header -Method Get
    $vidmUserId = $userResponse.Resources.id

#Set Password
$uri = "https://$vidmHostname/SAAS/jersey/manager/api/scim/Users/"+$vidmUserId
$body = @'
{
    "password": "VMware01!"
}
'@
$body
$resetUserPassword = Invoke-RestMethod -Uri $uri -Headers $header -Method patch -Body $body




###################################
# Delete User in System Directory #
###################################
    #First Get specific User
    $vidmUsername = "vratest04"
    $uri =  "https://$vidmHostname/SAAS/jersey/manager/api/scim/Users?filter=username%20eq%20%22$vidmusername%22"
    $userResponse = Invoke-RestMethod -Uri $uri -Headers $header -Method Get
    $vidmUserId = $userResponse.Resources.id

#delete user
$uri = "https://$vidmHostname/SAAS/jersey/manager/api/scim/Users/"+$vidmUserId
$deleteUserResponse = Invoke-RestMethod -Uri $uri -Headers $header -Method Delete
