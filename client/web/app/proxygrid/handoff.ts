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
 * Sign-in handoff from ProxyGridVPN to ProxyGrid Browser (desktop only).
 *
 * ProxyGrid Browser opens proxygridvpn://handoff?v=1&target=browser&challenge=<c>&state=<s>.
 * If the user is signed in and clicks Allow, the app asks the backend for a one-time code bound
 * to the browser's PKCE challenge, then opens proxygrid-browser://handoff?v=1&code&sub&state. The
 * code is useless without the browser's verifier. No token, email or password ever goes into a
 * URL, and nothing is requested before the user allows it.
 */

import {userMessage} from './errors';

/** base64url, no padding. */
const B64URL = /^[A-Za-z0-9_-]+$/;
/** BASE64URL(SHA256(verifier)) is always 43 characters. */
const CHALLENGE_LENGTH = 43;
/** state is 16 random bytes (22 characters); allow longer values up to 64. */
const STATE_MIN = 22;
const STATE_MAX = 64;
/** The one-time code from POST /auth/handoff: 43 base64url characters. */
const CODE_LENGTH = 43;
/** Cognito user pool subjects are UUIDs. */
const SUB = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const MAX_LINK_LENGTH = 512;
const ALLOWED_PARAMS = ['v', 'target', 'challenge', 'state'];

export const BROWSER_DOWNLOAD_URL = 'https://proxygrid.net/browser';

export const HANDOFF_MESSAGES = {
  invalidLink:
    'That sign-in request is not valid. Try again from ProxyGrid Browser.',
  notSignedIn:
    'Sign in to your ProxyGrid account in ProxyGridVPN first, then try again from ProxyGrid Browser.',
  expired: 'That sign-in link expired. Try again from ProxyGrid Browser.',
  browserNotInstalled: `ProxyGrid Browser is not installed. Download it from ${BROWSER_DOWNLOAD_URL}`,
} as const;

export interface HandoffRequest {
  challenge: string;
  state: string;
}

/** True if the URL is a proxygridvpn://handoff link (valid or not). */
export function isHandoffLink(url: string): boolean {
  return /^proxygridvpn:(\/\/)?handoff([/?#]|$)/i.test(url?.trim() ?? '');
}

/**
 * Parses and strictly validates a handoff link. Returns null if it is not a well-formed v1
 * browser handoff request: wrong version or target, missing, repeated or unknown parameters, or
 * values of the wrong length or character set.
 */
export function parseHandoffLink(url: string): HandoffRequest | null {
  if (typeof url !== 'string' || url.length > MAX_LINK_LENGTH) return null;
  const trimmed = url.trim();
  if (!isHandoffLink(trimmed)) return null;
  let parsed: URL;
  try {
    // Parse as https so URL and URLSearchParams behave the same for the custom scheme.
    parsed = new URL(trimmed.replace(/^proxygridvpn:(\/\/)?/i, 'https://app/'));
  } catch {
    return null;
  }
  if (parsed.pathname.replace(/\/+$/, '').toLowerCase() !== '/handoff') {
    return null;
  }
  if (parsed.hash) return null;
  const params = parsed.searchParams;
  const keys = [...params.keys()];
  if (new Set(keys).size !== keys.length) return null;
  if (keys.some(k => !ALLOWED_PARAMS.includes(k))) return null;
  if (params.get('v') !== '1' || params.get('target') !== 'browser') {
    return null;
  }
  const challenge = params.get('challenge') ?? '';
  const state = params.get('state') ?? '';
  if (challenge.length !== CHALLENGE_LENGTH || !B64URL.test(challenge)) {
    return null;
  }
  if (
    state.length < STATE_MIN ||
    state.length > STATE_MAX ||
    !B64URL.test(state)
  ) {
    return null;
  }
  return {challenge, state};
}

/** Builds the link that hands the one-time code to ProxyGrid Browser. Throws on bad values. */
export function buildBrowserHandoffUrl(
  code: string,
  sub: string,
  state: string
): string {
  if (code?.length !== CODE_LENGTH || !B64URL.test(code)) {
    throw new Error('invalid handoff code');
  }
  if (!SUB.test(sub ?? '')) throw new Error('invalid subject');
  if (
    state.length < STATE_MIN ||
    state.length > STATE_MAX ||
    !B64URL.test(state)
  ) {
    throw new Error('invalid state');
  }
  const q = new URLSearchParams({v: '1', code, sub, state});
  return `proxygrid-browser://handoff?${q.toString()}`;
}

export interface HandoffCode {
  code: string;
  sub: string;
  expires_in?: number;
}

export interface HandoffDependencies {
  /** The signed-in account's email, or null when signed out. */
  signedInEmail(): string | null;
  /** Shows "Sign in to ProxyGrid Browser as <email>?" and resolves true only on Allow. */
  confirm(email: string): Promise<boolean>;
  /** POST /auth/handoff with this app's own token. */
  requestCode(challenge: string): Promise<HandoffCode>;
  /** Opens a proxygrid-browser:// link. Resolves false if no app handles the scheme. */
  openExternal(url: string): Promise<boolean>;
  /** Shows a message to the user. */
  notify(message: string): void;
}

export type HandoffOutcome =
  | 'invalid'
  | 'not-signed-in'
  | 'cancelled'
  | 'handed-off'
  | 'browser-not-installed'
  | 'failed';

/** Runs one handoff request end to end. Makes no request unless the user clicked Allow. */
export async function handleHandoffLink(
  url: string,
  deps: HandoffDependencies
): Promise<HandoffOutcome> {
  const request = parseHandoffLink(url);
  if (!request) {
    deps.notify(HANDOFF_MESSAGES.invalidLink);
    return 'invalid';
  }
  const email = deps.signedInEmail();
  if (!email) {
    deps.notify(HANDOFF_MESSAGES.notSignedIn);
    return 'not-signed-in';
  }
  if (!(await deps.confirm(email))) return 'cancelled';
  let target: string;
  try {
    const result = await deps.requestCode(request.challenge);
    target = buildBrowserHandoffUrl(result.code, result.sub, request.state);
  } catch (e) {
    deps.notify(userMessage(e));
    return 'failed';
  }
  if (!(await deps.openExternal(target))) {
    deps.notify(HANDOFF_MESSAGES.browserNotInstalled);
    return 'browser-not-installed';
  }
  return 'handed-off';
}
