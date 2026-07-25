{
  flake.modules.nixos.llama-cpp =
    { lib, pkgs, ... }:
    {
      services.llama-cpp = {
        enable = true;
        package = pkgs.llama-cpp.override {
          rocmSupport = true;
          # RX 6800/6900 XT (Navi 21) only — building every target takes hours.
          rocmGpuTargets = [ "gfx1030" ];
        };
        settings = {
          host = "0.0.0.0";
          port = 8080;
          alias = "gemma-4-26b-a4b-heretic";
          hf-repo = "mradermacher/gemma-4-26B-A4B-it-heretic-GGUF";
          hf-file = "gemma-4-26B-A4B-it-heretic.IQ4_XS.gguf";
          n-gpu-layers = 999;
          # 26B total / 3.8B active MoE. IQ4_XS is 14.1G against 16G of VRAM,
          # so a few expert layers live in RAM to leave room for the desktop.
          n-cpu-moe = 6;
          ctx-size = 32768;
          flash-attn = "on";
          jinja = true;
        };
      };

      systemd.services.llama-cpp.serviceConfig = {
        SupplementaryGroups = [
          "video"
          "render"
        ];
        # The ROCm runtime maps code pages W+X when loading GPU kernels.
        MemoryDenyWriteExecute = lib.mkForce false;
      };
    };
}
