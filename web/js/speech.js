// Pengenal suara bawaan Safari/Chrome (Web Speech API) untuk Sambung Ayat.
(function () {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  // iPhone: aplikasi yang dibuka dari Layar Utama tidak mendapat pengenal
  // suara Safari (WebKit bug 225298), jadi langsung pakai model di HP.
  const homeScreenApp = window.navigator.standalone === true;
  let rec = null;
  window.qwSpeech = {
    supported: function () { return !!SR && !homeScreenApp; },
    // onResult(text, isFinal), onEnd(), onError(code)
    start: function (lang, onResult, onEnd, onError) {
      try { if (rec) { rec.onend = null; rec.abort(); } } catch (_) {}
      rec = new SR();
      rec.lang = lang;
      rec.continuous = true;
      rec.interimResults = true;
      rec.maxAlternatives = 1;
      rec.onresult = function (e) {
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
      try { if (rec) { rec.onend = null; rec.onresult = null; rec.abort(); } } catch (_) {}
      rec = null;
    },
  };
})();
