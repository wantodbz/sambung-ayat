// Jembatan antara aplikasi (Dart) dan worker whisper.
(function () {
  let worker = null;
  let nextId = 1;
  const pending = new Map();

  function getWorker() {
    if (!worker) {
      worker = new Worker('whisper/qw_worker.js');
      worker.onmessage = (e) => {
        const m = e.data;
        const p = pending.get(m.id);
        if (!p) return;
        if (m.type === 'progress') { if (p.onProgress) p.onProgress(m.received, m.total); return; }
        pending.delete(m.id);
        if (m.type === 'error') p.reject(new Error(m.message));
        else p.resolve(m);
      };
      worker.onerror = (e) => {
        for (const p of pending.values()) p.reject(new Error(e.message || 'Worker galat'));
        pending.clear();
        worker = null;
      };
    }
    return worker;
  }

  function call(msg, onProgress, transfer) {
    return new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject, onProgress });
      getWorker().postMessage(Object.assign({ id }, msg), transfer || []);
    });
  }

  window.qwBridge = {
    // Ukuran model tersimpan (0 bila belum ada).
    modelSize: async (url) => (await call({ type: 'has', url })).size,
    // size: ukuran asli model (bita) untuk memeriksa keutuhan unduhan.
    load: async (url, size, onProgress) => {
      if (typeof size === 'function') { onProgress = size; size = 0; }
      await call({ type: 'load', url, size: size || 0 }, onProgress);
      return true;
    },
    transcribe: async (pcm) => {
      // Salin hanya bagian ini (pcm bisa berupa potongan dari rekaman besar).
      const copy = pcm.slice();
      return (await call({ type: 'transcribe', pcm: copy }, null, [copy.buffer])).text;
    },
    deleteModel: async (url) => { await call({ type: 'delete', url }); return true; },
    // Perlu WebAssembly SIMD (Safari/iOS 16.4+), Worker, dan Cache API.
    supported: () => {
      try {
        return typeof WebAssembly === 'object' && typeof Worker === 'function' && 'caches' in self &&
          WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,96,0,1,123,3,2,1,0,10,10,1,8,0,65,0,253,15,253,98,11]));
      } catch (_) { return false; }
    },
  };
})();
