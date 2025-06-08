{config, ...}:

with config.my;

{
  services.audiobookshelf = {
    enable = true;
    openFirewall = false;
    port = audiobookshelfPort;
  };
}
