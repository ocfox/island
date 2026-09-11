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
          "/var/lib/ntfy-sh"
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
          ${pkgs.curl}/bin/curl -s \
            -H "Title: Backup Succeeded" \
            -H "Tags: white_check_mark" \
            -d "kumo: Daily backup to Backblaze B2 completed successfully" \
            http://127.0.0.1:2586/backup || true
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

      systemd.services.restic-backups-b2 = {
        onFailure = [ "notify-failure@%p.service" ];
        restartIfChanged = false;
      };

      # Disk space monitoring for the 80GB disk (hourly check, alerts if >= 80%)
      systemd.services.check-disk-space = {
        description = "Check disk space and notify if low";
        serviceConfig.Type = "oneshot";
        script = ''
          USAGE=$(${pkgs.coreutils}/bin/df -h / | ${pkgs.gawk}/bin/awk 'NR==2 {print $5}' | ${pkgs.coreutils}/bin/tr -d '%')
          if [ "$USAGE" -ge 80 ]; then
            ${pkgs.curl}/bin/curl -s \
              -H "Title: Disk Space Warning" \
              -H "Priority: high" \
              -H "Tags: warning,floppy_disk" \
              -d "kumo: Disk usage on / has reached ''${USAGE}%" \
              http://127.0.0.1:2586/system || true
          fi
        '';
      };
      systemd.timers.check-disk-space = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
        };
      };
    };
}
