// Worker: menjalankan whisper.cpp (WebAssembly) agar layar tidak membeku.
/* global createQW */
importScripts('qw.js');

let Module = null;
let ctx = 0;
let loadedUrl = null;

async function getModule() {
  if (!Module) Module = await createQW();
  return Module;
}

async function fetchModel(url, id) {
  const cache = await caches.open('sambung-ayat-model');
  let res = await cache.match(url);
  if (res) {
    return new Uint8Array(await res.arrayBuffer());
  }
  res = await fetch(url);
  if (!res.ok) throw new Error('Server menjawab ' + res.status);
  const total = Number(res.headers.get('Content-Length')) || 0;
  const reader = res.body.getReader();
  const parts = [];
  let received = 0, lastSent = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    parts.push(value);
    received += value.length;
    if (received - lastSent > 512 * 1024) {
      lastSent = received;
      postMessage({ id, type: 'progress', received, total });
    }
  }
  const bytes = new Uint8Array(received);
  let o = 0;
  for (const p of parts) { bytes.set(p, o); o += p.length; }
  if (total && received !== total) throw new Error('Unduhan terputus');
  try {
    await cache.put(url, new Response(bytes, { headers: { 'Content-Length': String(received) } }));
  } catch (_) { /* memori browser penuh: tetap lanjut tanpa cache */ }
  return bytes;
}

onmessage = async (e) => {
  const { id, type } = e.data;
  try {
    if (type === 'load') {
      const url = e.data.url;
      if (ctx && loadedUrl === url) { postMessage({ id, type: 'done' }); return; }
      const M = await getModule();
      const bytes = await fetchModel(url, id);
      if (ctx) { M._qw_free(ctx); ctx = 0; loadedUrl = null; }
      const ptr = M._malloc(bytes.length);
      M.HEAPU8.set(bytes, ptr);
      ctx = M._qw_init_from_buffer(ptr, bytes.length);
      M._free(ptr);
      if (!ctx) throw new Error('Model gagal dimuat');
      loadedUrl = url;
      postMessage({ id, type: 'done' });
    } else if (type === 'transcribe') {
      const M = await getModule();
      if (!ctx) throw new Error('Model belum dimuat');
      const pcm = e.data.pcm;
      const p = M._malloc(pcm.length * 4);
      M.HEAPF32.set(pcm, p >> 2);
      const outLen = 32768;
      const out = M._malloc(outLen);
      // Konteks audio sepanjang potongan (bukan 30 detik penuh) dan batas
      // token: hasil sama, ±40% lebih cepat (uji At-Tahrim).
      const sec = pcm.length / 16000;
      const audioCtx = Math.min(1500, Math.floor(sec * 50) + 64);
      const maxTokens = Math.min(220, Math.ceil(sec * 12) + 16);
      const n = M._qw_transcribe_ex
        ? M._qw_transcribe_ex(ctx, p, pcm.length, 1, maxTokens, audioCtx, 0, out, outLen)
        : M._qw_transcribe(ctx, p, pcm.length, 1, out, outLen);
      const text = n > 0 ? M.UTF8ToString(out, n) : '';
      M._free(p); M._free(out);
      if (n < 0) throw new Error('Pemrosesan gagal');
      postMessage({ id, type: 'done', text });
    } else if (type === 'has') {
      const cache = await caches.open('sambung-ayat-model');
      const res = await cache.match(e.data.url);
      postMessage({ id, type: 'done', size: res ? Number(res.headers.get('Content-Length')) || 1 : 0 });
    } else if (type === 'delete') {
      const cache = await caches.open('sambung-ayat-model');
      await cache.delete(e.data.url);
      if (loadedUrl === e.data.url && ctx) { (await getModule())._qw_free(ctx); ctx = 0; loadedUrl = null; }
      postMessage({ id, type: 'done' });
    }
  } catch (err) {
    postMessage({ id, type: 'error', message: String(err && err.message || err) });
  }
};
