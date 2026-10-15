// Uji versi web di browser sungguhan (WebKit ≈ Safari, dan Chromium):
// unduh model ke cache, jalankan mesin WASM di worker, transkripsi Al-Ikhlas.
import { webkit, chromium } from 'playwright';

const url = 'http://localhost:8080/sambung-ayat/';
for (const [name, bt] of [['webkit', webkit], ['chromium', chromium]]) {
  const browser = await bt.launch();
  const page = await browser.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  page.on('pageerror', (e) => logs.push('pageerror: ' + e.message));
  await page.goto(url);
  await page.waitForFunction(() => window.qwBridge && window.qwRecorder && window.qwSpeech, null, { timeout: 60000 });
  const r = await page.evaluate(async () => {
    const base = location.origin + '/sambung-ayat/';
    const t0 = performance.now();
    try {
      let last = 0;
      await qwBridge.load(base + 'models/ggml-quran-tiny.bin', (rcv) => { last = rcv; });
      const t1 = performance.now();
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
      const text = await qwBridge.transcribe(pcm);
      const cached = await qwBridge.modelSize(base + 'models/ggml-quran-tiny.bin');
      return { ok: true, unduh_s: +((t1 - t0) / 1000).toFixed(1), proses_s: +((performance.now() - t1) / 1000).toFixed(1),
               progres_terakhir: last, cache: cached, speech: qwSpeech.supported(), didukung: qwBridge.supported(), text };
    } catch (e) {
      return { ok: false, err: String(e && e.message || e) };
    }
  });
  console.log(`::notice title=Web ${name}::${JSON.stringify(r)}`);
  if (!r.ok) console.log(`::warning title=Log ${name}::${logs.slice(-15).join(' | ').slice(0, 900)}`);
  await browser.close();
}
