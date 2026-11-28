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

import {
  BROWSER_DOWNLOAD_URL,
  isAllowedBrowserLink,
  OPEN_BROWSER_URL,
  openBrowserLink,
} from './open_browser';

const HANDOFF =
  'proxygrid-browser://handoff?v=1&code=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ' +
  '&sub=0f8fad5b-d9cb-469f-a165-70867728950e&state=AAECAwQFBgcICQoLDA0ODw';

describe('openBrowserLink', () => {
  it('opens ProxyGrid Browser when it is installed', async () => {
    const openExternal = jasmine.createSpy('openExternal').and.resolveTo();
    const result = await openBrowserLink(OPEN_BROWSER_URL, {
      isBrowserInstalled: () => true,
      openExternal,
    });
    expect(result).toEqual('opened');
    expect(openExternal).toHaveBeenCalledOnceWith('proxygrid-browser://open');
  });

  it('reports not installed, without opening anything, when no app handles the scheme', async () => {
    const openExternal = jasmine.createSpy('openExternal').and.resolveTo();
    const result = await openBrowserLink(OPEN_BROWSER_URL, {
      isBrowserInstalled: () => false,
      openExternal,
    });
    expect(result).toEqual('not-installed');
    expect(openExternal).not.toHaveBeenCalled();
    expect(BROWSER_DOWNLOAD_URL).toEqual('https://proxygrid.net/browser');
  });

  it('opens only the open link and well-formed handoff links', async () => {
    expect(isAllowedBrowserLink(OPEN_BROWSER_URL)).toBeTrue();
    expect(isAllowedBrowserLink(HANDOFF)).toBeTrue();
    for (const url of [
      'https://evil.test',
      'proxygrid-browser://open?x=1',
      HANDOFF + '&token=x',
      HANDOFF.replace('code=abc', 'code=ab'),
      'file:///etc/passwd',
    ]) {
      expect(isAllowedBrowserLink(url)).withContext(url).toBeFalse();
    }
    const openExternal = jasmine.createSpy('openExternal').and.resolveTo();
    expect(
      await openBrowserLink('https://evil.test', {
        isBrowserInstalled: () => true,
        openExternal,
      })
    ).toEqual('rejected');
    expect(openExternal).not.toHaveBeenCalled();
  });
});
