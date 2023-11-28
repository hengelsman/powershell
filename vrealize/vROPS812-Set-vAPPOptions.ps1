# Aria / vRealize Operations 8.12 - enable vAPP Options, configure OVF Properties
#
# https://www.vtam.nl/
#
# Update 24/nov/2023 - Added InstanceId Variable, added FIPS option
#
# You can retrieve existing vAPP options with: # (get-vm bvidm |get-view).config.VAppConfig.Property
#$bvrops = (get-vm bvrops |get-view).config.VAppConfig.Property

#Variables
$vcenter = "vcsamgmt.infrajedi.local"
$vmname = "bvrops-clone"
$vAppProductname = "vRealize Operations Appliance"
$InstanceId = "vRealize_Operations_Appliance"

$vamitimezone = "Etc/UTC" # See #0. ADD TimeZone Property for options
$ForceIPv6 = $false
$fipsenabled = $false
$sshPriventDisable = $true
$vamigateway = "192.168.1.1"
$vamidomain = "infrajedi.local"
$vamisearchpath = "infrajedi.local"
$vamidns = "172.16.1.11,172.16.1.12"
$vamiip = "192.168.1.187"
$vaminetmask = "255.255.255.0"

#Connect
Connect-VIServer $vcenter

#Change Guest OS from SUSE Linux to Other3x
#Optional if you have started with an older version of VIDM
#get-vm $vmname |set-vm -GuestId "other3xLinux64Guest" -Confirm:$false




# Enable vAPP Options
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Product = New-Object VMware.Vim.VAppProductSpec[] (1)
$spec.VAppConfig.Product[0] = New-Object VMware.Vim.VAppProductSpec
$spec.VAppConfig.Product[0].Operation = 'add'
$spec.VAppConfig.Product[0].Info = New-Object VMware.Vim.VAppProductInfo
$spec.VAppConfig.Product[0].Info.Vendor = 'VMware Inc.'
$spec.VAppConfig.Product[0].Info.Name = $vAppProductname
$spec.VAppConfig.Product[0].Info.Key = -1
$spec.VAppConfig.OvfEnvironmentTransport = New-Object String[] (1)
$spec.VAppConfig.OvfEnvironmentTransport[0] = 'com.vmware.guestInfo'
$spec.VAppConfig.InstallBootRequired = $false
$spec.VAppConfig.InstallBootStopDelay = 0
$spec.VAppConfig.IpAssignment = New-Object VMware.Vim.VAppIPAssignmentInfo
$spec.VAppConfig.IpAssignment.IpProtocol = 'IPv4'
$spec.VAppConfig.IpAssignment.SupportedIpProtocol = New-Object String[] (2)
$spec.VAppConfig.IpAssignment.SupportedIpProtocol[0] = 'IPv4'
$spec.VAppConfig.IpAssignment.SupportedIpProtocol[1] = 'IPv6'
$spec.VAppConfig.IpAssignment.IpAllocationPolicy = 'fixedPolicy'
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

###########################
# ADD VIDM OVF Properties #
###########################

#0. ADD TimeZone Property
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = ''
$spec.VAppConfig.Property[0].Info.InstanceId = ''
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = "Etc/UTC"
$spec.VAppConfig.Property[0].Info.Description = 'Sets the selected timezone.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'vamitimezone'
$spec.VAppConfig.Property[0].Info.Label = 'Timezone setting'
$spec.VAppConfig.Property[0].Info.Category = 'Application'
#$spec.VAppConfig.Property[0].Info.Type = 'string["Pacific/Samoa", "US/Hawaii", "US/Alaska", "US/Pacific", "US/Mountain", "US/Central", "US/Eastern", "America/Caracas", "America/Argentina/Buenos_Aires", "America/Recife", "Etc/GMT-1", "Etc/UTC", "Europe/London", "Europe/Paris","Africa/Cairo", "Europe/Moscow", "Asia/Baku", "Asia/Karachi", "Asia/Calcutta", "Asia/Dacca", "Asia/Bangkok", "Asia/Hong_Kong", "Asia/Tokyo", "Australia/Sydney", "Pacific/Noumea", "Pacific/Fiji"]'
$spec.VAppConfig.Property[0].Info.Value = "Etc/UTC"
$spec.VAppConfig.Property[0].Info.Value = $vamitimezone
$spec.VAppConfig.Property[0].Info.Key = 0
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#1. Force IPv6
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = ''
$spec.VAppConfig.Property[0].Info.InstanceId = ''
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = $false
$spec.VAppConfig.Property[0].Info.Description = 'Use IPv6. If IPv6 is not available configuration will not succeed.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'forceIpv6'
$spec.VAppConfig.Property[0].Info.Label = 'IPv6'
$spec.VAppConfig.Property[0].Info.Category = 'Application'
$spec.VAppConfig.Property[0].Info.Type = 'boolean'
$spec.VAppConfig.Property[0].Info.Value = $ForceIPv6
$spec.VAppConfig.Property[0].Info.Key = 0
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#2. Enable FIPS setting
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = ''
$spec.VAppConfig.Property[0].Info.InstanceId = ''
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = $false
$spec.VAppConfig.Property[0].Info.Description = 'Enabling FIPS mode'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'enableFIPS'
$spec.VAppConfig.Property[0].Info.Label = 'FIPS'
$spec.VAppConfig.Property[0].Info.Category = 'Application'
$spec.VAppConfig.Property[0].Info.Type = 'boolean'
$spec.VAppConfig.Property[0].Info.Value = $fipsenabled
$spec.VAppConfig.Property[0].Info.Key = 2
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#3. Prevent disabling of SSH
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = ''
$spec.VAppConfig.Property[0].Info.InstanceId = ''
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = $false
$spec.VAppConfig.Property[0].Info.Description = 'Ensure that sshd is configured and running. WARNING: Using this option will result in a less than fully secure installation.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'guestinfo.cis.appliance.ssh.enabled'
$spec.VAppConfig.Property[0].Info.Label = 'Prevent disabling of SSH'
$spec.VAppConfig.Property[0].Info.Category = 'Optional Properties'
$spec.VAppConfig.Property[0].Info.Type = 'boolean'
$spec.VAppConfig.Property[0].Info.Value = $sshPriventDisable
$spec.VAppConfig.Property[0].Info.Key = 3
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#4. ADD Default Gateway Property
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = 'vami'
$spec.VAppConfig.Property[0].Info.InstanceId = $InstanceId
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = ''
$spec.VAppConfig.Property[0].Info.Description = 'The default gateway address for this VM.  Leave blank if DHCP is desired.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'gateway'
$spec.VAppConfig.Property[0].Info.Label = 'Default Gateway'
$spec.VAppConfig.Property[0].Info.Category = 'Networking Properties'
$spec.VAppConfig.Property[0].Info.Type = 'string'
$spec.VAppConfig.Property[0].Info.Value = $vamigateway
$spec.VAppConfig.Property[0].Info.Key = 4
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#5. ADD Domain Name Property
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = 'vami'
$spec.VAppConfig.Property[0].Info.InstanceId = $InstanceId
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = ''
$spec.VAppConfig.Property[0].Info.Description = 'The domain name of this VM. Leave blank if DHCP is desired.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'domain'
$spec.VAppConfig.Property[0].Info.Label = 'Domain Name'
$spec.VAppConfig.Property[0].Info.Category = 'Networking Properties'
$spec.VAppConfig.Property[0].Info.Type = 'string'
$spec.VAppConfig.Property[0].Info.Value = $vamidomain
$spec.VAppConfig.Property[0].Info.Key = 5
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#6. ADD VAMI Search Path Property
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = 'vami'
$spec.VAppConfig.Property[0].Info.InstanceId = $InstanceId
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = ''
$spec.VAppConfig.Property[0].Info.Description = 'The domain search path (comma or space separated domain names) for this VM. Leave blank if DHCP is desired.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'searchpath'
$spec.VAppConfig.Property[0].Info.Label = 'Domain Search Path'
$spec.VAppConfig.Property[0].Info.Category = 'Networking Properties'
$spec.VAppConfig.Property[0].Info.Type = 'string'
$spec.VAppConfig.Property[0].Info.Value = $vamisearchpath
$spec.VAppConfig.Property[0].Info.Key = 6
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#7. ADD VAMI DNS Property
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = 'vami'
$spec.VAppConfig.Property[0].Info.InstanceId = $InstanceId
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = ''
$spec.VAppConfig.Property[0].Info.Description = 'The domain name servers for this VM (comma separated).  Leave blank if DHCP is desired.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'DNS'
$spec.VAppConfig.Property[0].Info.Label = 'Domain Name Servers'
$spec.VAppConfig.Property[0].Info.Category = 'Networking Properties'
$spec.VAppConfig.Property[0].Info.Type = 'string'
$spec.VAppConfig.Property[0].Info.Value = $vamidns
$spec.VAppConfig.Property[0].Info.Key = 7
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#8. ADD VAMI IP Property
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = 'vami'
$spec.VAppConfig.Property[0].Info.InstanceId = $InstanceId
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = ''
$spec.VAppConfig.Property[0].Info.Description = 'The IP address for this interface.  Leave blank if DHCP is desired.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'ip0'
$spec.VAppConfig.Property[0].Info.Label = 'Network 1 IP Address'
$spec.VAppConfig.Property[0].Info.Category = 'Networking Properties'
$spec.VAppConfig.Property[0].Info.Type = 'string'
$spec.VAppConfig.Property[0].Info.Value = $vamiip
$spec.VAppConfig.Property[0].Info.Key = 8
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#9. ADD VAMI Netmask Property
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = 'vami'
$spec.VAppConfig.Property[0].Info.InstanceId = $InstanceId
$spec.VAppConfig.Property[0].Info.UserConfigurable = $true
$spec.VAppConfig.Property[0].Info.DefaultValue = ''
$spec.VAppConfig.Property[0].Info.Description = 'The netmask or prefix for this interface.  Leave blank if DHCP is desired.'
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'netmask0'
$spec.VAppConfig.Property[0].Info.Label = 'Network 1 Netmask'
$spec.VAppConfig.Property[0].Info.Category = 'Networking Properties'
$spec.VAppConfig.Property[0].Info.Type = 'string'
$spec.VAppConfig.Property[0].Info.Value = $vaminetmask
$spec.VAppConfig.Property[0].Info.Key = 9
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)

#10. ADD VAMI VMName Property
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$spec.VAppConfig.Property = New-Object VMware.Vim.VAppPropertySpec[] (1)
$spec.VAppConfig.Property[0] = New-Object VMware.Vim.VAppPropertySpec
$spec.VAppConfig.Property[0].Operation = 'add'
$spec.VAppConfig.Property[0].Info = New-Object VMware.Vim.VAppPropertyInfo
$spec.VAppConfig.Property[0].Info.ClassId = 'vm'
$spec.VAppConfig.Property[0].Info.InstanceId = ''
$spec.VAppConfig.Property[0].Info.UserConfigurable = $false
$spec.VAppConfig.Property[0].Info.DefaultValue = $InstanceId
$spec.VAppConfig.Property[0].Info.Description = ''
$spec.VAppConfig.Property[0].Info.TypeReference = ''
$spec.VAppConfig.Property[0].Info.Id = 'vmname'
$spec.VAppConfig.Property[0].Info.Label = 'vmname'
$spec.VAppConfig.Property[0].Info.Category = ''
$spec.VAppConfig.Property[0].Info.Type = 'string'
$spec.VAppConfig.Property[0].Info.Value = ''
$spec.VAppConfig.Property[0].Info.Key = 10
$_this = Get-View (get-vm -Name $vmname)
$_this.ReconfigVM_Task($spec)




disConnect-VIServer $vcenter -Confirm:$false