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
 * Opening ProxyGrid Browser from the desktop app ("Open ProxyGrid Browser" and the sign-in
 * handoff). Only proxygrid-browser://open and well-formed proxygrid-browser://handoff links are
 * ever opened; if no app handles the scheme, the caller shows the download link instead.
 */

import {BROWSER_DOWNLOAD_URL} from './handoff';

export const BROWSER_SCHEME = 'proxygrid-browser:';
export const OPEN_BROWSER_URL = 'proxygrid-browser://open';
export {BROWSER_DOWNLOAD_URL};

const HANDOFF_LINK =
  /^proxygrid-browser:\/\/handoff\?v=1&code=[A-Za-z0-9_-]{43}&sub=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}&state=[A-Za-z0-9_-]{22,64}$/;

/** True only for the two kinds of links this app may open in ProxyGrid Browser. */
export function isAllowedBrowserLink(url: string): boolean {
  return url === OPEN_BROWSER_URL || HANDOFF_LINK.test(url);
}

export interface OpenBrowserDependencies {
  /** Whether any installed app handles proxygrid-browser:// links. */
  isBrowserInstalled(): boolean;
  openExternal(url: string): Promise<void>;
}

export type OpenBrowserResult = 'opened' | 'not-installed' | 'rejected';

/** Opens a ProxyGrid Browser link if the link is allowed and the browser is installed. */
export async function openBrowserLink(
  url: string,
  deps: OpenBrowserDependencies
): Promise<OpenBrowserResult> {
  if (!isAllowedBrowserLink(url)) return 'rejected';
  if (!deps.isBrowserInstalled()) return 'not-installed';
  await deps.openExternal(url);
  return 'opened';
}
