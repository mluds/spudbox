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
    cacheDrives
    backupDrives
    ;

  statusDir = "/var/lib/drive-status";
  uniqueDevices = lib.unique (map (drive: drive.device) storageDrives);
  # Idle time before forcing the drive to standby via hdparm -y. Some drives
  # (e.g. the WD Ultrastar this was written for) ignore their own spindown
  # timer (hdparm -S), so this manages spindown itself.
  spindownSeconds = 300;

  # What wakes the disks: every first request to a storage disk after a
  # quiet spell (QUIET seconds; it spins down after spindownSeconds), with
  # the processes that asked a mergerfs pool for something in the WINDOW
  # before it. The disk itself only ever sees mergerfs or kernel threads,
  # so who asked mergerfs (a kprobe on FUSE requests, per cgroup) is what
  # names the cause. drive-wakes reads it back from the journal.
  pools =
    lib.optional (storageDrives != [ ]) cfg.storageDir
    ++ lib.optional (cacheDrives != [ ]) cfg.cacheDir
    ++ lib.optional (backupDrives != [ ]) cfg.backupDir;
  traceScript = pkgs.writeShellApplication {
    name = "drive-wake-trace";
    runtimeInputs = with pkgs; [
      bpftrace
      coreutils
    ];
    text = ''
      QUIET=60
      WINDOW_MS=30000
      # dev_t as the kernel stores it: major << 20 | minor
      kdev() { echo $(( ($1 << 20) | $2 )); }
      disks=() pools=()
      disk_paths=(${lib.escapeShellArgs uniqueDevices})
      pool_paths=(${lib.escapeShellArgs pools})
      for disk in "''${disk_paths[@]}"; do
        read -r maj min < <(stat -L -c '%Hr %Lr' "$disk")
        disks+=("args.dev == $(kdev "$maj" "$min")")
      done
      for pool in "''${pool_paths[@]}"; do
        read -r maj min < <(stat -c '%Hd %Ld' "$pool")
        pools+=("\$s == $(kdev "$maj" "$min")")
      done
      join() { local IFS="|"; local all="$*"; echo "''${all//|/ || }"; }

      cat > "$RUNTIME_DIRECTORY/wake.bt" <<EOF
      // Nothing to print on exit
      END { clear(@last); clear(@seen); }
      kprobe:__fuse_simple_request
      {
        \$s = ((struct fuse_mount *)arg1)->sb->s_dev;
        if ($(join "''${pools[@]}")) {
          @seen[cgroup] = (nsecs, comm, ((struct fuse_args *)arg2)->opcode);
        }
      }
      tracepoint:block:block_rq_issue
      / $(join "''${disks[@]}") /
      {
        \$prev = @last[args.dev];
        @last[args.dev] = nsecs;
        if (\$prev != 0 && nsecs - \$prev > (uint64)$QUIET * 1000000000) {
          printf("io-after-quiet dev=%d:%d quiet=%d rw=%s bytes=%d comm=%s cgroup=%s\\n",
            args.dev >> 20, args.dev & 0xfffff, (nsecs - \$prev) / 1000000000,
            args.rwbs, args.bytes, comm, cgroup_path(cgroup));
          for (\$kv : @seen) {
            \$age = (nsecs - \$kv.1.0) / 1000000;
            if (\$age < $WINDOW_MS) {
              printf("pool-request ms_before=%d op=%d comm=%s cgroup=%s\\n",
                \$age, \$kv.1.2, \$kv.1.1, cgroup_path(\$kv.0));
            }
          }
        }
      }
      EOF
      exec bpftrace --no-warnings "$RUNTIME_DIRECTORY/wake.bt"
    '';
  };

  wakesReport = pkgs.writers.writePython3Bin "drive-wakes" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./drive-wakes.py);
  # The configured paths check-drive-status logs, for drive-wakes to match.
  wakesCommand = pkgs.writeShellScriptBin "drive-wakes" ''
    DRIVES=${lib.escapeShellArg (toString uniqueDevices)} exec ${lib.getExe wakesReport} "$@"
  '';

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
  # drive-wakes [--since WHEN]: what woke the disks (sudo: reads the journal)
  environment.systemPackages = [ wakesCommand ];

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

      drive-wake-trace = {
        description = "Log what wakes the storage disks";
        wantedBy = [ "multi-user.target" ];
        # The pools must be mounted to know their device numbers.
        unitConfig.RequiresMountsFor = pools;
        serviceConfig = {
          ExecStart = lib.getExe traceScript;
          RuntimeDirectory = "drive-wake-trace";
          Restart = "on-failure";
          RestartSec = 30;
          Nice = 10;
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
