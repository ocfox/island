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
        swc = "sudo nixos-rebuild switch --flake /home/${config.my.name}/dev/den";
        gssm = "gamescope -W 3840 -H 2160 -r 60 -f --adaptive-sync --mangoapp -e -- steam -gamepadui";
        off = "poweroff";
        usd = "uwsm start default";
        g = "lazygit";
        "cd.." = "cd ..";
        fp = "fish --private";
        e = "exit";
        st = "sudo systemctl-tui";
        y = "yazi";
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

      interactiveShellInit = ''
        eval "$(${lib.getExe pkgs.atuin} init fish)"
        ${lib.getExe pkgs.zoxide} init fish | source
      '';

      fishPackages = with pkgs; [
        eza
        atuin
        zoxide
        just
        lazygit
        systemctl-tui
      ];
    in
    {
      users.users.${config.my.name}.shell = pkgs.fish;

      programs.fzf.keybindings = true;

      programs.fish = {
        enable = true;
        shellAliases = shellAliases;
        shellInit = shellInit;
        interactiveShellInit = interactiveShellInit;
      };

      my.packages = fishPackages;
    };
}
