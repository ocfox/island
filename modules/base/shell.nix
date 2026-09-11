{ config, ... }:
let
  inherit (config.flake.modules.nixos) starship;
in
{
  flake.modules.nixos.shell =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      shellAliases = {
        j = "just";
        ls = "eza --icons=auto --hyperlink --color=always --color-scale=all --color-scale-mode=fixed --git --git-repos";
        la = "eza --icons=auto --hyperlink --color=always --color-scale=all --color-scale-mode=fixed --git --git-repos -la";
        l = "eza --icons=auto --hyperlink --color=always --color-scale=all --color-scale-mode=fixed --git --git-repos -lh";
        swc = "sudo nixos-rebuild switch --flake /home/${config.my.name}/island";
        gssm = "gamescope -W 3840 -H 2160 -r 120 -f --adaptive-sync --cursor-scale-height 2160 --mangoapp -e -- steam -gamepadui";
        off = "poweroff";
        usd = "uwsm start default";
        g = "lazygit";
        "cd.." = "cd ..";
        fp = "fish --private";
        e = "exit";
        st = "sudo systemctl-tui";
        sc = "systemctl";
        scs = "systemctl status";
        scr = "systemctl restart";
        jc = "journalctl";
        ".." = "cd ..";
        "。。" = "cd ..";
        "..." = "cd ../..";
        "。。。" = "cd ../..";
        "...." = "cd ../../..";
        "。。。。" = "cd ../../..";
      };

      shellInit = ''
        fish_vi_key_bindings
        set -U fish_greeting
      '';

      fishPackages = with pkgs; [
        eza
        just
        systemctl-tui
      ];
    in
    {
      imports = [ starship ];

      users.users.${config.my.name}.shell = pkgs.fish;

      programs.fzf.keybindings = true;
      programs.zoxide.enable = true;

      programs.fish = {
        enable = true;
        useBabelfish = true;
        shellAliases = shellAliases;
        shellInit = shellInit;
      };

      my.packages = fishPackages;
    };
}
