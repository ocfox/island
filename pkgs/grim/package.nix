{
  lib,
  sources,
  stdenv,
  fetchgit,
  meson,
  ninja,
  pkg-config,
  scdoc,
  wayland-scanner,
  libjpeg,
  libpng,
  pixman,
  wayland,
  wayland-protocols,
}:

# nixpkgs builds grim from the old mirror, so this pins current upstream GitLab instead.
stdenv.mkDerivation {
  pname = "grim";
  inherit (sources.grim) version;

  src = fetchgit sources.grim.src;

  patches = [
    # Keep the 10 bits per channel that a capture of a 10-bit output provides
    ./10bpc-png.patch
    # Convert captures of HDR outputs to SDR, so they are not written as
    # PQ-encoded BT.2020 samples that every viewer reads as plain sRGB
    ./hdr-tonemap.patch
  ];

  mesonFlags = [ (lib.mesonBool "werror" false) ];

  strictDeps = true;

  depsBuildBuild = [
    # To find wayland-scanner
    pkg-config
  ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    scdoc
    wayland-scanner
  ];

  buildInputs = [
    libjpeg
    libpng
    pixman
    wayland
    wayland-protocols
  ];

  meta.mainProgram = "grim";
}
