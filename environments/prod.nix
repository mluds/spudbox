{
  my = {
    domain = "spudbox.win";
    hostIp = "192.168.0.42";
    cacheDrives = [
      { device = "/dev/nvme0n1"; partition = "/dev/nvme0n1p1"; mount = "/mnt/cache1"; }
    ];
    storageDrives = [
      { device = "/dev/sda"; partition = "/dev/sda1"; mount = "/mnt/storage1"; }
    ];
    backupDrives = [
      { device = "/dev/sdc"; partition = "/dev/sdc1"; mount = "/mnt/backup1"; }
    ];
    external_interface = "eno1";
  };
}
