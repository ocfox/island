{
  lib,
  stdenv,
  fetchFromGitLab,
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

# nixpkgs-wayland builds grim from the GitHub mirror, which was abandoned in
# 2022 when the project moved away, so this pins the current upstream instead.
stdenv.mkDerivation {
  pname = "grim";
  version = "1.5.0-unstable-2026-03-02";

  src = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "emersion";
    repo = "grim";
    rev = "07eb6914ceb2931894670875fabda3c65014d5b8";
    hash = "sha256-GSqZ3veRdUED1747Wg70oGyObzv9timm/88bVW3tRXI=";
  };

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
