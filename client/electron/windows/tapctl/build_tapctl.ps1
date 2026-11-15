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

# Builds OpenVPN's tapctl.exe (GPL-2.0) from a pinned source commit for x86, x64 and ARM64 and
# places it next to the TAP-Windows6 driver files in third_party/tap-windows6/bin/<arch>/.
# tapctl replaces Microsoft's proprietary devcon.exe: it creates the TAP adapter with our name
# and removes only that adapter on uninstall. Requires Visual Studio 2022 with the C++ x86/x64 and
# ARM64 build tools, and git.
#
#   pwsh client/electron/windows/tapctl/build_tapctl.ps1

$ErrorActionPreference = 'Stop'

# OpenVPN v2.7.9. Update both values together.
$OpenVpnTag = 'v2.7.9'
$OpenVpnCommit = '7b60c2aa34992639691e3a2d651fe27301e2e9d5'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) "proxygridvpn-tapctl-$OpenVpnCommit"
$src = Join-Path $work 'openvpn'

if (-not (Test-Path (Join-Path $src '.git'))) {
  New-Item -ItemType Directory -Force -Path $src | Out-Null
  git -C $src init -q
  git -C $src fetch -q --depth 1 https://github.com/OpenVPN/openvpn.git $OpenVpnCommit
  git -C $src checkout -q FETCH_HEAD
}
$actual = (git -C $src rev-parse HEAD).Trim()
if ($actual -ne $OpenVpnCommit) { throw "OpenVPN checkout is $actual, expected $OpenVpnCommit" }

# tapctl reads three values from OpenVPN's generated config.h.
$cfg = Join-Path $work 'config'
New-Item -ItemType Directory -Force -Path $cfg | Out-Null
@"
#define PACKAGE_NAME "tapctl"
#define PACKAGE_VERSION "$OpenVpnTag (ProxyGridVPN build)"
#define TAP_WIN_COMPONENT_ID "tap0901"
"@ | Set-Content -Encoding ascii (Join-Path $cfg 'config.h')

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw 'Visual Studio with C++ build tools not found' }
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat'

$targets = @(
  @{ vc = 'x86';       dir = 'i386'  },
  @{ vc = 'x86_amd64'; dir = 'amd64' },
  @{ vc = 'x86_arm64'; dir = 'arm64' }
)
$tapSrc = Join-Path $src 'src\tapctl'
foreach ($t in $targets) {
  $out = Join-Path $repoRoot "third_party\tap-windows6\bin\$($t.dir)"
  $obj = Join-Path $work "obj-$($t.dir)"
  New-Item -ItemType Directory -Force -Path $obj | Out-Null
  $cl = "cl /nologo /O2 /W3 /MT /DUNICODE /D_UNICODE /DHAVE_CONFIG_H /D_WIN32_WINNT=0x0600 " +
        "/I`"$cfg`" /I`"$src\include`" /I`"$src\src\compat`" /Fo`"$obj\\`" " +
        "`"$tapSrc\main.c`" `"$tapSrc\tap.c`" `"$tapSrc\error.c`" " +
        "/Fe:`"$out\tapctl.exe`" /link advapi32.lib ole32.lib setupapi.lib newdev.lib cfgmgr32.lib"
  cmd /c "`"$vcvars`" $($t.vc) >nul && $cl"
  if ($LASTEXITCODE -ne 0) { throw "tapctl build failed for $($t.dir)" }
  Write-Host "built $out\tapctl.exe"
}
