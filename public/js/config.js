/**
 * İstemci yapılandırması — AdSense / Google OAuth / IAP ürünleri
 * Anahtarları doldurunca reklam ve giriş aktif olur.
 */
window.ETUBU_CONFIG = {
  // Google AdSense (web) — https://www.google.com/adsense
  // Slot ID'lerini AdSense panelinden oluşturup yapıştırın
  ADSENSE_CLIENT: "ca-pub-8420759480841389",
  ADSENSE_SLOT_TOP: "",
  ADSENSE_SLOT_BOTTOM: "",
  ADSENSE_SLOT_LEFT: "",
  ADSENSE_SLOT_RIGHT: "",
  ADSENSE_SLOT_MIDDLE: "",
  ADS_ENABLED: true,            // banner: üst / sağ / alt (orta) — sol yok
  ADMOB_BANNER_UNIT_ID: "ca-app-pub-8420759480841389/8858393138", // native iOS/Android banner

  // Yandex RTB (web banner) — https://partner.yandex.com/
  YANDEX_RTB_ENABLED: true,
  YANDEX_RTB_BLOCK_TOP: "R-A-19654756-1",
  YANDEX_RTB_BLOCK_MIDDLE: "R-A-19654756-1",
  YANDEX_RTB_BLOCK_LEFT: "",
  YANDEX_RTB_BLOCK_RIGHT: "R-A-19654756-1",

  // Google ile giriş — Web client ID (client_secret tarayıcıya KONMAZ)
  // Origins + redirect: https://etubu.com
  GOOGLE_CLIENT_ID: "714993569178-uqr2ia01d9ej136rk7of07vlranlo5u3.apps.googleusercontent.com",

  SITE_URL: "https://etubu.com",
  TRIAL_KM_API_URL: "https://etubu.com/api/trial-km.php",
  // Destek: deneme km sıfırlama kodları (en az 8 karakter, A-Z0-9)
  TRIAL_RESET_CODES: [
    "ETUBURESET7K2M9P4XQ",
  ],
  // İsteğe bağlı sunucu admin key (api/config.php trial_admin_key ile aynı)
  TRIAL_ADMIN_KEY: "",

  // Abonelik → tüm ses/tema | Ömür boyu → reklamsız + erişim
  PRICE_TRY: 300,
  PRICE_YEARLY_TRY: 300,
  PRICE_MONTHLY_USD: 3,
  PRICE_LIFETIME_USD: 30,
  PRICE_ADFREE_TRY: 30, // legacy isim; artık USD
  FREE_KM: 5,
  IAP_UNLOCK_ID: "etubu.catalog.yearly",
  IAP_ADFREE_ID: "etubu.ads.remove",

  // Paddle Billing (production) — Developer tools → Authentication + Catalog price IDs
  // Client token tarayıcıda güvenli; API key / webhook secret SADECE api/config.php'de
  PADDLE_ENV: "production", // "sandbox" | "production"
  PADDLE_CLIENT_TOKEN: "live_a8155b3c3c1085b4d9eed394ace", // live_...
  PADDLE_PRICE_MONTHLY: "pri_01kxqsgrnbdcwtfnzmytdydta4", // $3/ay
  PADDLE_PRICE_LIFETIME: "pri_01kxqsf1p9t889jg86t2qqt8m0", // $30 one-time

  // Davet kodu — TEK kod (+ kısa alias), sınırsız kullanıcı, tüm katalog (reklamlı)
  INVITE_CODE: "ETUBU4313398",
  INVITE_CODES: ["ETUBU4313398"],

  DEV_UNLOCK: false,
};
