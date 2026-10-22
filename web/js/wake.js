// Jaga layar tetap menyala selama sesi latihan (Screen Wake Lock API).
// Bila layar mati, Safari menghentikan mikrofon dan pemrosesan.
(function () {
  let lock = null;
  let want = false;

  async function acquire() {
    if (!want || lock || !('wakeLock' in navigator)) return;
    try {
      lock = await navigator.wakeLock.request('screen');
      lock.addEventListener('release', () => { lock = null; });
    } catch (_) { /* tidak didukung / ditolak: abaikan */ }
  }

  // Kunci dilepas otomatis saat halaman tersembunyi; minta lagi saat kembali.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') acquire();
  });

  window.qwWake = function (on) {
    want = !!on;
    if (want) {
      acquire();
    } else if (lock) {
      lock.release().catch(() => {});
      lock = null;
    }
  };
})();
