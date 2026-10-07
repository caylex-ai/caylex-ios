(() => {
  const originalFetch = window.fetch.bind(window);
  let apiBase;
  const pending = new Map();
  const native = (message) => window.webkit.messageHandlers.caylexHTTP.postMessage(message);
  const decode = (base64) => Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  const encode = (bytes) => {
    let binary = '';
    for (let i = 0; i < bytes.length; i += 16384) {
      binary += String.fromCharCode(...bytes.subarray(i, i + 16384));
    }
    return btoa(binary);
  };
  const isAPI = (url) => {
    if (!apiBase) return false;
    const target = new URL(url, location.href);
    return target.origin === apiBase.origin && target.pathname.startsWith(apiBase.pathname);
  };
  window.CaylexHTTP = {
    configure(base) { apiBase = new URL(base.endsWith('/') ? base : base + '/'); },
    receive(event) {
      const operation = pending.get(event.id);
      if (!operation) return;
      if (event.type === 'headers') {
        const empty = [204, 205, 304].includes(event.status) || operation.method === 'HEAD';
        operation.resolve(new Response(empty ? null : operation.stream, {
          status: event.status, headers: event.headers,
        }));
        operation.started = true;
      } else if (event.type === 'data') {
        operation.controller.enqueue(decode(event.data));
      } else if (event.type === 'end') {
        operation.controller.close();
        pending.delete(event.id);
        operation.cleanup();
      } else if (event.type === 'error') {
        const error = new TypeError(event.message || 'Network request failed');
        operation.controller.error(error);
        if (!operation.started) operation.reject(error);
        pending.delete(event.id);
        operation.cleanup();
      }
    },
  };
  window.fetch = async (input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    if (!isAPI(url)) return originalFetch(input, init);
    const request = new Request(input, init);
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (request.signal.aborted) throw new DOMException('Aborted', 'AbortError');
    const id = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      let controller;
      const cleanup = () => request.signal.removeEventListener('abort', abort);
      const abort = () => {
        native({ type: 'abort', id });
        const error = new DOMException('Aborted', 'AbortError');
        controller.error(error);
        reject(error);
        pending.delete(id);
        cleanup();
      };
      const stream = new ReadableStream({
        start(value) { controller = value; },
        cancel() { native({ type: 'abort', id }); pending.delete(id); cleanup(); },
      });
      pending.set(id, { resolve, reject, controller, stream, cleanup, method: request.method, started: false });
      request.signal.addEventListener('abort', abort, { once: true });
      native({ type: 'request', id, url: request.url, method: request.method,
        headers: Object.fromEntries(request.headers.entries()), body: encode(bytes) });
    });
  };
})();
