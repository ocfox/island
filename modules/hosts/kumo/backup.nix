{
  flake.modules.nixos.kumo =
    { config, pkgs, ... }:
    {
      kix.secrets.restic-b2.mode = "640";

      # Offsite backup to Backblaze B2 via its S3-compatible API (free tier).
      # Backs up memos + vaultwarden data and a logical dump of the mastodon
      # Postgres DB. Mastodon media (mostly cached remote files, auto-refetched)
      # is intentionally excluded. The restic-b2 secret must contain
      # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and RESTIC_PASSWORD.
      services.restic.backups.b2 = {
        initialize = true;
        # S3 path uses the bucket NAME (not the bucket id).
        repository = "s3:https://s3.us-west-004.backblazeb2.com/kumoback";
        environmentFile = config.kix.secrets.restic-b2.path;
        paths = [
          "/var/lib/memos"
          "/var/lib/vaultwarden"
          "/var/backup/postgres"
        ];
        backupPrepareCommand = ''
          install -d -m 0700 /var/backup/postgres
          # pg_dump runs as postgres, but the output file is opened by the
          # root shell via redirection so the dir can stay root-owned 0700.
          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${config.services.postgresql.package}/bin/pg_dump -Fc mastodon \
            > /var/backup/postgres/mastodon.dump
        '';
        backupCleanupCommand = ''
          rm -f /var/backup/postgres/mastodon.dump
        '';
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 6"
        ];
      };
    };
}
