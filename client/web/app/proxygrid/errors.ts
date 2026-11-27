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

/** User-facing error wording shared by ProxyGridVPN and ProxyGrid Browser. */

import {ProxyGridApiError} from './api';
import {CognitoError} from './cognito';

export const ERROR_MESSAGES = {
  unreachable:
    'ProxyGrid is unreachable right now. Your saved settings still work.',
  sessionExpired: 'Your session expired. Sign in again.',
  clientNotAllowed: "This action isn't available in this app.",
} as const;

/** Maps an error from the ProxyGrid API or Cognito to the shared wording. */
export function userMessage(e: unknown): string {
  if (e instanceof ProxyGridApiError) {
    if (e.status === 0 || e.status >= 500) return ERROR_MESSAGES.unreachable;
    if (e.status === 401) return ERROR_MESSAGES.sessionExpired;
    if (e.status === 403 && e.code === 'client_not_allowed') {
      return ERROR_MESSAGES.clientNotAllowed;
    }
    return e.message;
  }
  if (e instanceof CognitoError && e.code === 'NetworkError') {
    return ERROR_MESSAGES.unreachable;
  }
  if (e instanceof Error) return e.message;
  return String(e);
}
