# iOS builds

## What CI does

[`ios-simulator.yml`](../.github/workflows/ios-simulator.yml) builds the app **unsigned for the
iOS Simulator**, checks the bundle ID and the packaged ProxyGrid account configuration, then
installs and launches it on a simulator and uploads a screenshot. The Simulator cannot run the
packet tunnel, so the VPN itself is only testable on a device.

## What a device or TestFlight build needs (maintainer actions)

Apple only lets members of the paid Apple Developer Program use the Network Extension
(packet tunnel) capability, and App Review guideline 5.4 requires VPN apps to come from a
developer **enrolled as an organization**, not an individual.

1. **Apple Developer Program, organization enrollment** (paid yearly; needs a D-U-N-S number
   for the company). Note the new **Team ID**.
2. **Identifiers** (Certificates, Identifiers & Profiles):
   - App ID `net.proxygrid.vpn.ios` with **Network Extensions** and **App Groups**;
   - App ID `net.proxygrid.vpn.ios.VpnExtension` with the same two capabilities;
   - App Group `group.net.proxygrid.vpn`, assigned to both App IDs.
3. **Team ID in the project:** replace upstream Outline's team `WP4DKSWWZM` with yours in
   `client/src/cordova/apple/OutlineLib/OutlineLib.xcodeproj/project.pbxproj` and the generated
   `client/platforms/ios/Outline.xcodeproj` (or pass `DEVELOPMENT_TEAM=<id>` to the release
   build, which `client/src/cordova/build.action.mjs` already supports).
4. **App Store Connect record:** New App > iOS, name "ProxyGridVPN" (if available), bundle ID
   `net.proxygrid.vpn.ios`, an SKU, primary language. Fill in the privacy policy URL
   (`PRIVACY.md` on GitHub or proxygrid.net) and the App Privacy answers.
5. **Encryption export compliance:** the app uses standard encryption (TLS, Shadowsocks
   AEAD). Answer the export questions in App Store Connect; add
   `ITSAppUsesNonExemptEncryption` to the Info.plist once the answer is settled.
6. **Signing for CI** (optional, for automated TestFlight uploads): create an App Store
   Connect API key (Users and Access > Integrations, role App Manager) and store the issuer ID,
   key ID and `.p8` file as GitHub Actions secrets in a protected environment. Until then,
   archive and upload from Xcode on a Mac signed in to the team.
7. **TestFlight:** after the first upload, add internal testers. External testing needs a
   short Beta App Review.

Nothing in this list has been created yet.
