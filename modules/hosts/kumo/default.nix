{ config, inputs, ... }:
let
  inherit (config.flake.lib) mkHostModule;
  nixosModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos.kumo =
    { config, ... }:
    {
      imports = mkHostModule {
        stateVersion = "25.11";
        hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGFOQAUa4fQiCbnD0lAoXI4HoYriPhCLAk/qOLS8IIC root@kumo";
        modules = with nixosModules; [
          vps
          disko
          {
            systemd.network.networks."10-eth0" = {
              address = [
                "2401:b60:e0fd:11::2/64"
                "2401:b60:e0fd:151::2/64"
                "2401:b60:e0fd:3d::2/64"
                "2401:b60:e0fd:2b::2/64"
              ];
              networkConfig = {
                DHCP = "no";
                IPv6AcceptRA = false;
              };
              routes = [
                { Gateway = "2401:b60:e0fd:2b::1"; }
              ];
            };
          }
          {
            kix.secrets.vault = {
              file = inputs.self + "/secrets/vault.age";
              mode = "640";
            };
            kix.secrets.cf-dns = {
              file = inputs.self + "/secrets/cf-dns.age";
              mode = "640";
            };
          }
          {
            security.acme = {
              acceptTerms = true;
              defaults.email = "civet@ocfox.me";
              certs."vault.s4r.in" = {
                dnsProvider = "cloudflare";
                environmentFile = config.kix.secrets.cf-dns.path;
                group = "caddy";
              };
            };

            services.vaultwarden = {
              enable = true;
              config = {
                SMTP_SECURITY = "starttls";
                SMTP_PORT = 587;
                SMTP_HOST = "smtp.migadu.com";
                SMTP_FROM = "vault@cyans.dev";
                SMTP_USERNAME = "vault@cyans.dev";
                DOMAIN = "https://vault.s4r.in";
              };
              environmentFile = config.kix.secrets.vault.path;
            };

            services.caddy = {
              enable = true;
              virtualHosts."vault.s4r.in" = {
                useACMEHost = "vault.s4r.in";
                extraConfig = ''
                  reverse_proxy localhost:8000 {
                    header_up X-Real-IP {remote_host}
                  }
                '';
              };
            };

            users.users.caddy.extraGroups = [ "acme" ];
          }
        ];
      };
    };
}
