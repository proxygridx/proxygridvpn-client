# Copyright 2026 ProxyGrid
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Silent install / uninstall check for the ProxyGridVPN Windows installer. Run as Administrator
# on a disposable machine (used by CI on a fresh GitHub-hosted runner). It does not connect a VPN.

param(
  [Parameter(Mandatory = $true)][string]$Installer,
  # Optional: run vpn_session_test.ps1 against this test Shadowsocks server before uninstalling.
  [string]$SessionServerExe = '',
  # Optional: the version that tun2socks.exe, backend.dll and smartdnsblock.exe must report.
  [string]$ExpectedVersion = ''
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]
function Check([string]$name, [scriptblock]$test) {
  try {
    $ok = & $test
  } catch {
    $ok = $false
    Write-Host "  error: $($_.Exception.Message)"
  }
  if ($ok) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name"; $failures.Add($name) }
}
function InstallDir {
  foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
    if ($root -and (Test-Path (Join-Path $root 'ProxyGridVPN\ProxyGridVPN.exe'))) {
      return (Join-Path $root 'ProxyGridVPN')
    }
  }
  return $null
}

Write-Host "Installer: $Installer"
Write-Host "OS: $((Get-CimInstance Win32_OperatingSystem).Caption) $([Environment]::OSVersion.Version)"
if ($ExpectedVersion) {
  Check 'installer product name and version' {
    $vi = (Get-Item $Installer).VersionInfo
    $vi.ProductName -eq 'ProxyGridVPN' -and $vi.ProductVersion -eq $ExpectedVersion
  }
}

$p = Start-Process -FilePath $Installer -ArgumentList '/S' -Wait -PassThru
Write-Host "installer exit code: $($p.ExitCode)"
Check 'installer exits with 0' { $p.ExitCode -eq 0 }

$dir = InstallDir
Check 'app installed' { $null -ne $dir }
if ($dir) {
  Check 'tapctl.exe installed' { Test-Path (Join-Path $dir 'tap-windows6\tapctl.exe') }
  Check 'devcon.exe not installed' { -not (Test-Path (Join-Path $dir 'tap-windows6\devcon.exe')) }
  Check 'routing service files installed' {
    (Test-Path (Join-Path $dir 'OutlineService.exe')) -and (Test-Path (Join-Path $dir 'smartdnsblock.exe'))
  }
  if ($ExpectedVersion) {
    Check 'routing service product name and version' {
      $vi = (Get-Item (Join-Path $dir 'OutlineService.exe')).VersionInfo
      $vi.ProductName -eq 'ProxyGridVPN' -and $vi.ProductVersion -eq $ExpectedVersion
    }
  }
  # Version resources on the Go and C++ binaries (SignPath metadata restrictions rely on them).
  $versioned = @(
    @{ name = 'tun2socks.exe'; desc = 'ProxyGridVPN network tunnel' },
    @{ name = 'backend.dll'; desc = 'ProxyGridVPN backend library' },
    @{ name = 'smartdnsblock.exe'; desc = 'ProxyGridVPN DNS leak protection' }
  )
  foreach ($f in $versioned) {
    Check "$($f.name) version info" {
      $file = Get-ChildItem -Path $dir -Recurse -Filter $f.name -ErrorAction Stop | Select-Object -First 1
      $vi = $file.VersionInfo
      Write-Host "  $($f.name): product=$($vi.ProductName) company=$($vi.CompanyName) description=$($vi.FileDescription) version=$($vi.ProductVersion)/$($vi.FileVersion)"
      $ok = $vi.ProductName -eq 'ProxyGridVPN' -and $vi.CompanyName -eq 'ProxyGrid' -and $vi.FileDescription -eq $f.desc
      if ($ExpectedVersion) { $ok = $ok -and $vi.ProductVersion -eq $ExpectedVersion -and $vi.FileVersion -eq $ExpectedVersion }
      $ok
    }
  }
}
Check 'ProxyGridVPNService installed and running' {
  (Get-Service -Name ProxyGridVPNService -ErrorAction Stop).Status -eq 'Running'
}
Check 'adapter proxygrid-tap0 exists' { $null -ne (Get-NetAdapter -Name 'proxygrid-tap0' -ErrorAction Stop) }
# tun2socks only opens a TAP adapter whose ComponentId is exactly tap0901 (not root\tap0901).
Check 'adapter ComponentId is tap0901' {
  $guid = (Get-NetAdapter -Name 'proxygrid-tap0' -ErrorAction Stop).InterfaceGuid
  $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\*'
  (Get-ItemProperty $class -ErrorAction SilentlyContinue | Where-Object { $_.NetCfgInstanceId -eq $guid }).ComponentId -eq 'tap0901'
}
Check 'adapter address is 10.0.86.2' {
  (Get-NetIPAddress -InterfaceAlias 'proxygrid-tap0' -AddressFamily IPv4 -ErrorAction Stop).IPAddress -contains '10.0.86.2'
}
Check 'adapter DNS is 169.254.113.53' {
  (Get-DnsClientServerAddress -InterfaceAlias 'proxygrid-tap0' -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses -contains '169.254.113.53'
}
Check 'exactly one TAP-Windows6 adapter' {
  @(Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceDescription -like 'TAP-Windows Adapter V9*' }).Count -eq 1
}

if ($dir -and $SessionServerExe) {
  Write-Host "`n=== VPN session test ==="
  & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'vpn_session_test.ps1') -InstallDir $dir -ServerExe $SessionServerExe
  Check 'VPN session test' { $LASTEXITCODE -eq 0 }
  Write-Host "=== end of VPN session test ===`n"
}

if ($dir) {
  # _?= runs the uninstaller in place so -Wait covers the whole uninstall.
  $u = Start-Process -FilePath (Join-Path $dir 'Uninstall ProxyGridVPN.exe') -ArgumentList '/S', "_?=$dir" -Wait -PassThru
  Write-Host "uninstaller exit code: $($u.ExitCode)"
  Check 'uninstaller exits with 0' { $u.ExitCode -eq 0 }
  Start-Sleep -Seconds 5
  Check 'service removed' { $null -eq (Get-Service -Name ProxyGridVPNService -ErrorAction SilentlyContinue) }
  Check 'adapter removed' { $null -eq (Get-NetAdapter -Name 'proxygrid-tap0' -ErrorAction SilentlyContinue) }
  Check 'app removed' { -not (Test-Path (Join-Path $dir 'ProxyGridVPN.exe')) }
}

if ($failures.Count -gt 0) {
  Write-Host "`n$($failures.Count) check(s) failed: $($failures -join '; ')"
  exit 1
}
Write-Host "`nAll checks passed."
