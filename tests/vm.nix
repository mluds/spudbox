# A fresh install in a VM, offline: the template's settings plus a blank
# data disk. Run with `nix build .#checks.x86_64-linux.vm` (or `nix flake
# check`); takes several minutes. Without internet, everything that needs
# plex.tv (plex-config, then Tautulli's Plex link, Jellyseerr, homepage) is
# expected to fail and isn't checked here.
{ pkgs, module }:

pkgs.testers.runNixOSTest {
  name = "spudbox";
  # The module sets nixpkgs.overlays (Plex) and allowUnfree itself.
  node.pkgsReadOnly = false;

  nodes.machine =
    { config, lib, ... }:
    {
      imports = [
        module
        ../template/spudbox.nix
      ];
      spudbox.storageDrives = [
        {
          device = "/dev/vdb";
          partition = "/dev/vdb1";
          mount = "/mnt/storage1";
        }
      ];
      virtualisation = {
        # A test VM replaces fileSystems with its own; add the data mounts.
        fileSystems = config.spudbox.dataMounts;
        # Over 4 GB: mergerfs skips branches with less free space (minfreespace).
        emptyDiskImages = [ 8192 ];
        memorySize = 4096;
        diskSize = 8192;
        cores = 2;
      };
      # The test VM boots its kernel directly.
      boot.loader.systemd-boot.enable = lib.mkForce false;
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("internal secrets are generated, none required are missing"):
        machine.succeed("journalctl -u spudbox-secrets | grep -q 'All required secrets present'")
        machine.succeed("test -s /var/lib/secrets/sonarr/api-key -a -s /var/lib/secrets/restic/password")
        machine.succeed("test \"$(stat -c %a /var/lib/secrets)\" = 700")

    with subtest("the blank data disk is partitioned, formatted and pooled"):
        machine.wait_for_unit("mnt-storage.mount")
        machine.succeed("findmnt -no FSTYPE --mountpoint /mnt/storage1 | grep -qx xfs")
        machine.succeed("findmnt -no FSTYPE --mountpoint /mnt/storage | grep -qx fuse.mergerfs")
        machine.wait_for_unit("create-dirs.service")
        machine.succeed("test -d /mnt/storage1/data/media/movies")

    with subtest("setup units that need no internet succeed"):
        for unit in ["sonarr-config", "radarr-config", "bazarr-config", "audiobookshelf-access",
                     "networkmanager-ipv6-off"]:
            machine.wait_for_unit(f"{unit}.service", timeout=600)

    with subtest("IPv6 is off, including in NetworkManager's wired profiles"):
        machine.succeed("test \"$(sysctl -n net.ipv6.conf.all.disable_ipv6)\" = 1")
        machine.succeed(
            "nmcli -t -f UUID,TYPE connection show | awk -F: '$2 == \"802-3-ethernet\" {print $1}'"
            " | while read -r u; do test \"$(nmcli -g ipv6.method connection show $u)\" = disabled; done"
        )

    with subtest("web UIs: loopback only, behind Caddy with its own CA, logins required"):
        machine.wait_for_open_port(443)
        ca = "/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt"
        machine.wait_until_succeeds(
            f"curl -sf --cacert {ca} --resolve sonarr.example.com:443:127.0.0.1"
            " -o /dev/null https://sonarr.example.com/login", timeout=120)
        machine.succeed("test \"$(curl -s -o /dev/null -w '%{http_code}' localhost:8989/api/v3/system/status)\" = 401")
        machine.succeed("ss -tlnH 'sport = :8989' | awk '{print $4}' | grep -qx '127.0.0.1:8989'")

    with subtest("a nightly backup, then spudbox-restore puts the state back"):
        # The unit itself ends failed here: restarting the apps afterwards
        # includes homepage, which can't start offline (no Plex token). That
        # alert is right on a real server; here only the snapshot matters.
        machine.execute("systemctl start restic-backups-local.service")
        machine.succeed("test \"$(restic-local snapshots --json | jq length)\" -ge 1")
        machine.wait_for_unit("sonarr.service")
        machine.succeed("touch /var/lib/sonarr/after-the-backup")
        machine.succeed("timeout 900 spudbox-restore --yes", timeout=960)
        machine.fail("test -e /var/lib/sonarr/after-the-backup")
        machine.wait_for_unit("sonarr.service")
        machine.wait_for_unit("sonarr-config.service", timeout=600)
        machine.succeed("test \"$(stat -c %U /var/lib/sonarr/.config/NzbDrone/config.xml)\" = sonarr")
  '';
}
