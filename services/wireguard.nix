{ config, pkgs, lib, ... }:

with config.my;

let
  public_domain = "public.${domain}";
  wireguard_port = 51820;
  wireguard_network_base = "10.42.0";
  wireguard_mask = 24;
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
  configScript = pkgs.writeShellScript "wireguard-config" ''
    set -e
    SECRETS="${secretsDir}/wireguard"

    SERVER_PRIVATE_KEY=$(cat "$SECRETS/server/private-key")
    SERVER_PUBLIC_KEY=$(cat "$SECRETS/server/public-key")

    mkdir -p /etc/wireguard/clients

    # Generate server config
    cat > /etc/wireguard/wg0.conf <<WGEOF
    [Interface]
    Address = ${wireguard_server_ip}/${toString wireguard_mask}
    ListenPort = ${toString wireguard_port}
    PrivateKey = $SERVER_PRIVATE_KEY
    PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${external_interface} -j MASQUERADE
    PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${external_interface} -j MASQUERADE

    ${lib.concatMapStrings (client: ''
    # ${client.name}
    [Peer]
    PublicKey = $(cat "$SECRETS/clients/${client.name}/public-key")
    AllowedIPs = ${client.ip}/32
    '') clients}
    WGEOF
    chmod 600 /etc/wireguard/wg0.conf

    # Generate client configs
    ${lib.concatMapStrings (client: ''
    mkdir -p /etc/wireguard/clients/${client.name}
    CLIENT_PRIVATE_KEY=$(cat "$SECRETS/clients/${client.name}/private-key")
    cat > /etc/wireguard/clients/${client.name}/client.conf <<CLIENTEOF
    [Interface]
    PrivateKey = $CLIENT_PRIVATE_KEY
    Address = ${client.ip}/${toString wireguard_mask}

    [Peer]
    PublicKey = $SERVER_PUBLIC_KEY
    Endpoint = ${public_domain}:${toString wireguard_port}
    AllowedIPs = ${wireguard_server_ip}/32, ${lan_cidr}
    CLIENTEOF
    chmod 600 /etc/wireguard/clients/${client.name}/client.conf
    '') clients}

    echo "WireGuard configs generated."
  '';
in
{
  environment.systemPackages = [ pkgs.wireguard-tools pkgs.qrencode ];

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
      ExecStartPre = "+${configScript}";
      ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up wg0";
      ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down wg0";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
