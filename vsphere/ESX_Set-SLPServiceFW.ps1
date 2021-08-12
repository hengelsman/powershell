#Import VMware PowerCLI Module(s)
import-module VMware.PowerCLI

#Variables
$vcenter = "<vcenter fqdn>"

#Create vCenter Connection
Connect-VIServer $vcenter

#Select All hosts from selected Clusters via UI
$Clusters=Get-Cluster | Out-GridView -Title "Select Cluster(s)" -OutputMode Multiple
$esxs=Get-Cluster $Clusters | Get-VMHost | Sort-Object Name

#Select All hosts from given Cluster
#$esxs=Get-Cluster "MyVmware Cluster" | Get-VMHost | Sort-Object Name

#Select All hosts from all Clusters
#$esxs=Get-Cluster | Get-VMHost | Sort-Object Name

foreach ($esx in $esxs){
    #$esx = Get-VMHost "esx01.infrajedi.local"

    #Select Service. Stop the Service, Set the startup policy to disabled/off
    $slpservice = Get-VMHostService -VMHost $esx |Where-Object {$_.Label -like "slpd"}
    $slpservice | Stop-VMHostService -Confirm:$false |Out-Null
    $slpservice | Set-VMHostService -Policy Off |Out-Null
    
    #Disable slp firewall rule
    $slpfirewall = Get-VMHostFirewallException -vMHost $esx -name "CIM SLP"
    $slpfirewall |Set-VMHostFirewallException -Enabled:$False -Confirm:$false |Out-Null 

    #Current Status
    write-host $esx.Name $slpservice "Service running Status: " $slpservice.Running "and set to: " $slpservice.Policy "firewall rule: " $slpfirewall.Enabled
}

Disconnect-VIServer -Confirm:$false
