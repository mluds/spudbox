{config, ...}:

with config.my;

{
  services.ttyd = {
    enable = true;
    writeable = true;
    port = ttydPort;
  };
}
