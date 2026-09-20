/**
 * PayTR / yasal mağaza bilgileri — tek kaynak.
 * Başvuru formundaki unvan, adres ve telefon ile birebir aynı olmalıdır.
 */
window.ETUBU_MERCHANT = {
  brand: "ETUBU",
  legalName: "Sinan Nergiz",
  emailSupport: "destek@etubu.com",
  emailPrivacy: "privacy@etubu.com",
  phoneDisplay: "+90 530 511 58 00",
  phoneTel: "+905305115800",
  addressLines: [
    "İstasyon Mah. TOKİ Göl Konutları",
    "B1-3 Blok No: 28",
    "Küçükçekmece / İstanbul",
  ],
  prices: {
    free: { try: "0 ₺", note: "Ücretsiz" },
    monthly: { try: "149 ₺ / ay", usd: "$3 / ay" },
    lifetime: { try: "1.499 ₺", usd: "$30 tek sefer" },
  },
};
