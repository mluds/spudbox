{ config, pkgs, lib, secrets, ... }:

with config.my;

let
  public_domain = "public.${domain}";
  wireguard_port = 51820;
  wireguard_network_base = "10.42.0";
  wireguard_mask = 24;
  lan_cidr = "192.168.0.0/24";
  wireguard_server_ip = "${wireguard_network_base}.1";
  clients = [
    {
      name = "mikes-iphone";
      ip = "${wireguard_network_base}.2";
    }
    {
      name = "mikes-pc";
      ip = "${wireguard_network_base}.3";
    }
  ];
  server_private_key = secrets.wireguard.server.private_key;
  server_public_key = secrets.wireguard.server.public_key;
  client_secrets = secrets.wireguard.clients;
  clientConfig = client: ''
    [Interface]
    PrivateKey = ${client_secrets.${client.name}.private_key}
    Address = ${client.ip}/${toString wireguard_mask}

    [Peer]
    PublicKey = ${server_public_key}
    Endpoint = ${public_domain}:${toString wireguard_port}
    AllowedIPs = ${wireguard_server_ip}/32, ${lan_cidr}
  '';
  serverConfig = ''
    [Interface]
    Address = ${wireguard_server_ip}/${toString wireguard_mask}
    ListenPort = ${toString wireguard_port}
    PrivateKey = ${server_private_key}
    PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

    ${lib.concatMapStrings (client: ''
      # ${client.name}
      [Peer]
      PublicKey = ${client_secrets.${client.name}.public_key}
      AllowedIPs = ${client.ip}/32
    '') clients}
  '';
in
{
  environment.systemPackages = [ pkgs.wireguard-tools pkgs.qrencode ];

  systemd.tmpfiles.rules = [
    "d /etc/wireguard 0700 root root - -"
    "d /etc/wireguard/clients 0700 root root - -"
  ] ++ (map (client:
    "d /etc/wireguard/clients/${client.name} 0700 root root - -"
  ) clients);

  environment.etc =
    let
      serverEntry = {
        "wireguard/wg0.conf" = {
          text = serverConfig;
          mode = "0600";
        };
      };
      clientEntries = lib.listToAttrs (map (client: {
        name = "wireguard/clients/${client.name}/client.conf";
        value = {
          text = clientConfig client;
          mode = "0600";
        };
      }) clients);
    in
    serverEntry // clientEntries;

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  networking.firewall = {
    allowedUDPPorts = [ wireguard_port ];
    trustedInterfaces = [ "wg0" ];
  };
  networking.nat = {
    enable = true;
    externalInterface = external_interface;
    internalInterfaces = [ "wg0" ];
  };

  systemd.services.wg-quick-wg0 = {
    description = "WireGuard for wg0";
    after = [ "network.target" ];
    wants = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up wg0";
      ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down wg0";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
