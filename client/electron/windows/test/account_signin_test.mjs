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

// Checks that the installed app can reach ProxyGrid sign-in (Cognito) from its own renderer.
//
// Starts the installed ProxyGridVPN.exe with Chromium's remote debugging port, then inside the
// app's page: (1) sends one raw request to the Cognito endpoint the app is configured for, and
// (2) runs the app's real sign-in with a made-up account and a wrong password. The expected
// result is Cognito's "incorrect username or password", never a network error. No account is
// created and no credentials are used.
//
// Usage: node account_signin_test.mjs <path to ProxyGridVPN.exe>
// Requires Node 22 (global WebSocket and fetch).

/* global fetch, WebSocket */
/* eslint-disable n/no-process-exit */
import {spawn} from 'node:child_process';
import {setTimeout as sleep} from 'node:timers/promises';

const exe = process.argv[2];
if (!exe) {
  console.error('usage: node account_signin_test.mjs <ProxyGridVPN.exe>');
  process.exit(2);
}
const PORT = 9333;
const PROBE_EMAIL = 'ci-signin-probe@proxygrid.invalid';
const NETWORK_ERROR = 'Could not reach the sign-in service.';

const app = spawn(exe, [`--remote-debugging-port=${PORT}`], {
  stdio: 'ignore',
  detached: false,
});

async function pageTarget() {
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (
        await fetch(`http://127.0.0.1:${PORT}/json/list`)
      ).json();
      const page = list.find(t => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) return page;
    } catch {
      // Not listening yet.
    }
    await sleep(1000);
  }
  throw new Error('the app did not open a debuggable page within 60 s');
}

function connect(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  const consoleLines = [];
  ws.onmessage = ev => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    } else if (msg.method === 'Runtime.consoleAPICalled') {
      consoleLines.push(
        `${msg.params.type}: ${msg.params.args.map(a => a.value ?? a.description ?? '').join(' ')}`
      );
    } else if (msg.method === 'Runtime.exceptionThrown') {
      consoleLines.push(
        `exception: ${msg.params.exceptionDetails?.exception?.description ?? ''}`
      );
    }
  };
  const send = (method, params = {}) =>
    new Promise(resolve => {
      const n = ++id;
      pending.set(n, resolve);
      ws.send(JSON.stringify({id: n, method, params}));
    });
  const evaluate = async expression => {
    const r = await send('Runtime.evaluate', {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (r.result?.exceptionDetails) {
      throw new Error(
        r.result.exceptionDetails.exception?.description ?? 'evaluation failed'
      );
    }
    return r.result?.result?.value;
  };
  return new Promise((resolve, reject) => {
    ws.onopen = () =>
      resolve({send, evaluate, consoleLines, close: () => ws.close()});
    ws.onerror = () => reject(new Error('could not connect to the app page'));
  });
}

const failures = [];
function check(name, ok, detail = '') {
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`
  );
  if (!ok) failures.push(name);
}

try {
  const page = await pageTarget();
  const cdp = await connect(page.webSocketDebuggerUrl);
  await cdp.send('Runtime.enable');

  // Wait for the app to finish starting (the ProxyGrid account is attached to <app-root>).
  let ready = false;
  for (let i = 0; i < 60 && !ready; i++) {
    ready = await cdp.evaluate(
      "!!document.querySelector('app-root')?.proxyGridAccount"
    );
    if (!ready) await sleep(1000);
  }
  check('app started with the ProxyGrid account', ready);

  // 1. One raw request from the renderer to the configured Cognito endpoint.
  const raw = await cdp.evaluate(`(async () => {
    const out = {online: navigator.onLine, origin: location.origin};
    try {
      const r = await fetch('https://cognito-idp.ap-northeast-1.amazonaws.com/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-amz-json-1.1',
          'X-Amz-Target': 'AWSCognitoIdentityProviderService.GetUser',
        },
        body: JSON.stringify({AccessToken: 'invalid'}),
      });
      out.status = r.status;
    } catch (e) {
      out.error = String(e && e.message || e);
    }
    try {
      out.apiStatus = (await fetch('https://api.proxygrid.net/vpn/status')).status;
    } catch (e) {
      out.apiError = String(e && e.message || e);
    }
    return out;
  })()`);
  console.log('  renderer probe:', JSON.stringify(raw));
  check(
    'renderer reaches Cognito',
    typeof raw.status === 'number',
    raw.error ?? `HTTP ${raw.status}`
  );
  check(
    'renderer reaches the ProxyGrid API',
    typeof raw.apiStatus === 'number',
    raw.apiError ?? `HTTP ${raw.apiStatus}`
  );

  // The main-process diagnosis used when the renderer cannot connect. On a working network it
  // reaches Cognito itself and says so.
  const diagnosis = await cdp.evaluate(`(async () => JSON.parse(
    await window.electron.methodChannel.invoke('invoke-method', 'DiagnoseConnection',
      JSON.stringify({url: 'https://cognito-idp.ap-northeast-1.amazonaws.com/'}))
  ).reason)()`);
  check(
    'connection diagnosis reaches Cognito from the main process',
    typeof diagnosis === 'string' && diagnosis.includes('works from the app itself'),
    String(diagnosis)
  );

  // 2. The app's real sign-in with a made-up account.
  await cdp.evaluate(`(() => {
    const root = document.querySelector('app-root');
    root.dispatchEvent(new CustomEvent('ProxyGridSignIn', {
      detail: {email: ${JSON.stringify(PROBE_EMAIL)}, password: 'wrong-password-ci'},
      bubbles: true,
      composed: true,
    }));
  })()`);
  let error = null;
  for (let i = 0; i < 30 && !error; i++) {
    await sleep(1000);
    error = await cdp.evaluate(
      "document.querySelector('app-root')?.proxyGridAccount?.error ?? null"
    );
  }
  console.log(`  sign-in result: ${JSON.stringify(error)}`);
  check(
    'sign-in reaches Cognito (no network error)',
    !!error && error !== NETWORK_ERROR,
    error ?? 'no result'
  );
  check(
    'sign-in reports incorrect credentials',
    /incorrect/i.test(error ?? ''),
    error ?? ''
  );
  if (failures.length) {
    console.log('  --- renderer console ---');
    for (const line of cdp.consoleLines.slice(-40)) console.log(`  ${line}`);
  }
  cdp.close();
} catch (e) {
  check('sign-in test ran', false, e.message);
} finally {
  app.kill();
}

if (failures.length) {
  console.log(`${failures.length} sign-in check(s) failed`);
  process.exit(1);
}
console.log('All sign-in checks passed.');
process.exit(0);
