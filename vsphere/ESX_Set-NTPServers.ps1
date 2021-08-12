# Script to change NTP Settings on all hosts in the selected VMware cluster(s)
#
#
# v2.0 - 02-12-2019: Henk Engelsman

#Import VMware PowerCLI Module(s)
import-module VMware.PowerCLi

#Variables
$vcenter = "<vcenter fqdn>"
$ntpservers = "ntp1","ntp2","ntp3"


#Create vCenter Connection
Connect-VIServer $vcenter

#Select All hosts from selected Clusters
$Clusters=Get-Cluster | Out-GridView -Title "Select Cluster(s)" -OutputMode Multiple
$esxs=Get-Cluster $Clusters | Get-VMHost | Sort-Object Name


foreach ($esx in $esxs)

{
	#Stoppen van de NTP Service
	$ntpsvc = Get-VMHostservice $esx | Where-Object {$_.key -eq "ntpd"}
	Stop-VMHostService -HostService $ntpsvc -Confirm:$false

	#Verwijderen van alle bestaande NTP Servers (indien meerdere staan ingesteld)
	$oldntps = Get-VMHostNtpServer -VMHost $esx	
	foreach ($oldntp in $oldntps)
	{
	Remove-VMHostNtpServer -NtpServer $oldntp -VMHost $esx -Confirm:$false
	}

	#Toevoegen van nieuwe NTP Servers
	foreach ($ntpserver in $ntpservers)
	{
		Add-VmHostNtpServer -NtpServer $ntpserver -VMHost $esx
	}

	#Starten van de NTP Service
	Start-VMHostService -HostService $ntpsvc -Confirm:$false
	
	#NTP Service op "Start and stop with host" zetten
	Set-VMHostService -HostService $ntpsvc -Policy "on"
}

Disconnect-VIServer -Confirm:$false
