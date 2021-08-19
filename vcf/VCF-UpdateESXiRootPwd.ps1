# Powershell Script to Update ESXI root passwords on selected hosts
# This Script requires PowerVCF either on Linux or Windows
# 
# Henk Engelsman
# 20 Aug 2021
#
Install-Module PowerVCF -ErrorAction Stop 
Import-Module PowerVCF -ErrorAction Stop

#################
### VARIABLES ###
#################
$SDDCManager = "sddc-manager.vrack.vsphere.local"
$vcfUsername = "administrator@vsphere.local"
$vcfPassword = "VMware01!"
$newRootPassword = "YourNewVMwPwd!1357"
#Password must include at least 1 uppercase and lowercase character, must also have 1 numeric and 1 special character from [!,@,#,$,^,*].
#Password should have length 8-20, with no 3 adjacent characters repeating
Request-VCFToken -fqdn $SDDCManager -username $vcfUsername -password $vcfPassword
#Configure Path to store json configuration files
    $jsonFilePath = "C:\Temp\VCF\" #Windows System
    #$jsonFilePath = "/root/" #Linux System

# Select All Hosts from Given Cluster
$VCFClusterName = "SDDC-Cluster1"
$VCFClusterId = (Get-VCFCluster -name $VCFClusterName).id
$vcfHosts = Get-VCFHost |Where-Object {$_.cluster.id -eq $VCFClusterId} |Select-Object fqdn, id |Sort-Object fqdn
# Or select ALL hosts from VCF | You may want to filter here
#$vcfHosts = Get-VCFHost |Select-Object fqdn

# Write current root passwords to console
foreach ($vcfHost in $vcfHosts){
    $recName = $vcfHost.fqdn
    $VCFCreds =  Get-VCFCredential -resourceName $recName|Where-Object {$_.username -eq "root"}
    Write-host "Current root credentials for VCF Host" $recName " : " $VCFCreds.password
}

# Change root passwords - Operation Type can be UPDATE, ROTATE, REMEDIATE
foreach ($vcfHost in $vcfHosts) {
    $esxFilename = $jsonFilePath + $vcfHost.fqdn + ".json"
    $recName = $vcfHost.fqdn
    #$recId = $vcfHost.id
    $jsonData = "{
        `"elements`": [ {
            `"credentials`": [ {
                `"credentialType`": `"SSH`",
                `"username`": `"root`",
                `"password`": `"$newRootPassword`"
            } ],
            `"resourceName`": `"$recName`",
            `"resourceType`": `"ESXI`"
        } ],
        `"operationType`": `"UPDATE`"
    }"
    $jsonData |Out-File $esxFilename -Force #Export the json to a file
    Set-VCFCredential -json $esxFilename
    Start-Sleep -Seconds 10 #This is really lazy. You should use Get-VCFCredentialTask :)
}

# Write current root passwords to console
foreach ($vcfHost in $vcfHosts){
    $recName = $vcfHost.fqdn
    $VCFCreds =  Get-VCFCredential -resourceName $recName|Where-Object {$_.username -eq "root"}
    Write-host "Current root credentials for VCF Host" $recName " : " $VCFCreds.password
}