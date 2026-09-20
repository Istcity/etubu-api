/**
 * ETUBU Identity & Account Module
 */
const Identity = (() => {
  let user = null;

  function init() {
    try {
      const stored = localStorage.getItem("etubu_user");
      if (stored) user = JSON.parse(stored);
    } catch (_) {}
    refreshAccountUi();
  }

  function refreshAccountUi() {
    // Account UI updates if elements present
    const el = document.getElementById("accountStatus");
    if (el) {
      el.textContent = user ? (user.name || user.email) : "";
    }
  }

  function syncToServer(km) {
    void km;
  }

  function scheduleSync(km) {
    void km;
  }

  function pullFromServer() {
    return Promise.resolve(null);
  }

  function getUser() {
    return user;
  }

  return {
    init,
    refreshAccountUi,
    syncToServer,
    scheduleSync,
    pullFromServer,
    getUser,
  };
})();

try {
  window.Identity = Identity;
} catch (_) {}
