// Uji situs web yang sudah tayang (GitHub Pages): unduh model lewat jembatan
// aplikasi di WebKit (≈ Safari) dan Chromium, seperti yang dilakukan iPhone.
import { webkit, chromium } from 'playwright';

const site = process.env.SITE || 'https://wantodbz.github.io/sambung-ayat/';
for (const [name, bt] of [['webkit', webkit], ['chromium', chromium]]) {
  const browser = await bt.launch();
  const page = await browser.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  page.on('pageerror', (e) => logs.push('pageerror: ' + e.message));
  await page.goto(site);
  await page.waitForFunction(() => window.qwBridge && window.qwRecorder && window.qwSpeech, null, { timeout: 90000 });
  for (const m of ['tiny', 'base']) {
    const r = await page.evaluate(async (m) => {
      const url = new URL('models/ggml-quran-' + m + '.bin', location.href).href;
      const t0 = performance.now();
      let last = 0, total = 0, n = 0;
      try {
        await qwBridge.load(url, m === 'tiny' ? 43537433 : 81768585, (rcv, tot) => { last = rcv; total = tot; n++; });
        const cached = await qwBridge.modelSize(url);
        return { ok: true, detik: +((performance.now() - t0) / 1000).toFixed(1), progres: last, total, kali: n, cache: cached };
      } catch (e) {
        return { ok: false, err: String(e && e.message || e), progres: last, total, kali: n };
      }
    }, m);
    console.log(`::notice title=Situs ${name} model ${m}::${JSON.stringify(r)}`);
    if (!r.ok) {
      console.log(`::error title=Unduh model ${m} gagal (${name})::${r.err} | ${logs.slice(-10).join(' | ').slice(0, 700)}`);
      process.exitCode = 1;
    }
  }
  await browser.close();
}
