# Powershell Script to Deploy vRSLCM
# Optionally copy vidm and vra files to configure NFS share
#
# Henk Engelsman - https://www.vtam.nl
# 20 Aug 2021
#
# 19 Nov 2021 - Updated for 8.6.1 release
# - bugfix for ova copy
# 22 Jan 2022 - Updated for 8.6.2 release
# 22 March 2022 - Updated for 8.7.0 Release
# - Added option to copy source OVA to NFS share or vRSLCM Appliance (Requires Posh-SSH module)
# 11 April 2022 - Added second snapshot creation option
import-module Posh-SSH -ErrorAction break

#################
### VARIABLES ###
#################
# Path to EasyInstaller ISO
#$vrslcmIso = "C:\Temp\vra-lcm-installer-19527797.iso" # "<path to iso file>"
$vrslcmIso = "C:\Temp\vra-lcm-installer-850_18488288.iso" # "<path to iso file>"
$copyVIDMOVA = $true # $true | $false
$copyvRAOVA = $true # $true | $false
$ovaDestinationType = "VRSLCM" # VRSLCM or NFS
$nfsshare = "\\192.168.1.10\data\ISO\vRealize\latest\" # "<path to NFS share>"
$createSnapshotPreboot = $false # $true|$false to create a snapshot after initial deployment.
$createSnapshotOVA = $true # $true|$false to create a snapshot after OVA files have been copied to vRSLCM.

# vCenter variables
$vcenter = "vcsamgmt.infrajedi.local" #vcenter FQDN
$vcUser = "administrator@vsphere.local"
$vcPassword = "VMware01!" #vCenter password
# General Configuration Parameters
$cluster = "cls-mgmt"
$network = "VMNet1"
$datastore = "DS01-SSD870-1" #vSphere Datastore to use for deployment
$vrslcmIp = "192.168.1.180" #vRSLCM IP Address
$netmask = "255.255.255.0"
$gateway = "192.168.1.1"
$dns = "192.168.1.204,192.168.1.205" # DNS Servers, Comma separated
$domain = "infrajedi.local" #dns domain name
$vrslcmVmname = "bvrslcm" #vRSLCM VM Name
$vrslcmHostname = $vrslcmVmname+"."+$domain #joins vmname and domain variable to generate fqdn
$vrlscmRootPassword = "VMware01!" #Note this is the root password, not the admin@local password
$ntp = "192.168.1.1"
$vmFolder = "vRealize-Beta" #VM Foldername to place the vm.


# Mount the Iso and extract ova paths
$mountResult = Mount-DiskImage $vrslcmIso -PassThru
Start-sleep -Seconds 5
$driveletter = ($mountResult | Get-Volume).DriveLetter
$vrslcmOva = (Get-ChildItem ($driveletter + ":\" + "vrlcm\*.ova")).Name
$vrslcmOvaPath = $driveletter + ":\vrlcm\" + $vrslcmOva
$vidmOva = "vidm.ova"
$vidmOvaPath = $driveletter+":\ova\"+$vidmOva
$vraOva = "vra.ova"
$vraOvaPath = $driveletter+":\ova\"+$vraOva
# Or Remark the above and configure the path to the vRLCM ova file below
#$vrslcmOva = "C:\temp\vrlcm\VMware-vLCM-Appliance-8.4.1.1-18627606_OVF10.ova"


# Connect to vCenter
Connect-VIServer $vcenter -User $vcUser -Password $vcPassword -WarningAction SilentlyContinue
$vmhost = get-cluster $cluster | Get-VMHost | Select-Object -First 1

#vRSLCM OVF Configuration Parameters
$ovfconfig = Get-OvfConfiguration $vrslcmOvaPath
$ovfconfig.Common.vami.hostname.Value = $vrslcmHostname
$ovfconfig.Common.varoot_password.Value = $vrlscmRootPassword
$ovfconfig.Common.va_ssh_enabled.Value = $true
#$ovfconfig.Common.va_firstboot_enabled.Value = $true #default is $true
$ovfconfig.Common.va_telemetry_enabled.Value = $false
$ovfconfig.Common.va_fips_enabled.Value = $false
$ovfconfig.Common.va_ntp_servers.Value = $ntp
#start optional certificate settings
#$ovfconfig.Common.vlcm.cert.commonname.Value = $vrslcmHostname
#$ovfconfig.Common.vlcm.cert.orgname.Value = "infrajedi"
#$ovfconfig.Common.vlcm.cert.orgunit.Value = "local"
#$ovfconfig.Common.vlcm.cert.countrycode.Value = "NL"
#end optional certificate settings
$ovfconfig.vami.VMware_vRealize_Suite_Life_Cycle_Manager_Appliance.gateway.Value = $gateway
$ovfconfig.vami.VMware_vRealize_Suite_Life_Cycle_Manager_Appliance.domain.Value = $domain
$ovfconfig.vami.VMware_vRealize_Suite_Life_Cycle_Manager_Appliance.searchpath.Value = $domain
$ovfconfig.vami.VMware_vRealize_Suite_Life_Cycle_Manager_Appliance.DNS.Value = $dns
$ovfconfig.vami.VMware_vRealize_Suite_Life_Cycle_Manager_Appliance.ip0.Value = $vrslcmIp
$ovfconfig.vami.VMware_vRealize_Suite_Life_Cycle_Manager_Appliance.netmask0.Value = $netmask
$ovfconfig.IpAssignment.IpProtocol.Value = "IPv4" #string["IPv4", "IPv6"]
$ovfconfig.NetworkMapping.Network_1.Value = $network


# Check if vRSCLM VM already exist
if (get-vm -Name $vrslcmVmName -ErrorAction SilentlyContinue){
    Write-Host "Checking if VM $vrslcmVmName exists..." -ForegroundColor black -BackgroundColor Yellow
    Write-Host "VM with name $vrslcmVmName already found. Stopping Deployment" -ForegroundColor White -BackgroundColor Red
    break
}
else {
    Write-Host "VM with name $vrslcmVmName not found, Deployment will continue..." -ForegroundColor White -BackgroundColor DarkGreen
}


# Deploy vRSLCM
Write-Host "Start Deployment of VRSLCM" -ForegroundColor White -BackgroundColor DarkGreen
$vrslcmvm = Import-VApp -Source $vrslcmOvaPath -OvfConfiguration $ovfconfig -Name $vrslcmVmname -Location $cluster -InventoryLocation $vmFolder -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

# Create Snapshot of vRSLCM VM
if ($createSnapshotPreboot -eq $true){
    Write-Host "Create Snapshot before initial PowerOn" -ForegroundColor White -BackgroundColor DarkGreen
    New-Snapshot -VM $vrslcmVmname -Name "vRSLCM Preboot Snapshot"
}



# Start vRSLCM
Write-Host "Starting VRSLCM VM" -ForegroundColor White -BackgroundColor DarkGreen
$vrslcmvm | Start-Vm -RunAsync | Out-Null
do { 
    Write-Host "Waiting for vRLSCM availability..." -ForegroundColor Yellow -BackgroundColor Black
    Start-Sleep -Seconds 5
} until (Test-Connection $vrslcmHostname -Quiet -Count 1) 


### Copy OVA Files to vRSLCM or NFS ###

# Copy VIDM OVA File to vRSLCM or NFS
if ($copyVIDMOVA -eq $true){
    if ($ovaDestinationType -eq "NFS") {
        Write-Host "VIDM OVA will be copied to NFS share $nfsshare" -ForegroundColor White -BackgroundColor DarkGreen
        If (Test-Path ("$nfsshare$vidmOva")){
            Write-Host "VIDM ova File exists and will be renamed" -ForegroundColor black -BackgroundColor Yellow
            Move-Item ("$nfsshare$vidmOva") -Destination ("$nfsshare$vidmOva"+".bak") -Force
            #Remove-Item "$nfsshare\vidm.ova"
        }
        Start-BitsTransfer -source $vidmOvaPath -Destination $nfsshare
    }
    elseif ($ovaDestinationType -eq "VRSLCM") {
        Write-Host "VIDM OVA will be copied to vRSLCM Local disk in /data/temp" -ForegroundColor White -BackgroundColor DarkGreen
        $vRSLCMRootSS = ConvertTo-SecureString -String $vrlscmRootPassword -AsPlainText -Force
        $vRSLCMCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList root, $vRSLCMRootSS
        Set-SCPItem -ComputerName $vrslcmHostname -AcceptKey:$true -Credential $vRSLCMCred -Destination "/data/temp" -Path $vidmOvaPath -Force
    }
}
elseif ($copyVIDMOVA -eq $false) {
    Write-Host "Skip copying VIDM OVA Files" -ForegroundColor black -BackgroundColor Yellow
    }


# Copy vRA OVA File to vRSLCM or NFS
if ($copyvRAOVA -eq $true){
    if ($ovaDestinationType -eq "NFS") {
        Write-Host "vRA OVA will be copied to NFS share $nfsshare" -ForegroundColor White -BackgroundColor DarkGreen
        If (Test-Path ("$nfsshare$vraOva")){
            Write-Host "vRA OVA File exists and will be renamed" -ForegroundColor black -BackgroundColor Yellow
            Move-Item ("$nfsshare$vraOva") -Destination ("$nfsshare$vraOva"+".bak") -Force
        }
        Start-BitsTransfer -source $vraOvaPath -Destination $nfsshare
    }
    elseif ($ovaDestinationType -eq "VRSLCM") {
        Write-Host "vRA OVA will be copied to vRSLCM Local disk in /data/temp" -ForegroundColor White -BackgroundColor DarkGreen
        $vRSLCMRootSS = ConvertTo-SecureString -String $vrlscmRootPassword -AsPlainText -Force
        $vRSLCMCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList root, $vRSLCMRootSS
        Set-SCPItem -ComputerName $vrslcmHostname -AcceptKey:$true -Credential $vRSLCMCred -Destination "/data/temp" -Path $vraOvaPath -Force
    }
}
elseif ($copyvRAOVA -eq $false) {
    Write-Host "Skip copying vRA OVA Files" -ForegroundColor black -BackgroundColor Yellow
    }


# Create Snapshot of vRSLCM VM
if ($createSnapshotOVA -eq $true){
    Write-Host "Create Snapshot with ova files (if selected)" -ForegroundColor White -BackgroundColor DarkGreen
    New-Snapshot -VM $vrslcmVmname -Name "vRSLCM Snapshot" -Description "vRSLCM Snapshot"
}


# Disconnect vCenter
Disconnect-VIServer $vcenter -Confirm:$false


# Unmount ISO
DisMount-DiskImage $vrslcmIso -Confirm:$false |Out-Null

# Note the default admin@local password is "vmware"