{
  perSystem =
    { pkgs, ... }:
    {
      devShells.milk = pkgs.mkShell {
        name = "milk-dev";
        packages = with pkgs; [
          cargo
          rustc
          rust-analyzer
          clippy
          rustfmt
          pkg-config
          wayland
          wayland-protocols
          wayland-scanner
          libdeflate
        ];
        RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
      };
    };
}
