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
# 26 Apr 2023 - Updates for 8.12 release.
# 23 Jun 2023 - Some minor updates and fixes
# 08 Sept 2023 - minor updates and fixes - Renamed variables
# 24 Okt 2023 - Bugfix in .ova copy parts

#Posh-SSH Module is required if you want to copy vra and vidm ova files to vRSLCM appliance
import-module -name Posh-SSH -ErrorAction Stop

#################
### VARIABLES ###
#################
# Path to EasyInstaller ISO
$vrslcmIso = "Z:\VMware\vRealize\vRA8\VMware-Aria-Automation-Lifecycle-Installer-22003350.iso" # "<path to iso file>". See https://kb.vmware.com/s/article/2143850
$copyVIDMOVA = $false # $true | $false
$copyvRAOVA = $false # $true | $false
$ovaDestinationType = "VRSLCM" #VRSLCM or SMB/NFS
    #Choose VRSLCM to copy the OVA files to VRSLCM via SSH
    #Choose NFS to copy the OVA files to SMB/NFS BitsTransfer
$share = "\\192.168.1.20\ISO\VMware\vRealize\latest\" # "<path to SMB/NFS share>"
$createSnapshotPreboot = $true # $true|$false to create a snapshot after initial deployment.
$createSnapshotOVA = $false # $true|$false to create a snapshot after OVA files have been copied to vRSLCM.
# vCenter variables
$vCenterHostname = "vcsamgmt.infrajedi.local" #vcenter FQDN
$vCenterUsername = "administrator@vsphere.local"
$vCenterPassword = "VMware01!" #vCenter password
# General Configuration Parameters
$cluster = "cls-mgmt"
$network = "VMNet1"
$datastore = "DS00-860EVO"
$vrslcmIp = "192.168.1.180" #vRSLCM IP Address
$vrslcmNetmask = "255.255.255.0"
$vrslcmGateway = "192.168.1.1"
$vrslcmDns = "172.16.1.11,172.16.1.12" # DNS Servers, Comma separated
$vrslcmDomain = "infrajedi.local" #dns domain name
$vrslcmVmname = "bvrslcm" #vRSLCM VM Name
$vrslcmHostname = $vrslcmVmname+"."+$vrslcmDomain #joins vmname and domain variable to generate fqdn
$vrlscmRootPassword = "VMware01!" #Note this is the root password, Not the admin@local password which is "vmware" by default
$ntp = "192.168.1.1"
$vmFolder = "vRealize-Beta" #VM Foldername to place the vm.
#$vAppProductname = "VMware_Aria_Suite_Lifecycle_Appliance" #For Pre 8.12 releases, use "VMware_vRealize_Suite_Life_Cycle_Manager_Appliance". #Replaced with dynamic option in the ovf properties part


##########################
# DEPLOYMENT STARTS HERE #
##########################

# Mount the Iso and extract ova paths
# Or Remark the part below and configure the path to the vRLCM ova file
#$vrslcmOva = "C:\temp\vrlcm\VMware-vLCM-Appliance-8.10.0.6-20590142_OVF10.ova"
$mountResult = Mount-DiskImage $vrslcmIso -PassThru -ErrorAction Stop
Start-sleep -Seconds 5
$driveletter = ($mountResult | Get-Volume).DriveLetter
$vrslcmOvaPath = $driveletter + ":\" + "vrlcm\"
$vrslcmOVAFilename = (Get-ChildItem $vrslcmOvaPath\*.ova).Name
$ovaPath = $driveletter + ":\" + "ova\"
$vidmOVAFilename = "vidm.ova"
$vraOVAFilename = "vra.ova"


# Connect to vCenter
Connect-VIServer $vCenterHostname -User $vCenterUsername -Password $vCenterPassword -WarningAction SilentlyContinue
$vmhost = get-cluster $cluster | Get-VMHost | Select-Object -First 1

#vRSLCM OVF Configuration Parameters
$ovfconfig = Get-OvfConfiguration "$vrslcmOVAPath\$vrslcmOVAFilename"
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
$vAppProductname = ($ovfconfig.vami |Get-Member |Where-Object {$_.MemberType -like "CodeProperty"} |Select-Object Name).name
$ovfconfig.vami.$vAppProductname.gateway.Value = $vrslcmGateway
$ovfconfig.vami.$vAppProductname.domain.Value = $vrslcmDomain
#$ovfconfig.vami.$vAppProductname.searchpath.Value = $vrslcmDomain #Not configurable in 8.12
$ovfconfig.vami.$vAppProductname.DNS.Value = $vrslcmDns
$ovfconfig.vami.$vAppProductname.ip0.Value = $vrslcmIp
$ovfconfig.vami.$vAppProductname.netmask0.Value = $vrslcmNetmask
#$ovfconfig.IpAssignment.IpProtocol.Value = "IPv4" #string["IPv4", "IPv6"]    #Not configurable in 8.12
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
$vrslcmvm = Import-VApp -Source "$vrslcmOvaPath\$vrslcmOVAFilename" -OvfConfiguration $ovfconfig -Name $vrslcmVmname -Location $cluster -InventoryLocation $vmFolder -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin -Force -ErrorAction Stop

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
    Start-Sleep -Seconds 5


#######################################    
### Copy OVA Files to vRSLCM or NFS ###
#######################################

# Copy VIDM OVA File to vRSLCM or SMB/NFS
if ($copyVIDMOVA -eq $true){
    if ($ovaDestinationType -eq "NFS") {
        Write-Host "VIDM OVA will be copied to SMB/NFS share $share" -ForegroundColor White -BackgroundColor DarkGreen
        If (Test-Path ("$share$vidmOVAFilename") -PathType Leaf){
            Write-Host "VIDM ova File exists and will be renamed" -ForegroundColor black -BackgroundColor Yellow
            Move-Item ("$share$vidmOVAFilename") -Destination ("$share$vidmOVAFilename"+".bak") -Force
        }
        Start-BitsTransfer -source "$OvaPath$vidmOVAFilename" -Destination $share
    }
    elseif ($ovaDestinationType -eq "VRSLCM") {
        Write-Host "VIDM OVA will be copied to vRSLCM Local disk in /data" -ForegroundColor White -BackgroundColor DarkGreen
        $vRSLCMRootSS = ConvertTo-SecureString -String $vrlscmRootPassword -AsPlainText -Force
        $vRSLCMCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList root, $vRSLCMRootSS
        Set-SCPItem -ComputerName $vrslcmHostname -AcceptKey:$true -Credential $vRSLCMCred -Path "$ovaPath$vidmOVAFilename" -Destination "/data" -Force
    }
}
elseif ($copyVIDMOVA -eq $false) {
    Write-Host "Skip copying VIDM OVA Files" -ForegroundColor black -BackgroundColor Yellow
    }


# Copy vRA OVA File to vRSLCM or NFS
if ($copyvRAOVA -eq $true){
    if ($ovaDestinationType -eq "NFS") {
        Write-Host "vRA OVA will be copied to NFS share $share" -ForegroundColor White -BackgroundColor DarkGreen
        If (Test-Path ("$share$vraOva") -pathtype Leaf){
            Write-Host "vRA OVA File exists and will be renamed" -ForegroundColor black -BackgroundColor Yellow
            Move-Item ("$share$vraOVAFilename") -Destination ("$share$vraOVAFilename"+".bak") -Force
        }
        Start-BitsTransfer -source "$OvaPath$vraOVAFilename" -Destination $share
    }
    elseif ($ovaDestinationType -eq "VRSLCM") {
        Write-Host "vRA OVA will be copied to vRSLCM Local disk in /data" -ForegroundColor White -BackgroundColor DarkGreen
        $vRSLCMRootSS = ConvertTo-SecureString -String $vrlscmRootPassword -AsPlainText -Force
        $vRSLCMCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList root, $vRSLCMRootSS
        Set-SCPItem -ComputerName $vrslcmHostname -AcceptKey:$true -Credential $vRSLCMCred -Path "$ovaPath$vraOVAFilename" -Destination "/data" -Force
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
Disconnect-VIServer $vCenterHostname -Confirm:$false

# Unmount ISO
DisMount-DiskImage $vrslcmIso -Confirm:$false |Out-Null