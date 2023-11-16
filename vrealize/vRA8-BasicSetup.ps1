# Sample Script show various vRA REST calls
# Henk Engelsman
# Lat Update 16 Nov 2023
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

#vRA VARIABLES
$vraName = "bvra"
$domain = "infrajedi.local"
$vraHostname = $vraname+"."+$domain
$vraUsername = "configadmin"
$vraPassword = "VMware1!" #note use ` as escape character for special chars like $
$vraUserDomain = "System Domain" #Use "System Domain" for local users", otherwise use the AD domain.

#vCenter (to add to vRA as CloudAccount) VARIABLES 
$vcenterName = "vcsamgmt"
$vcenterHostname = $vcenterName+"."+$domain
$vcenterUsername = "administrator@vsphere.local"
$vcenterPassword = "VMware11!"
$vcenterDatacenter = "dc-mgmt" #Name of the vCenter datacenter object to add

#Connect to vCenter to retrieve the datacenter id
Connect-VIServer $vcenterHostname -User $vcenterUsername -Password $vcenterPassword
$vcenterDatacenterId = (get-datacenter "$vcenterDatacenter" |Select Id).Id
#Results in Datacenter-datacenter-2 format, should be in Datacenter:datacenter-2 format for vRA
[regex]$pattern = "-"
$vcenterDatacenterIdFormatted = $pattern.Replace($vcenterDatacenterId, ":", 1)
Write-Host "vCenter Datacenter Id: " $vcenterDatacenterIdFormatted
DisConnect-VIServer $vcenterHostname -Confirm:$false


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
} catch {
    write-host "Failed to Connect to host: $vraHostname" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vraBearerToken = $response.token
#Write-Host "Bearer token: $vraBearerToken"

#Add Bearer Authentication to Header
$header.add("Authorization", "Bearer $vraBearerToken")

##########################
### End login to vRA   ###
##########################



####################################
#   Create vCenter Cloud Account   #
####################################
$vCenterJSON = @"
{
  "hostName": "$vcenterHostname",
  "username": "$vcenterUsername",
  "password": "$vcenterPassword",
  "acceptSelfSignedCertificate": true,
  "createDefaultZones": true,
  "regions": [
    {
      "name": "$vcenterDatacenter",
      "externalRegionId": "$vcenterDatacenterIdFormatted"
    }
  ],
  "name": "$vcenterName",
  "description": "$vcenterName Cloud Account"
}
"@

$uri = "https://$vraHostname/iaas/api/cloud-accounts-vsphere"
$vCenterCloudAccount = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $vCenterJSON
$vCenterCloudAccountId = $vCenterCloudAccount.id
$vCenterCloudAccountId




####################################
#   Create Infoblox Integration    #
####################################

#Get IPAM Providers
#Request URL: https://bvra.infrajedi.local/provisioning/uerp/provisioning/ipam/api/providers

$infobloxPlugin = "Y:\vRealize\vRA8\infoblox-v1.5.zip"
$infobloxBinary = Get-Item -Path $infobloxPlugin
$infobloxHostName = "infoblox.infrajedi.local"
$infobloxUsername = "admin"
$infobloxPassword = "VMware01!"

#Import Provider
#$uri = "https://bvra.infrajedi.local/provisioning/ipam/api/providers/packages/import"
#$response = Invoke-RestMethod -Uri $uri -Method Post -header $header -Form @{ file = $infobloxBinary }


#Validate
#Request URL: https://bvra.infrajedi.local/iaas/api/integrations?validateOnly&apiVersion=2021-07-15
$uri = "https://bvra.infrajedi.local/iaas/api/integrations&apiVersion=2021-07-15"
$body=@"
{
	"integrationProperties": {
		"providerId": "fcd5764f-4874-4ccb-87e2-8f22686f80e6",
		"faasProviderEndpointId": "e0014861-2c30-40c1-9c9a-1154fcc1af6b",
		"privateKeyId": "admin",
		"privateKey": "VMware01!",
		"hostName": "infoblox.infrajedi.local",
		"properties": "[{\"prop_key\":\"Infoblox.IPAM.DisableCertificateCheck\",\"prop_value\":\"True\"},{\"prop_key\":\"Infoblox.IPAM.WAPIVersion\",\"prop_value\":\"2.7\"},{\"prop_key\":\"Infoblox.IPAM.HTTPTimeout\",\"prop_value\":\"30\"},{\"prop_key\":\"Infoblox.IPAM.LogApiCallsAsInfo\",\"prop_value\":\"False\"},{\"prop_key\":\"Infoblox.IPAM.NetworkContainerFilter\",\"prop_value\":\"\"},{\"prop_key\":\"Infoblox.IPAM.NetworkFilter\",\"prop_value\":\"\"},{\"prop_key\":\"Infoblox.IPAM.RangeFilter\",\"prop_value\":\"\"}]",
		"isMockRequest": "false",
		"dcId": "onprem"
	},
	"customProperties": {
		"isExternal": "true"
	},
	"integrationType": "ipam",
	"associatedCloudAccountIds": [],
	"associatedMobilityCloudAccountIds": {},
	"name": "infoblox.infrajedi.local",
	"privateKey": "VMware01!",
	"privateKeyId": "admin"
}
"@
Invoke-RestMethod -Uri $uri -Method Post -header $header


Request URL: https://bvra.infrajedi.local/iaas/api/integrations?validateOnly&apiVersion=2021-07-15
Request Method: POST

$activeDirectoryJSON=@"
{
	"integrationProperties": {
		"server": "ldaps://ad01.infrajedi.local:636",
		"endpointId": "e0014861-2c30-40c1-9c9a-1154fcc1af6b",
		"user": "svcvidm",
		"privateKey": "VMware2022!",
		"defaultOU": "dc=infrajedi,dc=local",
		"alternativeHost": "ldaps://ad02.infrajedi.local:636",
		"connectionTimeout": 10,
		"endpointType": "activedirectory",
		"dcId": "onprem"
	},
	"customProperties": {
		"isExternal": "true"
	},
	"integrationType": "activedirectory",
	"associatedCloudAccountIds": [],
	"associatedMobilityCloudAccountIds": {},
	"privateKey": "VMware2022!",
	"name": "infrajedi.local",
	"description": "Active Directory infrajedi.local",
	"certificateInfo": {
		"certificate": "-----BEGIN CERTIFICATE-----\nMIIGTDCCBTSgAwIBAgITRgAAAEI9UyjQ+aUCkQABAAAAQjANBgkqhkiG9w0BAQsF\nADBJMRUwEwYKCZImiZPyLGQBGRYFbG9jYWwxGTAXBgoJkiaJk/IsZAEZFglpbmZy\nYWplZGkxFTATBgNVBAMTDENBLWluZnJhamVkaTAeFw0yMjA5MDcxNTQxMTRaFw0y\nNjA5MDYxNTQxMTRaMB8xHTAbBgNVBAMTFGFkMDEuaW5mcmFqZWRpLmxvY2FsMIIB\nIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA556hdrJVWJ1soIArEOcLk+Df\n2qzNjlpdSZitbnK1WaDKxpVxePk0mZW3/RFm4Qmb65c0wjhycyhFZfyBMtP5m1NM\nooUXLJtVcqJZ4xs09JgIi6OstFZFYwwr4xjo22Fnt4b01TWHFjrU6Wp024Nqdb1W\nBA7FdnAqtaggqh2YidB5Tymw9wyDkVRkBALnAejoK6qNiw+Txj0nd4YE3XSMVTuk\n9WoU+rhY3+ek499RnaS53oQYSXs2wmGdY6hfRy2NyupcRJXbFjBFQ/tAMrSVU4XU\nq6S7GcmaZSlDOMb8BXb8wh8GYhSoeQidbVVMejJ2+cYoDrSZFFEKT+fT3/2J5QID\nAQABo4IDVTCCA1EwPgYJKwYBBAGCNxUHBDEwLwYnKwYBBAGCNxUIhJL6Aoeb9CqD\nzY00gqyBdIeK6U+BPYbDxUqD0NZ4AgFkAgEEMDIGA1UdJQQrMCkGBysGAQUCAwUG\nCisGAQQBgjcUAgIGCCsGAQUFBwMBBggrBgEFBQcDAjAOBgNVHQ8BAf8EBAMCBaAw\nQAYJKwYBBAGCNxUKBDMwMTAJBgcrBgEFAgMFMAwGCisGAQQBgjcUAgIwCgYIKwYB\nBQUHAwEwCgYIKwYBBQUHAwIwHQYDVR0OBBYEFPf7okzyU6MqLTXNdrcP4/fY40dr\nMB8GA1UdIwQYMBaAFHU4VKHCLEShcd9yEtOnXHC3ihKlMIHOBgNVHR8EgcYwgcMw\ngcCggb2ggbqGgbdsZGFwOi8vL0NOPUNBLWluZnJhamVkaSgxKSxDTj1jYTAxLENO\nPUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1D\nb25maWd1cmF0aW9uLERDPWluZnJhamVkaSxEQz1sb2NhbD9jZXJ0aWZpY2F0ZVJl\ndm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9p\nbnQwgcIGCCsGAQUFBwEBBIG1MIGyMIGvBggrBgEFBQcwAoaBomxkYXA6Ly8vQ049\nQ0EtaW5mcmFqZWRpLENOPUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxD\nTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPWluZnJhamVkaSxEQz1sb2Nh\nbD9jQUNlcnRpZmljYXRlP2Jhc2U/b2JqZWN0Q2xhc3M9Y2VydGlmaWNhdGlvbkF1\ndGhvcml0eTBiBgNVHREEWzBZoCUGCisGAQQBgjcUAgOgFwwVQUQwMSRAaW5mcmFq\nZWRpLmxvY2FsghRhZDAxLmluZnJhamVkaS5sb2NhbIIPaW5mcmFqZWRpLmxvY2Fs\ngglJTkZSQUpFREkwTwYJKwYBBAGCNxkCBEIwQKA+BgorBgEEAYI3GQIBoDAELlMt\nMS01LTIxLTIzOTM1MDcyOTgtMTg2OTc1Mzc2Mi00MDkzNTEyNzI3LTEwMDAwDQYJ\nKoZIhvcNAQELBQADggEBAGyALwHOsCSaest7bKX1KLDKODX2Wuckxcf/NGM+m39U\nFcmb9zJLnTWSI7KMfK217yvxvOyFut0lZmysZlp5GhsCWDSEzveqbP+Y21/tUYZ4\n87MX/3rnjaAOgmZ/SrVQCneWFmoyi8aWLGVzl3mi5LbUMLA4gLNxl3e3xz1rwVvv\nX/ydBrKX7OIx0kkbmVsttH3XXSM26EAznB6XGe6BEe36ucnhc+or96Tu/QAgp/cG\nUiHFLgXkG2Uu/9WSCes6ab57IKGIicrFg94+tML+D4vvjmMscKoDKoI2cIYYXaaO\nwl4uB+FZZyAaY4cHDzW7eXGumzKDDmiP4w/mznVAidA=\n-----END CERTIFICATE-----\n"
	}
}
"@


$vROPSJSON=@"
{
	"integrationProperties": {
		"hostName": "https://vrops.infrajedi.local/suite-api",
		"privateKeyId": "admin",
		"privateKey": "VMware2021!",
		"acceptSelfSignedCertificate": true,
		"dcId": "onprem"
	},
	"customProperties": {
		"isExternal": "true"
	},
	"integrationType": "vrops",
	"associatedCloudAccountIds": [],
	"associatedMobilityCloudAccountIds": {},
	"privateKey": "VMware2021!",
	"privateKeyId": "admin",
	"name": "vrops.infrajedi.local",
	"certificateInfo": {
		"certificate": "-----BEGIN CERTIFICATE-----\nMIIGKDCCBRCgAwIBAgITRgAAAEhqECGREDWvcgABAAAASDANBgkqhkiG9w0BAQsF\nADBJMRUwEwYKCZImiZPyLGQBGRYFbG9jYWwxGTAXBgoJkiaJk/IsZAEZFglpbmZy\nYWplZGkxFTATBgNVBAMTDENBLWluZnJhamVkaTAeFw0yMzAxMjUyMjAyMzFaFw0y\nNzAxMjQyMjAyMzFaMH4xCzAJBgNVBAYTAk5MMRUwEwYDVQQIEwxadWlkLUhvbGxh\nbmQxEjAQBgNVBAcTCU1hYXNzbHVpczESMBAGA1UEChMJaW5mcmFqZWRpMQ4wDAYD\nVQQLEwVsb2NhbDEgMB4GA1UEAxMXdnJvcHNsYi5pbmZyYWplZGkubG9jYWwwggEi\nMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDDSvgCZtQrr8A4Pur/eS1w9raW\nwz2IKNXJIkF3AKO/oa/4G+M47YTHavFSp2RttjkCL2uQEAvN6NOI7e7USS8oJkNc\nkLyorCasiUoEEAf+2uOSCBhrd3lt1se2HvI3NibtmkuMRH+ObvNkw9oQGB1iDAr3\niSobtlDnd7j0yA2GQwQT9Dgdawj1aAZcWmfQsk9PzMdNReq6fw03Ha4X7WJ/RdUf\nukLms9E/2NxXzZjZDdeUbVnWjkpqnYsul37aieY79K8fPUeIBI35RmBuzW7fyokY\nItok3dLrX/6Vl7V/Tzh14KdeCQXEXUqiSkSwXjoDNCQ+u4zSynT8EUe6l2FnAgMB\nAAGjggLSMIICzjAOBgNVHQ8BAf8EBAMCBeAwIAYDVR0lAQH/BBYwFAYIKwYBBQUH\nAwIGCCsGAQUFBwMBMIGEBgNVHREEfTB7ghd2cm9wc2xiLmluZnJhamVkaS5sb2Nh\nbIIVdnJvcHMuaW5mcmFqZWRpLmxvY2Fsghd2cm9wczAxLmluZnJhamVkaS5sb2Nh\nbIIXdnJvcHMwMi5pbmZyYWplZGkubG9jYWyCF3Zyb3BzMDMuaW5mcmFqZWRpLmxv\nY2FsMB0GA1UdDgQWBBRWCHlIZ3BS87+6sP5bt1tfJghNBjAfBgNVHSMEGDAWgBR1\nOFShwixEoXHfchLTp1xwt4oSpTCBzgYDVR0fBIHGMIHDMIHAoIG9oIG6hoG3bGRh\ncDovLy9DTj1DQS1pbmZyYWplZGkoMSksQ049Y2EwMSxDTj1DRFAsQ049UHVibGlj\nJTIwS2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixE\nQz1pbmZyYWplZGksREM9bG9jYWw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9i\nYXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50MIHCBggrBgEFBQcB\nAQSBtTCBsjCBrwYIKwYBBQUHMAKGgaJsZGFwOi8vL0NOPUNBLWluZnJhamVkaSxD\nTj1BSUEsQ049UHVibGljJTIwS2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049\nQ29uZmlndXJhdGlvbixEQz1pbmZyYWplZGksREM9bG9jYWw/Y0FDZXJ0aWZpY2F0\nZT9iYXNlP29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwPQYJKwYB\nBAGCNxUHBDAwLgYmKwYBBAGCNxUIhJL6Aoeb9CqDzY00gqyBdIeK6U+BPdzwFIeT\n+RYCAWQCAQIwDQYJKoZIhvcNAQELBQADggEBAAEf2sCgT+u7vWoyabinaBJnmZhH\nsJNES7luXuosmYxs15+SWonewApWmMr9g5KlIngkH8twIaDfmX/lmi5CQ8V3BQMs\ny8FLHyeSS5la4zYvqBIrpeYXYTUBb67ZoRD7eBaTnpaYfn7BFmi3yRL/kxfZOzwb\nTlEIM8Wgh1cKaufk+3jvhYEYcknZTWLuSVskFKcQvD4FBCqLrv3QpX0CJKYLdElG\nghfdebqgQMZXT+7yWSE6wzjU7JyAEwqLxwZYz50WNMJCtdKf4AzzPStXzaoxhwa0\ny1rxzF8/TrvIbxu2ocSgQj0mk1+gSHI4S9MHqSUZXIAzbH6+fpI668oiQ9g=\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nMIIDlDCCAnygAwIBAgIQfe7LpdivtLlPC0RpIxwPbjANBgkqhkiG9w0BAQsFADBJ\nMRUwEwYKCZImiZPyLGQBGRYFbG9jYWwxGTAXBgoJkiaJk/IsZAEZFglpbmZyYWpl\nZGkxFTATBgNVBAMTDENBLWluZnJhamVkaTAeFw0yMjA2MTIxODM4MzBaFw0yNzA2\nMTMxODQ4MjlaMEkxFTATBgoJkiaJk/IsZAEZFgVsb2NhbDEZMBcGCgmSJomT8ixk\nARkWCWluZnJhamVkaTEVMBMGA1UEAxMMQ0EtaW5mcmFqShow more
"@


#Get vSphere Cloud Accounts
$uri = "https://$vraHostname/iaas/api/cloud-accounts-vsphere"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content


#Get Cloud Zones
$uri = "https://$vraHostname/iaas/zones"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content

######################
#   Create Project   #
######################

$projectJSON = @"
{
	"name": "p-infra",
	"description": "Infra Project",
	"properties": {
		"costcenter": "999",
		"__namingTemplate": "",
		"__projectPlacementPolicy": "DEFAULT"
	},
	"constraints": {
		"network": null,
		"storage": null,
		"extensibility": null
	},
	"sharedResources": true,
	"administrator": [
		{
		  "email": "configadmin",
		  "type": "user"
		}
	  ],
	  "viewers": [
		{
		  "email": "configadmin",
		  "type": "user"
		}
	  ]
	"operationTimeout": 0
}
"@

$uri = "https://$vraHostname/project-service/api/projects"
$uri
$vRAProject = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $projectJSON
Write-Host "Project Name: " $vRAProject.name " has id: " $vRAProject.id




<#
#Region Enumeration
$uri = https://bvra.infrajedi.local/iaas/api/cloud-accounts/region-enumeration?apiVersion=2021-07-15
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header


$uri = "https://$vraHostname/iaas/api/cloud-accounts/"
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $vCenterJSON
$response #show full result
$vraCloudAccountId = $response.id #save CloudAccount Id for later use
$vraCloudAccountName = $response.name #save CloudAccount name for later use


#Get Cloud Account filtered by name
$filterdata = "`$filter=name eq '$vraCloudAccountName'"
$uri = "https://$vraHostname/iaas/api/cloud-accounts/?" + $filterdata
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content

#Get All Cloud Accounts
$uri = "https://$vraHostname/iaas/api/cloud-accounts"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content

#Get vSphere Cloud Accounts
$uri = "https://$vraHostname/iaas/api/cloud-accounts-vsphere"
$response = $cloudAccount = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content
#>


# Patch Project
# will follow

#################################
#     Import Cloud Templates    #
#################################

#Blueprint uri
$uri = "https://$vraHostname/blueprint/api/blueprints"

#Import Ubuntu Cloud Template
$ubuntuContent = get-content "\\192.168.1.10\ISO\vRealize\vRA8\Henk-Blueprints\ubuntu-cn.yaml"
$ubuntuContentFlat = ([string]::join("\n",($ubuntuContent.Split("`n")))) + "\n"
$data = @"
{
	"name": "ubuntu",
	"description": null,
	"valid": true,
	"content": "$ubuntuContentFlat",
	"projectId": "$vraProjectId",
	"requestScopeOrg": true
}
"@
Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data

#Import Photon Cloud Template
$photonContent = get-content "\\192.168.1.10\ISO\vRealize\vRA8\Henk-Blueprints\photon-cn.yaml"
$photonContentFlat = ([string]::join("\n",($photonContent.Split("`n")))) + "\n"
$data = @"
{
	"name": "photon-cn",
	"description": null,
	"valid": true,
	"content": "$photonContentFlat",
	"projectId": "$vraProjectId",
	"requestScopeOrg": true
}
"@
Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data


#Get vSphere Cloud Regions
$uri = "https://$vraHostname/iaas/api/cloud-accounts-vsphere/region-enumeration"
$data=@"
{
	"hostName": "$vcenterHostname",
	"acceptSelfSignedCertificate": true,
	"password": "$vcenterPassword",
	"dcid": "$vcenterDatacenterIdFormatted",
	"cloudAccountId": "$vraCloudAccountId",
	"username": "$vcenterUsername"
}
"@
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data
$response.externalRegions.name
$vraRegionId = $response.externalRegions.externalRegionId

#Get Flavors
$uri = "https://$vraHostname/iaas/api/flavors"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content

#Get Flavor Profiles
$uri = "https://$vraHostname/iaas/api/flavor-profiles"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content

$uri = "https://$vraHostname/iaas/api/flavor-profiles/fdb77676-dc7f-45d1-8df1-530ee8d2ec1e-9152b4f9-7717-41c4-889f-a0dc779d6e6d"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response


<#
#Create Flavor Profile
$uri = "https://$vraHostname/iaas/api/flavor-profiles"
$data = @"
{
	"regionId": "9152b4f9-7717-41c4-889f-a0dc779d6e6d",
	"name": "vSphere_small",
	"description": "blaat",
	"flavorMapping": "{ \"vSphere_small\": { \"cpuCount\": \"2\", \"memoryInMB\": \"2048\"}}"
}
"@
Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $data
#>


#### MISC ####


#Get Endpoints
$uri = "https://$vraHostname/provisioning/uerp/provisioning/mgmt/endpoints?expand&$orderby=name%20asc&$top=100&$skip=0"
Invoke-RestMethod -Method Get -Uri $uri -Headers $header

#Get Regions
$uri = "https://$vraHostname/iaas/api/regions"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content

#Get vRA Flavors
$uri = "https://$vraHostname/iaas/api/flavors"
$flavors = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$flavors.content

#Get vRA Flavor Profiles
$uri = "https://$vraHostname/iaas/api/flavor-profiles"
$flavorProfiles = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$flavorProfiles.content

# OR

$uri = "https://bvra.infrajedi.local/provisioning/mgmt/instance-names"
$data = @"
{
	"name": "tiny",
	"instanceTypeMapping": {
		"/provisioning/resources/provisioning-regions/551d67c6-5ead-499e-a76b-157caca67247": {
			"cpuCount": 1,
			"memoryMb": 1048576
		}
	}
}
"@
Invoke-RestMethod -Method Post -Uri $uri -Headers $header



############################
#  Service Broker Requests #
############################
# Will follow 



