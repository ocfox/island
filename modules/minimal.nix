{ self, ... }:
{
  flake.modules.nixos.minimal =
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      imports = [
        self.modules.nixos.limine-minimal
        (modulesPath + "/profiles/perlless.nix")
        (modulesPath + "/profiles/minimal.nix")
        (modulesPath + "/profiles/headless.nix")
      ];

      # Minimal Nix package manager
      nix = {
        enable = lib.mkDefault true;
        channel.enable = lib.mkDefault false;
      };

      system.tools = {
        nixos-rebuild.enable = lib.mkDefault false;
        nixos-option.enable = lib.mkDefault false;
        nixos-install.enable = lib.mkDefault false;
        nixos-build-vms.enable = lib.mkDefault false;
        nixos-enter.enable = lib.mkDefault false;
        nixos-generate-config.enable = lib.mkDefault false;
      };

      boot.loader = {
        grub.enable = false;
        limine = {
          enable = lib.mkDefault true;
          efiInstallAsRemovable = lib.mkDefault true;
        };
        efi.canTouchEfiVariables = false;
      };

      # Kernel and Initrd tuning
      boot.kernelParams = [ "audit=0" ];
      boot.initrd.includeDefaultModules = false;
      boot.initrd.systemd.tpm2.enable = false;

      # i18n: Use glibc built-in C.UTF-8 (eliminate 3.96MB glibc-locales)
      i18n = {
        defaultLocale = lib.mkForce "C.UTF-8";
        supportedLocales = [ "C.UTF-8/UTF-8" ];
        glibcLocales = null;
        extraLocales = lib.mkForce [ ];
        extraLocaleSettings = lib.mkForce { };
      };

      # Disable systemd coredump
      systemd.coredump.enable = false;

      # Disable LVM
      boot.initrd.services.lvm.enable = false;
      services.lvm.enable = false;

      # Disable cloud-utils growpart (eliminate 135MB python3; disko uses x-systemd.growfs)
      boot.growPartition = false;

      # Memory-safe Rust sudo implementation
      security.sudo-rs.enable = true;
      security.sudo.enable = false;

      # Shrink runtime kernel modules tree (144MB -> ~5.8MB cloud/server modules)
      system.modulesTree =
        let
          kernel = config.boot.kernelPackages.kernel;
          ver = kernel.modDirVersion;
          targetModules = lib.unique (
            config.boot.initrd.availableKernelModules
            ++ config.boot.initrd.kernelModules
            ++ config.boot.kernelModules
          );
        in
        lib.mkForce [
          (pkgs.runCommand "shrunk-modules"
            {
              nativeBuildInputs = [ pkgs.buildPackages.kmod ];
            }
            ''
              src=${kernel.modules}
              dst=$out/lib/modules/${ver}
              mkdir -p "$dst"

              for f in modules.builtin modules.builtin.modinfo modules.order; do
                if [ -e "$src/lib/modules/${ver}/$f" ]; then
                  cp "$src/lib/modules/${ver}/$f" "$dst/$f"
                fi
              done

              for m in ${toString targetModules}; do
                for f in $(modprobe -d "$src" -S "${ver}" --show-depends "$m" 2>/dev/null | awk '{print $2}'); do
                  if [ -n "$f" ] && [ -f "$f" ]; then
                    rel="''${f#$src/lib/modules/${ver}/}"
                    mkdir -p "$dst/$(dirname "$rel")"
                    cp -n "$f" "$dst/$rel" 2>/dev/null || true
                  fi
                done
              done

              depmod -b "$out" "${ver}"
            ''
          )
        ];

      # Minimal OpenSSH server
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
        hostKeys = [
          {
            path = "/var/lib/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
      };

      # Base shell for login and chroot
      environment.systemPackages = [ pkgs.bashInteractive ];
    };
}
