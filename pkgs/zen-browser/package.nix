{
  stdenv,
  sources,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook3,
  patchelfUnstable,
  wrapFirefox,
  gtk3,
  alsa-lib,
  adwaita-icon-theme,
  dbus-glib,
  libXtst,
  curl,
  libva,
  pciutils,
  pipewire,
  writeText,
  ...
}:
let
  inherit (sources.zen-browser) version;
  source =
    sources.zen-browser.${stdenv.hostPlatform.system}
      or (throw "unsupported architecture for zen-browser: ${stdenv.hostPlatform.system}");

  policies = {
    DisableAppUpdate = true;
  };
  policiesJson = writeText "firefox-policies.json" (builtins.toJSON { inherit policies; });

  zen-unwrapped = stdenv.mkDerivation (finalAttrs: {
    pname = "zen-browser-unwrapped";
    applicationName = "Zen Browser";
    inherit version;

    src = fetchurl source;

    nativeBuildInputs = [
      wrapGAppsHook3
      autoPatchelfHook
      patchelfUnstable
    ];

    buildInputs = [
      gtk3
      alsa-lib
      adwaita-icon-theme
      dbus-glib
      libXtst
    ];

    runtimeDependencies = [
      curl
      libva.out
      pciutils
    ];

    appendRunpaths = [
      "${pipewire}/lib"
    ];

    installPhase = ''
      mkdir -p "$prefix/lib/zen-${version}"
      cp -r * "$prefix/lib/zen-${version}"

      mkdir -p $out/bin
      ln -s "$prefix/lib/zen-${version}/zen" $out/bin/zen

      mkdir -p "$out/lib/zen-${version}/distribution"
      ln -s ${policiesJson} "$out/lib/zen-${version}/distribution/policies.json"
    '';

    patchelfFlags = [ "--no-clobber-old-sections" ];

    meta = {
      mainProgram = "zen";
      description = "Zen is a privacy-focused browser that blocks trackers, ads, and other unwanted content while offering the best browsing experience!";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };

    passthru = {
      inherit gtk3;
      libName = "zen-${version}";
      binaryName = finalAttrs.meta.mainProgram;
      withFFmpeg = true;
      withGSSAPI = true;
    };
  });
in
wrapFirefox zen-unwrapped {
  pname = "zen-browser";
}
