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
  libGL,
  p11-kit,
  pciutils,
  pipewire,
  writeText,
  symlinkJoin,
  makeWrapper,
  policies ? { },
  extraPolicies ? { },
  ...
}:
let
  inherit (sources.zen-browser) version;
  source =
    sources.zen-browser.${stdenv.hostPlatform.system}
      or (throw "unsupported architecture for zen-browser: ${stdenv.hostPlatform.system}");

  basePolicies = {
    DisableAppUpdate = true;
    SecurityDevices = {
      "System Trust" = "${p11-kit}/lib/pkcs11/p11-kit-trust.so";
    };
  };

  policiesJson = writeText "firefox-policies.json" (builtins.toJSON {
    policies = basePolicies // policies // extraPolicies;
  });

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
      libGL
    ];

    appendRunpaths = [
      "${libGL}/lib"
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

  # Spoof Gecko version string so wrapFirefox selects latest ffmpeg (ffmpeg_9 / libavcodec 63)
  zen-wrapped = wrapFirefox (zen-unwrapped // { version = "9999"; }) {
    pname = "zen-browser";
    version = zen-unwrapped.version;
    extraPolicies = basePolicies // policies // extraPolicies;
  };
in
symlinkJoin {
  name = "zen-browser-${version}";
  paths = [ zen-wrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    rm $out/bin/zen
    makeWrapper ${zen-wrapped}/bin/zen $out/bin/zen \
      --set TZ "Asia/Tokyo"
  '';

  passthru = zen-wrapped.passthru // {
    unwrapped = zen-unwrapped;
  };

  meta = zen-wrapped.meta // {
    mainProgram = "zen";
  };
}
