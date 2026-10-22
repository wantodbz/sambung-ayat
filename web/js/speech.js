// Pengenal suara bawaan Safari/Chrome (Web Speech API) untuk Sambung Ayat.
(function () {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  // iPhone: aplikasi yang dibuka dari Layar Utama tidak mendapat pengenal
  // suara Safari (WebKit bug 225298), jadi langsung pakai model di HP.
  const homeScreenApp = window.navigator.standalone === true;
  let rec = null;
  let watchdog = 0;
  window.qwSpeech = {
    supported: function () { return !!SR && !homeScreenApp; },
    // onResult(text, isFinal), onEnd(), onError(code)
    // Galat khusus 'no-audio': mikrofon tidak pernah aktif dalam 4 detik
    // (pengenal suara macet), instansinya sudah dibuang.
    start: function (lang, onResult, onEnd, onError) {
      try { if (rec) { rec.onend = null; rec.abort(); } } catch (_) {}
      clearTimeout(watchdog);
      rec = new SR();
      const mine = rec;
      let audioStarted = false;
      // Tanda pengenal suara hidup: start/audiostart/hasil.
      rec.onstart = rec.onaudiostart = function () { audioStarted = true; };
      watchdog = setTimeout(function () {
        if (audioStarted || rec !== mine) return;
        try { mine.onend = null; mine.onresult = null; mine.onerror = null; mine.abort(); } catch (_) {}
        rec = null;
        onError('no-audio');
      }, 4000);
      rec.lang = lang;
      rec.continuous = true;
      rec.interimResults = true;
      rec.maxAlternatives = 1;
      rec.onresult = function (e) {
        audioStarted = true;
        let finalText = '', interim = '';
        for (let i = e.resultIndex; i < e.results.length; i++) {
          const r = e.results[i];
          if (r.isFinal) finalText += r[0].transcript + ' ';
          else interim += r[0].transcript + ' ';
        }
        if (finalText.trim()) onResult(finalText.trim(), true);
        else if (interim.trim()) onResult(interim.trim(), false);
      };
      rec.onerror = function (e) { onError(String(e.error || 'error')); };
      rec.onend = function () { onEnd(); };
      try { rec.start(); return true; } catch (err) { onError('start-failed'); return false; }
    },
    stop: function () {
      clearTimeout(watchdog);
      try { if (rec) { rec.onend = null; rec.onresult = null; rec.abort(); } } catch (_) {}
      rec = null;
    },
  };
})();
