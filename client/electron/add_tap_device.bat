:: Copyright 2018 The Outline Authors
::
:: Licensed under the Apache License, Version 2.0 (the "License");
:: you may not use this file except in compliance with the License.
:: You may obtain a copy of the License at
::
::      http://www.apache.org/licenses/LICENSE-2.0
::
:: Unless required by applicable law or agreed to in writing, software
:: distributed under the License is distributed on an "AS IS" BASIS,
:: WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
:: See the License for the specific language governing permissions and
:: limitations under the License.

@echo off
:: See https://ss64.com/nt/delayedexpansion.html
setlocal enabledelayedexpansion

set DEVICE_NAME=proxygrid-tap0
set DEVICE_HWID=tap0901

:: Error codes shown to the user by the installer.
set ERROR_TAP_INSTALL=1
set ERROR_TAP_FIND_NAME=2
set ERROR_TAP_RENAME=3
set ERROR_TAP_CONFIGURE_SUBNET=4
set ERROR_TAP_CONFIGURE_DNS=5

:: Because we've seen multiple failures due to commands (netsh, etc.) not being
:: found, append some common directories to the PATH.
::
:: Note:
::  - %SystemRoot% almost always expands to c:\windows.
::  - Do *not* surround with quotes.
set PATH=%PATH%;%SystemRoot%\system32;%SystemRoot%\system32\wbem;%SystemRoot%\system32\WindowsPowerShell/v1.0

:: Check whether the device already exists.
%SystemRoot%\System32\netsh interface show interface name=%DEVICE_NAME%
if %errorlevel% equ 0 (
  echo TAP network device already exists.
  goto :configure
)

echo Creating TAP network device...
:: The installer runs this script in a 32-bit cmd.exe; on 64-bit Windows, System32 is then
:: redirected and has no pnputil.exe, so use Sysnative to reach the 64-bit tool.
set PNPUTIL=%SystemRoot%\System32\pnputil.exe
if exist %SystemRoot%\Sysnative\pnputil.exe set PNPUTIL=%SystemRoot%\Sysnative\pnputil.exe

:: 1. Add the Microsoft-signed TAP-Windows6 driver package to the driver store (built-in pnputil).
%PNPUTIL% /add-driver tap-windows6\OemVista.inf /install
if %errorlevel% neq 0 if %errorlevel% neq 259 if %errorlevel% neq 3010 (
  echo Could not add the TAP driver package. >&2
  exit /b %ERROR_TAP_INSTALL%
)

:: 2. Create a root-enumerated TAP adapter with our name (OpenVPN tapctl, built from source).
tap-windows6\tapctl.exe create --hwid root\%DEVICE_HWID% --name %DEVICE_NAME%
if %errorlevel% neq 0 (
  echo Could not create TAP network device. >&2
  exit /b %ERROR_TAP_INSTALL%
)

:: Wait for the new name to propagate to netsh.
call :wait_for_device "%DEVICE_NAME%"

:: Attempt to configure the device even if waiting timed out.
:configure

:: Try to enable the device, in case it's somehow been disabled.
::
:: Annoyingly, this returns an error and outputs a confusing message if the device exists and is
:: already enabled:
::   This network connection does not exist.
::
:: So, continue even if this command fails - and always include its output.
echo (Re-)enabling TAP network device...
%SystemRoot%\System32\netsh interface set interface "%DEVICE_NAME%" admin=enabled
:: The powershell command is used to ensure the adapter is enabled if netsh fails and leaves it in
:: a disabled state. While no such failure has yet been observed, this command would correct it and
:: should behave idempotently otherwise.
powershell "Enable-NetAdapter -Name \"%DEVICE_NAME%\"" <nul

:: Give the device an IP address.
:: 10.0.86.x (Outline uses 10.0.85.x, so both apps can be installed) is a guess which we hope will work for most users (Docker for
:: Windows uses 10.0.75.x by default): if the address is already in use the
:: script will fail and the installer will show an error message to the user.
:: TODO: Actually search the system for an unused subnet or make the subnet
::       configurable in the Outline client.
echo Configuring TAP device subnet...
%SystemRoot%\System32\netsh interface ip set address %DEVICE_NAME% static 10.0.86.2 255.255.255.255
if %errorlevel% neq 0 (
  echo Could not set TAP network device subnet. >&2
  exit /b %ERROR_TAP_CONFIGURE_SUBNET%
)

:: Windows has no system-wide DNS server; each network device can have its
:: "own" set of DNS servers. Windows seems to use the DNS server(s) of the
:: network device associated with the default gateway. This is good for us
:: as it means we do not have to modify the DNS settings of any other network
:: device in the system. Configure with Cloudflare and Quad9 resolvers
echo Configuring primary DNS...
:: A "fake" local DNS resolver. Outline will intercept the real resolver at this address.
:: Must align with: client/go/outline/configregistry/outline_dns_intercept.go
%SystemRoot%\System32\netsh interface ip set dnsservers %DEVICE_NAME% static address=169.254.113.53
if %errorlevel% neq 0 (
  echo Could not configure TAP device primary DNS. >&2
  exit /b %ERROR_TAP_CONFIGURE_DNS%
)
echo TAP network device added and configured successfully
exit /b 0

:: Waits up to a minute until a device is visible to netsh. Accepts the device name as a parameter.
:: Exits with a non-zero code if the operation times out.
:wait_for_device
echo Testing that the network device "%~1" is visible to netsh...
%SystemRoot%\System32\netsh interface ip show interfaces | find "%~1" >nul 2>&1
if %errorlevel% equ 0 exit /b 0
for /l %%N in (1, 1, 6) do (
  echo Waiting... %%N
  :: timeout doesn't like the environment created by nsExec::ExecToStack and exits with:
  :: "ERROR: Input redirection is not supported, exiting the process immediately."
  waitfor /t 10 thisisnotarealsignalname >nul 2>&1
  %SystemRoot%\System32\netsh interface ip show interfaces | find "%~1" >nul 2>&1
  if !errorlevel! equ 0 exit /b 0
)
exit /b 1
