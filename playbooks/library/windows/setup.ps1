#!powershell
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

# WANT_JSON
# POWERSHELL_COMMON

# enabled $params (David O'Brien, 06/08/2015)
$params = Parse-Args $args;


Function Get-CustomFacts {
  [cmdletBinding()]
  param (
    [Parameter(mandatory=$false)]
    $factspath = $null
  )

  if (-not (Test-Path -Path $factspath)) {
    Fail-Json $result "The path $factspath does not exist. Typo?"
  }

  $FactsFiles = Get-ChildItem -Path $factspath | Where-Object -FilterScript {($PSItem.PSIsContainer -eq $false) -and ($PSItem.Extension -eq '.ps1')}

  foreach ($FactsFile in $FactsFiles) {
      $out = . $($FactsFile.FullName)
      Set-Attr $result.ansible_facts "ansible_$(($FactsFile.Name).Split('.')[0])" $out
  }
}

$result = New-Object psobject @{
    ansible_facts = New-Object psobject
    changed = $false
};

If ($params.facts_path) {
  $factspath = $params.facts_path
}

$win32_os = Get-CimInstance Win32_OperatingSystem

$osversion = [Environment]::OSVersion
$memory = @()
$memory += Get-WmiObject win32_Physicalmemory
$capacity = 0
$memory | foreach {$capacity += $_.Capacity}
$netcfg = Get-WmiObject win32_NetworkAdapterConfiguration

$ActiveNetcfg = @(); $ActiveNetcfg+= $netcfg | where {$_.ipaddress -ne $null}
$formattednetcfg = @()
foreach ($adapter in $ActiveNetcfg)
{
    $thisadapter = New-Object psobject @{
    interface_name = $adapter.description
    dns_domain = $adapter.dnsdomain
    default_gateway = $null
    interface_index = $adapter.InterfaceIndex
    }

    if ($adapter.defaultIPGateway)
    {
        $thisadapter.default_gateway = $adapter.DefaultIPGateway[0].ToString()
    }

    $formattednetcfg += $thisadapter;$thisadapter = $null
}

Set-Attr $result.ansible_facts "ansible_interfaces" $formattednetcfg

Set-Attr $result.ansible_facts "ansible_architecture" $win32_os.OSArchitecture

Set-Attr $result.ansible_facts "ansible_hostname" $env:COMPUTERNAME;
Set-Attr $result.ansible_facts "ansible_fqdn" "$([System.Net.Dns]::GetHostByName((hostname)).HostName)"
Set-Attr $result.ansible_facts "ansible_system" $osversion.Platform.ToString()
Set-Attr $result.ansible_facts "ansible_os_family" "Windows"
Set-Attr $result.ansible_facts "ansible_os_name" ($win32_os.Name.Split('|')[0]).Trim()
Set-Attr $result.ansible_facts "ansible_distribution" $osversion.VersionString
Set-Attr $result.ansible_facts "ansible_distribution_version" $osversion.Version.ToString()

Set-Attr $result.ansible_facts "ansible_totalmem" $capacity

Set-Attr $result.ansible_facts "ansible_lastboot" $win32_os.lastbootuptime.ToString("u")
Set-Attr $result.ansible_facts "ansible_uptime_seconds" $([System.Convert]::ToInt64($(Get-Date).Subtract($win32_os.lastbootuptime).TotalSeconds))

$ips = @()
Foreach ($ip in $netcfg.IPAddress) { If ($ip) { $ips += $ip } }
Set-Attr $result.ansible_facts "ansible_ip_addresses" $ips

$psversion = $PSVersionTable.PSVersion.Major
Set-Attr $result.ansible_facts "ansible_powershell_version" $psversion

$winrm_https_listener_parent_path = Get-ChildItem -Path WSMan:\localhost\Listener -Recurse | Where-Object {$_.PSChildName -eq "Transport" -and $_.Value -eq "HTTPS"} | select PSParentPath

if ($winrm_https_listener_parent_path ) {
    $winrm_https_listener_path = $winrm_https_listener_parent_path.PSParentPath.Substring($winrm_https_listener_parent_path.PSParentPath.LastIndexOf("\"))
}

if ($winrm_https_listener_path)
{
    $https_listener = Get-ChildItem -Path "WSMan:\localhost\Listener$winrm_https_listener_path"
}

if ($https_listener)
{
    $winrm_cert_thumbprint = $https_listener | where {$_.Name -EQ "CertificateThumbprint" } | select Value
}

if ($winrm_cert_thumbprint)
{
   $uppercase_cert_thumbprint = $winrm_cert_thumbprint.Value.ToString().ToUpper()
}

$winrm_cert_expiry = Get-ChildItem -Path Cert:\LocalMachine\My | where Thumbprint -EQ $uppercase_cert_thumbprint | select NotAfter

if ($winrm_cert_expiry)
{
    Set-Attr $result.ansible_facts "ansible_winrm_certificate_expires" $winrm_cert_expiry.NotAfter.ToString("yyyy-MM-dd HH:mm:ss")
}

# Get any custom facts
Get-CustomFacts -factspath $factspath

Exit-Json $result;
