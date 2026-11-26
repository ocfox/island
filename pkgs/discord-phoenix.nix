{
  lib,
  sources,
  appimageTools,
  fetchurl,
}:
let
  pname = "discord-phoenix";
  inherit (sources.discord-phoenix) version;

  src = fetchurl sources.discord-phoenix.src;

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/com.discord.libdiscord.desktop \
      $out/share/applications/com.discord.libdiscord.desktop
    cp -r ${appimageContents}/usr/share/icons $out/share/
  '';

  passthru = {
    inherit appimageContents;
  };

  meta = {
    description = "Discord's native Rust client (Phoenix)";
    homepage = "https://discord.com";
    license = lib.licenses.unfree;
    mainProgram = "discord-phoenix";
    platforms = [ "x86_64-linux" ];
  };
}
