# Script to Enable custom Names on vRA 8.6.1 with PowervRA
# Please be aware this is a beta feature for this release.
# The existing custom naming on project level is removed after enabling.
# This can break your current scripting to setup projects.
# Reachout to VMware Global Support for assistance
#
# Henk Engelsman
# 2021/11/26
#
#

import-module Powervra

# Variables
$vraName = "vra"
$domain = "infrajedi.local"
$vraHostname = $vraname+"."+$domain
$vraUsername = "configadmin"
$vraPassword = "VMware01!" #note use ` as escape character for special chars like $
#$vraUserDomain = "System Domain" #Use "System Domain" for local users", otherwise use the AD domain.
$vraPasswordSS = ConvertTo-SecureString -String $vraPassword -AsPlainText -Force
$vRACredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $vraUsername, $vraPasswordSS
$vRAConnection = Connect-vRAServer -Server $vraHostname -Credential $vRACredential -IgnoreCertRequirements

###########################
# Enable custom hostnames #
###########################
$uri = "/provisioning/config/toggles"
$data = @"
{
    "key": "enable.custom.naming",
    "value": "true"
}
"@
Invoke-vRARestMethod -Method PATCH -URI $uri -Body $data

Disconnect-vRAServer -Confirm:$false

