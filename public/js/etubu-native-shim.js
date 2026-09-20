/**
 * Capacitor EtubuNative shim — StoreKit / AdMob native plugin bağlanınca aktif olur.
 */
(function () {
  if (window.EtubuNative) return;
  var Cap = window.Capacitor;
  if (!Cap || !Cap.Plugins || !Cap.Plugins.EtubuNative) return;
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
  };
})();
