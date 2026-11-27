# Working with ProxyGrid Browser

ProxyGridVPN and ProxyGrid Browser are separate apps that share a ProxyGrid account. They only
talk through the ProxyGrid backend and two URL schemes. ProxyGrid Browser never uses the VPN's
routing service, pipe or files, and neither app changes the system proxy settings: the VPN
routes all traffic with its TUN adapter.

## Open ProxyGrid Browser (desktop)

The tray menu has **Open ProxyGrid Browser**. It opens `proxygrid-browser://open`. If no app
handles that scheme, it offers the download page, https://proxygrid.net/browser. The action is
not on Android or iOS.

## Sign-in handoff (desktop)

ProxyGrid Browser can sign in with the VPN app's account instead of asking for the password:

1. The browser opens `proxygridvpn://handoff?v=1&target=browser&challenge=<c>&state=<s>`,
   where `c` is a PKCE S256 challenge. The app rejects any other version, target, parameter,
   length or character.
2. If you're signed in, the app shows a native dialog: "Sign in to ProxyGrid Browser as
   <email>?". Nothing is sent unless you click **Allow**. If you're signed out, it asks you to
   sign in first.
3. On Allow, the app calls `POST /auth/handoff` with its own token and gets a one-time code
   (single use, two minutes, bound to the challenge).
4. It opens `proxygrid-browser://handoff?v=1&code=<code>&sub=<sub>&state=<s>`. The code is
   useless without the browser's verifier. No token, email or password goes into a URL.

The browser then has its own session. Signing out of either app revokes only that app's refresh
token (Cognito `RevokeToken`).

## Cognito client per app

The build reads the Cognito app client ID from `PROXYGRID_USER_POOL_CLIENT_ID` (repository
variable for CI). Builds use ProxyGridVPN's own client, `proxygrid-vpn-prod`
(`6m9dciajpmhcg3pi19htvqor8t`, SRP and refresh only); the backend accepts handoff requests only
from it. Beta 1 was built with the shared client (`7q16t0jtuhsdtl4ut53b5j88cn`), which keeps
working.
