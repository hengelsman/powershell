# Powershell Script to Deploy vRSLCM
# Optionally copy vidm and vra OVA files to vRSLCM or NFS share
#
# Henk Engelsman - https://www.vtam.nl
# For vRA buildnumbers see https://kb.vmware.com/s/article/2143850
# 20 Aug 2021
# 19 Nov 2021 - Updated for 8.6.1 release - vra-lcm-installer-18940322.iso
# - bugfix for ova copy
# 22 Jan 2022 - Updated for 8.6.2 release - vra-lcm-installer-19221692.iso
# 22 March 2022 - Updated for 8.7.0 Release - vra-lcm-installer-19527797.iso
# - Added option to copy source OVA to NFS share or vRSLCM Appliance (Requires Posh-SSH module)
# 11 April 2022 - Added second snapshot creation option
# 29 April 2022 - Updated for 8.8.0 Release - vra-lcm-installer-19716706.iso
# 07 October 2022 - Updated for 8.10.0 Release - vra-lcm-installer-20590145.iso
# - Added force option on import-vapp cmd
# 21 Jan 2022 - Minor Updates for 8.11 release

#Posh-SSH Module is required if you want to copy vra and vidm ova files to vRSLCM appliance
import-module -name Posh-SSH -ErrorAction Stop

#################
### VARIABLES ###
#################
# Path to EasyInstaller ISO
$vrslcmIso = "Y:\vRealize\vRA8\vra-lcm-installer-21329473.iso" # "<path to iso file>". See https://kb.vmware.com/s/article/2143850
$copyVIDMOVA = $true # $true | $false
$copyvRAOVA = $false # $true | $false
$ovaDestinationType = "VRSLCM" #VRSLCM or NFS
    #Choose VRSLCM to copy the OVA files to VRSLCM via SSH
    #Choose NFS to copy the OVA files to SMB/NFS BitsTransfer
$nfsshare = "\\192.168.1.10\ssd1\ISO2\vRealize\latest\" # "<path to SMB/NFS share>"
$createSnapshotPreboot = $false # $true|$false to create a snapshot after initial deployment.
$createSnapshotOVA = $false # $true|$false to create a snapshot after OVA files have been copied to vRSLCM.

# vCenter variables
$vcenter = "vcsamgmt.infrajedi.local" #vcenter FQDN
$vcUser = "administrator@vsphere.local"
$vcPassword = "VMware01!" #vCenter password
# General Configuration Parameters
$cluster = "cls-mgmt"
$network = "VMNet1"
$datastore = "DS02-870EVO" #vSphere Datastore to use for deployment
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
# Or Remark the part below and configure the path to the vRLCM ova file
#$vrslcmOva = "C:\temp\vrlcm\VMware-vLCM-Appliance-8.10.0.6-20590142_OVF10.ova"
$mountResult = Mount-DiskImage $vrslcmIso -PassThru -ErrorAction Stop
Start-sleep -Seconds 5
$driveletter = ($mountResult | Get-Volume).DriveLetter
$vrslcmOva = (Get-ChildItem ($driveletter + ":\" + "vrlcm\*.ova")).Name
$vrslcmOvaPath = $driveletter + ":\vrlcm\" + $vrslcmOva
$vidmOva = "vidm.ova"
$vidmOvaPath = $driveletter+":\ova\"+$vidmOva
$vraOva = "vra.ova"
$vraOvaPath = $driveletter+":\ova\"+$vraOva


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
$vrslcmvm = Import-VApp -Source $vrslcmOvaPath -OvfConfiguration $ovfconfig -Name $vrslcmVmname -Location $cluster -InventoryLocation $vmFolder -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin -Force -ErrorAction Stop

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
        Write-Host "VIDM OVA will be copied to vRSLCM Local disk in /data" -ForegroundColor White -BackgroundColor DarkGreen
        $vRSLCMRootSS = ConvertTo-SecureString -String $vrlscmRootPassword -AsPlainText -Force
        $vRSLCMCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList root, $vRSLCMRootSS
        Set-SCPItem -ComputerName $vrslcmHostname -AcceptKey:$true -Credential $vRSLCMCred -Destination "/data" -Path $vidmOvaPath -Force
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
        Write-Host "vRA OVA will be copied to vRSLCM Local disk in /data" -ForegroundColor White -BackgroundColor DarkGreen
        $vRSLCMRootSS = ConvertTo-SecureString -String $vrlscmRootPassword -AsPlainText -Force
        $vRSLCMCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList root, $vRSLCMRootSS
        Set-SCPItem -ComputerName $vrslcmHostname -AcceptKey:$true -Credential $vRSLCMCred -Destination "/data" -Path $vraOvaPath -Force
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

# Note the default username/password for vRSLCM is admin@local password is "vmware"