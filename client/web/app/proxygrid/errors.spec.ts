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
import {CognitoError} from './cognito';
import {ERROR_MESSAGES, userMessage} from './errors';

describe('userMessage', () => {
  it('uses the shared wording', () => {
    expect(userMessage(new ProxyGridApiError(0, 'x'))).toEqual(
      ERROR_MESSAGES.unreachable
    );
    expect(userMessage(new ProxyGridApiError(502, 'x'))).toEqual(
      ERROR_MESSAGES.unreachable
    );
    expect(userMessage(new CognitoError('NetworkError', 'x'))).toEqual(
      ERROR_MESSAGES.unreachable
    );
    expect(userMessage(new ProxyGridApiError(401, 'x'))).toEqual(
      ERROR_MESSAGES.sessionExpired
    );
    expect(
      userMessage(new ProxyGridApiError(403, 'x', 'client_not_allowed'))
    ).toEqual(ERROR_MESSAGES.clientNotAllowed);
  });

  it('adds the network reason when the platform knows it', () => {
    expect(
      userMessage(
        new CognitoError('NetworkError', 'x', 'a proxy blocked the connection')
      )
    ).toEqual(
      `${ERROR_MESSAGES.unreachable} (Reason: a proxy blocked the connection.)`
    );
  });

  it('keeps other backend messages, for example limits', () => {
    expect(
      userMessage(new ProxyGridApiError(429, 'Daily key limit reached.'))
    ).toEqual('Daily key limit reached.');
    expect(userMessage(new ProxyGridApiError(403, 'Plan required.'))).toEqual(
      'Plan required.'
    );
  });
});
