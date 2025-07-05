{
  my = {
    domain = "dev.spudbox.win";
    hostIp = "192.168.42.130";
    cacheDrives = [
      { device = "/dev/nvme0n2"; partition = "/dev/nvme0n2p1"; mount = "/mnt/cache1"; }
    ];
    storageDrives = [
      { device = "/dev/nvme0n3"; partition = "/dev/nvme0n3p1"; mount = "/mnt/storage1"; }
    ];
    external_interface = "eth0";
  };
}
