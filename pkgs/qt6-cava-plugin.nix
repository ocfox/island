{
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  qt6,
  pipewire,
  fftw,
}:

stdenv.mkDerivation {
  pname = "qt6-cava-plugin";
  version = "0.1.0-unstable-2026-05-18";

  src = fetchFromGitHub {
    owner = "Yujonpradhananga";
    repo = "Qt6-Cava-plugin";
    rev = "23b108a7919da59d4eaaced5f0bf4cbe21867093";
    hash = "sha256-itoyEEpT3ZeAjzjz8yASU9gXFQg3nF29lkiK7v45OxM=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    pipewire
    fftw
  ];

  # cavacore.c is vendored, so no external libcava is needed.
  cmakeFlags = [
    "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}/lib/qt6/qml"
  ];

  meta.description = "Qt6 QML plugin exposing CAVA audio spectrum data";
}
