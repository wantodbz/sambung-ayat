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
    load: async (url, onProgress) => { await call({ type: 'load', url }, onProgress); return true; },
    transcribe: async (pcm) => {
      // Salin hanya bagian ini (pcm bisa berupa potongan dari rekaman besar).
      const copy = pcm.slice();
      return (await call({ type: 'transcribe', pcm: copy }, null, [copy.buffer])).text;
    },
    deleteModel: async (url) => { await call({ type: 'delete', url }); return true; },
    supported: () => typeof WebAssembly === 'object' && typeof Worker === 'function' && 'caches' in self,
  };
})();
