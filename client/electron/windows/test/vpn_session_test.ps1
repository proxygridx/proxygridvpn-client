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

# VPN session test for an installed ProxyGridVPN, run as Administrator on a disposable machine
# (CI uses a fresh GitHub-hosted runner). It drives the installed tun2socks.exe and the
# ProxyGridVPNService routing service the same way the app does, against a local test
# Shadowsocks server with a throwaway secret, and checks routing, TCP, DNS, the DNS-leak block,
# disconnect and reconnect. It does not exercise the app's user interface.

param(
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$ServerExe
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]
function Check([string]$name, [scriptblock]$test) {
  try { $ok = & $test } catch { $ok = $false; Write-Host "  error: $($_.Exception.Message)" }
  if ($ok) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name"; $failures.Add($name) }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) 'pgvpn-session-test'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$serverLog = Join-Path $tmp 'server.log'
$tunLog = Join-Path $tmp 'tun2socks.log'

# Throwaway secret for the local test server only.
$secret = -join ((1..32) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
$userInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("chacha20-ietf-poly1305:$secret")).TrimEnd('=').Replace('+', '-').Replace('/', '_')
# tun2socks binds its sockets to the physical adapter (to keep them out of the tunnel), and a socket
# bound there cannot reach 127.0.0.1. Run the test server on this machine's own address on the
# default-route adapter instead, like a real server outside the tunnel.
$serverIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
  Select-Object -First 1).IPv4Address.IPAddress
if (-not $serverIp) { throw 'no IPv4 address on the default-route adapter' }
Write-Host "  test server address: $serverIp"
$clientConfig = "transport: ss://$userInfo@${serverIp}:8488"

function Stats {
  $line = Get-Content $serverLog -ErrorAction SilentlyContinue | Where-Object { $_ -like 'STATS *' } | Select-Object -Last 1
  $s = @{ tcp = 0; udp = 0; dns = 0 }
  if ($line) { foreach ($kv in ($line -replace '^STATS ', '').Split(' ')) { $k, $v = $kv.Split('='); $s[$k] = [int]$v } }
  return $s
}

function Send-Routing([hashtable]$request) {
  $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'ProxyGridVPNServicePipe', [System.IO.Pipes.PipeDirection]::InOut)
  $pipe.Connect(15000)
  $pipe.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Message
  $bytes = [Text.Encoding]::UTF8.GetBytes(($request | ConvertTo-Json -Compress))
  $pipe.Write($bytes, 0, $bytes.Length)
  $pipe.Flush()
  $buf = New-Object byte[] 65536
  $ms = New-Object IO.MemoryStream
  do { $n = $pipe.Read($buf, 0, $buf.Length); $ms.Write($buf, 0, $n) } while (-not $pipe.IsMessageComplete)
  $pipe.Dispose()
  $text = [Text.Encoding]::UTF8.GetString($ms.ToArray()).Trim([char]0)
  Write-Host "  service: $text"
  return ($text | ConvertFrom-Json)
}

$tun2socks = Get-ChildItem -Path (Join-Path $InstallDir 'resources') -Recurse -Filter tun2socks.exe | Select-Object -First 1
Check 'installed tun2socks.exe found' { $null -ne $tun2socks }

New-NetFirewallRule -DisplayName 'ProxyGridVPN CI test server' -Direction Inbound -Action Allow `
  -Program $ServerExe -Profile Any | Out-Null
$server = Start-Process -FilePath $ServerExe -ArgumentList '-listen', "${serverIp}:8488", '-secret', $secret `
  -RedirectStandardOutput $serverLog -RedirectStandardError (Join-Path $tmp 'server.err') -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2

$tun = $null
function Connect-Vpn([string]$label) {
  # As in the app, the proxy server's address is routed around the tunnel.
  $r = Send-Routing @{ action = 'configureRouting'; parameters = @{ proxyIp = $serverIp; isAutoConnect = 'false' } }
  Check "$label configureRouting succeeds" { $r.statusCode -eq 0 }
  $targs = @('-keyID', 'ci-test', '-tunName', 'proxygrid-tap0', '-tunAddr', '10.0.86.2', '-tunGw', '10.0.86.1',
    '-tunMask', '255.255.255.0', '-tunDNS', '169.254.113.53', '-client', "`"$clientConfig`"", '-logLevel', 'debug')
  if ($r.gatewayAdapterIndex) { $targs += @('-adapterIndex', $r.gatewayAdapterIndex) }
  $script:tun = Start-Process -FilePath $tun2socks.FullName -ArgumentList $targs `
    -RedirectStandardOutput $tunLog -RedirectStandardError "$tunLog.err" -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 5
  Check "$label tun2socks running" { -not $script:tun.HasExited }
}

function Disconnect-Vpn([string]$label) {
  if ($script:tun -and -not $script:tun.HasExited) { Stop-Process -Id $script:tun.Id -Force }
  $r = Send-Routing @{ action = 'resetRouting'; parameters = @{} }
  Check "$label resetRouting succeeds" { $r.statusCode -eq 0 }
  Start-Sleep -Seconds 3
}

function Test-Traffic([string]$label) {
  $before = Stats
  Check "$label default route uses the tunnel (0.0.0.0/1 via proxygrid-tap0)" {
    $null -ne (Get-NetRoute -DestinationPrefix '0.0.0.0/1' -ErrorAction Stop | Where-Object { $_.InterfaceAlias -eq 'proxygrid-tap0' })
  }
  Check "$label HTTPS request succeeds" {
    (Invoke-WebRequest -Uri 'https://www.example.com/' -UseBasicParsing -TimeoutSec 30).StatusCode -eq 200
  }
  Check "$label DNS lookup succeeds" { $null -ne (Resolve-DnsName -Name 'www.wikipedia.org' -Type A -DnsOnly -QuickTimeout -ErrorAction Stop) }
  Start-Sleep -Seconds 3
  $after = Stats
  Write-Host "  server counters before: tcp=$($before.tcp) dns=$($before.dns); after: tcp=$($after.tcp) dns=$($after.dns)"
  Check "$label TCP went through the Shadowsocks server" { $after.tcp -gt $before.tcp }
  Check "$label DNS went through the Shadowsocks server" { $after.dns -gt $before.dns }
  Check "$label DNS outside the tunnel is blocked (UDP to 8.8.8.8)" {
    try { Resolve-DnsName -Name 'example.org' -Server 8.8.8.8 -DnsOnly -QuickTimeout -ErrorAction Stop | Out-Null; $false } catch { $true }
  }
}

try {
  Connect-Vpn 'connect:'
  Test-Traffic 'connected:'
  Disconnect-Vpn 'disconnect:'
  Check 'disconnected: tunnel route removed' {
    $null -eq (Get-NetRoute -DestinationPrefix '0.0.0.0/1' -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -eq 'proxygrid-tap0' })
  }
  Check 'disconnected: direct HTTPS works' { (Invoke-WebRequest -Uri 'https://www.example.com/' -UseBasicParsing -TimeoutSec 30).StatusCode -eq 200 }
  Check 'disconnected: direct DNS works again' { $null -ne (Resolve-DnsName -Name 'example.org' -Server 8.8.8.8 -DnsOnly -QuickTimeout -ErrorAction Stop) }

  Connect-Vpn 'reconnect:'
  Test-Traffic 'reconnected:'
  Disconnect-Vpn 'final disconnect:'
} finally {
  if ($tun -and -not $tun.HasExited) { Stop-Process -Id $tun.Id -Force }
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  Remove-NetFirewallRule -DisplayName 'ProxyGridVPN CI test server' -ErrorAction SilentlyContinue
  Write-Host "`n--- tun2socks log (tail) ---"; Get-Content "$tunLog.err", $tunLog -ErrorAction SilentlyContinue | Select-Object -Last 40
}

if ($failures.Count -gt 0) { Write-Host "`n$($failures.Count) check(s) failed: $($failures -join '; ')"; exit 1 }
Write-Host "`nAll VPN session checks passed."
