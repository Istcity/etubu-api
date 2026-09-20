/**
 * ETUBU Paddle Checkout Module
 */
const PaddleCheckout = (() => {
  function open() {}
  return { open };
})();

try {
  window.PaddleCheckout = PaddleCheckout;
} catch (_) {}
