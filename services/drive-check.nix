{ config, pkgs, lib, ... }:

with config.my;

{
  systemd.services.check-drive-status = {
    description = "Check drive status";
    path = with pkgs; [ hdparm lsof ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = let
        uniqueDevices = lib.unique (map (drive: drive.device) storageDrives);
        hdparmCmds = lib.concatMapStrings (dev: "hdparm -C ${dev}\n") uniqueDevices;
      in pkgs.writeShellScript "check-drive-script" ''
        ${hdparmCmds}
        lsof -Q ${storageDir}
      '';
    };
  };

  systemd.timers.check-drive-status = {
    description = "Timer for drive status check";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
      Unit = "check-drive-status.service";
    };
  };
}
