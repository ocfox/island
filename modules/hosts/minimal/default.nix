{ self, ... }:
{
  hosts.minimal = {
    system = "x86_64-linux";
    stateVersion = "26.11";
    useBase = false;
    module =
      { ... }:
      {
        imports = with self.modules.nixos; [
          vps
          disko
          minimal-disko
        ];

        users = {
          mutableUsers = false;
          users.root = {
            hashedPassword = "$6$jVI2tdENaEqUyZGh$rni.joO5US9t9RYM9wlIvia4L1YOObs44Kt3gBcooBJTeSFGyEorciM2CrKMEnzbojpi1KgPPe256i5Q46N1d0";
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHysCjoqwXAumW+cUCcFZDpC9yLx3Jh7x5du7r21fPE4"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICFP2wSho7RDutjcMwnvPHHMnQcvuqX841gHlQdkpTdc me@s4r.in"
              "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHnLWTS5/vPyPFY+tCVYn3Ejf3NQpQzcGnWLQTyE7lbzAAAAC3NzaDpwYXNzZm94 ssh:passfox"
            ];
          };
        };
      };
  };
}
