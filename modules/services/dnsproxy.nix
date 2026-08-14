{ ... }:
{
  flake.modules.nixos.dnsproxy =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.dnsproxy;
    in
    {
      meta.maintainers = [ "ocfox" ];

      config = lib.mkIf cfg.enable {
        services.resolved.enable = false;

        services.dnsproxy = {
          flags = lib.mkDefault [
            "--cache"
            "--cache-optimistic"
            "--edns"
          ];
          settings = {
            bootstrap = lib.mkDefault [
              "8.8.8.8"
              "119.29.29.29"
              "tcp://223.6.6.6:53"
            ];
            listen-addrs = lib.mkDefault [ "0.0.0.0" ];
            listen-ports = lib.mkDefault [ 53 ];
            upstream-mode = lib.mkDefault "parallel";
            upstream = lib.mkDefault [
              "https://1.1.1.1/dns-query"
              "h3://dns.alidns.com/dns-query"
              "tls://dot.pub"
            ];
          };
        };
      };
    };
}
