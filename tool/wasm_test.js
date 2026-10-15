// Uji mesin whisper WebAssembly (varian Node) dengan murottal: memastikan
// pemuatan model dari memori & transkripsi berjalan, serta mengukur kecepatan.
const fs = require('fs');
const createQW = require(process.argv[2]);
(async () => {
  const M = await createQW();
  const model = fs.readFileSync(process.argv[3]);
  const p = M._malloc(model.length);
  M.HEAPU8.set(model, p);
  const ctx = M._qw_init_from_buffer(p, model.length);
  M._free(p);
  if (!ctx) { console.log('::error title=WASM::model gagal dimuat'); process.exit(1); }
  const wav = fs.readFileSync(process.argv[4]);
  let pos = 12, data = null;
  while (pos + 8 <= wav.length) {
    const id = wav.toString('ascii', pos, pos + 4), size = wav.readUInt32LE(pos + 4);
    if (id === 'data') { data = wav.subarray(pos + 8, pos + 8 + size); break; }
    pos += 8 + size + (size & 1);
  }
  const n = data.length >> 1;
  const pcm = new Float32Array(n);
  for (let i = 0; i < n; i++) pcm[i] = data.readInt16LE(i * 2) / 32768;
  const pp = M._malloc(n * 4);
  M.HEAPF32.set(pcm, pp >> 2);
  const out = M._malloc(32768);
  const t = Date.now();
  const len = M._qw_transcribe(ctx, pp, n, 1, out, 32768);
  const secs = ((Date.now() - t) / 1000).toFixed(1);
  const text = len > 0 ? M.UTF8ToString(out, len) : '(kosong)';
  console.log(`::notice title=WASM ${process.argv[5]}::${secs}s untuk ${(n / 16000).toFixed(0)}s audio :: ${text}`);
  if (len <= 0) process.exit(1);
})();
