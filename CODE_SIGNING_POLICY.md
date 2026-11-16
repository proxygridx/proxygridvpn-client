# Code signing policy

**Status:** ProxyGridVPN intends to apply for free code signing through the
[SignPath Foundation](https://signpath.org) program and has not applied yet. Until an application
is approved, Windows builds are **unsigned**. This page describes how signing will work once it
is active.

Once signing is active, signed releases will carry this attribution: free code signing provided
by [SignPath.io](https://about.signpath.io), certificate by
[SignPath Foundation](https://signpath.org).

## What is signed

Only files built in this repository's public GitHub Actions workflow
([`windows-release.yml`](.github/workflows/windows-release.yml)) from the tagged source are
submitted for signing:

| File | Built from |
|---|---|
| `ProxyGridVPN.exe` | Electron app packaged from `client/` |
| `tun2socks.exe`, `backend.dll` | Go code in `client/go/` |
| `OutlineService.exe` (ProxyGridVPN routing service) | C# code in `client/electron/windows/OutlineService/` |
| `smartdnsblock.exe` | C++ code in `client/electron/windows/smartdnsblock/` |
| `ProxyGridVPN-<version>-<arch>.exe` (installer) | NSIS installer built by electron-builder |

Third-party binaries keep their upstream signatures, or stay unsigned, and are never signed
with the ProxyGridVPN identity. These are the TAP-Windows6 driver (signed by Microsoft for
OpenVPN), `tapctl.exe` (OpenVPN, GPLv2, built unmodified from pinned OpenVPN source in the
release workflow), Electron/Chromium runtime libraries, `elevate.exe`
(electron-builder), Newtonsoft.Json and NSIS plugins. The full
list with origins and licences: [docs/windows-binaries.md](docs/windows-binaries.md).

## Team roles

ProxyGridVPN is currently maintained by one person. The roles below follow the SignPath
Foundation terms and will grow as the team grows.

| Role | Responsibility | Members |
|---|---|---|
| Committers (authors) | May change source code without additional review | [Members of the proxygridx organization](https://github.com/orgs/proxygridx/people) |
| Reviewers | Review every pull request from people who are not committers before it is merged | [Members of the proxygridx organization](https://github.com/orgs/proxygridx/people) |
| Approvers | Approve each signing request in SignPath after checking that it was built from a reviewed, tagged commit | [Owners of the proxygridx organization](https://github.com/orgs/proxygridx/people?query=role%3Aowner) |

All team members use multi-factor authentication for GitHub and SignPath.

## Release approval

1. A release is a signed Git tag `proxygridvpn-vX.Y.Z` on `main`. `main` is protected: changes
   land through pull requests.
2. The tag triggers the public workflow, which builds every Windows file from source on
   GitHub-hosted runners and records a build-provenance attestation.
3. Signing requests go to SignPath only from the `release-signing` GitHub environment, which
   requires a manual approval. SignPath then requires an approver to approve each request.
4. Signed files are published on the [Releases](https://github.com/proxygridx/proxygridvpn-client/releases)
   page with SHA-256 checksums. Verification steps: [docs/windows.md](docs/windows.md#verify-a-download).

## Privacy

See the [privacy policy](PRIVACY.md). It also covers the third-party services the app can
connect to.
