{
  my = {
    domain = "spudbox.win";
    lan_cidr = "192.168.1.0/24";
    cacheDrives = [ ];
    storageDrives = [
      {
        device = "/dev/sda";
        partition = "/dev/sda1";
        mount = "/mnt/storage1";
      }
    ];
    external_interface = "eno1";
  };
}
