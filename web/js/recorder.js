// Perekam mikrofon untuk versi web: hasil langsung diturunkan ke 16 kHz mono
// (format yang dibutuhkan model), disimpan di memori, tanpa berkas.
(function () {
  const OUT_RATE = 16000;
  let ctx = null, stream = null, src = null, node = null, sink = null;
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
      if (!ctx) {
        const AC = window.AudioContext || window.webkitAudioContext;
        ctx = new AC();
      }
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

  // Pemutar murottal: satu elemen audio yang "dibuka" saat ketukan pertama,
  // agar pemutaran berikutnya diizinkan iPhone.
  const audio = new Audio();
  audio.preload = 'auto';
  let unlocked = false;
  window.qwAudio = {
    unlock: function () {
      if (unlocked) return;
      unlocked = true;
      // WAV hening sangat pendek
      audio.src = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YQAAAAA=';
      audio.play().catch(() => {});
    },
    // Putar url sampai selesai. Promise selesai (true) atau gagal (false).
    play: function (url) {
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
    },
    stop: function () { try { audio.pause(); } catch (_) {} },
  };
})();
