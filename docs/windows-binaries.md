# Windows installer contents

Every executable, library and driver in the Windows installer, where it comes from, its licence,
and how it is treated for code signing. Checked against `ProxyGridVPN-<version>-ia32.exe` built
by [`windows-release.yml`](../.github/workflows/windows-release.yml); the arm64 installer has
the same set with arm64 builds.

## Built from this repository (signed with the ProxyGridVPN identity once signing is active)

| File | Source | Licence |
|---|---|---|
| `ProxyGridVPN-<version>-<arch>.exe` (installer) | electron-builder NSIS, `client/electron/custom_install_steps.nsh` | Apache-2.0 (our scripts); NSIS is zlib |
| `ProxyGridVPN.exe` | Electron runtime with our app (`resources/app.asar`) from `client/` | Apache-2.0 (app); Electron MIT |
| `resources/app.asar.unpacked/.../tun2socks.exe`, `backend.dll` | `client/go` | Apache-2.0 |
| `OutlineService.exe` (service `ProxyGridVPNService`) | `client/electron/windows/OutlineService` (C#) | Apache-2.0 |
| `smartdnsblock.exe` | `client/electron/windows/smartdnsblock` (C++) | Apache-2.0 |

Each of these files carries a Windows version resource with ProductName `ProxyGridVPN`,
CompanyName `ProxyGrid` and the release version (`tun2socks.exe` and `backend.dll` from
`client/go/outline/electron/winres` through the pinned `go-winres` tool; `smartdnsblock.exe`
from `smartdnsblock.rc`). The installer smoke test checks it on the installed files.

## Third-party (never signed with the ProxyGridVPN identity)

| File | Origin | Licence | Signature |
|---|---|---|---|
| `tap-windows6/tap0901.sys`, `tap0901.cat`, `OemVista.inf` | [OpenVPN tap-windows6](https://github.com/OpenVPN/tap-windows6) 9.27 driver, `third_party/tap-windows6` | MIT / GPL-2.0 (dual) | Microsoft Windows Hardware Compatibility Publisher (kept) |
| `tap-windows6/tapctl.exe` | [OpenVPN](https://github.com/OpenVPN/openvpn) `src/tapctl` at v2.7.9 (commit `7b60c2a`), compiled in CI by `client/electron/windows/tapctl/build_tapctl.ps1` | GPL-2.0, run as a separate program; the installer ships its notice and licence (`tap-windows6\TAPCTL.txt`, `COPYRIGHT.GPL`) | Unsigned (upstream code) |
| `Newtonsoft.Json.dll` | Json.NET 11.0.2, `third_party/newtonsoft` | MIT | Unsigned |
| `d3dcompiler_47.dll` | Microsoft, shipped with Electron | Microsoft; also ships with Windows (System32) since Windows 8.1, so it counts as a system library | Microsoft Corporation (kept) |
| `ffmpeg.dll`, `libEGL.dll`, `libGLESv2.dll`, `vk_swiftshader.dll`, `vulkan-1.dll` | Electron / Chromium runtime | LGPL-2.1 (FFmpeg), BSD-3 / Apache-2.0 | Unsigned (upstream) |
| `resources/elevate.exe` | electron-builder | MIT | Unsigned (upstream) |
| NSIS plugins (`nsExec.dll`, `StdUtils.dll`, `nsis7z.dll`, ...) | NSIS / electron-builder, inside the installer only | zlib and similar | Unsigned (upstream) |

`devcon.exe` (Microsoft, proprietary) is no longer shipped.

The Windows system tools the installer calls (`pnputil.exe`, `netsh.exe`, `sc.exe`,
`powershell.exe`) are part of Windows and are not bundled.

## No server code

The installer contains only the client listed above. ProxyGrid's servers, backend, billing and
infrastructure code are not in this repository and not in any download.
