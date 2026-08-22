{
  flake.modules.nixos.limine-minimal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.boot.loader.limine;
      efi = config.boot.loader.efi;

      limineInstallConfig = pkgs.writeText "limine-install.json" (
        builtins.toJSON {
          inherit (config.system.nixos) distroName;
          nixPath = config.nix.package;
          efiBootMgrPath = pkgs.efibootmgr;
          liminePath = cfg.package;
          efiMountPoint = efi.efiSysMountPoint;
          fileSystems = config.fileSystems;
          luksDevices = builtins.attrNames config.boot.initrd.luks.devices;
          canTouchEfiVariables = efi.canTouchEfiVariables;
          efiSupport = cfg.efiSupport;
          efiRemovable = cfg.efiInstallAsRemovable;
          secureBoot = cfg.secureBoot;
          biosSupport = cfg.biosSupport;
          biosDevice = cfg.biosDevice;
          partitionIndex = cfg.partitionIndex;
          force = cfg.force;
          enrollConfig = cfg.enrollConfig;
          style = cfg.style;
          resolution = cfg.resolution;
          maxGenerations = if cfg.maxGenerations == null then 0 else cfg.maxGenerations;
          hostArchitecture = pkgs.stdenv.hostPlatform.parsed.cpu;
          timeout = if config.boot.loader.timeout == null then "no" else config.boot.loader.timeout;
          enableEditor = cfg.enableEditor;
          extraConfig = cfg.extraConfig;
          extraEntries = cfg.extraEntries;
          additionalFiles = cfg.additionalFiles;
          validateChecksums = cfg.validateChecksums;
          panicOnChecksumMismatch = cfg.panicOnChecksumMismatch;
        }
      );
    in
    {
      config = lib.mkIf cfg.enable {
        system.build.installBootLoader = lib.mkForce (
          let
            install = pkgs.replaceVarsWith {
              src = ./limine-install.sh;
              isExecutable = true;
              replacements = {
                jq = pkgs.jq;
                configPath = limineInstallConfig;
              };
            };
          in
          pkgs.writeScript "limine-install.sh" ''
            #!${pkgs.runtimeShell}
            set -euo pipefail
            ${install} "$@"
            ${cfg.extraInstallCommands}
          ''
        );
      };
    };
}
