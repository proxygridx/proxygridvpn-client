# Windows version resources

`tun2socks.json` and `backend.json` define the version information embedded in `tun2socks.exe`
and `backend.dll`. The Windows build (`client/go/Taskfile.yml`) turns each into a temporary
`.syso` file with the pinned `go tool go-winres` and sets FileVersion and ProductVersion from
the build's version (`PROXYGRIDVPN_VERSION`, default `0.0.0`). The `0.0.0` values in the JSON
files are placeholders that the build always overrides.
