_:

# Settings for your server. Every spudbox option, with its default, is in the
# spudbox repo's common/options.nix; anything else here is ordinary NixOS
# configuration (https://search.nixos.org/options).
{
  spudbox = {
    # Web UIs are served at https://<service>.<domain> on your LAN. Point a
    # wildcard DNS record (*.example.com) at the server's LAN address.
    domain = "example.com";
    # "internal": Caddy's own CA (browsers warn until you trust its root).
    # "cloudflare": a real Let's Encrypt wildcard certificate via a
    # Cloudflare DNS challenge; needs secrets/cloudflare/api-token.
    tls = "internal";

    users = [
      {
        username = "alice";
        sshPublicKey = "ssh-ed25519 AAAA... alice@laptop";
        superuser = true;
      }
    ];

    # The data disks, formatted XFS with one partition each. Use stable
    # /dev/disk/by-id paths. Without any, the library lives on the boot disk.
    storageDrives = [
      # {
      #   device = "/dev/disk/by-id/ata-WDC_WUH721818ALE6L4_XXXXXXXX";
      #   partition = "/dev/disk/by-id/ata-WDC_WUH721818ALE6L4_XXXXXXXX-part1";
      #   mount = "/mnt/storage1";
      # }
    ];
    # cacheDrives = [ ... ];  # optional fast disk for downloads in progress

    # Usenet: secrets/usenet/{username,password} log in to every server.
    usenet.servers = [
      # "news.example-provider.com"
    ];
    # Newznab indexers; each needs secrets/<lowercased name>/api-key.
    indexers = [
      # {
      #   name = "NZBGeek";
      #   url = "https://api.nzbgeek.info/";
      # }
    ];

    # Bazarr: "opensubtitlescom" (secrets/opensubtitles/{username,password}),
    # "assrt" (secrets/assrt/api-token).
    subtitleProviders = [ ];
    # bazarr.languageProfiles = [ { name = "Default"; languages = [ "en" ]; } ];

    # Optional extras, all off by default:
    # pushover.enable = true;        # failure alerts; secrets/pushover/{app-token,user-key}
    # offsiteBackup = {              # copy nightly backups to S3/R2; secrets/r2/s3-credentials.env
    #   enable = true;
    #   repository = "s3:https://<account>.r2.cloudflarestorage.com/<bucket>";
    # };
    # hddSpindown.enable = true;     # spin idle storage HDDs down
    # mediaFixup.enable = true;      # fix DV5/hybrid-DV videos (Intel iGPU)
    # homebridge.enable = true;      # HomeKit bridge
    # claudeCode = {                 # Claude Code Remote Control
    #   enable = true;
    #   user = "alice";
    # };

    # homepage = {
    #   title = "SpudBox";
    #   bookmarks = [
    #     { title = "Indexer"; href = "https://..."; description = "Usenet Indexer"; icon = "mdi-multimedia"; }
    #   ];
    # };
  };

  time.timeZone = "America/New_York";
  # The NixOS release this machine was first installed with. Set it once and
  # never bump it: it gates data migrations in some services.
  system.stateVersion = "26.05";
}
