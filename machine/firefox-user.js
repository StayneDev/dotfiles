// =============================================================================
// Firefox — Perfil de privacidade e segurança
// Mantido em: StayneDev/dotfiles/machine/firefox-user.js
// Aplicado automaticamente pelo setup.sh --firefox
// =============================================================================

// --- Startup ---
user_pref("browser.startup.page", 3);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.shell.checkDefaultBrowser", false);

// --- Extensoes — habilitar automaticamente sem prompt ---
// Permite que extensoes instaladas no perfil (ex: Bitwarden via XPI)
// sejam ativadas sem exigir confirmacao manual do usuario
user_pref("extensions.autoDisableScopes", 0);
user_pref("extensions.enabledScopes", 15);

// --- Senhas e formularios ---
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.formfill.enable", false);
user_pref("extensions.formautofill.addresses.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);

// --- Telemetria ---
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);

// --- Sugestoes e patrocinios ---
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
user_pref("browser.urlbar.quicksuggest.enabled", false);

// --- Pocket ---
user_pref("extensions.pocket.enabled", false);
user_pref("browser.pocket.enabled", false);

// --- Privacidade e rastreamento ---
user_pref("privacy.donottrackheader.enabled", true);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);
user_pref("geo.enabled", false);
user_pref("media.peerconnection.enabled", false);

// --- Safe Browsing (local — sem envio de hashes ao Google) ---
user_pref("browser.safebrowsing.malware.enabled", true);
user_pref("browser.safebrowsing.phishing.enabled", true);
user_pref("browser.safebrowsing.downloads.enabled", true);
user_pref("browser.safebrowsing.downloads.remote.enabled", false);

// --- HTTPS Only ---
user_pref("dom.security.https_only_mode", true);
user_pref("dom.security.https_only_mode_ever_enabled", true);

// --- DNS over HTTPS (DoH via Cloudflare/Mozilla) ---
user_pref("network.trr.mode", 2);
user_pref("network.trr.uri", "https://mozilla.cloudflare-dns.com/dns-query");
