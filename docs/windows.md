# ProxyGridVPN on Windows

## Install

1. Download `ProxyGridVPN-<version>-ia32.exe` (most PCs, including 64-bit Intel and AMD) or
   `ProxyGridVPN-<version>-arm64.exe` (Windows on ARM) from
   [Releases](https://github.com/proxygridx/proxygridvpn-client/releases). Windows 10 or 11 is
   required.
2. [Verify the download](#verify-a-download).
3. Run the installer. Its first page explains what it changes and which network connections the
   app makes; then accept the administrator prompt.

### What the installer changes

The installer needs administrator rights because a VPN changes system networking. It:

- installs the app in `C:\Program Files\ProxyGridVPN`;
- adds the TAP-Windows6 virtual network driver (signed by Microsoft for OpenVPN) with the
  built-in `pnputil`, and creates one adapter named `proxygrid-tap0` with OpenVPN's `tapctl`.
  Windows may ask you to confirm the driver;
- installs the `ProxyGridVPNService` Windows service, which sets routes and DNS while the VPN is
  connected and restores them when it disconnects;
- adds Start menu and desktop shortcuts and the `proxygridvpn://` link handler.

It does not change anything else. The names above are different from the official Outline
app, so both can be installed at the same time.

## Uninstall

1. Open **Settings > Apps > Installed apps**, find **ProxyGridVPN** and choose **Uninstall** (or
   run `Uninstall ProxyGridVPN.exe` in the install folder). This removes the app and stops and
   deletes the `ProxyGridVPNService` service.
2. The uninstaller also removes the `proxygrid-tap0` network adapter, and only that adapter;
   other apps' TAP-Windows6 adapters are left alone. The TAP-Windows6 driver package stays in
   the Windows driver store, because other apps (such as OpenVPN or Outline) may use it. To
   remove it, run `pnputil /enum-drivers`, find the `oemNN.inf` whose original name is
   `oemvista.inf` from provider TAP-Windows Provider V9, and run `pnputil /delete-driver oemNN.inf`.
   If an adapter is left behind (for example after an interrupted uninstall), open
   **Device Manager > Network adapters**, right-click the TAP-Windows Adapter V9 named
   `proxygrid-tap0`, and choose **Uninstall device**.
3. To delete saved keys and settings, delete the folders `%APPDATA%\ProxyGridVPN` and `%APPDATA%\net.proxygrid.vpn`.

## Components

| Component | What it does | Source |
|---|---|---|
| `ProxyGridVPN.exe` | The app (Electron) | `client/web`, `client/electron` |
| `tun2socks.exe`, `backend.dll` | Moves packets between the TAP adapter and the Shadowsocks server | `client/go` |
| `OutlineService.exe` (`ProxyGridVPNService`) | Privileged routing and DNS changes, controlled over a local named pipe | `client/electron/windows/OutlineService` |
| `smartdnsblock.exe` | Blocks DNS outside the tunnel with Windows Filtering Platform rules while connected | `client/electron/windows/smartdnsblock` |
| TAP-Windows6 (`tap0901.sys`) | Virtual network adapter driver (signed by Microsoft for OpenVPN) | Upstream binaries in `third_party/tap-windows6` |
| `tapctl.exe` | Creates and removes the `proxygrid-tap0` adapter (GPLv2, see `third_party/tap-windows6/TAPCTL.txt`) | Built from pinned OpenVPN source by `client/electron/windows/tapctl/build_tapctl.ps1` |

Every file with its origin, licence and signing treatment: [windows-binaries.md](windows-binaries.md).

## Build from source

Requirements: Windows 10 or 11, Node.js 22, Go (version in `go.mod`), Zig 0.13, git, and Visual
Studio 2022 Build Tools with MSBuild and the C++ x86/x64 and ARM64 toolsets.

```powershell
npm ci
# Helpers (routing service and DNS-leak blocker):
& "$msbuild" client\electron\windows\OutlineService\OutlineService.sln /p:Configuration=Release /p:Platform=x86
& "$msbuild" client\electron\windows\smartdnsblock\smartdnsblock.sln /p:Configuration=Release /p:Platform=x86 /p:PlatformToolset=v143
# tapctl.exe (TAP adapter tool) from pinned OpenVPN source; needs git and the C++ ARM64 tools too:
pwsh client/electron/windows/tapctl/build_tapctl.ps1
# Installer (unsigned), written to output\client\electron\build\:
npm run action client/electron/build windows -- --arch ia32
```

Release builds are made by the public workflow
[`windows-release.yml`](../.github/workflows/windows-release.yml). Before tagging an official
release, set `PROXYGRID_COGNITO_REGION`, `PROXYGRID_USER_POOL_ID` and
`PROXYGRID_USER_POOL_CLIENT_ID` in **Settings > Secrets and variables > Actions > Variables**.
These are public Cognito identifiers for the hosted service, not credentials. The workflow
checks that both packaged apps contain them before staging anything for signing. For
own-server-only development builds, leave all three unset.

## Verify a download

Each release lists SHA-256 checksums in `SHA256SUMS.txt`, and GitHub keeps a build-provenance
attestation that ties each file to the workflow run and commit that built it.

```powershell
# 1. Compare the hash with the entry for the same filename in SHA256SUMS.txt.
$installer = '.\ProxyGridVPN-1.0.0-beta.1-ia32.exe' # use the file you downloaded
Get-FileHash $installer -Algorithm SHA256
# 2. Provenance (GitHub CLI)
gh attestation verify $installer --repo proxygridx/proxygridvpn-client `
  --signer-workflow proxygridx/proxygridvpn-client/.github/workflows/windows-release.yml `
  --source-ref refs/tags/proxygridvpn-v1.0.0-beta.1  # use the tag you downloaded
```

Once signing is active (see the [code signing policy](../CODE_SIGNING_POLICY.md)), also check the
Authenticode signature:

```powershell
Get-AuthenticodeSignature $installer | Format-List Status, SignerCertificate
signtool verify /pa /v $installer   # from the Windows SDK
```

`Status` must be `Valid`, and the signer must be `SignPath Foundation`.
