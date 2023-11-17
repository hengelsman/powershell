# Sample Script to create Cloud Account and Cloudzone
# Henk Engelsman
# Last Update 17 Nov 2023
#
# VMware Developer Documentation - APIs
#   https://developer.vmware.com/apis
# Aria Automation API Programming Guide
#   https://developer.vmware.com/docs/18201/


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
$vraName = "vra"
$domain = "infrajedi.local"
$vraHostname = $vraname+"."+$domain
$vraUsername = "configadmin"
$vraPassword = "VMware1!" #note use ` as escape character for special chars like $
$vraUserDomain = "System Domain" #Use "System Domain" for local users", otherwise use the AD domain.

#vCenter (to add to vRA as CloudAccount) VARIABLES 
$vcenterName = "vcsamgmt"
$vcenterHostname = $vcenterName+"."+$domain
$vcenterUsername = "administrator@vsphere.local"
$vcenterPassword = "VMware1!"
$vcenterDatacenter = "dc-mgmt" #Name of the vCenter datacenter object to add
$vcenterCluster = "cls-mgmt"
$vcenterDeploymentFolder = "vRADeployments"

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
$response

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
  "createDefaultZones": false,
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
try {
    $vCenterCloudAccount = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $vCenterJSON
} catch {
    write-host "Failed to create Cloud Account on host: $vraHostname" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$vCenterCloudAccountId = $vCenterCloudAccount.id


# Get RegionId
$response=""
$uri = "https://$vraHostname/iaas/api/regions"
try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
} catch {
    write-host "Failed to retreive Regions" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$regionId = $response.content.id
$regionId


##################################################
# Create Cloud Zone - Option 1                   #
# including all clusters from vSphere datacenter #
##################################################
# tags the Cloud Zone (example)
$cloudzoneName = "cz-mgmt"
$cloudZoneDescription = "Cloudzone for $cloudzoneName"
$cloudzoneJSON = @"
{
    "name": "$cloudzoneName",
    "description": "$cloudZoneDescription",
    "regionId": "$regionId",
    "tags": [
        {
            "key": "cz",
            "value": "mgmt"
        }
    ],
	"folder": "$vcenterDeploymentFolder",
    "placementPolicy": "DEFAULT"
}
"@
$uri = "https://$vraHostname/iaas/zones"
try {
    $cloudZone = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $cloudzoneJSON
} catch {
    write-host "Failed to create Cloudzone $cloudzoneName" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}


##################################################
# Create Cloud Zone - Option 2                   #
# Dynamically include compute by tags on Cluster #
##################################################

# If you did not set tags in vCenter on the cluster, you can set tags in vRA.
# First Get vSphere Cluster (Fabric Computes) id by name
$uri = "https://$vraHostname/iaas/api/fabric-computes?`$filter=name eq '$vcenterCluster'"
try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
} catch {
    write-host "Failed to retrieve clusters" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$response.content
$fabricExternalId = $response.content.externalId
$fabricId = $response.content.id

# Tag a vSphere Cluster in Aria Automation
$clusterTagJSON =@"
{
    "tags": [
        {
            "key": "cz",
            "value": "mgmt"
        }
    ]
}
"@
$uri = "https://$vraHostname/iaas/api/fabric-computes/$fabricId"
try {
    $response = Invoke-RestMethod -Method Patch -Uri $uri -Headers $header -Body $clusterTagJSON
} catch {
    write-host "Failed to set Tags on Cluster: $clusterName" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

# Create the Tag based Cloudzone
$cloudzoneName = "cz-mgmt"
$cloudZoneDescription = "Cloudzone for $cloudzoneName"
$cloudzoneJSON = @"
{
    "name": "$cloudzoneName",
    "description": "$cloudZoneDescription",
    "regionId": "$regionId",
	"tagsToMatch": [
		{
		  "key": "cz",
		  "value": "mgmt"
		}
	  ],
	"folder": "$vcenterDeploymentFolder",
    "placementPolicy": "DEFAULT"
}
"@
$uri = "https://$vraHostname/iaas/zones"
try {
    $cloudZone = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $cloudzoneJSON
} catch {
    write-host "Failed to create Cloudzone $cloudzoneName" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}


##################################################
# Create Cloud Zone - Option 3                   #
# Manually include compute by tags on Cluster    #
##################################################
# First Get vSphere Cluster (Fabric Computes) id by name
$uri = "https://$vraHostname/iaas/api/fabric-computes?`$filter=name eq '$vcenterCluster'"
try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
} catch {
    write-host "Failed to retrieve clusters" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$fabricId = $response.content.id

$cloudzoneName = "cz-mgmt"
$cloudZoneDescription = "Cloudzone for $cloudzoneName"
$cloudzoneJSON = @"
{
    "name": "$cloudzoneName",
    "description": "$cloudZoneDescription",
    "regionId": "$regionId",
    "tags": [
        {
            "key": "cz",
            "value": "mgmt"
        }
    ],
    "placementPolicy": "DEFAULT",
    "folder": "$vcenterDeploymentFolder",
    "computeIds": [$fabricId]
}
"@
$uri = "https://$vraHostname/iaas/zones"
try {
    $cloudZone = Invoke-RestMethod -Method Post -Uri $uri -Headers $header -Body $cloudzoneJSON
} catch {
    write-host "Failed to create Cloudzone $cloudzoneName" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}


# Retrieve Cloud Zones
$uri = "https://$vraHostname/iaas/api/zones/"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $header
$response.content