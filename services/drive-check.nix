{
  config,
  pkgs,
  lib,
  ...
}:

with config.my;

let
  statusDir = "/var/lib/drive-status";
  uniqueDevices = lib.unique (map (drive: drive.device) storageDrives);
  checkScript = pkgs.writeShellScript "check-drive-script" ''
    mkdir -p ${statusDir}

    ${lib.concatMapStrings (dev: ''
      DEVICE="${dev}"
      BLOCK_NAME=$(basename "$DEVICE")

      # Get spin state
      STATE=$(${pkgs.hdparm}/bin/hdparm -C "$DEVICE" 2>/dev/null | grep -oP 'drive state is:\s+\K\S+' || echo "unknown")

      # Detect I/O activity by comparing block device stats
      STAT_FILE="${statusDir}/prev_stat_$BLOCK_NAME"
      TIMESTAMP_FILE="${statusDir}/last_access_$BLOCK_NAME"
      CURRENT_STAT=$(cat /sys/block/$BLOCK_NAME/stat 2>/dev/null | tr -s ' ')

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

      # Get processes currently accessing the storage
      PROCS=$(${pkgs.lsof}/bin/lsof -Q ${storageDir} 2>/dev/null | awk 'NR>1 {print $1}' | sort -u | paste -sd ", " || echo "")
      [ -z "$PROCS" ] && PROCS="none"

      ${pkgs.jq}/bin/jq -n \
        --arg device "$DEVICE" \
        --arg state "$STATE" \
        --arg lastAccess "$LAST_ACCESS" \
        --arg processes "$PROCS" \
        '{device: $device, state: $state, lastAccess: $lastAccess, processes: $processes}' \
        > ${statusDir}/status.json
    '') uniqueDevices}
  '';
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
          ExecStart = checkScript;
        };
      };

      drive-status-http = {
        description = "Serve drive status JSON";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.darkhttpd}/bin/darkhttpd ${statusDir} --port 9100 --addr 127.0.0.1";
          Restart = "always";
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
