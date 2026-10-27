{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.spudbox;
  inherit (cfg)
    driveStatusPort
    storageDrives
    ;

  statusDir = "/var/lib/drive-status";
  uniqueDevices = lib.unique (map (drive: drive.device) storageDrives);
  # Idle time before forcing the drive to standby via hdparm -y. Some drives
  # (e.g. the WD Ultrastar this was written for) ignore their own spindown
  # timer (hdparm -S), so this manages spindown itself.
  spindownSeconds = 300;

  checkScript = pkgs.writeShellApplication {
    name = "check-drive-status";
    runtimeInputs = with pkgs; [
      hdparm
      jq
    ];
    text = ''
      mkdir -p ${statusDir}

      # check-drive-status DEVICE...
      for DEVICE in "$@"; do
        # Files are named after the configured path (sda, or a by-id name);
        # the kernel's stats are under the device it points to.
        BLOCK_NAME=$(basename "$DEVICE")
        SYS_NAME=$(basename "$(readlink -f "$DEVICE")")
        STATUS_FILE="${statusDir}/status_$BLOCK_NAME.json"

        # Detect I/O activity by comparing block device stats.
        # We never call hdparm -C because the ATA CHECK POWER MODE
        # command resets the drive's idle timer on some drives.
        STAT_FILE="${statusDir}/prev_stat_$BLOCK_NAME"
        TIMESTAMP_FILE="${statusDir}/last_access_$BLOCK_NAME"
        CURRENT_STAT=$(tr -s ' ' 2>/dev/null < "/sys/block/$SYS_NAME/stat" || true)
        if [ ! -f "$TIMESTAMP_FILE" ] || [ "$CURRENT_STAT" != "$(cat "$STAT_FILE" 2>/dev/null)" ]; then
          date -u +%Y-%m-%dT%H:%M:%SZ > "$TIMESTAMP_FILE"
        fi
        echo "$CURRENT_STAT" > "$STAT_FILE"
        LAST_ACCESS=$(cat "$TIMESTAMP_FILE")
        IDLE_SECS=$(( $(date -u +%s) - $(date -d "$LAST_ACCESS" +%s) ))

        PREV_STATE=$(jq -r '.state // empty' "$STATUS_FILE" 2>/dev/null || true)

        # Force spindown when idle long enough. The standby command goes out
        # once, on the transition, and both transitions are logged:
        # `journalctl -u check-drive-status` counts how often the drive wakes.
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

        jq -n \
          --arg device "$DEVICE" \
          --arg state "$STATE" \
          --arg lastAccess "$LAST_ACCESS" \
          '{device: $device, state: $state, lastAccess: $lastAccess}' \
          > "$STATUS_FILE"
      done
    '';
  };
in
lib.mkIf cfg.hddSpindown.enable {
  systemd = {
    tmpfiles.rules = [
      "d ${statusDir} 0755 root root -"
    ];

    services = {
      check-drive-status = {
        description = "Check drive status";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe checkScript} ${toString uniqueDevices}";
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
