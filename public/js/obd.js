/**
 * ETUBU OBD-II Module
 */
const ObdLink = (() => {
  function init() {}
  function disconnect() {}
  function isConnected() { return false; }
  return { init, disconnect, isConnected };
})();

try {
  window.ObdLink = ObdLink;
} catch (_) {}
