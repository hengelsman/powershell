# Sample Script show various vRA REST calls
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
$vraName = "bvra"
$domain = "infrajedi.local"
$vraHostname = $vraname+"."+$domain
$vraUsername = "configadmin"
$vraPassword = "VMware01!" #note use ` as escape character for special chars like $
$vraUserDomain = "System Domain" #Use "System Domain" for local users", otherwise use the AD domain.

#vCenter (to add to vRA as CloudAccount) VARIABLES 
$vcenterName = "vcsamgmt"
$vcenterHostname = $vcenterName+"."+$domain
$vcenterUsername = "administrator@vsphere.local"
$vcenterPassword = "VMware01!"
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
    $response
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



################################
#        Cloud Account         #
################################

# Create vSphere cloud Account by using Generic Cloud Account URI
$vCenterJSON = @"
{
	"cloudAccountType": "vsphere",
	"cloudAccountProperties": {
		"hostName": "$vcenterHostname",
		"dcId": "onprem",
		"privateKeyId": "$vcenterUsername",
		"privateKey": "$vcenterPassword",
		"acceptSelfSignedCertificate": true
	},
	"createDefaultZones": true,
	"regions": [{
		"name": "$vcenterDatacenter",
		"externalRegionId": "$vcenterDatacenterIdFormatted"
	}],
	"name": "vcenter-$vcenterHostname",
	"privateKeyId": "$vcenterUsername",
	"privateKey": "$vcenterPassword",
	"customProperties": {
		"isExternal": "false"
	},
	"associatedCloudAccountIds": []
}
"@
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


################################
#           Projects           #
################################

# Create Project
$projectJSON = @"
{
	"name": "p-test",
	"description": "First Project",
	"properties": {
		"costcenter": "999",
		"__namingTemplate": "${resource.name}",
		"__projectPlacementPolicy": "DEFAULT"
	},
	"constraints": {
		"network": null,
		"storage": null,
		"extensibility": null
	},
	"sharedResources": true,
	"operationTimeout": 0
}
"@

# Patch Project
# will follow

#################################
#     Import Cloud Templates    #
#################################

#Blueprint uri
$uri = "https://$vraHostname/blueprint/api/blueprints"

#Import Ubuntu Cloud Template
$ubuntuContent = get-content "\\192.168.1.10\ISO\vRealize\vRA8\Henk-Blueprints\20211001_ubuntu.yaml"
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
$photonContent = get-content "\\192.168.1.10\ISO\vRealize\vRA8\Henk-Blueprints\20211027_photon4.yaml"
$photonContentFlat = ([string]::join("\n",($photonContent.Split("`n")))) + "\n"
$data = @"
{
	"name": "photon",
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



################################
# Allow Selfsigned certificate #
################################
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
	