{
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "persona-shell";
  version = "0-unstable-2026-08-09";

  # Fork with the sway port: no hyprctl shaders, no nmcli, theme toggle instead.
  src = fetchFromGitHub {
    owner = "ocfox";
    repo = "Persona-Quickshell";
    rev = "7d6ef3dcf12d18587cff02f95484160f45e64cf4";
    hash = "sha256-KC7cSGadu7QHOaNTn72Yox1TbMxlTrpUEXSJZnTOgr8=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r Assets Data Layers Widgets shell.qml $out/
    runHook postInstall
  '';

  meta.description = "Persona 3 Reload themed Quickshell config";
}
