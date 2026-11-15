; Copyright 2018 The Outline Authors
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
;      http://www.apache.org/licenses/LICENSE-2.0
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

!include StrFunc.nsh
!include WinVer.nsh
!include x64.nsh

!include env.nsh


!macro customInstall
  ; Normally, because we mark the installer binary as requiring administrator permissions, the
  ; installer will be running with administrator permissions at this point. The exception is when
  ; the system is running with the *lowest* (least safe) UAC setting in which case the installer
  ; can progress to this point without administrator permissions.
  ;
  ; If that's the case, exit now so we don't waste time to trying to install the TAP device, etc.
  ; Additionally, the client can detect their absence and prompt the user to reinstall.
  ;
  ; The returned value does *not* seem to be based on the user's current diaplay language.
  UserInfo::GetAccountType
  Pop $0
  StrCmp $0 "Admin" isadmin
  MessageBox MB_OK "Sorry, ProxyGridVPN requires administrator permissions to install its network adapter and service."
  Quit

  isadmin:

  ; TAP device files. Pick the arch-specific driver bundle.
  ; ${RunningX64} is true on both x64 and arm64 Windows, so check arm64 first.
  SetOutPath "$INSTDIR\tap-windows6"
  ${If} ${IsNativeARM64}
    File /r "${PROJECT_DIR}\third_party\tap-windows6\bin\arm64\*"
  ${ElseIf} ${RunningX64}
    File /r "${PROJECT_DIR}\third_party\tap-windows6\bin\amd64\*"
  ${Else}
    File /r "${PROJECT_DIR}\third_party\tap-windows6\bin\i386\*"
  ${EndIf}
  SetOutPath -
  File "${PROJECT_DIR}\client\electron\add_tap_device.bat"

  ; Routing service (OutlineService.exe, registered as ProxyGridVPNService), stopping it first in case it's still running.
  nsExec::Exec "$SYSDIR\net stop ProxyGridVPNService"
  File "${PROJECT_DIR}\client\electron\windows\OutlineService\OutlineService\bin\OutlineService.exe"
  File "${PROJECT_DIR}\client\electron\windows\smartdnsblock\bin\smartdnsblock.exe"
  File "${PROJECT_DIR}\third_party\newtonsoft\Newtonsoft.Json.dll"
  File "${PROJECT_DIR}\client\electron\install_windows_service.bat"

  ; ExecToStack captures both stdout and stderr from the script, in the order output.
  ; Set a (long) timeout in case the device never becomes visible to netsh.
  ReadEnvStr $0 COMSPEC
  nsExec::ExecToStack /timeout=180000 '$0 /c add_tap_device.bat'

  Pop $0
  Pop $1
  StrCmp $0 0 installservice

  ; Show the error locally. The installer sends no data over the network.
  MessageBox MB_OK "Sorry, ProxyGridVPN could not set up its network adapter (error $0). Please \
    try running the installer again. If it still fails, see \
    https://github.com/proxygridx/proxygridvpn-client/blob/main/docs/windows.md or contact \
    contact@proxygrid.net with this error code.$\n$\n$1"
  Quit

  installservice:

  nsExec::Exec install_windows_service.bat

  nsExec::Exec "$SYSDIR\sc query ProxyGridVPNService"
  Pop $0
  StrCmp $0 0 success
  MessageBox MB_OK "Sorry, ProxyGridVPN could not install its background service \
    (ProxyGridVPNService). Please try running the installer again. If it still fails, contact \
    contact@proxygrid.net."
  Quit

  success:

!macroend

; Removes only our adapter (by name), never other apps' TAP-Windows6 adapters. Skipped during an
; automatic update, where the new version keeps using the same adapter.
!macro customUnInstall
  nsExec::Exec "$SYSDIR\net stop ProxyGridVPNService"
  nsExec::Exec "$SYSDIR\sc delete ProxyGridVPNService"
  ${ifNot} ${isUpdated}
    nsExec::Exec '"$INSTDIR\tap-windows6\tapctl.exe" delete proxygrid-tap0'
  ${endIf}
!macroend
