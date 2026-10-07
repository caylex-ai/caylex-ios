import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';
import { setTimeout as delay } from 'node:timers/promises';
import { webcrypto } from 'node:crypto';

const source = readFileSync(new URL('../../Sources/CaylexChat/Resources/native-fetch.js', import.meta.url), 'utf8');
function fixture() {
  const messages = [];
  const fallback = [];
  const window = {
    fetch: async (...args) => { fallback.push(args); return new Response('fallback'); },
    webkit: { messageHandlers: { caylexHTTP: { postMessage: (message) => messages.push(message) } } },
  };
  const context = vm.createContext({ window, location: new URL('http://127.0.0.1:9999/widget/index.html'),
    URL, Request, Response, ReadableStream, Uint8Array, DOMException, crypto: webcrypto, btoa, atob });
  vm.runInContext(source, context);
  window.CaylexHTTP.configure('https://api.caylex.ai/api/v1/assistants/');
  return { window, messages, fallback };
}
async function dispatched(f) {
  const deadline = performance.now() + 2000;
  while (performance.now() < deadline) {
    const request = f.messages.find((message) => message.type === 'request');
    if (request) return request;
    await delay(5);
  }
  throw new Error('Native bridge request was not dispatched within 2 seconds');
}

test('stream reaches the reader before native completion', async () => {
  const f = fixture();
  const promise = f.window.fetch('https://api.caylex.ai/api/v1/assistants/chat/stream', {
    method: 'POST', headers: { Authorization: 'Bearer widget-token', 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: 'hello' }),
  });
  const request = await dispatched(f);
  assert.equal(request.headers.authorization, 'Bearer widget-token');
  assert.deepEqual(JSON.parse(Buffer.from(request.body, 'base64').toString()), { message: 'hello' });
  f.window.CaylexHTTP.receive({ id: request.id, type: 'headers', status: 200, headers: { 'content-type': 'text/event-stream' } });
  const response = await promise;
  const reader = response.body.getReader();
  f.window.CaylexHTTP.receive({ id: request.id, type: 'data', data: Buffer.from('data: hello\n\n').toString('base64') });
  const first = await reader.read();
  assert.equal(new TextDecoder().decode(first.value), 'data: hello\n\n');
  assert.equal(first.done, false);
  f.window.CaylexHTTP.receive({ id: request.id, type: 'end' });
  assert.equal((await reader.read()).done, true);
});

test('multipart uploads keep their generated content type and file bytes', async () => {
  const f = fixture();
  const data = new FormData();
  data.append('file', new Blob(['attachment content'], { type: 'text/plain' }), 'notes.txt');
  const promise = f.window.fetch('https://api.caylex.ai/api/v1/assistants/files/parse', { method: 'POST', body: data });
  const request = await dispatched(f);
  assert.match(request.headers['content-type'], /^multipart\/form-data; boundary=/);
  const body = Buffer.from(request.body, 'base64').toString();
  assert.match(body, /filename="notes.txt"/);
  assert.match(body, /attachment content/);
  f.window.CaylexHTTP.receive({ id: request.id, type: 'headers', status: 204, headers: {} });
  f.window.CaylexHTTP.receive({ id: request.id, type: 'end' });
  assert.equal((await promise).status, 204);
});

test('abort cancels a native request before response headers', async () => {
  const f = fixture();
  const abort = new AbortController();
  const promise = f.window.fetch('https://api.caylex.ai/api/v1/assistants/chat/stream', { signal: abort.signal });
  const request = await dispatched(f);
  abort.abort();
  await assert.rejects(promise, { name: 'AbortError' });
  assert.ok(f.messages.some((message) => message.id === request.id && message.type === 'abort'));
});

test('non-API origins and neighboring paths use ordinary fetch', async () => {
  const f = fixture();
  await f.window.fetch('https://example.com/logo.png');
  await f.window.fetch('https://api.caylex.ai/api/v1/assistants-other/init');
  assert.equal(f.messages.length, 0);
  assert.equal(f.fallback.length, 2);
});

test('401 stays a normal Response so existing widget refresh logic can retry', async () => {
  const f = fixture();
  const promise = f.window.fetch('https://api.caylex.ai/api/v1/assistants/init');
  const request = await dispatched(f);
  f.window.CaylexHTTP.receive({ id: request.id, type: 'headers', status: 401, headers: {} });
  f.window.CaylexHTTP.receive({ id: request.id, type: 'data', data: Buffer.from('{"detail":"expired"}').toString('base64') });
  f.window.CaylexHTTP.receive({ id: request.id, type: 'end' });
  const response = await promise;
  assert.equal(response.ok, false);
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { detail: 'expired' });
});
