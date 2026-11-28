# iOS builds

## What CI does

[`ios-simulator.yml`](../.github/workflows/ios-simulator.yml) builds the app **unsigned for the
iOS Simulator**, checks the bundle ID and the packaged ProxyGrid account configuration, then
installs and launches it on a simulator and uploads a screenshot. The Simulator cannot run the
packet tunnel, so the VPN itself is only testable on a device.

## Signing team

The Xcode projects use the **Phu Duc** team (`797NU6L392`) for the app
(`net.proxygrid.vpn.ios`, Mac Catalyst `net.proxygrid.vpn.macos`) and its packet tunnel
extensions (`.VpnExtension`), with the app group `group.net.proxygrid.vpn`. Development
provisioning profiles with Network Extension (packet-tunnel-provider) and App Groups exist for
all four bundle IDs, so a development-signed device build works from Xcode on a Mac signed in to
the team.

## What TestFlight and the App Store still need (maintainer actions)

App Review guideline 5.4 requires VPN apps to come from a developer **enrolled as an
organization**. Check whether the Phu Duc membership is an organization (Membership details in
the Apple Developer account). If it is an individual membership, apply for organization
enrollment first (needs a D-U-N-S number).

1. **Apple Distribution certificate** for the team (Certificates, Identifiers & Profiles >
   Certificates, or Xcode > Settings > Accounts > Manage Certificates).
2. **App Store provisioning profiles** for `net.proxygrid.vpn.ios` and
   `net.proxygrid.vpn.ios.VpnExtension` (Xcode creates them with automatic signing on the first
   archive).
3. **App Store Connect record:** New App > iOS, name "ProxyGridVPN" (if available), bundle ID
   `net.proxygrid.vpn.ios`, an SKU, primary language. Fill in the privacy policy URL and the App
   Privacy answers.
4. **Encryption export compliance:** the app uses standard encryption (TLS, Shadowsocks
   AEAD). Answer the export questions in App Store Connect; add
   `ITSAppUsesNonExemptEncryption` to the Info.plist once the answer is settled.
5. **Signing for CI** (optional, for automated TestFlight uploads): an App Store Connect API key
   (Users and Access > Integrations, role App Manager), stored with its issuer ID and key ID as
   GitHub Actions secrets in a protected environment. Until then, archive and upload from Xcode.
6. **TestFlight:** after the first upload, add internal testers. External testing needs a
   short Beta App Review.

None of these records have been created.
