{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config.my)
    driveStatusPort
    storageDrives
    ;

  statusDir = "/var/lib/drive-status";
  uniqueDevices = lib.unique (map (drive: drive.device) storageDrives);
  # Idle time before forcing the drive to standby via hdparm -y.
  # The drive's own spindown timer (hdparm -S) doesn't work on this
  # enterprise drive (WD Ultrastar), so we manage spindown ourselves.
  spindownSeconds = 300;

  checkScript = pkgs.writeShellApplication {
    name = "check-drive-status";
    runtimeInputs = with pkgs; [
      hdparm
      jq
    ];
    text = ''
      mkdir -p ${statusDir}

      ${lib.concatMapStrings (dev: ''
        DEVICE="${dev}"
        BLOCK_NAME=$(basename "$DEVICE")

        # Detect I/O activity by comparing block device stats.
        # We never call hdparm -C because the ATA CHECK POWER MODE
        # command resets the drive's idle timer on some drives.
        STAT_FILE="${statusDir}/prev_stat_$BLOCK_NAME"
        TIMESTAMP_FILE="${statusDir}/last_access_$BLOCK_NAME"
        CURRENT_STAT=$(tr -s ' ' 2>/dev/null < "/sys/block/$BLOCK_NAME/stat" || true)

        if [ -f "$STAT_FILE" ]; then
          PREV_STAT=$(cat "$STAT_FILE")
          if [ "$CURRENT_STAT" != "$PREV_STAT" ]; then
            date -u +%Y-%m-%dT%H:%M:%SZ > "$TIMESTAMP_FILE"
          fi
        else
          date -u +%Y-%m-%dT%H:%M:%SZ > "$TIMESTAMP_FILE"
        fi
        echo "$CURRENT_STAT" > "$STAT_FILE"

        LAST_ACCESS=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "unknown")

        PREV_STATE=$(jq -r '.state // empty' "${statusDir}/status_$BLOCK_NAME.json" 2>/dev/null || true)

        # Determine spin state and force spindown when idle long enough.
        # The standby command goes out once, on the transition, and both
        # transitions are logged: `journalctl -u check-drive-status` counts
        # how often the drive wakes.
        if [ "$LAST_ACCESS" != "unknown" ]; then
          LAST_EPOCH=$(date -d "$LAST_ACCESS" +%s 2>/dev/null || echo 0)
          NOW_EPOCH=$(date -u +%s)
          IDLE_SECS=$(( NOW_EPOCH - LAST_EPOCH ))
          if [ "$IDLE_SECS" -ge ${toString spindownSeconds} ]; then
            if [ "$PREV_STATE" != standby ]; then
              echo "$DEVICE: spinning down after ''${IDLE_SECS}s idle"
              hdparm -y "$DEVICE" > /dev/null 2>&1 || true
            fi
            STATE="standby"
          else
            [ "$PREV_STATE" != standby ] || echo "$DEVICE: woke (I/O at $LAST_ACCESS)"
            STATE="active/idle"
          fi
        else
          STATE="active/idle"
        fi

        jq -n \
          --arg device "$DEVICE" \
          --arg state "$STATE" \
          --arg lastAccess "$LAST_ACCESS" \
          '{device: $device, state: $state, lastAccess: $lastAccess}' \
          > "${statusDir}/status_$BLOCK_NAME.json"
      '') uniqueDevices}
    '';
  };
in
{
  systemd = {
    tmpfiles.rules = [
      "d ${statusDir} 0755 root root -"
    ];

    services = {
      check-drive-status = {
        description = "Check drive status";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          ExecStart = lib.getExe checkScript;
        };
      };

      drive-status-http = {
        description = "Serve drive status JSON";
        wantedBy = [ "multi-user.target" ];
        # Only reads the world-readable status files, so no root needed
        serviceConfig = import ./hardening.nix // {
          ExecStart = "${pkgs.darkhttpd}/bin/darkhttpd ${statusDir} --port ${toString driveStatusPort} --addr 127.0.0.1";
          Restart = "always";
          DynamicUser = true;
        };
      };
    };

    timers.check-drive-status = {
      description = "Timer for drive status check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5";
        Persistent = true;
        Unit = "check-drive-status.service";
      };
    };
  };
}
