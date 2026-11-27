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

import {ProxyGridApiError} from './api';
import {ERROR_MESSAGES} from './errors';
import {
  buildBrowserHandoffUrl,
  handleHandoffLink,
  HANDOFF_MESSAGES,
  HandoffDependencies,
  isHandoffLink,
  parseHandoffLink,
} from './handoff';

const CHALLENGE = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
const STATE = 'AAECAwQFBgcICQoLDA0ODw';
const CODE = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';
const SUB = '0f8fad5b-d9cb-469f-a165-70867728950e';
const LINK = `proxygridvpn://handoff?v=1&target=browser&challenge=${CHALLENGE}&state=${STATE}`;

function deps(overrides: Partial<HandoffDependencies> = {}) {
  const d = {
    signedInEmail: jasmine.createSpy('signedInEmail').and.returnValue('a@b.c'),
    confirm: jasmine.createSpy('confirm').and.resolveTo(true),
    requestCode: jasmine
      .createSpy('requestCode')
      .and.resolveTo({code: CODE, sub: SUB, expires_in: 120}),
    openExternal: jasmine.createSpy('openExternal').and.resolveTo(true),
    notify: jasmine.createSpy('notify'),
    ...overrides,
  };
  return d;
}

describe('parseHandoffLink', () => {
  it('accepts a well-formed v1 browser request', () => {
    expect(parseHandoffLink(LINK)).toEqual({
      challenge: CHALLENGE,
      state: STATE,
    });
    expect(isHandoffLink(LINK)).toBeTrue();
  });

  it('accepts the trailing slash some systems add', () => {
    expect(
      parseHandoffLink(LINK.replace('handoff?', 'handoff/?'))
    ).not.toBeNull();
  });

  const bad: Array<[string, string]> = [
    ['wrong version', LINK.replace('v=1', 'v=2')],
    ['wrong target', LINK.replace('target=browser', 'target=web')],
    ['missing challenge', LINK.replace(`&challenge=${CHALLENGE}`, '')],
    ['missing state', LINK.replace(`&state=${STATE}`, '')],
    ['short challenge', LINK.replace(CHALLENGE, CHALLENGE.slice(1))],
    [
      'challenge with bad characters',
      LINK.replace(CHALLENGE, CHALLENGE.slice(1) + '+'),
    ],
    ['short state', LINK.replace(STATE, 'abc')],
    ['state with bad characters', LINK.replace(STATE, STATE.slice(1) + '%2F')],
    ['repeated parameter', LINK + '&state=' + STATE],
    ['unknown parameter', LINK + '&redirect=https%3A%2F%2Fevil.test'],
    ['fragment', LINK + '#x'],
    ['other action', LINK.replace('handoff', 'add')],
    ['other scheme', LINK.replace('proxygridvpn', 'proxygrid-browser')],
    ['too long', LINK + '&x=' + 'a'.repeat(600)],
  ];
  for (const [name, link] of bad) {
    it(`rejects a link with ${name}`, () => {
      expect(parseHandoffLink(link)).toBeNull();
    });
  }
});

describe('buildBrowserHandoffUrl', () => {
  it('carries only the code, subject and state', () => {
    const url = buildBrowserHandoffUrl(CODE, SUB, STATE);
    expect(url).toEqual(
      `proxygrid-browser://handoff?v=1&code=${CODE}&sub=${SUB}&state=${STATE}`
    );
  });

  it('rejects malformed values from the backend', () => {
    expect(() => buildBrowserHandoffUrl('short', SUB, STATE)).toThrow();
    expect(() => buildBrowserHandoffUrl(CODE, 'a@b.c', STATE)).toThrow();
    expect(() => buildBrowserHandoffUrl(CODE, SUB, 'x')).toThrow();
  });
});

describe('handleHandoffLink', () => {
  it('asks for confirmation, then requests a code and opens ProxyGrid Browser', async () => {
    const d = deps();
    expect(await handleHandoffLink(LINK, d)).toEqual('handed-off');
    expect(d.confirm).toHaveBeenCalledOnceWith('a@b.c');
    expect(d.requestCode).toHaveBeenCalledOnceWith(CHALLENGE);
    const opened = (d.openExternal as jasmine.Spy).calls.mostRecent()
      .args[0] as string;
    expect(opened).toEqual(buildBrowserHandoffUrl(CODE, SUB, STATE));
    expect(opened).not.toContain('a@b.c');
    expect(d.confirm).toHaveBeenCalledBefore(d.requestCode);
  });

  it('makes no request when the user cancels', async () => {
    const d = deps({
      confirm: jasmine.createSpy('confirm').and.resolveTo(false),
    });
    expect(await handleHandoffLink(LINK, d)).toEqual('cancelled');
    expect(d.requestCode).not.toHaveBeenCalled();
    expect(d.openExternal).not.toHaveBeenCalled();
  });

  it('asks the user to sign in first when signed out, without a dialog or request', async () => {
    const d = deps({
      signedInEmail: jasmine.createSpy('signedInEmail').and.returnValue(null),
    });
    expect(await handleHandoffLink(LINK, d)).toEqual('not-signed-in');
    expect(d.notify).toHaveBeenCalledOnceWith(HANDOFF_MESSAGES.notSignedIn);
    expect(d.confirm).not.toHaveBeenCalled();
    expect(d.requestCode).not.toHaveBeenCalled();
  });

  it('rejects a bad link without a dialog or request', async () => {
    const d = deps();
    expect(await handleHandoffLink(LINK.replace('v=1', 'v=9'), d)).toEqual(
      'invalid'
    );
    expect(d.notify).toHaveBeenCalledOnceWith(HANDOFF_MESSAGES.invalidLink);
    expect(d.confirm).not.toHaveBeenCalled();
    expect(d.requestCode).not.toHaveBeenCalled();
  });

  it('shows the shared wording when the backend refuses', async () => {
    const d = deps({
      requestCode: jasmine
        .createSpy('requestCode')
        .and.rejectWith(new ProxyGridApiError(403, 'no', 'client_not_allowed')),
    });
    expect(await handleHandoffLink(LINK, d)).toEqual('failed');
    expect(d.notify).toHaveBeenCalledOnceWith(ERROR_MESSAGES.clientNotAllowed);
    expect(d.openExternal).not.toHaveBeenCalled();
  });

  it('does not open a link built from a malformed backend response', async () => {
    const d = deps({
      requestCode: jasmine
        .createSpy('requestCode')
        .and.resolveTo({code: 'x', sub: SUB}),
    });
    expect(await handleHandoffLink(LINK, d)).toEqual('failed');
    expect(d.openExternal).not.toHaveBeenCalled();
  });

  it('shows the download link when ProxyGrid Browser is not installed', async () => {
    const d = deps({
      openExternal: jasmine.createSpy('openExternal').and.resolveTo(false),
    });
    expect(await handleHandoffLink(LINK, d)).toEqual('browser-not-installed');
    expect(d.notify).toHaveBeenCalledOnceWith(
      HANDOFF_MESSAGES.browserNotInstalled
    );
  });
});
