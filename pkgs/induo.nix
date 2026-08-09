{ pkgs, callPackage }:
let
  stage = callPackage ./induo-stage/package.nix { };
in
pkgs.writers.writePython3Bin "induo" {
  flakeIgnore = [ "E501" ];
  libraries = with pkgs.python3Packages; [
    rich
  ];
} (builtins.replaceStrings [ "@stage@" ] [ "${stage}" ] (builtins.readFile ./induo.py))
