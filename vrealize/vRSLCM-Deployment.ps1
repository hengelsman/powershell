# Powershell Script to Deploy vRSLCM
# Optionally copy vidm and vra files to configure NFS share
#
# Henk Engelsman - https://www.vtam.nl
# 20 Aug 2021
#
# Import-Module VMware.PowerCLI #

#################
### VARIABLES ###
#################
# Path to EasyInstaller ISO
$vrslcmIso = "C:\Temp\vra-lcm-installer-18488288.iso" # "<path to iso file>"
$copyOVA = $false #Select $true to copy vra and vidm ova files to a NFS Share
$nfsshare = "\\192.168.1.10\data\iso\vRealize\vRA8\latest\" #"<path to NFS share>""
$createSnapshot = $true #Set to $true to create a snapshot after deployment
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
$vrslcmHostname = $vrslcmVmname+"."+$domain #joins vmname and domain to generate fqdn
$vrlscmPassword = "VMware01!" #Note this is the root password, not the admin@local password
$ntp = "192.168.1.1"
$vmFolder = "vRealize-Beta" #VM Foldername to place the vm.


# Mount the Iso and extract ova paths
$mountResult = Mount-DiskImage $vrslcmIso -PassThru
$driveletter = ($mountResult | Get-Volume).DriveLetter
$vrslcmOva = (Get-ChildItem ($driveletter + ":\" + "vrlcm\*.ova")).Name
$vrslcmOvaPath = $driveletter + ":\vrlcm\" + $vrslcmOvaFileName
$vidmOva = "vidm.ova"
$vidmOvaPath = $driveletter+":\ova\"+$vidmOva
$vraOva = "vra.ova"
$vraOvaPath = $driveletter+":\ova\"+$vraOva
# Or Remark the above and configure the path to the vRLCM ova file below
#$vrslcmOva = "D:\vrlcm\VMware-vLCM-Appliance-8.4.1.1-18067607_OVF10.ova"


# Connect to vCenter
Connect-VIServer $vcenter -User $vcUser -Password $vcPassword -WarningAction SilentlyContinue
$vmhost = get-cluster $cluster | Get-VMHost | Select-Object -First 1

#vRSLCM OVF Configuration Parameters
$ovfconfig = Get-OvfConfiguration $vrslcmOva
$ovfconfig.Common.vami.hostname.Value = $vrslcmHostname
$ovfconfig.Common.varoot_password.Value = $vrlscmPassword
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
    Write-Host "Check if VM $vrslcmVmName exists"
    Write-Host "VM with name $vrslcmVmName already found. Stopping Deployment" -ForegroundColor White -BackgroundColor Red
    break
}
else {
    Write-Host "VM with name $$vrslcmVmName not found, Deployment will continue..." -ForegroundColor White -BackgroundColor DarkGreen
}


# Deploy vRSLCM
Write-Host "Start Deployment of VRSLCM"
$vrslcmvm = Import-VApp -Source $vrslcmOvaPath -OvfConfiguration $ovfconfig -Name $vrslcmVmname -Location $cluster -InventoryLocation $vmFolder -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

# Create Snapshot if configured and start vRSLCM VM
#Note the admin@local password defaults to "vmware"
if ($createSnapshot -eq $true){
    Write-Host "Create Pre Firstboot Snapshot"
    New-Snapshot -VM $vrslcmVmname -Name "Pre Firstboot Snapshot"
}
Write-Host "Starting VRSLCM VM"
$vrslcmvm | Start-Vm -RunAsync | Out-Null

# Disconnect vCenter
Disconnect-VIServer $vcenter -Confirm:$false

# Copy OVA files to NFS Share if selected. Existing files will be renamed.
if ($copyOVA -eq $true){
    Write-Host "VIDM and vRA OVA Files will be copied to $nfsshare" -BackgroundColor Green -ForegroundColor black
    If (Test-Path ("$nfsshare$vidmOva")){
        Write-Host "VIDM ova File exists and will be renamed" -BackgroundColor Yellow -ForegroundColor black
        Move-Item ("$nfsshare$vidmOva") -Destination ("$nfsshare$vidmOva"+".bak") -Force
        #Remove-Item "$nfsshare\vidm.ova"
        Start-BitsTransfer -source $vidmOvaPath -Destination $nfsshare
    }
    If (Test-Path ("$nfsshare$vraOva")){
        Write-Host "vRA ova File exists and will be renamed" -BackgroundColor Yellow -ForegroundColor black
        Move-Item ("$nfsshare$vraOva") -Destination ("$nfsshare$vraOva"+".bak") -Force
        #Remove-Item "$nfsshare\vra.ova"
        Start-BitsTransfer -source $vraOvaPath -Destination $nfsshare
    }
}
    elseif ($copyOVA -eq $false) {
    Write-Host "Skip copying VIDM and vRA OVA Files to NFS" -BackgroundColor Green -ForegroundColor black
    }

# Unmount ISO
DisMount-DiskImage $vrslcmIso -Confirm:$false |Out-Null
