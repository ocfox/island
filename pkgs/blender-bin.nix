{
  stdenv,
  lib,
  fetchurl,
  makeWrapper,
  wayland,
  libdecor,
  libx11,
  libxi,
  libxxf86vm,
  libxfixes,
  libxrender,
  libxkbcommon,
  libGLU,
  libglvnd,
  numactl,
  SDL2,
  libdrm,
  ocl-icd,
  openal,
  alsa-lib,
  pulseaudio,
  libsm,
  libice,
  zlib,
  vulkan-loader,
}:

let
  version = "5.1.2";

  src = fetchurl {
    url = "https://ftp.nluug.nl/pub/graphics/blender/release/Blender5.1/blender-${version}-linux-x64.tar.xz";
    hash = "sha256-qsyzVfUBg5ebaYvM50ZxA6diYbX6WfSXIpWEJmKihfs=";
  };

  libs = [
    wayland
    libdecor
    libx11
    libxi
    libxxf86vm
    libxfixes
    libxrender
    libxkbcommon
    libGLU
    libglvnd
    numactl
    SDL2
    libdrm
    ocl-icd
    stdenv.cc.cc.lib
    openal
    alsa-lib
    pulseaudio
    libsm
    libice
    zlib
    vulkan-loader
  ];
in

stdenv.mkDerivation {
  pname = "blender-bin";
  inherit version src;

  buildInputs = [ makeWrapper ];

  preUnpack = ''
    mkdir -p $out/libexec
    cd $out/libexec
  '';

  installPhase = ''
    cd $out/libexec
    mv blender-* blender

    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor/scalable/apps
    mv ./blender/blender.desktop $out/share/applications/blender.desktop
    mv ./blender/blender.svg $out/share/icons/hicolor/scalable/apps/blender.svg

    mkdir $out/bin

    makeWrapper $out/libexec/blender/blender $out/bin/blender \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib:${lib.makeLibraryPath libs}

    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      blender/blender

    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      $out/libexec/blender/*/python/bin/python3*
  '';

  meta.mainProgram = "blender";
}
