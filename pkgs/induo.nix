{ pkgs, callPackage }:
let
  stage = callPackage ./induo-stage/package.nix { };
in
pkgs.writers.writePython3Bin "induo" { flakeIgnore = [ "E501" ]; } (
  builtins.replaceStrings [ "@stage@" ] [ "${stage}" ] (builtins.readFile ./induo.py)
)
