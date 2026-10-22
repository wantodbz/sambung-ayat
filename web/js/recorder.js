// Perekam mikrofon untuk versi web: hasil langsung diturunkan ke 16 kHz mono
// (format yang dibutuhkan model), disimpan di memori, tanpa berkas.
(function () {
  const OUT_RATE = 16000;
  let ctx = null, stream = null, src = null, node = null, sink = null;
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  // Satu AudioContext untuk merekam dan memutar murottal.
  function audioContext() {
    if (!ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      ctx = new AC();
    }
    return ctx;
  }
  let capturing = false, chunks = [], level = 0;
  let ratio = 3, nextBoundary = 3, g = 0, acc = 0, accN = 0;

  function resetResampler() {
    ratio = ctx ? ctx.sampleRate / OUT_RATE : 3;
    nextBoundary = ratio; g = 0; acc = 0; accN = 0;
  }

  function onAudio(e) {
    const input = e.inputBuffer.getChannelData(0);
    let sum = 0;
    for (let i = 0; i < input.length; i++) sum += input[i] * input[i];
    const rms = Math.sqrt(sum / input.length);
    // ke skala 0..1 (≈ dBFS -50..0)
    const db = 20 * Math.log10(rms + 1e-9);
    level = Math.max(0, Math.min(1, (db + 50) / 50));
    if (!capturing) return;
    const out = new Float32Array(Math.ceil(input.length / ratio) + 2);
    let n = 0;
    for (let i = 0; i < input.length; i++) {
      acc += input[i]; accN++; g++;
      if (g >= nextBoundary) {
        out[n++] = acc / accN; acc = 0; accN = 0; nextBoundary += ratio;
      }
    }
    chunks.push(out.subarray(0, n));
  }

  window.qwRecorder = {
    // Harus dipanggil dari ketukan pengguna (aturan iPhone).
    open: async function () {
      audioContext();
      if (ctx.state !== 'running') { try { await ctx.resume(); } catch (_) {} }
      if (!stream) {
        stream = await navigator.mediaDevices.getUserMedia({
          audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
        });
        src = ctx.createMediaStreamSource(stream);
        node = ctx.createScriptProcessor(4096, 1, 1);
        node.onaudioprocess = onAudio;
        sink = ctx.createGain();
        sink.gain.value = 0;
        src.connect(node); node.connect(sink); sink.connect(ctx.destination);
      }
      return true;
    },
    begin: function () {
      chunks = []; resetResampler(); capturing = true;
      if (ctx && ctx.state !== 'running') ctx.resume().catch(() => {});
    },
    // Mengembalikan seluruh rekaman (Float32Array 16 kHz) lalu mengosongkan memori.
    end: function () {
      capturing = false;
      return this.take();
    },
    // Ambil suara yang terekam sejak pengambilan terakhir tanpa menghentikan
    // perekaman (Murajaah: diperiksa sambil membaca).
    take: function () {
      let total = 0;
      for (const c of chunks) total += c.length;
      const pcm = new Float32Array(total);
      let o = 0;
      for (const c of chunks) { pcm.set(c, o); o += c.length; }
      chunks = [];
      return pcm;
    },
    discard: function () { capturing = false; chunks = []; },
    level: function () { return level; },
    seconds: function () {
      let total = 0;
      for (const c of chunks) total += c.length;
      return total / OUT_RATE;
    },
    close: function () {
      capturing = false; chunks = [];
      try { if (stream) stream.getTracks().forEach((t) => t.stop()); } catch (_) {}
      try { if (node) node.disconnect(); if (src) src.disconnect(); if (sink) sink.disconnect(); } catch (_) {}
      stream = null; src = null; node = null; sink = null;
    },
  };

  // Pemutar murottal lewat Web Audio API. Di iOS 26+, setelah elemen <audio>
  // memutar suara, pengenal suara Safari berhenti total tanpa kabar galat
  // (WebKit bug 321436); Web Audio tidak mengganggu sesi pengenal suara.
  // Elemen <audio> hanya dipakai sebagai cadangan bila Web Audio gagal.
  const audio = new Audio();
  audio.preload = 'auto';
  let current = null; // { src, resolve } yang sedang diputar
  let playGen = 0; // naik setiap stop(): pemutaran yang masih dimuat dibatalkan
  let sessionSet = false;

  function resumeCtx(c, ms) {
    if (c.state === 'running') return Promise.resolve(true);
    return Promise.race([
      c.resume().then(() => c.state === 'running').catch(() => false),
      new Promise((r) => setTimeout(() => r(c.state === 'running'), ms)),
    ]);
  }

  function playElement(url) {
    return new Promise((resolve) => {
      let done = false;
      const finish = (ok) => { if (!done) { done = true; cleanup(); resolve(ok); } };
      const onEnd = () => finish(true);
      const onErr = () => finish(false);
      function cleanup() {
        audio.removeEventListener('ended', onEnd);
        audio.removeEventListener('pause', onEnd);
        audio.removeEventListener('error', onErr);
      }
      audio.addEventListener('ended', onEnd);
      audio.addEventListener('pause', onEnd);
      audio.addEventListener('error', onErr);
      audio.src = url;
      audio.play().catch(() => finish(false));
    });
  }

  window.qwAudio = {
    // Dipanggil dari ketukan pengguna (aturan iPhone).
    unlock: function () {
      const c = audioContext();
      if (c.state !== 'running') c.resume().catch(() => {});
      try {
        const b = c.createBuffer(1, 1, 22050);
        const s = c.createBufferSource();
        s.buffer = b; s.connect(c.destination); s.start(0);
      } catch (_) {}
      // iOS 17+: tetapkan sesi audio "putar & rekam" sekali di awal sesi,
      // agar murottal tetap lewat speaker (juga saat mode senyap) dan tidak
      // berganti-ganti sesi dengan mikrofon.
      if (isIOS && !sessionSet && navigator.audioSession) {
        try { navigator.audioSession.type = 'play-and-record'; sessionSet = true; } catch (_) {}
      }
    },
    // Putar url sampai selesai. Promise selesai (true) atau gagal (false).
    play: async function (url) {
      const c = audioContext();
      const gen = playGen;
      try {
        if (!(await resumeCtx(c, 1500))) throw new Error('AudioContext tidak berjalan');
        const res = await fetch(url);
        if (!res.ok) return false;
        const buf = await c.decodeAudioData(await res.arrayBuffer());
        if (gen !== playGen) return true; // dihentikan saat memuat
        return await new Promise((resolve) => {
          const s = c.createBufferSource();
          s.buffer = buf;
          s.connect(c.destination);
          current = { src: s, resolve };
          s.onended = () => {
            if (current && current.src === s) current = null;
            resolve(true);
          };
          s.start(0);
        });
      } catch (_) {
        if (gen !== playGen) return true;
        return playElement(url); // cadangan
      }
    },
    stop: function () {
      playGen++;
      const cur = current;
      current = null;
      if (cur) {
        try { cur.src.onended = null; cur.src.stop(); } catch (_) {}
        cur.resolve(true);
      }
      try { audio.pause(); } catch (_) {}
    },
  };
})();
