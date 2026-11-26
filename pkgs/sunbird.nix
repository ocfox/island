{
  lib,
  sources,
  rustPlatform,
  fetchFromGitHub,
  makeDesktopItem,
  copyDesktopItems,
  local,
  discord-phoenix ? local.discord-phoenix,
}:

rustPlatform.buildRustPackage {
  pname = "sunbird";
  inherit (sources.sunbird) version cargoHash;

  src = fetchFromGitHub sources.sunbird.src;

  nativeBuildInputs = [ copyDesktopItems ];

  cargoBuildFlags = [
    "-p"
    "phoenix-loader"
  ];

  cargoTestFlags = [
    "-p"
    "phoenix-loader"
  ];

  # cargo-setup-hook forces system libsqlite3 via pkg-config, whereas
  # libphoenix.so is LD_PRELOADed into Discord and uses rusqlite's bundled feature.
  postConfigure = ''
    unset LIBSQLITE3_SYS_USE_PKG_CONFIG
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "sunbird";
      desktopName = "Sunbird";
      comment = "Discord Phoenix with Sunbird";
      exec = "sunbird %U";
      icon = "com.discord.libdiscord";
      startupWMClass = "com.discord.libdiscord";
      categories = [
        "Network"
        "InstantMessaging"
      ];
      mimeTypes = [ "x-scheme-handler/discord" ];
    })
    (makeDesktopItem {
      name = "sunbird-gate-only";
      desktopName = "Sunbird (access gate only)";
      comment = "Discord Phoenix past the access gate, without plugins";
      exec = "sunbird --no-runtime %U";
      icon = "com.discord.libdiscord";
      startupWMClass = "com.discord.libdiscord";
      categories = [
        "Network"
        "InstantMessaging"
      ];
    })
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 target/*/release/libphoenix.so $out/lib/libphoenix.so

    install -dm755 $out/bin
    cat > $out/bin/sunbird <<EOF
    #!/bin/sh
    while [ "\''${1:-}" = --no-runtime ] || [ "\''${1:-}" = --gate-only ]; do
      export SUNBIRD_GATE_ONLY=1
      shift
    done
    export LD_PRELOAD="$out/lib/libphoenix.so\''${LD_PRELOAD:+:\$LD_PRELOAD}"
    exec ${lib.getExe discord-phoenix} "\$@"
    EOF
    chmod +x $out/bin/sunbird

    mkdir -p $out/share
    ln -s ${discord-phoenix}/share/icons $out/share/icons

    runHook postInstall
  '';

  meta = {
    description = "Unlock Discord's native Phoenix client with plugin runtime";
    homepage = "https://sunbird.tools/";
    license = lib.licenses.mit;
    mainProgram = "sunbird";
    platforms = [ "x86_64-linux" ];
  };
}
