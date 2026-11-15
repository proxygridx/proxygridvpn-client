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
$deadline = (Get-Date).AddSeconds(20)
do {
  Start-Sleep -Milliseconds 500
  $ready = Test-NetConnection -ComputerName $serverIp -Port 8488 -InformationLevel Quiet -WarningAction SilentlyContinue
} until ($ready -or (Get-Date) -gt $deadline)
Check 'test server accepts connections' { $ready }

$tun = $null
$script:connectCount = 0
function Connect-Vpn([string]$label) {
  $script:connectCount++
  $script:tunLog = Join-Path $tmp "tun2socks-$($script:connectCount).log"
  # As in the app, the proxy server's address is routed around the tunnel.
  $r = Send-Routing @{ action = 'configureRouting'; parameters = @{ proxyIp = $serverIp; isAutoConnect = 'false' } }
  Check "$label configureRouting succeeds" { $r.statusCode -eq 0 }
  $targs = @('-keyID', 'ci-test', '-tunName', 'proxygrid-tap0', '-tunAddr', '10.0.86.2', '-tunGw', '10.0.86.1',
    '-tunMask', '255.255.255.0', '-tunDNS', '169.254.113.53', '-client', "`"$clientConfig`"", '-logLevel', 'debug')
  if ($r.gatewayAdapterIndex) { $targs += @('-adapterIndex', $r.gatewayAdapterIndex) }
  # Debug logs from the Go libraries (DNS interception, UDP health) go to stderr only with this set.
  $env:OUTLINE_DEBUG = '1'
  $script:tun = Start-Process -FilePath $tun2socks.FullName -ArgumentList $targs `
    -RedirectStandardOutput $script:tunLog -RedirectStandardError "$($script:tunLog).err" -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 5
  Check "$label tun2socks running" { -not $script:tun.HasExited }
}

function Disconnect-Vpn([string]$label) {
  if ($script:tun -and -not $script:tun.HasExited) { Stop-Process -Id $script:tun.Id -Force }
  $r = Send-Routing @{ action = 'resetRouting'; parameters = @{} }
  Check "$label resetRouting succeeds" { $r.statusCode -eq 0 }
  Start-Sleep -Seconds 3
}

# Runs only after a traffic check failed, to record the state behind the failure. It changes no
# check result.
function Show-Diagnostics([string]$label) {
  Write-Host "  --- diagnostics after failed $label checks ---"
  $tapIf = Get-NetAdapter -IncludeHidden -Name 'proxygrid-tap0' -ErrorAction SilentlyContinue
  if ($tapIf) { Write-Host "  adapter: status=$($tapIf.Status) media=$($tapIf.MediaConnectionState) ifIndex=$($tapIf.ifIndex)" }
  Get-NetIPAddress -InterfaceAlias 'proxygrid-tap0' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "  tap address: $($_.IPAddress) state=$($_.AddressState) origin=$($_.PrefixOrigin)" }
  Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object ConnectionState -eq 'Connected' |
    ForEach-Object { Write-Host "  interface: $($_.InterfaceAlias) metric=$($_.InterfaceMetric) dhcp=$($_.Dhcp)" }
  Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object ServerAddresses |
    ForEach-Object { Write-Host "  dns servers: $($_.InterfaceAlias) = $($_.ServerAddresses -join ',')" }
  Get-NetConnectionProfile -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "  profile: $($_.InterfaceAlias) category=$($_.NetworkCategory) ipv4=$($_.IPv4Connectivity)" }
  $s0 = Stats
  $tcpOk = $false
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $tcpOk = $c.ConnectAsync('1.1.1.1', 443).Wait(5000) -and $c.Connected
    $c.Dispose()
  } catch { }
  $s1 = Stats
  Write-Host "  TCP to 1.1.1.1:443 by IP: connected=$tcpOk; server tcp $($s0.tcp) -> $($s1.tcp)"
  foreach ($mode in @('udp', 'tcp')) {
    $t0 = Get-Date
    try {
      if ($mode -eq 'tcp') { $r = Resolve-DnsName -Name 'example.net' -Type A -Server 169.254.113.53 -DnsOnly -TcpOnly -ErrorAction Stop }
      else { $r = Resolve-DnsName -Name 'example.net' -Type A -Server 169.254.113.53 -DnsOnly -QuickTimeout -ErrorAction Stop }
      Write-Host "  DNS over $mode straight to 169.254.113.53: ok in $([int]((Get-Date) - $t0).TotalMilliseconds) ms"
    } catch { Write-Host "  DNS over $mode straight to 169.254.113.53: $($_.Exception.Message)" }
  }
  $s2 = Stats
  Write-Host "  server counters after direct DNS: tcp=$($s2.tcp) dns=$($s2.dns)"
  $start = Get-Date
  $okAt = $null
  while (((Get-Date) - $start).TotalSeconds -lt 60) {
    Clear-DnsClientCache
    try {
      if (Resolve-DnsName -Name 'www.wikipedia.org' -Type A -DnsOnly -QuickTimeout -ErrorAction Stop) { $okAt = ((Get-Date) - $start).TotalSeconds; break }
    } catch { }
    Start-Sleep -Seconds 2
  }
  if ($null -ne $okAt) { Write-Host ("  system DNS started working {0:N0} s after the checks failed" -f $okAt) }
  else { Write-Host '  system DNS still failing after 60 s' }
}

function Test-Traffic([string]$label) {
  $failedBefore = $failures.Count
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
  # smartdnsblock must drop DNS that bypasses the tunnel. Send a query from a socket bound to the
  # physical adapter (which keeps it out of the tunnel) and expect no answer.
  Check "$label DNS from the physical adapter is blocked (UDP to 8.8.8.8)" {
    $udp = New-Object System.Net.Sockets.UdpClient([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($serverIp), 0))
    try {
      $udp.Client.ReceiveTimeout = 3000
      # Standard query for example.org A, id 0x1234.
      [byte[]]$q = 0x12,0x34,0x01,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,7,0x65,0x78,0x61,0x6d,0x70,0x6c,0x65,3,0x6f,0x72,0x67,0,0x00,0x01,0x00,0x01
      [void]$udp.Send($q, $q.Length, '8.8.8.8', 53)
      $from = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
      try { [void]$udp.Receive([ref]$from); $false } catch { $true }
    } finally { $udp.Dispose() }
  }
  if ($failures.Count -gt $failedBefore) { Show-Diagnostics $label }
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
  foreach ($n in 1..$script:connectCount) {
    $log = Join-Path $tmp "tun2socks-$n.log"
    Write-Host "`n--- tun2socks log, connect $n (tail) ---"
    $lines = @(Get-Content "$log.err", $log -ErrorAction SilentlyContinue)
    # The debug log is long: keep the health, DNS and error lines, then the tail.
    $lines | Where-Object { $_ -match 'health|UDP|DNS|dns|relay|level=(WARN|ERROR)' } | Select-Object -First 120
    Write-Host '  ...'
    $lines | Select-Object -Last 20
  }
}

if ($failures.Count -gt 0) { Write-Host "`n$($failures.Count) check(s) failed: $($failures -join '; ')"; exit 1 }
Write-Host "`nAll VPN session checks passed."
