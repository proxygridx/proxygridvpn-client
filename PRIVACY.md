# ProxyGridVPN privacy policy

This policy covers the ProxyGridVPN client apps built from this repository. The hosted
ProxyGrid service (accounts, billing, VPN servers) is covered by the
[ProxyGrid privacy policy](https://proxygrid.net/privacy).

## What the app sends, and to whom

ProxyGridVPN only connects to systems you choose, plus the update check below.

| When | Destination | What is sent |
|---|---|---|
| You connect to a server | The VPN server in your access key (your own server, or a ProxyGrid server) | Your network traffic, encrypted with Shadowsocks. |
| You add an `ssconf://` dynamic key | The web address in that key | A request for the current server settings. |
| You sign in to a ProxyGrid account (optional) | `cognito-idp.ap-northeast-1.amazonaws.com` (Amazon Cognito, used by ProxyGrid for sign-in) and `api.proxygrid.net` | Your email and a password proof (the password itself never leaves the device), then requests for your plan, usage and access keys. |
| Windows and Linux release builds, every 6 hours | The update address configured at build time (official builds: `proxygrid.net`) | A request for the latest version number. No account or usage data. |

The app does **not** collect analytics. Crash reporting (Sentry) is compiled in only when a
build sets `SENTRY_DSN`; builds from this repository's public workflow do not set it, so they
send no crash reports.

If you use only your own servers ("My own servers" mode), the app never contacts ProxyGrid,
apart from the update check on Windows and Linux.

## What is stored on your device

Access keys and your ProxyGrid session are stored in the operating system's protected storage
(Apple Keychain, Android Keystore, or Electron safeStorage on Windows and Linux). On Android
and iOS, removing the app removes them. On Windows, delete the app's data folders after
uninstalling ([how](docs/windows.md#uninstall)); on macOS, keychain items can be removed in
Keychain Access.

## Turning things off

- Don't sign in to ProxyGrid, and the app makes no ProxyGrid account requests.
- Remove a server or sign out to delete its key from the device.
- Automatic update checks can't be turned off in the app yet. Until they can, you can block the
  update address in your firewall. A setting is planned.

## Contact

Questions about this policy: contact@proxygrid.net. Security reports: see [SECURITY.md](SECURITY.md).
