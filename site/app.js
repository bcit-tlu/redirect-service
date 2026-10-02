(function () {
  "use strict";

  var params = new URLSearchParams(location.search);
  // HAProxy passes the original host as ?from=; fall back to the
  // current hostname so the page also works when the proxy forwards
  // with the Host header preserved instead of issuing a 302 (e.g. the
  // wildcard-ingress catch-all for unknown *.ltc.bcit.ca hosts).
  var from = (params.get("from") || location.hostname)
    .split(":")[0]
    .toLowerCase();

  function startRedirect(section, target, delaySeconds) {
    var beaconUrl =
      "/e/redirect?from=" +
      encodeURIComponent(from) +
      "&to=" +
      encodeURIComponent(target);
    var leave = function () {
      // Beacon records the follow-through before navigation.
      if (navigator.sendBeacon) navigator.sendBeacon(beaconUrl);
      location.replace(target);
    };

    // `target` comes from the served config, never from request input —
    // keep it that way (no open redirect) and render via textContent.
    section.querySelector(".target").textContent = target;
    var link = section.querySelector(".continue");
    link.href = target;
    link.addEventListener("click", function (e) {
      e.preventDefault();
      leave();
    });
    section.hidden = false;

    var remaining = Math.max(0, delaySeconds);
    var el = section.querySelector(".countdown");
    el.textContent = remaining;
    var timer = setInterval(function () {
      remaining -= 1;
      el.textContent = remaining;
      if (remaining <= 0) {
        clearInterval(timer);
        leave();
      }
    }, 1000);
  }

  fetch("/config.json", { cache: "no-store" })
    .then(function (resp) {
      if (!resp.ok) throw new Error("config fetch failed: " + resp.status);
      return resp.json();
    })
    .then(function (cfg) {
      var target = cfg.mappings && cfg.mappings[from];
      if (target) {
        document.title = "Site migration in progress";
        startRedirect(
          document.getElementById("redirecting"),
          target,
          cfg.delaySeconds || 5
        );
        return;
      }
      if (cfg.defaultUrl) {
        document.title = "Address not in service";
        startRedirect(
          document.getElementById("default-redirect"),
          cfg.defaultUrl,
          cfg.defaultDelaySeconds != null
            ? cfg.defaultDelaySeconds
            : cfg.delaySeconds || 5
        );
        return;
      }
      document.getElementById("no-mapping").hidden = false;
    })
    .catch(function () {
      document.getElementById("no-mapping").hidden = false;
    });
})();
