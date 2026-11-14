{{flutter_js}}
{{flutter_build_config}}

// Digitales Register web app loader. A template: `flutter build web` fills in
// the two lines above. The deployment rewrites the three addresses below to
// fingerprinted folders, so they can be cached for a year (docs/WEB_APP.md).
// Keep them literal.
(function () {
  var drConfig = {
    // Self-hosted: the web app loads nothing from Google (gstatic).
    canvasKitBaseUrl: "canvaskit/",
    assetBase: "/",
    // Only Roboto, the app's default font, is hosted here. Other fallback
    // fonts are not loaded from anywhere.
    fontFallbackBaseUrl: "/static/fonts/",
  };

  var splash = document.getElementById("dr-splash");

  function showLoadError() {
    var tag = (navigator.language || "de").toLowerCase();
    var lang = tag.indexOf("lld") === 0 ? "lld" : tag.slice(0, 2);
    var texts = {
      de: "Die Web-App konnte nicht geladen werden. Bitte lade die Seite neu oder verwende die App.",
      it: "Impossibile caricare la web app. Ricarica la pagina o usa l’app.",
      en: "The web app could not be loaded. Please reload the page or use the app.",
      lld: "Al ne s’à nia podü ciarié la web app. Ciaria danü la plata o adora l’app.",
    };
    var el = document.getElementById("dr-splash-error");
    if (el) {
      el.textContent = texts[lang] || texts.de;
      el.hidden = false;
    }
  }

  _flutter.loader
    .load({
      config: drConfig,
      onEntrypointLoaded: async function (engineInitializer) {
        try {
          var appRunner = await engineInitializer.initializeEngine(drConfig);
          await appRunner.runApp();
        } catch (e) {
          showLoadError();
          throw e;
        }
        // Flutter has drawn its first frame below the splash; fade it out.
        if (splash) {
          requestAnimationFrame(function () {
            splash.classList.add("dr-gone");
            setTimeout(function () { splash.remove(); }, 400);
          });
        }
      },
    })
    .catch(function (e) {
      showLoadError();
      throw e;
    });
})();
