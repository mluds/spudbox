{
  my = {
    domain = "spudbox.online";
    cacheDrives = [ ];
    storageDrives = [
      {
        device = "/dev/sda";
        partition = "/dev/sda1";
        mount = "/mnt/storage1";
      }
    ];
  };
}
