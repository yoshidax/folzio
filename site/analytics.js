// Google Analytics 4 for the published site. Local previews send nothing.
// The privacy policy pages (privacy.html, ja/privacy.html) describe what this sends.
(function () {
  if (location.hostname !== 'yoshidax.github.io') {
    return;
  }
  var id = 'G-SN0LDJXDKG';
  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = gtag;

  // The site has no ads, so ad storage and ad signals are denied for everyone.
  gtag('consent', 'default', {
    'ad_storage': 'denied',
    'ad_user_data': 'denied',
    'ad_personalization': 'denied'
  });
  // The EEA, the UK, and Switzerland: no Analytics cookies either (cookieless measurement, no consent banner).
  gtag('consent', 'default', {
    'ad_storage': 'denied',
    'ad_user_data': 'denied',
    'ad_personalization': 'denied',
    'analytics_storage': 'denied',
    'region': [
      'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE',
      'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE',
      'IS', 'LI', 'NO', 'GB', 'CH'
    ]
  });

  gtag('js', new Date());
  gtag('set', 'allow_google_signals', false);
  gtag('set', 'allow_ad_personalization_signals', false);
  gtag('config', id);

  var script = document.createElement('script');
  script.async = true;
  script.src = 'https://www.googletagmanager.com/gtag/js?id=' + id;
  document.head.appendChild(script);
})();
