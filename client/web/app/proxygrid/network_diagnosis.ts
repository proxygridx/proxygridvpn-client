// Copyright 2026 ProxyGrid
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Turns a Chromium network error code (net::ERR_*) into a short reason a user can act on. The
 * renderer's fetch() only says "Failed to fetch"; the desktop app asks its main process for the
 * real error so that "could not reach" messages say why.
 */

const REASONS: Array<[RegExp, string]> = [
  [
    /^ERR_NAME_NOT_RESOLVED$|^ERR_NAME_RESOLUTION_FAILED$|^ERR_DNS_/,
    'the name could not be looked up (DNS)',
  ],
  [
    /^ERR_INTERNET_DISCONNECTED$|^ERR_NETWORK_CHANGED$|^ERR_ADDRESS_UNREACHABLE$/,
    'this PC is offline',
  ],
  [
    /^ERR_CERT_DATE_INVALID$/,
    "the secure connection failed; check this PC's date and time",
  ],
  [
    /^ERR_CERT_|^ERR_SSL_|^ERR_BAD_SSL_/,
    'the secure connection was rejected (a security product or proxy may be inspecting HTTPS)',
  ],
  [
    /^ERR_PROXY_|^ERR_TUNNEL_CONNECTION_FAILED$|^ERR_MANDATORY_PROXY_/,
    'a proxy blocked the connection',
  ],
  [
    /^ERR_NETWORK_ACCESS_DENIED$|^ERR_BLOCKED_/,
    'a firewall or security product blocked the app',
  ],
  [/^ERR_CONNECTION_TIMED_OUT$|^ERR_TIMED_OUT$/, 'the connection timed out'],
  [
    /^ERR_CONNECTION_(REFUSED|RESET|CLOSED|ABORTED|FAILED)$/,
    'the connection was interrupted',
  ],
];

/** Describes a net::ERR_* code; unknown codes are shown as they are. */
export function describeNetError(code: string): string {
  const c = code.replace(/^net::/, '');
  for (const [pattern, reason] of REASONS) {
    if (pattern.test(c)) return `${reason} [${c}]`;
  }
  return c;
}

/** Hosts the diagnosis may contact: ProxyGrid sign-in and API only. */
export function isDiagnosableUrl(url: string): boolean {
  try {
    const u = new URL(url);
    return (
      u.protocol === 'https:' &&
      !u.port &&
      (/^cognito-idp\.[a-z0-9-]+\.amazonaws\.com$/.test(u.hostname) ||
        u.hostname === 'api.proxygrid.net')
    );
  } catch {
    return false;
  }
}
