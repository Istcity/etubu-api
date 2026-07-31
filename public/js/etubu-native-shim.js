/**
 * Capacitor EtubuNative shim — StoreKit, Live Activity, ses karışımı.
 * Capacitor köprüsü hazır olana kadar yeniden dener (head'de erken yükleme güvenli).
 */
(function () {
  if (window.EtubuNative) return;

  function wireNative() {
    if (window.EtubuNative) return true;
    var Cap = window.Capacitor;
    if (!Cap || !Cap.Plugins || !Cap.Plugins.EtubuNative) return false;
    var P = Cap.Plugins.EtubuNative;
    window.EtubuNative = {
      purchase: function (productId) {
        return P.purchase({ productId: productId });
      },
      restore: function () {
        return P.restore();
      },
      showBannerAds: function () {
        return P.showBannerAds();
      },
      hideAds: function () {
        return P.hideAds();
      },
      setAudioMixMode: function (mode) {
        return P.setAudioMixMode({ mode: mode || "blend" });
      },
      showAudioRoutePicker: function () {
        return P.showAudioRoutePicker();
      },
      startDriveSession: function (payload) {
        return P.startDriveSession(payload || {});
      },
      updateDriveSession: function (payload) {
        return P.updateDriveSession(payload || {});
      },
      endDriveSession: function () {
        return P.endDriveSession();
      },
      signInWithApple: function () {
        return P.signInWithApple();
      },
      obdBleConnect: function () {
        return P.obdBleConnect();
      },
      obdBleDisconnect: function () {
        return P.obdBleDisconnect();
      },
      obdBleState: function () {
        return P.obdBleState();
      },
      trafikGet: function (params) {
        return P.trafikGet(params || {});
      },
      trafikPost: function (body) {
        return P.trafikPost({ body: body || {} });
      },
      addObdBleListener: function (fn) {
        return P.addListener("obdBleEvent", fn);
      },
    };
    return true;
  }

  if (wireNative()) return;

  document.addEventListener("DOMContentLoaded", wireNative);
  window.addEventListener("load", wireNative);
  document.addEventListener("deviceready", wireNative, false);

  var tries = 0;
  var timer = setInterval(function () {
    if (wireNative() || ++tries > 80) clearInterval(timer);
  }, 100);
})();
