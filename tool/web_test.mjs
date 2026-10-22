// Uji versi web di browser sungguhan (WebKit ≈ Safari, dan Chromium):
// unduh model ke cache, jalankan mesin WASM di worker, transkripsi Al-Ikhlas.
// Setiap tahap dicatat; bila macet, tahap terakhir dilaporkan (tidak menunggu
// selamanya).
import { webkit, chromium } from 'playwright';

const url = 'http://localhost:8080/sambung-ayat/';
const LIMIT_MS = 240000;

for (const [name, bt] of [['webkit', webkit], ['chromium', chromium]]) {
  const browser = await bt.launch();
  const page = await browser.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  page.on('pageerror', (e) => logs.push('pageerror: ' + e.message));
  let r;
  try {
    await page.goto(url);
    await page.waitForFunction(() => window.qwBridge && window.qwRecorder && window.qwSpeech, null, { timeout: 60000 });
    const run = page.evaluate(async () => {
      const stage = (s) => { window.__tahap = s; };
      const base = location.origin + '/sambung-ayat/';
      const t0 = performance.now();
      try {
        let last = 0;
        stage('unduh model');
        await qwBridge.load(base + 'models/ggml-quran-tiny.bin', 43537433, (rcv) => { last = rcv; window.__progres = rcv; });
        const t1 = performance.now();
        stage('ambil audio uji');
        const buf = await (await fetch(base + 'test/ikhlas.wav')).arrayBuffer();
        const dv = new DataView(buf);
        let pos = 12, off = 0, len = 0;
        while (pos + 8 <= buf.byteLength) {
          const id = String.fromCharCode(dv.getUint8(pos), dv.getUint8(pos + 1), dv.getUint8(pos + 2), dv.getUint8(pos + 3));
          const size = dv.getUint32(pos + 4, true);
          if (id === 'data') { off = pos + 8; len = size; break; }
          pos += 8 + size + (size & 1);
        }
        const n = len >> 1, pcm = new Float32Array(n);
        for (let i = 0; i < n; i++) pcm[i] = dv.getInt16(off + i * 2, true) / 32768;
        stage('transkripsi');
        const text = await qwBridge.transcribe(pcm);
        stage('cek cache');
        const cached = await qwBridge.modelSize(base + 'models/ggml-quran-tiny.bin');
        stage('selesai');
        return { ok: true, unduh_s: +((t1 - t0) / 1000).toFixed(1), proses_s: +((performance.now() - t1) / 1000).toFixed(1),
                 progres_terakhir: last, cache: cached, speech: qwSpeech.supported(), didukung: qwBridge.supported(), text };
      } catch (e) {
        return { ok: false, err: String(e && e.message || e), tahap: window.__tahap };
      }
    });
    r = await Promise.race([run, new Promise((res) => setTimeout(() => res(null), LIMIT_MS))]);
    if (r === null) {
      const st = await page.evaluate(() => ({ tahap: window.__tahap, progres: window.__progres })).catch(() => ({}));
      r = { ok: false, err: 'MACET (lebih dari ' + LIMIT_MS / 1000 + ' detik)', ...st };
    }
  } catch (e) {
    r = { ok: false, err: String(e && e.message || e) };
  }
  console.log(`::notice title=Web ${name}::${JSON.stringify(r)}`);
  if (!r.ok) console.log(`::warning title=Log ${name}::${logs.slice(-15).join(' | ').slice(0, 900)}`);
  await browser.close().catch(() => {});
}
process.exit(0);
