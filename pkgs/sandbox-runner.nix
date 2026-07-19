{ pkgs }:
pkgs.writers.writePython3Bin "sandbox-runner" {
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./sandbox-runner.py)
