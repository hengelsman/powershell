# Deploy vRSLCM
#   Optional copy vidm and vra files to NFS share
#
# Henk Engelsman
# 14 Aug 2021

#################
### VARIABLES ###
#################
# Path to EasyInstaller ISO
$vrslcmIso = "<path to iso file>" #"C:\Temp\vra-lcm-installer-18067628.iso"
$copyOVA = $true #Select $true or $false to copy vra and vidm files to a NFS Share
$nfsshare = "<path to NFS share>" #"\\192.168.1.10\data\iso\vRealize\vRA8\latest\"
#vcenter variables
$vcenter = "<vcenter FQDN>" #vcsamgmt.infrajedi.local"
$vcUser = "administrator@vsphere.local"
$vcPassword = "<password>"
# General Configuration Parameters
$cluster = "cls-mgmt"
$network = "VMNet1"
$datastore = "<Datastore Name>"
$vrslcmIp = "<vRSLCM IP Address>"
$netmask = "<subnetmask>"
$gateway = "<gateway>"
$dns = "<dns1,dns2>" #DNS Servers, Comma separated "192.168.1.11,192.168.1.12"
$domain = "<dns domain name>" # infrajedi.local
$vrslcmVmname = "vrslcm" #vRSLCM VM Name
$vrslcmHostname = $vrslcmVmname+"."+$domain #joins vmname and domain to generate fqdn
$vrlscmPassword = "VMware01!" #Note this is the root password, not the admin@local password
$ntp = "<ntpserver>"
$vmFolder = "<vCenter VM Foldername>" #VM Foldername to place the vm


#Mount the Iso and extract ova paths
$mountResult = Mount-DiskImage $vrslcmIso -PassThru
$driveletter = ($mountResult | Get-Volume).DriveLetter
$vrslcmOvaFileName = (Get-ChildItem ($driveletter + ":\" + "vrlcm\*.ova")).Name
$vrslcmOva = $driveletter + ":\vrlcm\" + $vrslcmOvaFileName
$vidmOva = $driveletter + ":\" + "ova\vidm.ova"
$vraOva = $driveletter + ":\" + "ova\vra.ova"
#Or Remark the above and configure the path to the vRLCM ova file below
#$vrslcmOva = "D:\vrlcm\VMware-vLCM-Appliance-8.4.1.1-18067607_OVF10.ova"


#connect to vCenter
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


#Deploying vRSLCM OVA
Write-Host "Start Deployment of VRSLCM"
$vrslcmvm = Import-VApp -Source $vrslcmOva -OvfConfiguration $ovfconfig -Name $vrslcmVmname -Location $cluster -InventoryLocation $vmFolder -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

#Start vRSLCM VM
Write-Host "Start VRSLCM VM"
$vrslcmvm | Start-Vm -RunAsync | Out-Null
#Note the admin@local password defaults to "vmware"

#Disconnect vCenter
Disconnect-VIServer $vcenter -Confirm:$false

#Copy OVA files to NFS Share if selected
if ($copyOVA -eq $true){
    Write-Host "VIDM and vRA OVA Files will be copied to $nfsshare"
    Start-BitsTransfer -source $vidmOva -Destination $nfsshare
    Start-BitsTransfer -source $vraOva -Destination $nfsshare
    }
elseif ($copyOVA -eq $false) {
    Write-Host "Skip copying VIDM and vRA OVA Files to NFS"
}

#Unmount ISO
DisMount-DiskImage $vrslcmIso -Confirm:$false |Out-Null
