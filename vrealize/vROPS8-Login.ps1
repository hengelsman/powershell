# Sample Script show various vROPS REST calls
# Henk Engelsman
# 25/09/2023
#
# Aria Operations API Programming Operations
#   https://docs.vmware.com/en/VMware-Aria-Operations/8.12/API-Programming-Operations.pdf
# Aria Operations 8.12 API Programming Guide
#   https://docs.vmware.com/en/VMware-Aria-Operations/8.12/API-Programming-Operations/GUID-79DD20A4-2F38-4EAB-94BF-771DF2C596B1.html
#

#vROPS Variables
$vropsHostname = "vrops80-weekly.cmbu.local"
$vropsUsername = "admin"
$vropsPassword ="VMware1!"
$vropsAuthsource = "Local"


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




#build Header
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/json')
$header.Add("Content-Type", 'application/json')
$uri =  "https://$vropsHostname/lcm/authzn/api/firstboot/updatepassword"
$data=@"
{
    "username" : "$vropsUsername",
    "authSource" : "$vropsAuthsource",
    "password" : "$vropsPassword"
}
"@

#Login to get opsToken
$uri = "https://$vropsHostname/suite-api/api/auth/token/acquire"
$opsToken = (Invoke-RestMethod -Uri $uri -Headers $header -Method Post -Body $data).token

#Add (opsToken) Authentication to Header
# Old Format (Should still work)
#    Authorization: vRealizeOpsToken <vROps_token>
# Alternatively, if you acquired the token from an SSO source, the Authorization header is of
#   Authorization: SSO2Token <SSO_SAML_TOKEN>
$header.add("Authorization", "OpsToken $opsToken")




#Get Policies
$uri = "https://$vropsHostname/suite-api/api/policies"
$policies = Invoke-RestMethod -Uri $uri -Headers $header -Method Get
$policies


$uri = "https://$vropsHostname/suite-api/api/adapterkinds"
$adapterKinds = Invoke-RestMethod -Uri $uri -Headers $header -Method Get
$adapterKinds."adapter-kind"



#Aria Ops - Internal API examples
#Set Unsupported
$header.Add("X-Ops-API-use-unsupported", "true")

#Check Cost Calculation Status
$uri = "https://$vropsHostname/suite-api/internal/costcalculation/status"
Invoke-RestMethod -Uri $uri -Headers $header -Method Get


#example vm/id
$vm = "vcf-fd-vrli8-01a"
$vmvropsid = "cc67aa34-f07d-49c0-828b-2f37973056d7"

$uri = "https://$vropsHostname/suite-api/internal/optimization/cc67aa34-f07d-49c0-828b-2f37973056d7/reclaim"
Invoke-RestMethod -Uri $uri -Headers $header -Method Get

#Get Oversized VM in Cluster with ID 7811f06f-cd58-48cd-8892-7fb7fc499811
# https://vrops80-weekly.cmbu.local/suite-api/internal/optimization/7811f06f-cd58-48cd-8892-7fb7fc499811/rightsizing?groupAdapterKind=VMWARE&groupResourceKind=ClusterComputeResource&vmNameFilter=vrcu-sky&_no_links=true
# groupAdapterKind string (query) ==> VMWARE
# groupResourceKind string (query) ==> ClusterComputeResource
# id string (path) ==> vROPS Object `ClusterId



# Terminate vROPS Session
#$uri = "https://$vropsHostname/suite-api/api/auth/token/release"
#Invoke-RestMethod -Method Post -Uri $uri -Headers $header

