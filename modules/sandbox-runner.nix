{ ... }:
{
  flake.modules.nixos.sandbox-runner =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.sandbox-runner;
      sandboxPython = pkgs.python3.withPackages (
        ps: with ps; [
          pillow
          pillow-heif # iPhone HEIC photos
          numpy
          opencv4
        ]
      );
      # PATH exposed inside each sandboxed execution -- NixOS has no FHS, so
      # this is how code *running inside* the sandbox (e.g. subprocess.run(["ffmpeg", ...]))
      # resolves other binaries by name via PATH lookup (hardcoded paths like
      # /bin/sh still won't exist). This does NOT help systemd-run find the
      # entry command itself -- see SANDBOX_PYTHON_BIN/SANDBOX_NODE_BIN below.
      sandboxPath = lib.makeBinPath [
        sandboxPython
        pkgs.nodejs
        pkgs.ffmpeg
        pkgs.imagemagick
        pkgs.coreutils
        pkgs.systemd
      ];
    in
    {
      options.services.sandbox-runner = {
        enable = lib.mkEnableOption "sandboxed code-execution runner for Dorothy";

        listenAddr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
        };

        listenPort = lib.mkOption {
          type = lib.types.port;
          default = 8686;
        };

        apiKeyFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to a file containing the shared-secret bearer token, used both to authenticate incoming requests and to sign outgoing job callbacks.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.sandbox-runner = {
          description = "Dorothy sandboxed code-execution runner";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.local.sandbox-runner}/bin/sandbox-runner";
            Restart = "on-failure";
            RestartSec = "3s";
            StateDirectory = "sandbox-runner";
            # runs as root (no DynamicUser here): it needs permission to create
            # the transient, DynamicUser-sandboxed units it spawns per job.
            Environment = [
              "SANDBOX_LISTEN_ADDR=${cfg.listenAddr}"
              "SANDBOX_LISTEN_PORT=${toString cfg.listenPort}"
              "SANDBOX_API_KEY_FILE=${cfg.apiKeyFile}"
              "SANDBOX_JOBS_DIR=/var/lib/sandbox-runner/jobs"
              "SANDBOX_RESULTS_DIR=/var/lib/sandbox-runner/results"
              "SANDBOX_PATH=${sandboxPath}"
              # systemd-run resolves its entry command against its own default
              # search path, not --setenv=PATH -- so that command must be given
              # as an absolute path regardless of SANDBOX_PATH above
              "SANDBOX_PYTHON_BIN=${sandboxPython}/bin/python3"
              "SANDBOX_NODE_BIN=${pkgs.nodejs}/bin/node"
            ];
          };
        };
      };
    };
}
