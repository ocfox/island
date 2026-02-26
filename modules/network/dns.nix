{
  flake.modules.nixos.dns = {
    services.resolved.enable = false;
    networking.resolvconf.enable = false;
    services.dnsproxy = {
      enable = true;
      flags = [
        "--cache"
        "--cache-optimistic"
        "--edns"
      ];
      settings = {
        bootstrap = [
          "8.8.8.8"
          "119.29.29.29"
          "114.114.114.114"
          "223.6.6.6"
        ];
        listen-addrs = [ "::" ];
        listen-ports = [ 53 ];
        upstream-mode = "fastest_addr";
        upstream = [
          "tls://1.1.1.1"
          "tls://dot.pub"
          "https://doh.pub/dns-query"
        ];
      };
    };
  };
}
