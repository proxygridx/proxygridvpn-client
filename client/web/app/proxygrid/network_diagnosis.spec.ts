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

import {describeNetError, isDiagnosableUrl} from './network_diagnosis';

describe('describeNetError', () => {
  it('explains common failures', () => {
    expect(describeNetError('net::ERR_NAME_NOT_RESOLVED')).toContain('DNS');
    expect(describeNetError('ERR_CERT_DATE_INVALID')).toContain(
      'date and time'
    );
    expect(describeNetError('ERR_CERT_AUTHORITY_INVALID')).toContain(
      'inspecting HTTPS'
    );
    expect(describeNetError('ERR_PROXY_CONNECTION_FAILED')).toContain('proxy');
    expect(describeNetError('ERR_NETWORK_ACCESS_DENIED')).toContain('firewall');
    expect(describeNetError('ERR_CONNECTION_TIMED_OUT')).toContain('timed out');
  });

  it('keeps unknown codes', () => {
    expect(describeNetError('ERR_SOMETHING_NEW')).toEqual('ERR_SOMETHING_NEW');
  });
});

describe('isDiagnosableUrl', () => {
  it('allows only ProxyGrid sign-in and API over https', () => {
    expect(
      isDiagnosableUrl('https://cognito-idp.ap-northeast-1.amazonaws.com/')
    ).toBeTrue();
    expect(isDiagnosableUrl('https://api.proxygrid.net/vpn/status')).toBeTrue();
    expect(isDiagnosableUrl('http://api.proxygrid.net/')).toBeFalse();
    expect(isDiagnosableUrl('https://api.proxygrid.net:8443/')).toBeFalse();
    expect(isDiagnosableUrl('https://evil.test/')).toBeFalse();
    expect(
      isDiagnosableUrl('https://cognito-idp.evil.test.amazonaws.com.evil.test/')
    ).toBeFalse();
    expect(isDiagnosableUrl('file:///c:/')).toBeFalse();
  });
});
